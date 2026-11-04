# Slow Date

Application de rencontre « slow » : on se découvre par les mots, près de chez soi, et on se voit en vrai sous 48 heures — ou la conversation se ferme.

**Stack** : Flutter (iOS / Android) + Supabase (Postgres, PostGIS, Auth, Storage, Realtime, pg_cron).

---

## Le parcours

| Étape | Règle | Où c'est appliqué |
|---|---|---|
| 1. Géographie | On ne voit que les personnes de **sa commune et des communes limitrophes** (contours officiels, pas un rayon en km) | `commune_neighbors`, `can_discover()` |
| 2. Intérieur d'abord | Profil = prénom, âge, commune, bio, **réponses à des questions de fond**. Aucune photo | `public_profile_json()`, RLS photos |
| 3. Match | Réciprocité → **48 h pour écrire le premier message**, sinon le match s'efface | `matches.status = waiting → expired` |
| 4. Photos | **24 h après le premier message**, si chacun a écrit au moins 3 messages | `photos_unlocked_at`, policy Storage |
| 5. Rendez-vous | Un RDV doit être **accepté par les deux dans les 48 h** suivant le premier message, sinon le fil est clos | `date_proposals`, `talking → closed` |

Le lieu : l'app calcule le **point à mi-chemin** entre les deux communes, suggère la commune qui s'y trouve (avec un raccourci « chercher un café »), mais chacun propose librement le lieu de son choix ; l'autre accepte, décline ou contre-propose.

Garde-fous « slow » (modifiables) : 3 conversations en cours max, 10 envies d'échanger par jour.

> **Choix d'interprétation** : les horloges « photos » et « rendez-vous » partent du **premier message**, pas de la création du match. Ainsi un match ouvert tard (47 h) garde 48 h pleines de discussion. Pour tout ancrer sur la création du match, il suffit de changer `send_message()` (3 lignes).

### Toutes les durées sont en base

```sql
update public.app_rules set
  first_message_window = '48 hours',
  photo_unlock_after   = '24 hours',
  min_messages_each_for_photos = 3,
  date_deadline        = '48 hours',
  date_max_ahead       = '7 days',
  max_active_matches   = 3,
  daily_likes          = 10;
```

Aucun redéploiement de l'app n'est nécessaire.

---

## Mise en route

### 0. Sécurité des clés

- La clé **publishable** (`sb_publishable_…`) est dans `app/lib/config.dart` : c'est normal, elle est faite pour être embarquée.
- La clé **secrète** (`sb_secret_…`) contourne toute la sécurité. Elle n'est utilisée nulle part dans ce projet. Si elle a circulé (chat, e-mail…), **régénérez-la** : Dashboard → Project Settings → API Keys.

### 1. Nettoyer la base (irréversible)

Dashboard → **SQL Editor** → coller et exécuter `supabase/reset.sql`.
Il vide entièrement le schéma `public` (pas les comptes `auth.users`, ni les fichiers Storage — voir les sections optionnelles en bas du script).

### 2. Créer le schéma

Toujours dans le SQL Editor, exécuter **dans l'ordre** :

1. `supabase/migrations/20261104000100_communes.sql` — PostGIS, communes
2. `supabase/migrations/20261104000200_core.sql` — tout le reste
3. `supabase/migrations/20261104000300_meeting_point.sql` — point à mi-chemin
4. `supabase/migrations/20261104000400_cron.sql` — horloge (chaque minute)

Ou avec la CLI :
```bash
supabase init          # crée supabase/config.toml, garde les migrations
supabase link --project-ref pshxbltlhwsjfjbnoyzj
supabase db push
```

### 3. Importer les communes

```bash
pip install "psycopg[binary]"
export SUPABASE_DB_URL="postgresql://postgres.pshxbltlhwsjfjbnoyzj:<MOT_DE_PASSE_DB>@<hôte-pooler>:5432/postgres"
python scripts/import_communes.py --departements 75,92,93,94   # test rapide (Île-de-France proche)
python scripts/import_communes.py                              # toute la France
```
La connection string : Dashboard → **Connect** → *Session pooler* (port 5432). Le calcul des voisinages sur toute la France prend quelques minutes.

> Paris, Lyon et Marseille sont des communes uniques dans le référentiel : un utilisateur de Boulogne voit tout Paris, et un Parisien voit tout Paris + les communes limitrophes. Si vous voulez raisonner par arrondissement, il faudra importer les arrondissements municipaux à la place.

### 4. Configurer l'authentification (code par e-mail)

L'app se connecte par **code à 6 chiffres** (pas de lien magique, donc pas de deep link à configurer).

1. Dashboard → Authentication → **Emails** → modèle **Magic Link** : remplacer le contenu par quelque chose comme
   `Votre code Slow Date : <strong>{{ .Token }}</strong>`
2. Authentication → Providers → Email : activé.
3. Pour de vrais utilisateurs, brancher un **SMTP** (Resend, Brevo…) : le SMTP intégré de Supabase est très limité en débit.

### 5. Lancer l'app

```bash
cd app
flutter create . --org fr.slowdate --platforms=android,ios   # génère android/ et ios/ sans toucher à lib/
flutter pub get
flutter run
```

iOS : ajouter dans `ios/Runner/Info.plist`
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Pour ajouter des photos à votre profil.</string>
```

Pour pointer vers un autre projet : `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...`

---

## Architecture

```
supabase/
  reset.sql                      nettoyage complet (à lancer à la main)
  migrations/                    schéma, règles, RLS, Storage, Realtime, cron
  tests/run_local.sh             rejoue la machine à états sur un Postgres local
scripts/import_communes.py       contours geo.api.gouv.fr → communes + voisinages
app/lib/
  api.dart                       tous les appels Supabase
  screens/  auth · profile_form · discover · matches · chat · settings
  widgets/  countdown · commune_picker · date_proposal_sheet
```

**Principe de sécurité** : l'app ne peut quasiment rien écrire directement. Les tables sensibles (`matches`, `messages`, `date_proposals`, `decisions`) sont en lecture seule pour les participants ; toute action passe par une fonction SQL (`decide`, `send_message`, `propose_date`, `respond_date`…) qui vérifie les règles et l'horloge. Les photos sont dans un bucket **privé** dont la policy n'ouvre le dossier d'une personne qu'aux matchs dont les photos sont débloquées — même un client modifié ne peut pas les obtenir avant.

**Horloge** : `advance_matches()` tourne chaque minute (pg_cron) et est aussi appelée par chaque RPC, donc l'état lu par l'app est toujours à jour, même entre deux passages du cron.

### Machine à états d'un match

```
waiting ──1er message──▶ talking ──RDV accepté──▶ date_confirmed
   │                        │
   └─48 h─▶ expired         └─48 h─▶ closed          (+ unmatched : départ / blocage)
```

### Tests

`supabase/tests/run_local.sh` crée une base jetable, simule les briques Supabase et rejoue 29 vérifications : voisinage, invisibilité des photos, RLS, expiration à 48 h, dévoilement à 24 h, RDV, clôture, blocage, refus des mineurs, accès anonyme.

```bash
PGHOST=localhost PGUSER=postgres ./supabase/tests/run_local.sh
```

`scripts/e2e_supabase.py` teste le **vrai projet** par les mêmes API que l'app (clé publishable + connexion utilisateur) : 2 comptes de test, profils, photo dans le bucket privé, découverte, match, messages, photos refusées puis dévoilées, RDV, tentatives de triche. Les comptes sont supprimés à la fin.

> État au 4 novembre 2026 : base nettoyée, migrations appliquées, 35 357 communes et 211 114 liens de voisinage importés depuis les contours `gregoiredavid/france-geojson` (2018, faute d'accès à geo.api.gouv.fr depuis l'environnement de déploiement). Pour des communes à jour (fusions depuis 2019, codes postaux), relancer `scripts/import_communes.py` depuis une machine qui a accès à geo.api.gouv.fr.

---

## Pistes pour la suite

- **Notifications push** (nouveau match, message, « plus que 6 h pour fixer le RDV ») : Edge Function + FCM, déclenchée par un webhook sur `matches` / `messages`.
- **Après le rendez-vous** : « Vous êtes-vous vus ? » pour mesurer le taux de passage à l'acte et écarter ceux qui ne viennent jamais.
- **Vérification de profil** (selfie) avant le premier RDV.
- **Modération** : tableau de bord des `reports` (table déjà en place).
