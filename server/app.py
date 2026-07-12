import os
import sqlite3
import secrets
import string
from datetime import datetime
from flask import Flask, request, jsonify, render_template, redirect, url_for, flash, Response

BASE_DIR = os.path.dirname(__file__)
DB_PATH = os.environ.get("LICENSE_DB", os.path.join(BASE_DIR, "license_lab.sqlite3"))
ADMIN_TOKEN = os.environ.get("ADMIN_TOKEN", "changeme")

app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET", "dev-secret")

ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

def db():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    return con

def init_db():
    con = db()
    con.executescript("""
    CREATE TABLE IF NOT EXISTS games (
      appid INTEGER PRIMARY KEY,
      game_name TEXT NOT NULL,
      meta TEXT DEFAULT '{}'
    );
    CREATE TABLE IF NOT EXISTS cdk_codes (
      cdk TEXT PRIMARY KEY,
      appid INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      used_at TEXT,
      machine_id TEXT,
      status TEXT NOT NULL DEFAULT 'unused',
      note TEXT,
      FOREIGN KEY(appid) REFERENCES games(appid)
    );
    CREATE TABLE IF NOT EXISTS activation_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cdk TEXT,
      appid INTEGER,
      machine_id TEXT,
      ok INTEGER NOT NULL,
      msg TEXT,
      created_at TEXT NOT NULL
    );
    """)
    con.execute("INSERT OR IGNORE INTO games(appid, game_name, meta) VALUES(?,?,?)", (1623730, "幻兽帕鲁", "{}"))
    con.commit()
    con.close()

@app.before_request
def ensure_db():
    init_db()

def now():
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"

def gen_cdk():
    raw = ''.join(secrets.choice(ALPHABET) for _ in range(25))
    return '-'.join(raw[i:i+5] for i in range(0, 25, 5))

def require_admin():
    token = request.headers.get("X-Admin-Token") or request.args.get("token") or request.form.get("token")
    return token == ADMIN_TOKEN

@app.post("/api/cdk/validate-v2")
@app.post("/api/cdk/validate/v2")
@app.post("/api/cdk/validate")
def api_validate():
    data = request.get_json(force=True, silent=True) or {}
    cdk = str(data.get("cdk", "")).strip().upper()
    appid = int(data.get("appid", 0))
    machine_id = str(data.get("machine_id", "")).strip()
    con = db()
    row = con.execute("SELECT c.*, g.game_name FROM cdk_codes c JOIN games g ON g.appid=c.appid WHERE c.cdk=? AND c.appid=?", (cdk, appid)).fetchone()
    ok, msg = False, "激活码无效"
    payload = {"success": False, "msg": msg}
    if row:
        if row["status"] == "unused":
            con.execute("UPDATE cdk_codes SET status='used', used_at=?, machine_id=? WHERE cdk=?", (now(), machine_id, cdk))
            ok, msg = True, "ok"
        elif row["status"] == "used" and row["machine_id"] == machine_id:
            ok, msg = True, "already bound to this machine"
        else:
            msg = "激活码已被其他机器使用"
        if ok:
            payload = {
                "success": True,
                "appid": appid,
                "game_name": row["game_name"],
                "license_data": {
                    "cdk": cdk,
                    "machine_id": machine_id,
                    "issued_at": now(),
                    "offline_grace_days": 7,
                    "features": ["base_game"]
                }
            }
        else:
            payload = {"success": False, "msg": msg}
    con.execute("INSERT INTO activation_log(cdk, appid, machine_id, ok, msg, created_at) VALUES(?,?,?,?,?,?)", (cdk, appid, machine_id, int(ok), msg, now()))
    con.commit()
    con.close()
    return jsonify(payload)

@app.get("/api/cdk/user-games")
def api_user_games():
    machine_id = request.args.get("machine_id", "")
    con = db()
    rows = con.execute("""
      SELECT c.appid, g.game_name, c.cdk, c.used_at FROM cdk_codes c
      JOIN games g ON g.appid=c.appid
      WHERE c.machine_id=? AND c.status='used'
      ORDER BY c.used_at DESC
    """, (machine_id,)).fetchall()
    con.close()
    return jsonify({"success": True, "machine_id": machine_id, "games": [dict(r) for r in rows]})

@app.get("/api/cdk/install-apps")
def api_install_apps():
    """Return all games that have available CDK codes — DLL auto-install uses this"""
    con = db()
    rows = con.execute("""
      SELECT DISTINCT g.appid, g.game_name FROM games g
      WHERE EXISTS (SELECT 1 FROM cdk_codes c WHERE c.appid=g.appid)
    """).fetchall()
    con.close()
    return jsonify({"success": True, "apps": [dict(r) for r in rows]})

@app.route("/")
def index():
    if not require_admin():
        return render_template("login.html")
    con = db()
    games = con.execute("SELECT * FROM games ORDER BY appid").fetchall()
    codes = con.execute("SELECT c.*, g.game_name FROM cdk_codes c JOIN games g ON g.appid=c.appid ORDER BY created_at DESC LIMIT 200").fetchall()
    logs = con.execute("SELECT * FROM activation_log ORDER BY id DESC LIMIT 100").fetchall()
    con.close()
    return render_template("index.html", token=ADMIN_TOKEN, games=games, codes=codes, logs=logs)

@app.post("/admin/games")
def add_game():
    if not require_admin(): return "forbidden", 403
    appid = int(request.form["appid"])
    name = request.form["game_name"]
    con = db(); con.execute("INSERT OR REPLACE INTO games(appid, game_name) VALUES(?,?)", (appid, name)); con.commit(); con.close()
    return redirect(url_for("index", token=ADMIN_TOKEN))

@app.post("/admin/cdk/generate")
def generate_codes():
    if not require_admin(): return "forbidden", 403
    appid = int(request.form["appid"])
    count = max(1, min(1000, int(request.form.get("count", 1))))
    con = db()
    made = []
    for _ in range(count):
        c = gen_cdk()
        made.append(c)
        con.execute("INSERT INTO cdk_codes(cdk, appid, created_at, note) VALUES(?,?,?,?)", (c, appid, now(), request.form.get("note", "")))
    con.commit(); con.close()
    flash(f"generated {len(made)} codes")
    return redirect(url_for("index", token=ADMIN_TOKEN))

@app.route("/install")
def install_script():
    script_path = os.path.join(os.path.dirname(__file__), "install.ps1")
    if not os.path.exists(script_path):
        return "install.ps1 not found", 404
    return Response(open(script_path, "r", encoding="utf-8").read(), mimetype="text/plain")

@app.route("/dll/<name>")
def serve_dll(name):
    dll_path = os.path.join(os.path.dirname(BASE_DIR), "dll", name)
    if not os.path.exists(dll_path):
        return f"DLL not found: {dll_path}", 404
    return Response(open(dll_path, "rb").read(), mimetype="application/octet-stream")

if __name__ == "__main__":
    init_db()
    app.run(host="127.0.0.1", port=int(os.environ.get("PORT", 5000)), debug=True)
