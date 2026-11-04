-- Scénario de bout en bout de la machine à états (exécuté par run_local.sh)
\set ON_ERROR_STOP 1
\set QUIET 1

create or replace function pg_temp.check(cond boolean, label text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'ÉCHEC : %', label; end if;
  raise notice 'ok  %', label;
end $$;

create or replace function pg_temp.act_as(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, false)
$$;

-- Données : 3 communes (A et B voisines, Z loin) ---------------------------
insert into public.communes (code, nom, nom_normalise, codes_postaux, departement, lat, lng) values
  ('92012', 'Boulogne-Billancourt', public.normalize_txt('Boulogne-Billancourt'), '{92100}', '92', 48.835, 2.24),
  ('75056', 'Paris',                public.normalize_txt('Paris'),                '{75001,75016}', '75', 48.856, 2.35),
  ('13055', 'Marseille',            public.normalize_txt('Marseille'),            '{13001}', '13', 43.296, 5.37);
insert into public.commune_neighbors values ('92012','75056'), ('75056','92012');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'alice@test'),
  ('00000000-0000-0000-0000-00000000000b', 'bob@test'),
  ('00000000-0000-0000-0000-00000000000c', 'carl@test'),
  ('00000000-0000-0000-0000-00000000000d', 'dan@test');

-- Chaque utilisateur remplit son profil lui-même (RLS active)
set role authenticated;

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
insert into public.profiles (id, first_name, birthdate, gender, seeking, commune_code, bio)
values (auth.uid(), 'Alice', '1992-05-01', 'femme', '{homme}', '92012', 'Bonjour');
insert into public.answers (user_id, question_id, answer) select auth.uid(), id, 'Réponse de fond' from public.questions limit 3;
insert into public.profile_photos (user_id, storage_path) values (auth.uid(), auth.uid() || '/1.jpg');

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');
insert into public.profiles (id, first_name, birthdate, gender, seeking, commune_code, bio)
values (auth.uid(), 'Bob', '1990-01-01', 'homme', '{femme}', '75056', 'Salut');
insert into public.answers (user_id, question_id, answer) select auth.uid(), id, 'Réponse de fond' from public.questions limit 3;
insert into public.profile_photos (user_id, storage_path) values (auth.uid(), auth.uid() || '/1.jpg');

select pg_temp.act_as('00000000-0000-0000-0000-00000000000c');
insert into public.profiles (id, first_name, birthdate, gender, seeking, commune_code)
values (auth.uid(), 'Carl', '1991-01-01', 'homme', '{femme}', '13055');
insert into public.answers (user_id, question_id, answer) select auth.uid(), id, 'Réponse de fond' from public.questions limit 3;
insert into public.profile_photos (user_id, storage_path) values (auth.uid(), auth.uid() || '/1.jpg');

-- Mineur refusé
select pg_temp.act_as('00000000-0000-0000-0000-00000000000d');
do $$ begin
  insert into public.profiles (id, first_name, birthdate, gender, seeking, commune_code)
  values (auth.uid(), 'Dan', current_date - interval '17 years', 'homme', '{femme}', '92012');
  raise exception 'ÉCHEC : mineur accepté';
exception when others then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'ok  mineur refusé (%)', sqlerrm;
end $$;

-- Découverte ------------------------------------------------------------
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
select pg_temp.check((public.get_my_profile()->>'complete')::boolean, 'profil d''Alice complet');
select pg_temp.check(
  (select jsonb_agg(p->>'first_name') from jsonb_array_elements(public.get_discovery()->'profiles') p) = '["Bob"]'::jsonb,
  'Alice voit Bob (commune voisine) mais pas Carl (Marseille)');
select pg_temp.check(public.get_discovery()::text not like '%.jpg%', 'aucune photo dans Découvrir');
select pg_temp.check((select count(*) from public.profiles) = 1, 'RLS : Alice ne lit que son propre profil');
select pg_temp.check((select count(*) from public.profile_photos) = 1, 'RLS : Alice ne voit pas les photos de Bob');
select pg_temp.check(
  (select count(*) from public.search_communes('boulogne')) = 1 and (select count(*) from public.search_communes('9210')) = 1,
  'recherche de commune par nom et code postal');

select pg_temp.check((public.decide('00000000-0000-0000-0000-00000000000b', true)->>'matched')::boolean = false, 'Alice aime Bob : pas encore réciproque');

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');
create temp table t (match_id uuid);
grant all on t to authenticated;
insert into t select (public.decide('00000000-0000-0000-0000-00000000000a', true)->>'match_id')::uuid;
select pg_temp.check((select match_id from t) is not null, 'Bob aime Alice : match créé');
select pg_temp.check(public.get_match((select match_id from t))->>'status' = 'waiting', 'match en attente du 1er message');
select pg_temp.check(public.get_match((select match_id from t))->'photos' = '[]'::jsonb, 'photos cachées au match');

-- Proposer un RDV avant d'avoir parlé : refusé
do $$ begin
  perform public.propose_date((select match_id from t), 'Café', null, now() + interval '1 day');
  raise exception 'ÉCHEC : RDV accepté sans discussion';
exception when others then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'ok  RDV refusé avant discussion (%)', sqlerrm;
end $$;

-- Discussion -------------------------------------------------------------
select public.send_message((select match_id from t), 'Bonjour Alice !');
select pg_temp.check(public.get_match((select match_id from t))->>'status' = 'talking', '1er message → discussion lancée');
select public.send_message((select match_id from t), 'Message 2');
select public.send_message((select match_id from t), 'Message 3');
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
select public.send_message((select match_id from t), 'Bonjour Bob');
select public.send_message((select match_id from t), 'Message 2');
select public.send_message((select match_id from t), 'Message 3');
select pg_temp.check((select count(*) from public.messages) = 6, 'RLS : Alice lit les 6 messages');
select pg_temp.check(public.get_match((select match_id from t))->'photos' = '[]'::jsonb, 'photos toujours cachées avant 24 h');

-- +24 h : on recule les horloges
reset role;
update public.matches set conversation_started_at = conversation_started_at - interval '25 hours',
  photos_unlock_at = photos_unlock_at - interval '25 hours', date_deadline = date_deadline - interval '25 hours';
set role authenticated;
select pg_temp.check(jsonb_array_length(public.get_match((select match_id from t))->'photos') = 1, '24 h + 3 messages chacun → photos de Bob visibles');
select pg_temp.check((select count(*) from public.profile_photos) = 2, 'RLS : Alice lit maintenant les photos de Bob');
select pg_temp.check(public.can_see_photos_of('00000000-0000-0000-0000-00000000000b'), 'storage : accès au dossier de Bob');

-- RDV : proposition puis acceptation
select public.propose_date((select match_id from t), 'Café du Parc', '1 rue X', now() + interval '2 days');
do $$ begin
  perform public.respond_date((select (public.get_match((select match_id from t))->'pending_proposal'->>'id')::uuid), true);
  raise exception 'ÉCHEC : on peut accepter sa propre proposition';
exception when others then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'ok  impossible d''accepter sa propre proposition';
end $$;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');
select public.respond_date((select (public.get_match((select match_id from t))->'pending_proposal'->>'id')::uuid), true);
select pg_temp.check(public.get_match((select match_id from t))->>'status' = 'date_confirmed', 'RDV accepté → confirmé');

-- Le délai passe : un match confirmé ne se ferme pas
reset role;
update public.matches set date_deadline = now() - interval '1 minute';
select public.advance_matches();
select pg_temp.check((select status from public.matches) = 'date_confirmed', 'match confirmé non clôturé à l''échéance');

-- Second scénario : match sans RDV → clôturé ; match muet → expiré -------
update public.app_rules set max_active_matches = 5;
insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000e1'), ('00000000-0000-0000-0000-0000000000e2');
insert into public.profiles (id, first_name, birthdate, gender, seeking, commune_code) values
  ('00000000-0000-0000-0000-0000000000e1', 'Eve', '1993-01-01', 'femme', '{homme}', '92012'),
  ('00000000-0000-0000-0000-0000000000e2', 'Ève', '1994-01-01', 'femme', '{homme}', '75056');
insert into public.matches (user_a, user_b, first_message_deadline, status, conversation_started_at, photos_unlock_at, date_deadline)
values ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000e1', now(), 'talking',
        now() - interval '49 hours', now() - interval '25 hours', now() - interval '1 hour');
insert into public.matches (user_a, user_b, first_message_deadline)
values ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000e2', now() - interval '1 minute');
select public.advance_matches();
select pg_temp.check((select status from public.matches where user_b = '00000000-0000-0000-0000-0000000000e1') = 'closed', 'pas de RDV en 48 h → fil clôturé');
select pg_temp.check((select status from public.matches where user_b = '00000000-0000-0000-0000-0000000000e2') = 'expired', 'pas de 1er message en 48 h → match effacé');

set role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');
do $$ begin
  perform public.send_message((select id from public.matches where user_b = '00000000-0000-0000-0000-0000000000e1'), 'trop tard');
  raise exception 'ÉCHEC : message accepté dans un fil clôturé';
exception when others then
  if sqlerrm like 'ÉCHEC%' then raise; end if;
  raise notice 'ok  fil clôturé en lecture seule';
end $$;
select pg_temp.check(jsonb_array_length(public.get_my_matches()) = 3, 'Bob voit ses 3 rencontres (1 en cours, 2 terminées)');

-- Blocage ------------------------------------------------------------------
select public.report_user('00000000-0000-0000-0000-00000000000a', (select match_id from t), 'Comportement', 'test');
select pg_temp.check(jsonb_array_length(public.get_my_matches()) = 2, 'signalement → match retiré de la liste');
select pg_temp.check((select count(*) from public.messages) = 0, 'RLS : plus d''accès aux messages après blocage');
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
select pg_temp.check(not public.can_see_photos_of('00000000-0000-0000-0000-00000000000b'), 'plus d''accès aux photos après blocage');

-- Accès anonyme ------------------------------------------------------------
reset role;
set role anon;
do $$ begin
  perform public.get_discovery();
  raise exception 'ÉCHEC : anon peut appeler get_discovery';
exception when insufficient_privilege then
  raise notice 'ok  anon ne peut pas appeler l''API';
end $$;
reset role;

\echo 'Tous les tests sont passés.'
