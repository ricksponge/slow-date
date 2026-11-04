"""Test de bout en bout contre le vrai projet Supabase, en passant par les mêmes
API que l'app Flutter (clé publishable + JWT utilisateur). Crée 2 comptes de
test puis les supprime.

    export SUPABASE_PUBLISHABLE_KEY=sb_publishable_...  SUPABASE_SECRET_KEY=sb_secret_...
    export SUPABASE_ACCESS_TOKEN=sbp_...
    python scripts/e2e_supabase.py
"""
import datetime, json, os, ssl, struct, sys, urllib.request, zlib

URL = os.environ.get("SUPABASE_URL", "https://pshxbltlhwsjfjbnoyzj.supabase.co")
PUB = os.environ["SUPABASE_PUBLISHABLE_KEY"]
SECRET = os.environ["SUPABASE_SECRET_KEY"]          # admin : création/suppression des comptes de test
ACCESS_TOKEN = os.environ["SUPABASE_ACCESS_TOKEN"]  # sbp_… : avance l'horloge d'un match en SQL
PROJECT_REF = URL.split("//")[1].split(".")[0]
ctx = ssl.create_default_context()


def call(method, path, body=None, token=None, key=PUB, raw=None, ctype="application/json"):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    h = {"apikey": key, "Content-Type": ctype}
    if token:
        h["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(URL + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=60) as r:
            t = r.read().decode()
            return r.status, (json.loads(t) if t else None)
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try:
            return e.code, json.loads(t)
        except Exception:
            return e.code, t


def sql(query):
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query",
        data=json.dumps({"query": query}).encode(), method="POST",
        headers={"Authorization": f"Bearer {ACCESS_TOKEN}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, context=ctx, timeout=60) as r:
        return json.loads(r.read().decode())


def check(cond, label, extra=""):
    print(("ok  " if cond else "ÉCHEC ") + label + (f"  → {extra}" if not cond and extra else ""), flush=True)
    if not cond:
        raise SystemExit(1)


def rpc(tok, fn, **params):
    return call("POST", f"/rest/v1/rpc/{fn}", params, tok)


def png():
    raw = b"\x00\xff\x80\x40"
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


users = {}
try:
    # 0. Anonyme : rien d'accessible
    s, r = call("POST", "/rest/v1/rpc/get_discovery", {})
    check(s in (401, 403, 404), "anonyme : API refusée", f"{s} {r}")

    # 1. Deux comptes de test (admin API), connexion par mot de passe
    for name in ("test-alice", "test-bob"):
        s, r = call("POST", "/auth/v1/admin/users",
                    {"email": f"{name}@slowdate.test", "password": "Test-Slow-Date-1!", "email_confirm": True},
                    token=SECRET, key=SECRET)
        check(s in (200, 201), f"compte {name} créé", f"{s} {r}")
        uid = r["id"]
        s, r = call("POST", "/auth/v1/token?grant_type=password",
                    {"email": f"{name}@slowdate.test", "password": "Test-Slow-Date-1!"})
        check(s == 200, f"{name} connecté", f"{s} {r}")
        users[name] = (uid, r["access_token"])

    (ua, ta), (ub, tb) = users["test-alice"], users["test-bob"]

    # 2. Profils (RLS : chacun écrit le sien)
    for (uid, tok, prenom, g, seek, commune) in ((ua, ta, "Alice", "femme", ["homme"], "92012"),
                                                 (ub, tb, "Bob", "homme", ["femme"], "75056")):
        s, r = call("POST", "/rest/v1/profiles", {"id": uid, "first_name": prenom, "birthdate": "1992-03-04",
                    "gender": g, "seeking": seek, "commune_code": commune, "bio": "Test"}, tok)
        check(s == 201, f"profil {prenom} enregistré", f"{s} {r}")
        s, qs = call("GET", "/rest/v1/questions?select=id&order=position", token=tok)
        for q in qs[:3]:
            s, r = call("POST", "/rest/v1/answers", {"user_id": uid, "question_id": q["id"], "answer": "Une vraie réponse"}, tok)
            check(s == 201, f"réponse {prenom} q{q['id']}", f"{s} {r}")
        path = f"{uid}/test.png"
        s, r = call("POST", f"/storage/v1/object/photos/{path}", token=tok, raw=png(), ctype="image/png")
        check(s == 200, f"photo {prenom} envoyée dans le bucket privé", f"{s} {r}")
        s, r = call("POST", "/rest/v1/profile_photos", {"user_id": uid, "storage_path": path}, tok)
        check(s == 201, f"photo {prenom} référencée", f"{s} {r}")
        s, r = rpc(tok, "get_my_profile")
        check(r.get("complete") is True, f"profil {prenom} complet", r)

    # 3. Découverte et photos cachées
    s, r = rpc(ta, "get_discovery")
    names = [p["first_name"] for p in r.get("profiles", [])]
    check("Bob" in names, "Alice (Boulogne) découvre Bob (Paris, commune voisine)", r)
    s, r = call("POST", f"/storage/v1/object/sign/photos/{ub}/test.png", {"expiresIn": 60}, ta)
    check(s >= 400, "Alice ne peut PAS obtenir la photo de Bob avant le match", f"{s} {r}")

    # 4. Match
    s, r = rpc(ta, "decide", p_target=ub, p_like=True)
    check(s == 200 and r["matched"] is False, "Alice : « j'aimerais échanger »", r)
    s, r = rpc(tb, "decide", p_target=ua, p_like=True)
    check(s == 200 and r["matched"] is True, "Bob aussi → match", r)
    mid = r["match_id"]

    # 5. Discussion
    s, r = rpc(ta, "send_message", p_match_id=mid, p_body="Bonjour Bob !")
    check(s == 200, "premier message", r)
    s, r = rpc(tb, "get_match", p_match_id=mid)
    check(r["status"] == "talking" and r["last_message"]["body"] == "Bonjour Bob !", "Bob voit la discussion lancée", r)
    s, r = call("GET", f"/rest/v1/messages?match_id=eq.{mid}&select=body", token=tb)
    check(s == 200 and len(r) == 1, "lecture des messages via RLS (comme le Realtime)", r)
    s, r = rpc(ta, "suggest_meeting_point", p_match_id=mid)
    check(s == 200 and r.get("commune"), f"point à mi-chemin : {r.get('commune')}", r)
    for i in range(3):
        rpc(ta, "send_message", p_match_id=mid, p_body=f"a{i}")
        rpc(tb, "send_message", p_match_id=mid, p_body=f"b{i}")

    # 6. On avance l'horloge de 25 h côté serveur → photos dévoilées
    sql(f"update public.matches set photos_unlock_at = now() - interval '1 minute' where id = '{mid}'")
    s, r = rpc(ta, "get_match", p_match_id=mid)
    check(r["photos_unlocked"] is True and len(r["photos"]) == 1, "après 24 h : photos dévoilées", r)
    s, r = call("POST", f"/storage/v1/object/sign/photos/{ub}/test.png", {"expiresIn": 60}, ta)
    check(s == 200 and "signedURL" in str(r), "Alice obtient maintenant la photo de Bob", f"{s} {r}")

    # 7. Rendez-vous
    s, r = rpc(ta, "propose_date", p_match_id=mid, p_place_name="Café test", p_place_address=None,
               p_meeting_at="2030-01-01T18:00:00Z")
    check(s >= 400, "RDV trop lointain refusé", r)
    when = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=2)).isoformat()
    s, r = rpc(ta, "propose_date", p_match_id=mid, p_place_name="Café test", p_place_address="1 rue Test",
               p_meeting_at=when)
    check(s == 200, "Alice propose un RDV", r)
    s, r = rpc(tb, "respond_date", p_proposal_id=r["id"], p_accept=True)
    check(s == 200 and r["status"] == "date_confirmed", "Bob accepte → RDV confirmé", r)

    # 8. Écriture directe interdite
    s, r = call("POST", "/rest/v1/messages", {"match_id": mid, "sender_id": ua, "body": "triche"}, ta)
    check(s >= 400, "écriture directe dans messages refusée (passage obligé par les règles)", f"{s}")
    call("PATCH", f"/rest/v1/matches?id=eq.{mid}", {"status": "talking"}, ta)
    s, r = rpc(ta, "get_match", p_match_id=mid)
    check(r["status"] == "date_confirmed", "modification directe d'un match sans effet (RLS)", r.get("status"))
    print("\nTous les tests de bout en bout sont passés.")
finally:
    # Nettoyage : fichiers puis comptes
    for name, (uid, tok) in users.items():
        call("DELETE", "/storage/v1/object/photos", {"prefixes": [f"{uid}/test.png"]}, tok)
        s, _ = call("DELETE", f"/auth/v1/admin/users/{uid}", token=SECRET, key=SECRET)
        print(f"nettoyage {name} : {s}")
