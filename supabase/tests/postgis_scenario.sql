-- Vérifications PostGIS (voisinage, point à mi-chemin). Lancé après scenario.sql
-- par run_local.sh quand WITH_POSTGIS=1 (en CI, image postgis/postgis).
\set ON_ERROR_STOP 1
\set QUIET 1

create or replace function pg_temp.check(cond boolean, label text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'ÉCHEC : %', label; end if;
  raise notice 'ok  %', label;
end $$;

-- Contours simplifiés : Boulogne et Paris se touchent en lng 2.26, Marseille est loin
update public.communes set geom = extensions.st_multi(extensions.st_makeenvelope(2.20, 48.82, 2.26, 48.85, 4326)) where code = '92012';
update public.communes set geom = extensions.st_multi(extensions.st_makeenvelope(2.26, 48.82, 2.42, 48.90, 4326)) where code = '75056';
update public.communes set geom = extensions.st_multi(extensions.st_makeenvelope(5.30, 43.20, 5.50, 43.40, 4326)) where code = '13055';

select pg_temp.check(public.rebuild_commune_neighbors() = 2, 'voisinage recalculé : Boulogne ↔ Paris uniquement');
select pg_temp.check(not exists (select 1 from public.commune_neighbors where '13055' in (code, neighbor_code)),
                     'Marseille sans voisine');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
set role authenticated;
select pg_temp.check(
  public.suggest_meeting_point((select id from public.matches
                                where user_a = '00000000-0000-0000-0000-00000000000a'
                                  and user_b = '00000000-0000-0000-0000-00000000000b'))->>'commune' = 'Paris',
  'point à mi-chemin Boulogne / Paris situé dans Paris');
reset role;

\echo 'Tests PostGIS passés.'
