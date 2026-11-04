#!/usr/bin/env python3
"""
Importe les communes françaises (contours officiels de geo.api.gouv.fr) dans
Supabase, puis calcule les communes limitrophes.

    pip install "psycopg[binary]"
    export SUPABASE_DB_URL="postgresql://postgres.<ref>:<mot-de-passe>@<hôte>:5432/postgres"
    python scripts/import_communes.py                    # toute la France (~35 000 communes)
    python scripts/import_communes.py --departements 75,92,93,94   # pour tester vite

La connection string se trouve dans Supabase > Connect > « Session pooler »
(port 5432). N'utilisez pas le « Transaction pooler » (6543) : le calcul des
voisinages est une longue requête.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.request

try:
    import psycopg
except ImportError:
    sys.exit('Installez d\'abord psycopg :  pip install "psycopg[binary]"')

API = "https://geo.api.gouv.fr"

INSERT_SQL = """
insert into public.communes (code, nom, nom_normalise, codes_postaux, departement, lat, lng, geom)
select %(code)s, %(nom)s, public.normalize_txt(%(nom)s), %(cps)s, %(dep)s,
       extensions.st_y(extensions.st_pointonsurface(g)),
       extensions.st_x(extensions.st_pointonsurface(g)),
       g
from (
  select extensions.st_multi(
           extensions.st_collectionextract(
             extensions.st_makevalid(
               extensions.st_setsrid(extensions.st_geomfromgeojson(%(geojson)s), 4326)), 3)) as g
) s
on conflict (code) do update set
  nom = excluded.nom, nom_normalise = excluded.nom_normalise,
  codes_postaux = excluded.codes_postaux, departement = excluded.departement,
  lat = excluded.lat, lng = excluded.lng, geom = excluded.geom
"""


def fetch_json(url: str, retries: int = 4):
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "slow-date-import/1.0"})
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.load(resp)
        except Exception as exc:  # réseau capricieux : on réessaie
            if attempt == retries - 1:
                raise
            wait = 2 ** attempt
            print(f"  ! {exc} — nouvel essai dans {wait}s", file=sys.stderr)
            time.sleep(wait)


def departements(selection: str | None) -> list[str]:
    if selection:
        return [d.strip().upper() for d in selection.split(",") if d.strip()]
    return [d["code"] for d in fetch_json(f"{API}/departements?fields=code")]


def communes_of(dep: str) -> list[dict]:
    url = (f"{API}/departements/{dep}/communes"
           "?fields=nom,code,codesPostaux,codeDepartement&format=geojson&geometry=contour")
    data = fetch_json(url)
    rows = []
    for feat in data.get("features", []):
        geom = feat.get("geometry")
        props = feat.get("properties", {})
        if not geom:
            print(f"  - {props.get('nom')} ({props.get('code')}) sans contour, ignorée")
            continue
        rows.append({
            "code": props["code"],
            "nom": props["nom"],
            "cps": props.get("codesPostaux") or [],
            "dep": props.get("codeDepartement") or dep,
            "geojson": json.dumps(geom),
        })
    return rows


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db-url", default=os.environ.get("SUPABASE_DB_URL"),
                    help="connection string Postgres (défaut : $SUPABASE_DB_URL)")
    ap.add_argument("--departements", help="liste de départements, ex. 75,92,93,94 (défaut : tous)")
    ap.add_argument("--tolerance", type=float, default=30.0,
                    help="distance max (m) entre deux contours pour être voisines (défaut : 30)")
    ap.add_argument("--skip-neighbors", action="store_true", help="ne pas recalculer les voisinages")
    args = ap.parse_args()

    if not args.db_url:
        sys.exit("Indiquez --db-url ou définissez SUPABASE_DB_URL.")

    deps = departements(args.departements)
    print(f"{len(deps)} département(s) à importer")

    total = 0
    with psycopg.connect(args.db_url, autocommit=False) as conn:
        conn.execute("set statement_timeout = 0")
        for i, dep in enumerate(deps, 1):
            rows = communes_of(dep)
            with conn.cursor() as cur:
                cur.executemany(INSERT_SQL, rows)
            conn.commit()
            total += len(rows)
            print(f"[{i:>3}/{len(deps)}] {dep:>3} : {len(rows):>4} communes")

        print(f"{total} communes importées.")

        if not args.skip_neighbors:
            print("Calcul des communes limitrophes (quelques minutes pour toute la France)…")
            t0 = time.time()
            n = conn.execute("select public.rebuild_commune_neighbors(%s)", (args.tolerance,)).fetchone()[0]
            conn.commit()
            print(f"{n} liens de voisinage en {time.time() - t0:.0f}s.")

            sample = conn.execute("""
                select c.nom, string_agg(v.nom, ', ' order by v.nom)
                from public.communes c
                join public.commune_neighbors n on n.code = c.code
                join public.communes v on v.code = n.neighbor_code
                group by c.code, c.nom order by random() limit 3
            """).fetchall()
            for nom, voisines in sample:
                print(f"  ex. {nom} ↔ {voisines}")


if __name__ == "__main__":
    main()
