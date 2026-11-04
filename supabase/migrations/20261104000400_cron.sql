-- =====================================================================
-- Slow Date — 4/4 : horloge serveur
-- Chaque minute : expiration des matchs muets, clôture des fils sans RDV,
-- dévoilement des photos. (Les RPC appellent aussi advance_matches, donc
-- l'état est toujours juste au moment où l'app le lit.)
-- =====================================================================

create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'slowdate-advance-matches',
  '* * * * *',
  $$select public.advance_matches()$$
);
