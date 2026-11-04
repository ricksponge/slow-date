-- =====================================================================
-- Slow Date — 2/4 : profils, matchs, machine à états, messages, RDV
--
-- Parcours d'un match (toutes les durées sont dans app_rules) :
--
--   waiting ──(1er message < 48 h)──▶ talking ──(RDV accepté < 48 h)──▶ date_confirmed
--      │                                │
--      └─ 48 h sans message ─▶ expired  └─ 48 h sans RDV ─▶ closed
--
--   • L'horloge « discussion » démarre au premier message (conversation_started_at).
--   • Photos : visibles 24 h après ce premier message, à condition que chacun ait
--     écrit au moins N messages (ou dès que le RDV confirmé approche).
--   • N'importe quel participant peut quitter (unmatched) ou bloquer/signaler.
--
-- Toute écriture passe par des fonctions RPC « security definer » qui font
-- respecter les règles ; les tables ne sont lisibles qu'à travers la RLS.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Règles du jeu (une seule ligne, modifiable sans redéployer l'app)
-- ---------------------------------------------------------------------
create table public.app_rules (
  id                           boolean primary key default true check (id),
  first_message_window         interval not null default interval '48 hours',
  photo_unlock_after           interval not null default interval '24 hours',
  min_messages_each_for_photos int      not null default 3,
  date_deadline                interval not null default interval '48 hours',
  date_max_ahead               interval not null default interval '7 days',
  max_active_matches           int      not null default 3,
  daily_likes                  int      not null default 10,
  min_age                      int      not null default 18,
  min_answers                  int      not null default 3,
  min_photos                   int      not null default 1
);
insert into public.app_rules default values;

create or replace function public.current_rules()
returns public.app_rules
language sql stable security definer set search_path = public
as $$ select * from public.app_rules where id $$;

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------
create type public.gender          as enum ('femme', 'homme', 'non_binaire');
create type public.match_status    as enum ('waiting', 'talking', 'date_confirmed', 'expired', 'closed', 'unmatched');
create type public.proposal_status as enum ('pending', 'accepted', 'declined', 'cancelled');

-- ---------------------------------------------------------------------
-- Profils
-- ---------------------------------------------------------------------
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  first_name   text not null check (char_length(btrim(first_name)) between 1 and 40),
  birthdate    date not null,
  gender       public.gender not null,
  seeking      public.gender[] not null check (cardinality(seeking) > 0),
  age_min      int not null default 18,
  age_max      int not null default 99,
  commune_code text not null references public.communes (code),
  bio          text not null default '' check (char_length(bio) <= 2000),
  is_visible   boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (age_max >= age_min and age_max <= 120)
);
create index profiles_commune_idx on public.profiles (commune_code);

create or replace function public.validate_profile()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  r public.app_rules := public.current_rules();
begin
  if new.birthdate > (current_date - make_interval(years => r.min_age))::date then
    raise exception 'Vous devez avoir au moins % ans pour utiliser Slow Date.', r.min_age;
  end if;
  if tg_op = 'UPDATE' and new.birthdate <> old.birthdate then
    raise exception 'La date de naissance ne peut pas être modifiée.';
  end if;
  new.first_name := btrim(new.first_name);
  new.age_min    := greatest(new.age_min, r.min_age);
  new.updated_at := now();
  return new;
end
$$;

create trigger profiles_validate
  before insert or update on public.profiles
  for each row execute function public.validate_profile();

-- ---------------------------------------------------------------------
-- Questions de fond et réponses
-- ---------------------------------------------------------------------
create table public.questions (
  id       serial primary key,
  text     text not null,
  position int  not null default 0,
  active   boolean not null default true
);

create table public.answers (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  question_id int  not null references public.questions (id) on delete cascade,
  answer      text not null check (char_length(btrim(answer)) between 2 and 1000),
  updated_at  timestamptz not null default now(),
  primary key (user_id, question_id)
);

-- ---------------------------------------------------------------------
-- Photos (fichiers dans le bucket privé « photos », dossier = id utilisateur)
-- ---------------------------------------------------------------------
create table public.profile_photos (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  storage_path text not null unique,
  position     int  not null default 0,
  created_at   timestamptz not null default now(),
  check (split_part(storage_path, '/', 1) = user_id::text)
);
create index profile_photos_user_idx on public.profile_photos (user_id);

-- ---------------------------------------------------------------------
-- Décisions (« j'aimerais échanger » / « passer »), matchs, messages
-- ---------------------------------------------------------------------
create table public.decisions (
  from_user  uuid not null references public.profiles (id) on delete cascade,
  to_user    uuid not null references public.profiles (id) on delete cascade,
  liked      boolean not null,
  created_at timestamptz not null default now(),
  primary key (from_user, to_user),
  check (from_user <> to_user)
);
create index decisions_to_idx on public.decisions (to_user) where liked;

create table public.matches (
  id                      uuid primary key default gen_random_uuid(),
  user_a                  uuid not null references public.profiles (id) on delete cascade,
  user_b                  uuid not null references public.profiles (id) on delete cascade,
  status                  public.match_status not null default 'waiting',
  created_at              timestamptz not null default now(),
  first_message_deadline  timestamptz not null,
  conversation_started_at timestamptz,
  photos_unlock_at        timestamptz,
  photos_unlocked_at      timestamptz,
  date_deadline           timestamptz,
  date_confirmed_at       timestamptz,
  ended_at                timestamptz,
  ended_reason            text,
  check (user_a < user_b),
  unique (user_a, user_b)
);
create index matches_user_a_idx on public.matches (user_a);
create index matches_user_b_idx on public.matches (user_b);
create index matches_open_idx   on public.matches (status) where status in ('waiting', 'talking', 'date_confirmed');

create table public.messages (
  id         bigint generated always as identity primary key,
  match_id   uuid not null references public.matches (id) on delete cascade,
  sender_id  uuid not null references public.profiles (id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index messages_match_idx on public.messages (match_id, created_at);

create table public.date_proposals (
  id            uuid primary key default gen_random_uuid(),
  match_id      uuid not null references public.matches (id) on delete cascade,
  proposer_id   uuid not null references public.profiles (id) on delete cascade,
  place_name    text not null check (char_length(place_name) between 2 and 120),
  place_address text check (char_length(place_address) <= 200),
  meeting_at    timestamptz not null,
  status        public.proposal_status not null default 'pending',
  created_at    timestamptz not null default now(),
  responded_at  timestamptz
);
create index date_proposals_match_idx on public.date_proposals (match_id);
create unique index date_proposals_one_pending on public.date_proposals (match_id) where status = 'pending';

-- ---------------------------------------------------------------------
-- Sécurité : blocages et signalements
-- ---------------------------------------------------------------------
create table public.blocks (
  blocker    uuid not null references public.profiles (id) on delete cascade,
  blocked    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);
create index blocks_blocked_idx on public.blocks (blocked);

create table public.reports (
  id         uuid primary key default gen_random_uuid(),
  reporter   uuid references public.profiles (id) on delete set null,
  reported   uuid references public.profiles (id) on delete set null,
  match_id   uuid references public.matches (id) on delete set null,
  reason     text not null check (char_length(reason) between 2 and 60),
  details    text check (char_length(details) <= 2000),
  created_at timestamptz not null default now()
);

-- =====================================================================
-- Fonctions utilitaires (internes)
-- =====================================================================
create or replace function public.age_of(p_birthdate date)
returns int language sql stable
as $$ select extract(year from age(current_date, p_birthdate))::int $$;

create or replace function public.is_blocked_between(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.blocks
                 where (blocker = p_a and blocked = p_b) or (blocker = p_b and blocked = p_a))
$$;

create or replace function public.is_profile_complete(p_user uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = p_user)
     and (select count(*) from public.answers        where user_id = p_user) >= (select min_answers from public.app_rules)
     and (select count(*) from public.profile_photos where user_id = p_user) >= (select min_photos  from public.app_rules)
$$;

create or replace function public.active_match_count(p_user uuid)
returns int language sql stable security definer set search_path = public
as $$
  select count(*)::int from public.matches
  where (user_a = p_user or user_b = p_user) and status in ('waiting', 'talking')
$$;

create or replace function public.likes_today(p_user uuid)
returns int language sql stable security definer set search_path = public
as $$
  select count(*)::int from public.decisions
  where from_user = p_user and liked
    and (created_at at time zone 'Europe/Paris')::date = (now() at time zone 'Europe/Paris')::date
$$;

-- Ma commune + les communes limitrophes
create or replace function public.nearby_communes(p_code text)
returns setof text language sql stable security definer set search_path = public
as $$
  select p_code
  union
  select neighbor_code from public.commune_neighbors where code = p_code
$$;

-- p_me peut-il voir p_other dans « Découvrir » ?
create or replace function public.can_discover(p_me uuid, p_other uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.profiles me
    join public.profiles o on o.id = p_other
    where me.id = p_me
      and o.id <> me.id
      and o.is_visible
      and o.commune_code in (select public.nearby_communes(me.commune_code))
      and o.gender  = any (me.seeking)
      and me.gender = any (o.seeking)
      and public.age_of(o.birthdate)  between me.age_min and me.age_max
      and public.age_of(me.birthdate) between o.age_min  and o.age_max
      and public.is_profile_complete(o.id)
      and not public.is_blocked_between(me.id, o.id)
      and not exists (select 1 from public.decisions d where d.from_user = me.id and d.to_user = o.id)
      and not exists (select 1 from public.matches m
                      where m.user_a = least(me.id, o.id) and m.user_b = greatest(me.id, o.id))
      and public.active_match_count(o.id) < (select max_active_matches from public.app_rules)
  )
$$;

-- Profil « intérieur » : AUCUNE photo ici, jamais
create or replace function public.public_profile_json(p_user uuid)
returns jsonb language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'id',           p.id,
    'first_name',   p.first_name,
    'age',          public.age_of(p.birthdate),
    'gender',       p.gender,
    'commune',      c.nom,
    'commune_code', c.code,
    'bio',          p.bio,
    'answers',      coalesce((
        select jsonb_agg(jsonb_build_object('question', q.text, 'answer', a.answer)
                         order by q.position, q.id)
        from public.answers a join public.questions q on q.id = a.question_id
        where a.user_id = p.id), '[]'::jsonb)
  )
  from public.profiles p
  join public.communes c on c.code = p.commune_code
  where p.id = p_user
$$;

-- Accès aux photos de p_owner (dossier storage = texte) pour l'utilisateur courant
create or replace function public.can_see_photos_of(p_owner text)
returns boolean language sql stable security definer set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from public.matches m
    where m.photos_unlocked_at is not null
      and m.status in ('talking', 'date_confirmed')
      and (   (m.user_a::text = p_owner and m.user_b = auth.uid())
           or (m.user_b::text = p_owner and m.user_a = auth.uid()))
  )
$$;

-- =====================================================================
-- Moteur temporel : fait avancer les matchs dont une échéance est passée.
-- Appelé chaque minute par pg_cron, et à chaque appel RPC concerné.
-- =====================================================================
create or replace function public.advance_matches(p_match_id uuid default null, p_user uuid default null)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.app_rules := public.current_rules();
  n int := 0;
  k int;
begin
  -- 1. Personne n'a écrit dans la fenêtre → le match s'efface
  update public.matches m
     set status = 'expired', ended_at = m.first_message_deadline, ended_reason = 'no_first_message'
   where m.status = 'waiting' and m.first_message_deadline <= now()
     and (p_match_id is null or m.id = p_match_id)
     and (p_user is null or p_user in (m.user_a, m.user_b));
  get diagnostics k = row_count; n := n + k;

  -- 2. Pas de rendez-vous accepté dans les temps → fil clôturé
  update public.matches m
     set status = 'closed', ended_at = m.date_deadline, ended_reason = 'no_date'
   where m.status = 'talking' and m.date_deadline <= now()
     and (p_match_id is null or m.id = p_match_id)
     and (p_user is null or p_user in (m.user_a, m.user_b));
  get diagnostics k = row_count; n := n + k;

  -- 3. Dévoilement des photos après 24 h de vraie discussion
  update public.matches m
     set photos_unlocked_at = now()
   where m.status = 'talking' and m.photos_unlocked_at is null and m.photos_unlock_at <= now()
     and (select count(*) from public.messages x where x.match_id = m.id and x.sender_id = m.user_a) >= r.min_messages_each_for_photos
     and (select count(*) from public.messages x where x.match_id = m.id and x.sender_id = m.user_b) >= r.min_messages_each_for_photos
     and (p_match_id is null or m.id = p_match_id)
     and (p_user is null or p_user in (m.user_a, m.user_b));
  get diagnostics k = row_count; n := n + k;

  -- 4. RDV confirmé : photos à l'échéance normale, ou 3 h avant le RDV au plus tard
  update public.matches m
     set photos_unlocked_at = now()
   where m.status = 'date_confirmed' and m.photos_unlocked_at is null
     and (   m.photos_unlock_at <= now()
          or exists (select 1 from public.date_proposals p
                     where p.match_id = m.id and p.status = 'accepted'
                       and p.meeting_at - interval '3 hours' <= now()))
     and (p_match_id is null or m.id = p_match_id)
     and (p_user is null or p_user in (m.user_a, m.user_b));
  get diagnostics k = row_count; n := n + k;

  -- 5. Propositions de RDV devenues caduques
  update public.date_proposals p
     set status = 'cancelled', responded_at = now()
    from public.matches m
   where p.match_id = m.id and p.status = 'pending'
     and (m.status in ('expired', 'closed', 'unmatched') or p.meeting_at <= now())
     and (p_match_id is null or m.id = p_match_id)
     and (p_user is null or p_user in (m.user_a, m.user_b));

  return n;
end
$$;

-- Représentation d'un match pour la liste « Rencontres »
create or replace function public.match_json(p_match_id uuid, p_me uuid)
returns jsonb language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'id',                      m.id,
    'status',                  m.status,
    'created_at',              m.created_at,
    'first_message_deadline',  m.first_message_deadline,
    'conversation_started_at', m.conversation_started_at,
    'photos_unlock_at',        m.photos_unlock_at,
    'photos_unlocked',         m.photos_unlocked_at is not null,
    'date_deadline',           m.date_deadline,
    'date_confirmed_at',       m.date_confirmed_at,
    'ended_at',                m.ended_at,
    'ended_reason',            m.ended_reason,
    'other', (
      select jsonb_build_object('id', o.id, 'first_name', o.first_name,
                                'age', public.age_of(o.birthdate), 'commune', c.nom)
      from public.profiles o join public.communes c on c.code = o.commune_code
      where o.id = case when m.user_a = p_me then m.user_b else m.user_a end),
    'last_message', (
      select jsonb_build_object('body', x.body, 'from_me', x.sender_id = p_me, 'created_at', x.created_at)
      from public.messages x where x.match_id = m.id
      order by x.created_at desc, x.id desc limit 1),
    'confirmed_date', (
      select jsonb_build_object('place_name', p.place_name, 'place_address', p.place_address,
                                'meeting_at', p.meeting_at)
      from public.date_proposals p where p.match_id = m.id and p.status = 'accepted'
      order by p.responded_at desc limit 1)
  )
  from public.matches m
  where m.id = p_match_id
$$;

-- =====================================================================
-- API appelée par l'application (RPC)
-- =====================================================================

create or replace function public.require_user()
returns uuid language plpgsql stable
as $$
begin
  if auth.uid() is null then
    raise exception 'Vous devez être connecté·e.' using errcode = '28000';
  end if;
  return auth.uid();
end
$$;

-- Mon profil complet (pour l'onboarding et l'édition)
create or replace function public.get_my_profile()
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_me uuid := public.require_user();
  r public.app_rules := public.current_rules();
begin
  return jsonb_build_object(
    'profile', (select to_jsonb(p) || jsonb_build_object('commune_nom', c.nom, 'age', public.age_of(p.birthdate))
                from public.profiles p join public.communes c on c.code = p.commune_code
                where p.id = v_me),
    'answers', coalesce((select jsonb_agg(jsonb_build_object('question_id', a.question_id, 'answer', a.answer))
                         from public.answers a where a.user_id = v_me), '[]'::jsonb),
    'photos',  coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'storage_path', ph.storage_path)
                                          order by ph.position, ph.created_at)
                         from public.profile_photos ph where ph.user_id = v_me), '[]'::jsonb),
    'complete', public.is_profile_complete(v_me),
    'rules', jsonb_build_object(
      'first_message_hours',  extract(epoch from r.first_message_window) / 3600,
      'photo_unlock_hours',   extract(epoch from r.photo_unlock_after)   / 3600,
      'date_deadline_hours',  extract(epoch from r.date_deadline)        / 3600,
      'date_max_ahead_days',  extract(epoch from r.date_max_ahead)       / 86400,
      'min_messages_each',    r.min_messages_each_for_photos,
      'max_active_matches',   r.max_active_matches,
      'daily_likes',          r.daily_likes,
      'min_age',              r.min_age,
      'min_answers',          r.min_answers,
      'min_photos',           r.min_photos)
  );
end
$$;

-- Fil « Découvrir » : profils de ma commune et des communes limitrophes, sans photo
create or replace function public.get_discovery(p_limit int default 10)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_me     uuid := public.require_user();
  r        public.app_rules := public.current_rules();
  v_prof   public.profiles;
  v_likes  int;
  v_slots  int;
  v_status text := 'ok';
  v_list   jsonb := '[]'::jsonb;
begin
  select * into v_prof from public.profiles where id = v_me;
  if not found or not public.is_profile_complete(v_me) then
    v_status := 'incomplete';
  end if;

  perform public.advance_matches(null, v_me);
  v_likes := greatest(0, r.daily_likes - public.likes_today(v_me));
  v_slots := greatest(0, r.max_active_matches - public.active_match_count(v_me));

  if v_status = 'ok' then
    if not v_prof.is_visible then v_status := 'paused';
    elsif v_slots = 0       then v_status := 'no_slot';
    elsif v_likes = 0       then v_status := 'no_likes_left';
    end if;
  end if;

  if v_status = 'ok' then
    select coalesce(jsonb_agg(x.j order by x.k), '[]'::jsonb) into v_list
    from (
      select public.public_profile_json(o.id) as j,
             md5(o.id::text || v_me::text || current_date::text) as k
      from public.profiles o
      where o.commune_code in (select public.nearby_communes(v_prof.commune_code))
        and public.can_discover(v_me, o.id)
      order by k
      limit least(greatest(p_limit, 1), 30)
    ) x;
  end if;

  return jsonb_build_object('status', v_status, 'likes_left', v_likes,
                            'slots_left', v_slots, 'profiles', v_list);
end
$$;

-- « J'aimerais échanger » (p_like = true) ou « Passer » (false)
create or replace function public.decide(p_target uuid, p_like boolean)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_me    uuid := public.require_user();
  r       public.app_rules := public.current_rules();
  v_match uuid;
begin
  -- évite qu'un double « oui » simultané rate le match
  perform pg_advisory_xact_lock(hashtext(least(v_me, p_target)::text || greatest(v_me, p_target)::text));
  perform public.advance_matches(null, v_me);

  if not public.is_profile_complete(v_me) then
    raise exception 'Complétez votre profil avant de découvrir d''autres personnes.';
  end if;
  if not public.can_discover(v_me, p_target) then
    raise exception 'Ce profil n''est plus disponible.';
  end if;

  if p_like then
    if public.likes_today(v_me) >= r.daily_likes then
      raise exception 'Vous avez utilisé vos % envies d''échanger du jour. Revenez demain.', r.daily_likes;
    end if;
    if public.active_match_count(v_me) >= r.max_active_matches then
      raise exception 'Vous avez déjà % conversations en cours. Allez au bout avant d''en ouvrir une autre.', r.max_active_matches;
    end if;
  end if;

  insert into public.decisions (from_user, to_user, liked) values (v_me, p_target, p_like);

  if p_like and exists (select 1 from public.decisions
                        where from_user = p_target and to_user = v_me and liked) then
    insert into public.matches (user_a, user_b, first_message_deadline)
    values (least(v_me, p_target), greatest(v_me, p_target), now() + r.first_message_window)
    on conflict (user_a, user_b) do nothing
    returning id into v_match;
  end if;

  return jsonb_build_object('matched', v_match is not null, 'match_id', v_match);
end
$$;

-- Liste de mes rencontres (en cours puis terminées)
create or replace function public.get_my_matches()
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_me uuid := public.require_user();
begin
  perform public.advance_matches(null, v_me);
  return coalesce((
    select jsonb_agg(public.match_json(m.id, v_me)
                     order by (m.status in ('waiting', 'talking', 'date_confirmed')) desc,
                              coalesce((select max(x.created_at) from public.messages x where x.match_id = m.id),
                                       m.created_at) desc)
    from public.matches m
    where v_me in (m.user_a, m.user_b)
      and m.status <> 'unmatched'
      and not public.is_blocked_between(m.user_a, m.user_b)
  ), '[]'::jsonb);
end
$$;

-- Détail d'un match (écran de conversation)
create or replace function public.get_match(p_match_id uuid)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_me    uuid := public.require_user();
  r       public.app_rules := public.current_rules();
  m       public.matches;
  v_other uuid;
  v_open  boolean;
begin
  perform public.advance_matches(p_match_id);
  select * into m from public.matches where id = p_match_id;
  if not found or v_me not in (m.user_a, m.user_b) or m.status = 'unmatched'
     or public.is_blocked_between(m.user_a, m.user_b) then
    raise exception 'Conversation introuvable.';
  end if;

  v_other := case when m.user_a = v_me then m.user_b else m.user_a end;
  v_open  := m.status in ('talking', 'date_confirmed');

  return public.match_json(m.id, v_me) || jsonb_build_object(
    'me',            v_me,
    'other_profile', public.public_profile_json(v_other),
    'photos', case when m.photos_unlocked_at is not null and v_open then
                coalesce((select jsonb_agg(ph.storage_path order by ph.position, ph.created_at)
                          from public.profile_photos ph where ph.user_id = v_other), '[]'::jsonb)
              else '[]'::jsonb end,
    'my_message_count',    (select count(*) from public.messages x where x.match_id = m.id and x.sender_id = v_me),
    'their_message_count', (select count(*) from public.messages x where x.match_id = m.id and x.sender_id = v_other),
    'min_messages_each',   r.min_messages_each_for_photos,
    'date_max_ahead_days', extract(epoch from r.date_max_ahead) / 86400,
    'pending_proposal', (
      select jsonb_build_object('id', p.id, 'from_me', p.proposer_id = v_me, 'place_name', p.place_name,
                                'place_address', p.place_address, 'meeting_at', p.meeting_at,
                                'created_at', p.created_at)
      from public.date_proposals p where p.match_id = m.id and p.status = 'pending')
  );
end
$$;

-- Envoyer un message (le premier message lance l'horloge de la discussion)
create or replace function public.send_message(p_match_id uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_me   uuid := public.require_user();
  r      public.app_rules := public.current_rules();
  m      public.matches;
  v_body text := btrim(coalesce(p_body, ''));
  v_msg  public.messages;
begin
  perform public.advance_matches(p_match_id);
  select * into m from public.matches where id = p_match_id for update;
  if not found or v_me not in (m.user_a, m.user_b) then
    raise exception 'Conversation introuvable.';
  end if;
  if m.status not in ('waiting', 'talking', 'date_confirmed')
     or public.is_blocked_between(m.user_a, m.user_b) then
    raise exception 'Cette conversation est terminée.';
  end if;
  if char_length(v_body) = 0 then
    raise exception 'Le message est vide.';
  end if;
  if char_length(v_body) > 2000 then
    raise exception 'Message trop long (2000 caractères maximum).';
  end if;

  if m.status = 'waiting' then
    update public.matches
       set status = 'talking',
           conversation_started_at = now(),
           photos_unlock_at = now() + r.photo_unlock_after,
           date_deadline    = now() + r.date_deadline
     where id = m.id;
  end if;

  insert into public.messages (match_id, sender_id, body)
  values (m.id, v_me, v_body)
  returning * into v_msg;

  perform public.advance_matches(m.id);   -- débloque les photos si le quota vient d'être atteint
  return to_jsonb(v_msg);
end
$$;

-- Proposer un rendez-vous (remplace une éventuelle proposition en attente)
create or replace function public.propose_date(p_match_id uuid, p_place_name text,
                                               p_place_address text, p_meeting_at timestamptz)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_me    uuid := public.require_user();
  r       public.app_rules := public.current_rules();
  m       public.matches;
  v_place text := btrim(coalesce(p_place_name, ''));
  v_addr  text := nullif(btrim(coalesce(p_place_address, '')), '');
  v_prop  public.date_proposals;
begin
  perform public.advance_matches(p_match_id);
  select * into m from public.matches where id = p_match_id for update;
  if not found or v_me not in (m.user_a, m.user_b) then
    raise exception 'Conversation introuvable.';
  end if;
  if m.status <> 'talking' or public.is_blocked_between(m.user_a, m.user_b) then
    raise exception 'Un rendez-vous ne peut être proposé que pendant la discussion.';
  end if;
  if char_length(v_place) < 2 then
    raise exception 'Indiquez le lieu du rendez-vous.';
  end if;
  if p_meeting_at < now() + interval '1 hour' then
    raise exception 'Le rendez-vous doit avoir lieu dans au moins une heure.';
  end if;
  if p_meeting_at > now() + r.date_max_ahead then
    raise exception 'Le rendez-vous doit avoir lieu dans les % prochains jours.',
      (extract(epoch from r.date_max_ahead) / 86400)::int;
  end if;

  update public.date_proposals set status = 'cancelled', responded_at = now()
   where match_id = m.id and status = 'pending';

  insert into public.date_proposals (match_id, proposer_id, place_name, place_address, meeting_at)
  values (m.id, v_me, left(v_place, 120), left(v_addr, 200), p_meeting_at)
  returning * into v_prop;

  return to_jsonb(v_prop);
end
$$;

-- Accepter / décliner la proposition de l'autre
create or replace function public.respond_date(p_proposal_id uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_me   uuid := public.require_user();
  v_prop public.date_proposals;
  m      public.matches;
begin
  select * into v_prop from public.date_proposals where id = p_proposal_id;
  if not found then
    raise exception 'Proposition introuvable.';
  end if;

  perform public.advance_matches(v_prop.match_id);
  select * into m from public.matches where id = v_prop.match_id for update;
  if v_me not in (m.user_a, m.user_b) then
    raise exception 'Proposition introuvable.';
  end if;

  select * into v_prop from public.date_proposals where id = p_proposal_id for update;
  if v_prop.proposer_id = v_me then
    raise exception 'C''est à l''autre personne de répondre à votre proposition.';
  end if;
  if v_prop.status <> 'pending' or m.status <> 'talking' then
    raise exception 'Cette proposition n''est plus valable.';
  end if;

  if p_accept then
    update public.date_proposals set status = 'accepted', responded_at = now() where id = v_prop.id;
    update public.matches set status = 'date_confirmed', date_confirmed_at = now() where id = m.id;
    perform public.advance_matches(m.id);
  else
    update public.date_proposals set status = 'declined', responded_at = now() where id = v_prop.id;
  end if;

  return public.match_json(m.id, v_me);
end
$$;

-- Quitter une conversation
create or replace function public.unmatch(p_match_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_me uuid := public.require_user();
begin
  update public.matches
     set status = 'unmatched', ended_at = now(), ended_reason = 'unmatched'
   where id = p_match_id and v_me in (user_a, user_b)
     and status in ('waiting', 'talking', 'date_confirmed');
  perform public.advance_matches(p_match_id);
end
$$;

-- Bloquer quelqu'un (met fin à tout match avec cette personne)
create or replace function public.block_user(p_user uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_me uuid := public.require_user();
begin
  if p_user = v_me then raise exception 'Action impossible.'; end if;
  insert into public.blocks (blocker, blocked) values (v_me, p_user) on conflict do nothing;
  update public.matches
     set status = 'unmatched', ended_at = now(), ended_reason = 'blocked'
   where user_a = least(v_me, p_user) and user_b = greatest(v_me, p_user)
     and status in ('waiting', 'talking', 'date_confirmed');
  perform public.advance_matches(null, v_me);
end
$$;

-- Signaler (bloque automatiquement)
create or replace function public.report_user(p_user uuid, p_match_id uuid, p_reason text, p_details text)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_me uuid := public.require_user();
begin
  insert into public.reports (reporter, reported, match_id, reason, details)
  values (v_me, p_user, p_match_id, left(btrim(p_reason), 60), left(nullif(btrim(coalesce(p_details, '')), ''), 2000));
  perform public.block_user(p_user);
end
$$;

-- Suppression de compte (les fichiers photo sont supprimés par l'app juste avant)
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, auth
as $$
declare
  v_me uuid := public.require_user();
begin
  delete from auth.users where id = v_me;
end
$$;

-- =====================================================================
-- Row Level Security
-- =====================================================================
alter table public.app_rules      enable row level security;
alter table public.profiles       enable row level security;
alter table public.questions      enable row level security;
alter table public.answers        enable row level security;
alter table public.profile_photos enable row level security;
alter table public.decisions      enable row level security;
alter table public.matches        enable row level security;
alter table public.messages       enable row level security;
alter table public.date_proposals enable row level security;
alter table public.blocks         enable row level security;
alter table public.reports        enable row level security;

create policy "règles lisibles"    on public.app_rules for select to authenticated using (true);
create policy "questions lisibles" on public.questions for select to authenticated using (active);

-- Mon profil uniquement (les autres passent par les RPC, sans photo ni date de naissance)
create policy "profil: lecture perso"  on public.profiles for select to authenticated using (id = auth.uid());
create policy "profil: création perso" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "profil: édition perso"  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy "réponses: perso" on public.answers for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "photos: lecture" on public.profile_photos for select to authenticated
  using (user_id = auth.uid() or public.can_see_photos_of(user_id::text));
create policy "photos: ajout perso" on public.profile_photos for insert to authenticated
  with check (user_id = auth.uid());
create policy "photos: suppression perso" on public.profile_photos for delete to authenticated
  using (user_id = auth.uid());
create policy "photos: ordre perso" on public.profile_photos for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Lecture seule pour les participants ; écriture uniquement via RPC
create policy "matchs: participants" on public.matches for select to authenticated
  using (auth.uid() in (user_a, user_b));
create policy "messages: participants" on public.messages for select to authenticated
  using (exists (select 1 from public.matches m
                 where m.id = match_id and auth.uid() in (m.user_a, m.user_b)
                   and m.status <> 'unmatched'));
create policy "rdv: participants" on public.date_proposals for select to authenticated
  using (exists (select 1 from public.matches m
                 where m.id = match_id and auth.uid() in (m.user_a, m.user_b)));
create policy "blocages: perso" on public.blocks for select to authenticated
  using (blocker = auth.uid());
-- decisions, reports : aucune policy → inaccessibles directement

-- =====================================================================
-- Storage : bucket privé « photos »
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "slowdate photos: lecture"     on storage.objects;
drop policy if exists "slowdate photos: ajout"       on storage.objects;
drop policy if exists "slowdate photos: suppression" on storage.objects;

create policy "slowdate photos: lecture" on storage.objects for select to authenticated
  using (bucket_id = 'photos'
         and ((storage.foldername(name))[1] = auth.uid()::text
              or public.can_see_photos_of((storage.foldername(name))[1])));
create policy "slowdate photos: ajout" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "slowdate photos: suppression" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- =====================================================================
-- Droits d'exécution
-- =====================================================================
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function
  public.get_my_profile(),
  public.get_discovery(int),
  public.decide(uuid, boolean),
  public.get_my_matches(),
  public.get_match(uuid),
  public.send_message(uuid, text),
  public.propose_date(uuid, text, text, timestamptz),
  public.respond_date(uuid, boolean),
  public.unmatch(uuid),
  public.block_user(uuid),
  public.report_user(uuid, uuid, text, text),
  public.delete_my_account(),
  public.search_communes(text, int),
  -- utilisées par la RLS et les triggers :
  public.can_see_photos_of(text),
  public.current_rules(),
  public.validate_profile(),
  public.normalize_txt(text)
to authenticated;

-- =====================================================================
-- Realtime : messages, état des matchs, propositions de RDV
-- =====================================================================
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.messages, public.matches, public.date_proposals;
  end if;
end $$;

-- =====================================================================
-- Questions de départ
-- =====================================================================
insert into public.questions (text, position) values
  ('Qu''est-ce qui vous fait perdre la notion du temps ?', 1),
  ('Un dimanche idéal, ça ressemble à quoi ?', 2),
  ('Quelle conviction avez-vous changée ces dernières années, et pourquoi ?', 3),
  ('Qu''est-ce qu''on vous reproche souvent… et que vous assumez ?', 4),
  ('Le dernier livre, film ou podcast qui vous a vraiment marqué·e ?', 5),
  ('Qu''attendez-vous d''une relation, concrètement ?', 6),
  ('De quoi êtes-vous fier·ère sans l''avoir jamais dit ?', 7),
  ('Qu''est-ce qui vous fait rire à coup sûr ?', 8),
  ('Votre coin préféré dans votre ville, et ce que vous y faites ?', 9),
  ('Une petite chose qui rend votre quotidien meilleur ?', 10);
