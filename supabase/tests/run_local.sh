#!/usr/bin/env bash
# Rejoue les migrations + les scénarios sur un Postgres jetable.
#   Sans PostGIS (par défaut) : la géométrie est simulée, les tests géo sont sautés.
#   WITH_POSTGIS=1            : migrations réelles + tests de voisinage et mi-chemin.
# Usage : PGHOST=... PGPORT=... PGUSER=postgres [WITH_POSTGIS=1] ./supabase/tests/run_local.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DB=slowdate_test
psql -q -c "drop database if exists $DB" -c "create database $DB"
P="psql -q -v ON_ERROR_STOP=1 -d $DB"
NOTICES='s/^psql:[^ ]* NOTICE:  /  /'

$P -f tests/local_stub.sql

if [ "${WITH_POSTGIS:-0}" = "1" ]; then
  $P -f migrations/20261104000100_communes.sql
  $P -f migrations/20261104000200_core.sql
  $P -f migrations/20261104000300_meeting_point.sql
else
  $P -c "create schema extensions; create extension unaccent with schema extensions;"
  sed -e '/create extension if not exists postgis/d' \
      -e 's/extensions.geometry(MultiPolygon, 4326)/text/' \
      -e '/communes_geom_idx/d' \
      -e '/create extension if not exists unaccent/d' \
      migrations/20261104000100_communes.sql | $P
  $P -f migrations/20261104000200_core.sql
fi
# 4/4 (pg_cron) : propre à Supabase, non rejoué ici

$P -P tuples_only=on -P format=unaligned -o /dev/null -f tests/scenario.sql 2>&1 | sed -E "$NOTICES"

if [ "${WITH_POSTGIS:-0}" = "1" ]; then
  $P -P tuples_only=on -P format=unaligned -o /dev/null -f tests/postgis_scenario.sql 2>&1 | sed -E "$NOTICES"
fi
