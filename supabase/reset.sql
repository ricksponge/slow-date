-- =====================================================================
-- Slow Date — NETTOYAGE COMPLET DE LA BASE (irréversible)
-- ---------------------------------------------------------------------
-- À exécuter UNE fois, AVANT les migrations, dans :
--   Supabase Dashboard > SQL Editor  (ou psql avec la connection string)
--
-- Ce script :
--   1. supprime la tâche planifiée Slow Date si elle existe ;
--   2. supprime TOUT le schéma public (tables, vues, fonctions, types,
--      données) puis le recrée vide avec les droits Supabase standards.
--
-- Il ne touche PAS aux comptes utilisateurs (auth.users) ni aux fichiers
-- du Storage : voir les sections optionnelles en bas.
-- Faites un export (Database > Backups) si quoi que ce soit doit être gardé.
-- =====================================================================

-- 1. Tâche planifiée (si pg_cron est installé)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'slowdate-advance-matches';
  end if;
end $$;

-- 2. Schéma public
drop schema if exists public cascade;
create schema public;

alter schema public owner to postgres;
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on schema public to postgres, service_role;

alter default privileges in schema public grant all on tables    to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to postgres, anon, authenticated, service_role;

-- (Les tables supprimées sortent d'elles-mêmes de la publication Realtime.)

-- =====================================================================
-- OPTIONNEL — décommentez si vous voulez aussi repartir sans utilisateurs
-- =====================================================================
-- delete from auth.users;

-- =====================================================================
-- OPTIONNEL — fichiers du Storage
-- Supabase interdit la suppression des fichiers en SQL : videz puis
-- supprimez les buckets depuis Dashboard > Storage (menu « … » du bucket).
-- =====================================================================
