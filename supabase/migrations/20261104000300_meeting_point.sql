-- =====================================================================
-- Slow Date — 3/4 : suggestion de lieu de rendez-vous à mi-chemin
-- Point milieu entre les deux communes → commune qui le contient
-- (ou la plus proche). L'app propose ensuite d'y chercher un café, un parc…
-- =====================================================================

create or replace function public.suggest_meeting_point(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_me  uuid := public.require_user();
  m     public.matches;
  ca    public.communes;
  cb    public.communes;
  v_mid extensions.geometry;
  v_c   public.communes;
begin
  select * into m from public.matches where id = p_match_id;
  if not found or v_me not in (m.user_a, m.user_b) then
    raise exception 'Conversation introuvable.';
  end if;

  select c.* into ca from public.communes c join public.profiles p on p.commune_code = c.code where p.id = m.user_a;
  select c.* into cb from public.communes c join public.profiles p on p.commune_code = c.code where p.id = m.user_b;

  if ca.code = cb.code then
    return jsonb_build_object('same_commune', true, 'commune', ca.nom, 'code', ca.code,
                              'lat', ca.lat, 'lng', ca.lng, 'from', ca.nom, 'to', cb.nom);
  end if;

  v_mid := st_setsrid(st_makepoint((ca.lng + cb.lng) / 2, (ca.lat + cb.lat) / 2), 4326);

  select c.* into v_c from public.communes c
  where c.geom is not null and st_intersects(c.geom, v_mid)
  limit 1;

  if not found then
    select c.* into v_c from public.communes c
    where c.geom is not null
    order by c.geom <-> v_mid
    limit 1;
  end if;

  return jsonb_build_object('same_commune', false, 'commune', v_c.nom, 'code', v_c.code,
                            'lat', st_y(v_mid), 'lng', st_x(v_mid), 'from', ca.nom, 'to', cb.nom);
end
$$;

revoke execute on function public.suggest_meeting_point(uuid) from public, anon;
grant  execute on function public.suggest_meeting_point(uuid) to authenticated;
