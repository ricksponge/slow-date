-- =====================================================================
-- Slow Date — 1/4 : communes françaises et voisinage strict
-- Rempli par scripts/import_communes.py (contours geo.api.gouv.fr)
-- =====================================================================

create schema if not exists extensions;
create extension if not exists postgis  with schema extensions;
create extension if not exists unaccent with schema extensions;

-- Normalisation pour la recherche : minuscules, sans accents ni ponctuation
create or replace function public.normalize_txt(p text)
returns text
language sql
stable
set search_path = public, extensions
as $$
  select btrim(regexp_replace(lower(extensions.unaccent(coalesce(p, ''))), '[^a-z0-9]+', ' ', 'g'))
$$;

create table public.communes (
  code          text primary key,                 -- code INSEE
  nom           text not null,
  nom_normalise text not null,
  codes_postaux text[] not null default '{}',
  departement   text,
  lat           double precision not null,        -- point intérieur (pas le centroïde brut)
  lng           double precision not null,
  geom          extensions.geometry(MultiPolygon, 4326)
);

create index communes_geom_idx on public.communes using gist (geom);
create index communes_nom_idx  on public.communes (nom_normalise text_pattern_ops);
create index communes_cp_idx   on public.communes using gin (codes_postaux);

-- Voisinage : la commune elle-même n'y figure pas (ajoutée à la volée)
create table public.commune_neighbors (
  code          text not null references public.communes (code) on delete cascade,
  neighbor_code text not null references public.communes (code) on delete cascade,
  primary key (code, neighbor_code),
  check (code <> neighbor_code)
);

alter table public.communes          enable row level security;
alter table public.commune_neighbors enable row level security;

create policy "communes lisibles" on public.communes
  for select to authenticated using (true);
create policy "voisinage lisible" on public.commune_neighbors
  for select to authenticated using (true);

-- Recalcule toutes les adjacences (communes qui se touchent, à `tolerance_m` près,
-- pour absorber les petits défauts des contours simplifiés).
-- Long sur toute la France : à lancer depuis psql avec statement_timeout = 0.
create or replace function public.rebuild_commune_neighbors(tolerance_m double precision default 30)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  n integer;
begin
  truncate public.commune_neighbors;

  insert into public.commune_neighbors (code, neighbor_code)
  select a.code, b.code
  from public.communes a
  join public.communes b
    on a.code <> b.code
   and a.geom && st_expand(b.geom, 0.002)                       -- pré-filtre index (≈ 200 m)
   and st_dwithin(a.geom::geography, b.geom::geography, tolerance_m)
  where a.geom is not null and b.geom is not null;

  get diagnostics n = row_count;
  return n;
end
$$;

-- Recherche par nom (préfixe, sans accents) ou par code postal
create or replace function public.search_communes(p_query text, p_limit int default 15)
returns table (code text, nom text, codes_postaux text[], departement text)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with q as (select btrim(coalesce(p_query, '')) as raw, public.normalize_txt(p_query) as norm)
  select c.code, c.nom, c.codes_postaux, c.departement
  from public.communes c, q
  where (q.raw ~ '^\d{2,5}$'
         and exists (select 1 from unnest(c.codes_postaux) cp where cp like q.raw || '%'))
     or (q.raw !~ '^\d' and char_length(q.norm) >= 2 and c.nom_normalise like q.norm || '%')
  order by (c.nom_normalise = q.norm) desc, char_length(c.nom), c.nom
  limit least(greatest(p_limit, 1), 50)
$$;

revoke execute on function public.rebuild_commune_neighbors(double precision) from public, anon, authenticated;
revoke execute on function public.search_communes(text, int) from public, anon;
grant  execute on function public.search_communes(text, int) to authenticated;
