#!/usr/bin/env python3
"""RJ Furz-App Partner Backend v2.0

Small self-hosted FastAPI server for a private group of Furz-App users.
Data is stored as human-readable JSON files plus audio files under ./furz_data.
On first start a config file is generated and the server exits. Review it,
set setup_complete=true, then start again.

This backend intentionally has no public registration and no external cloud
services. Every account login requires the shared server master password.
Use HTTPS via a reverse proxy (nginx/Caddy/Cloudflare Tunnel) when reachable
outside your LAN.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import shutil
import sys
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

try:
    from fastapi import FastAPI, HTTPException, Request, Depends
    from fastapi.responses import FileResponse, JSONResponse
    import uvicorn
except ImportError:
    print("Missing dependencies. Install with: pip install fastapi uvicorn")
    raise

APP_VERSION = "2.0.0"
ROOT = Path(__file__).resolve().parent
CONFIG_PATH = ROOT / "furz_backend_config.json"
USERNAME_RE = re.compile(r"^[A-Za-z0-9_.-]{2,32}$")
LOCK = threading.RLock()


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime | None = None) -> str:
    return (dt or utcnow()).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def atomic_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temp, path)


def read_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def create_config() -> None:
    if CONFIG_PATH.exists():
        return
    config = {
        "setup_complete": False,
        "server_password": secrets.token_urlsafe(24),
        "bind_host": "0.0.0.0",
        "port": 8788,
        "data_directory": "furz_data",
        "token_days": 90,
        "max_audio_mb": 25,
        "allow_account_creation": True,
        "server_name": "Private RJ Furzfreunde",
    }
    atomic_json(CONFIG_PATH, config)
    print("\nRJ Furz Backend: first-start configuration created:")
    print(f"  {CONFIG_PATH}")
    print("Review server_password/port and set setup_complete to true, then restart.")
    print(f"Generated server password: {config['server_password']}\n")


create_config()
CONFIG = read_json(CONFIG_PATH, {})
if not CONFIG.get("setup_complete"):
    if __name__ == "__main__":
        print(f"Setup is not complete. Edit {CONFIG_PATH.name}, set setup_complete=true, then restart.")
        sys.exit(0)

DATA = ROOT / str(CONFIG.get("data_directory", "furz_data"))
USERS = DATA / "users"
FARTS = DATA / "farts"
AUDIO = DATA / "audio"
SESSIONS = DATA / "sessions.json"
for d in (USERS, FARTS, AUDIO):
    d.mkdir(parents=True, exist_ok=True)


def clean_username(name: str) -> str:
    name = name.strip()
    if not USERNAME_RE.fullmatch(name):
        raise HTTPException(400, "Benutzername: 2–32 Zeichen, nur Buchstaben, Zahlen, _, . und -")
    return name


def user_path(username: str) -> Path:
    return USERS / f"{clean_username(username)}.json"


def fart_path(username: str) -> Path:
    return FARTS / f"{clean_username(username)}.json"


def load_user(username: str) -> dict[str, Any] | None:
    p = user_path(username)
    return read_json(p, None) if p.exists() else None


def save_user(user: dict[str, Any]) -> None:
    atomic_json(user_path(user["username"]), user)


def all_users() -> list[dict[str, Any]]:
    result = []
    for p in USERS.glob("*.json"):
        u = read_json(p, None)
        if isinstance(u, dict) and u.get("username"):
            result.append(u)
    return result


def load_farts(username: str) -> list[dict[str, Any]]:
    return read_json(fart_path(username), [])


def save_farts(username: str, items: list[dict[str, Any]]) -> None:
    atomic_json(fart_path(username), items)


def load_sessions() -> dict[str, Any]:
    return read_json(SESSIONS, {})


def save_sessions(value: dict[str, Any]) -> None:
    atomic_json(SESSIONS, value)


def purge_sessions() -> None:
    with LOCK:
        sessions = load_sessions()
        now = utcnow()
        keep = {}
        for token, item in sessions.items():
            exp = parse_iso(item.get("expiresAt"))
            if exp and exp > now and load_user(item.get("username", "")):
                keep[token] = item
        if keep != sessions:
            save_sessions(keep)


def issue_token(username: str) -> str:
    with LOCK:
        purge_sessions()
        token = secrets.token_urlsafe(40)
        sessions = load_sessions()
        days = max(1, int(CONFIG.get("token_days", 90)))
        sessions[token] = {"username": username, "expiresAt": iso(utcnow() + timedelta(days=days))}
        save_sessions(sessions)
        return token


async def current_user(request: Request) -> dict[str, Any]:
    header = request.headers.get("authorization", "")
    if not header.lower().startswith("bearer "):
        raise HTTPException(401, "Anmeldung erforderlich")
    token = header.split(" ", 1)[1].strip()
    sessions = load_sessions()
    session = sessions.get(token)
    if not session:
        raise HTTPException(401, "Sitzung ungültig oder abgelaufen")
    exp = parse_iso(session.get("expiresAt"))
    if not exp or exp <= utcnow():
        sessions.pop(token, None)
        save_sessions(sessions)
        raise HTTPException(401, "Sitzung abgelaufen")
    user = load_user(session.get("username", ""))
    if not user:
        raise HTTPException(401, "Konto nicht mehr vorhanden")
    return user


def verify_server_password(value: str) -> None:
    expected = str(CONFIG.get("server_password", ""))
    if not expected or not secrets.compare_digest(value, expected):
        raise HTTPException(403, "Hauptpasswort ist falsch")


def are_friends(a: dict[str, Any], b: str) -> bool:
    return b in a.get("friends", [])


def visible_people(user: dict[str, Any]) -> list[str]:
    return [user["username"]] + [x for x in user.get("friends", []) if load_user(x)]


def presence_view(viewer: dict[str, Any], target: dict[str, Any]) -> dict[str, Any]:
    p = target.get("presence", {})
    location_allowed = target["username"] == viewer["username"] or (are_friends(viewer, target["username"]) and p.get("shareLocation", False))
    battery_allowed = target["username"] == viewer["username"] or (are_friends(viewer, target["username"]) and p.get("shareBattery", False))
    return {
        "battery": p.get("battery") if battery_allowed else None,
        "latitude": p.get("latitude") if location_allowed else None,
        "longitude": p.get("longitude") if location_allowed else None,
        "locationUpdatedAt": p.get("updatedAt") if location_allowed else None,
        "lastFartAt": p.get("lastFartAt"),
    }


def recent_stats(username: str, days: int) -> tuple[int, int, float, float]:
    cutoff = utcnow() - timedelta(days=days)
    items = [f for f in load_farts(username) if (parse_iso(f.get("eventDate")) or datetime.min.replace(tzinfo=timezone.utc)) >= cutoff]
    score = 0
    smells, ratings = [], []
    loud_map = {"Leise": 1, "Mittel": 2, "Laut": 3, "Nuklear": 4}
    for f in items:
        smell = int(f.get("smellRating", 1))
        rating = int(f.get("personalRating", 3))
        duration = min(int(round(float(f.get("duration", 0)))), 25)
        score += loud_map.get(str(f.get("loudness", "Mittel")), 2) * 10 + smell * 6 + rating * 5 + duration
        smells.append(smell); ratings.append(rating)
    return len(items), score, (sum(smells)/len(smells) if smells else 0.0), (sum(ratings)/len(ratings) if ratings else 0.0)


app = FastAPI(title="RJ Furz-App Partner Backend", version=APP_VERSION, docs_url="/docs", redoc_url=None)


@app.get("/api/ping")
def ping() -> dict[str, Any]:
    return {"ok": True, "version": APP_VERSION, "serverName": CONFIG.get("server_name", "RJ Furzfreunde"), "time": iso()}


@app.post("/api/account/register")
async def register(request: Request) -> dict[str, Any]:
    body = await request.json()
    username = clean_username(str(body.get("username", "")))
    verify_server_password(str(body.get("serverPassword", "")))
    if not CONFIG.get("allow_account_creation", True):
        raise HTTPException(403, "Neue Konten sind auf diesem Server deaktiviert")
    with LOCK:
        if load_user(username):
            raise HTTPException(409, "Benutzername existiert bereits")
        user = {
            "username": username,
            "createdAt": iso(),
            "friends": [],
            "incoming": [],
            "outgoing": [],
            "presence": {"shareLocation": False, "shareBattery": False, "updatedAt": None, "lastFartAt": None},
            "nudges": [],
        }
        save_user(user)
    return {"token": issue_token(username), "username": username, "created": True}


@app.post("/api/account/login")
async def login(request: Request) -> dict[str, Any]:
    body = await request.json()
    username = clean_username(str(body.get("username", "")))
    verify_server_password(str(body.get("serverPassword", "")))
    if not load_user(username):
        raise HTTPException(404, "Benutzer existiert nicht")
    return {"token": issue_token(username), "username": username, "created": False}


@app.delete("/api/account")
def delete_account(user: dict[str, Any] = Depends(current_user)) -> dict[str, bool]:
    username = user["username"]
    with LOCK:
        for other in all_users():
            if other["username"] == username:
                continue
            changed = False
            for key in ("friends", "incoming", "outgoing"):
                old = other.get(key, [])
                new = [x for x in old if x != username]
                if new != old:
                    other[key] = new; changed = True
            if changed:
                save_user(other)
        user_path(username).unlink(missing_ok=True)
        fart_path(username).unlink(missing_ok=True)
        shutil.rmtree(AUDIO / username, ignore_errors=True)
        sessions = {k: v for k, v in load_sessions().items() if v.get("username") != username}
        save_sessions(sessions)
    return {"ok": True}


@app.get("/api/friends")
def friends(user: dict[str, Any] = Depends(current_user)) -> list[dict[str, Any]]:
    out = []
    today = utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    for name in user.get("friends", []):
        target = load_user(name)
        if not target:
            continue
        items = load_farts(name)
        today_count = sum(1 for f in items if (parse_iso(f.get("eventDate")) or datetime.min.replace(tzinfo=timezone.utc)) >= today)
        c7, s7, _, _ = recent_stats(name, 7)
        p = presence_view(user, target)
        out.append({"username": name, "status": "friends", "todayCount": today_count, "sevenDayCount": c7, "score7d": s7, **p})
    return out


@app.get("/api/friends/requests")
def friend_requests(user: dict[str, Any] = Depends(current_user)) -> dict[str, list[str]]:
    return {"incoming": user.get("incoming", []), "outgoing": user.get("outgoing", [])}


@app.post("/api/friends/request/{target_name}")
def friend_request(target_name: str, user: dict[str, Any] = Depends(current_user)) -> dict[str, bool]:
    target_name = clean_username(target_name)
    if target_name == user["username"]:
        raise HTTPException(400, "Du kannst dich nicht selbst hinzufügen")
    target = load_user(target_name)
    if not target:
        raise HTTPException(404, "Benutzer nicht gefunden")
    with LOCK:
        user = load_user(user["username"]) or user
        target = load_user(target_name) or target
        if target_name in user.get("friends", []):
            return {"ok": True}
        if target_name not in user.setdefault("outgoing", []): user["outgoing"].append(target_name)
        if user["username"] not in target.setdefault("incoming", []): target["incoming"].append(user["username"])
        save_user(user); save_user(target)
    return {"ok": True}


@app.post("/api/friends/accept/{requester}")
def friend_accept(requester: str, user: dict[str, Any] = Depends(current_user)) -> dict[str, bool]:
    requester = clean_username(requester)
    other = load_user(requester)
    if not other or requester not in user.get("incoming", []):
        raise HTTPException(404, "Keine passende Anfrage")
    with LOCK:
        user = load_user(user["username"]) or user; other = load_user(requester) or other
        user["incoming"] = [x for x in user.get("incoming", []) if x != requester]
        other["outgoing"] = [x for x in other.get("outgoing", []) if x != user["username"]]
        if requester not in user.setdefault("friends", []): user["friends"].append(requester)
        if user["username"] not in other.setdefault("friends", []): other["friends"].append(user["username"])
        save_user(user); save_user(other)
    return {"ok": True}


@app.post("/api/friends/decline/{requester}")
def friend_decline(requester: str, user: dict[str, Any] = Depends(current_user)) -> dict[str, bool]:
    requester = clean_username(requester); other = load_user(requester)
    with LOCK:
        user = load_user(user["username"]) or user
        user["incoming"] = [x for x in user.get("incoming", []) if x != requester]
        save_user(user)
        if other:
            other["outgoing"] = [x for x in other.get("outgoing", []) if x != user["username"]]
            save_user(other)
    return {"ok": True}


@app.delete("/api/friends/{friend_name}")
def friend_remove(friend_name: str, user: dict[str, Any] = Depends(current_user)) -> dict[str, bool]:
    friend_name = clean_username(friend_name); other = load_user(friend_name)
    with LOCK:
        user = load_user(user["username"]) or user
        user["friends"] = [x for x in user.get("friends", []) if x != friend_name]
        save_user(user)
        if other:
            other["friends"] = [x for x in other.get("friends", []) if x != user["username"]]
            save_user(other)
    return {"ok": True}


@app.post("/api/presence")
async def presence(request: Request, user: dict[str, Any] = Depends(current_user)) -> dict[str, bool]:
    body = await request.json()
    share_location = bool(body.get("shareLocation", False))
    share_battery = bool(body.get("shareBattery", False))
    p = {
        "shareLocation": share_location,
        "shareBattery": share_battery,
        "latitude": float(body["latitude"]) if share_location and body.get("latitude") is not None else None,
        "longitude": float(body["longitude"]) if share_location and body.get("longitude") is not None else None,
        "battery": max(0, min(100, int(body["battery"]))) if share_battery and body.get("battery") is not None else None,
        "lastFartAt": body.get("lastFartAt"),
        "updatedAt": iso(),
    }
    user = load_user(user["username"]) or user; user["presence"] = p; save_user(user)
    return {"ok": True}


@app.post("/api/farts")
async def create_fart(request: Request, user: dict[str, Any] = Depends(current_user)) -> dict[str, str]:
    body = await request.json()
    fart_id = secrets.token_urlsafe(12)
    record = {
        "id": fart_id,
        "localID": str(body.get("localID", ""))[:80],
        "owner": user["username"],
        "title": str(body.get("title", "Furz 💨"))[:120],
        "eventDate": body.get("eventDate") or iso(),
        "loudness": str(body.get("loudness", "Mittel"))[:20],
        "smellRating": max(1, min(5, int(body.get("smellRating", 3)))),
        "personalRating": max(1, min(5, int(body.get("personalRating", 3)))),
        "duration": max(0.0, min(3600.0, float(body.get("duration", 0)))),
        "notes": str(body.get("notes", ""))[:4000],
        "context": str(body.get("context", ""))[:500],
        "address": str(body.get("address", ""))[:500],
        "geofence": str(body.get("geofence", ""))[:120],
        "latitude": body.get("latitude"),
        "longitude": body.get("longitude"),
        "hasAudio": False,
        "comments": [],
        "createdAt": iso(),
    }
    with LOCK:
        items = load_farts(user["username"])
        # Idempotent-ish: update an existing record from the same localID.
        existing = next((x for x in items if record["localID"] and x.get("localID") == record["localID"]), None)
        if existing:
            fart_id = existing["id"]
            record["id"] = fart_id
            record["hasAudio"] = existing.get("hasAudio", False)
            record["comments"] = existing.get("comments", [])
            items[items.index(existing)] = record
        else:
            items.append(record)
        save_farts(user["username"], items[-5000:])
    return {"id": fart_id}


@app.put("/api/farts/{fart_id}/audio")
async def upload_audio(fart_id: str, request: Request, user: dict[str, Any] = Depends(current_user)) -> dict[str, bool]:
    data = await request.body()
    max_size = max(1, int(CONFIG.get("max_audio_mb", 25))) * 1024 * 1024
    if len(data) > max_size:
        raise HTTPException(413, "Audiodatei ist zu groß")
    with LOCK:
        items = load_farts(user["username"])
        record = next((x for x in items if x.get("id") == fart_id), None)
        if not record: raise HTTPException(404, "Furz nicht gefunden")
        folder = AUDIO / user["username"]; folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{fart_id}.m4a").write_bytes(data)
        record["hasAudio"] = True
        save_farts(user["username"], items)
    return {"ok": True}


def fart_public(record: dict[str, Any], viewer: dict[str, Any]) -> dict[str, Any]:
    # Location is only retained in a shared fart if the owner uploaded it; the app
    # only uploads coordinates when its explicit share-location toggle is enabled.
    return {k: record.get(k) for k in (
        "id", "owner", "title", "eventDate", "loudness", "smellRating", "personalRating", "duration",
        "notes", "context", "address", "geofence", "latitude", "longitude", "hasAudio", "comments"
    )}


@app.get("/api/feed")
def feed(days: int = 7, user: dict[str, Any] = Depends(current_user)) -> list[dict[str, Any]]:
    days = max(1, min(3650, days)); cutoff = utcnow() - timedelta(days=days)
    result = []
    for name in visible_people(user):
        for f in load_farts(name):
            dt = parse_iso(f.get("eventDate"))
            if dt and dt >= cutoff: result.append(fart_public(f, user))
    result.sort(key=lambda x: x.get("eventDate", ""), reverse=True)
    return result[:1000]


@app.get("/api/leaderboard")
def leaderboard(days: int = 7, user: dict[str, Any] = Depends(current_user)) -> list[dict[str, Any]]:
    days = max(1, min(3650, days)); result = []
    for name in visible_people(user):
        count, score, avg_smell, avg_rating = recent_stats(name, days)
        result.append({"username": name, "count": count, "score": score, "averageSmell": avg_smell, "averageRating": avg_rating})
    return sorted(result, key=lambda x: (x["score"], x["count"]), reverse=True)


@app.get("/api/farts/{owner}/{fart_id}/audio")
def download_audio(owner: str, fart_id: str, user: dict[str, Any] = Depends(current_user)):
    owner = clean_username(owner)
    if owner != user["username"] and owner not in user.get("friends", []):
        raise HTTPException(403, "Nur Furzfreunde dürfen diese Aufnahme hören")
    record = next((x for x in load_farts(owner) if x.get("id") == fart_id), None)
    if not record or not record.get("hasAudio"):
        raise HTTPException(404, "Keine geteilte Aufnahme")
    path = AUDIO / owner / f"{fart_id}.m4a"
    if not path.exists(): raise HTTPException(404, "Audiodatei fehlt")
    return FileResponse(path, media_type="audio/mp4", filename=f"furz-{owner}-{fart_id}.m4a")


@app.post("/api/farts/{owner}/{fart_id}/comments")
async def comment(owner: str, fart_id: str, request: Request, user: dict[str, Any] = Depends(current_user)) -> dict[str, bool]:
    owner = clean_username(owner)
    if owner != user["username"] and owner not in user.get("friends", []):
        raise HTTPException(403, "Nur Furzfreunde dürfen kommentieren")
    body = await request.json(); text = str(body.get("text", "")).strip()
    if not text or len(text) > 1000: raise HTTPException(400, "Kommentar muss 1–1000 Zeichen lang sein")
    with LOCK:
        items = load_farts(owner); record = next((x for x in items if x.get("id") == fart_id), None)
        if not record: raise HTTPException(404, "Furz nicht gefunden")
        record.setdefault("comments", []).append({"id": secrets.token_urlsafe(8), "author": user["username"], "text": text, "createdAt": iso()})
        record["comments"] = record["comments"][-200:]
        save_farts(owner, items)
    return {"ok": True}


@app.post("/api/nudges/{target_name}")
async def nudge(target_name: str, request: Request, user: dict[str, Any] = Depends(current_user)) -> dict[str, bool]:
    target_name = clean_username(target_name)
    if target_name not in user.get("friends", []): raise HTTPException(403, "Nur Furzfreunde können angestupst werden")
    target = load_user(target_name)
    if not target: raise HTTPException(404, "Benutzer nicht gefunden")
    body = await request.json(); message = str(body.get("message", "Zeit für einen Furz 💨")).strip()[:300]
    target.setdefault("nudges", []).append({"id": secrets.token_urlsafe(10), "from": user["username"], "message": message, "createdAt": iso(), "status": "pending"})
    target["nudges"] = target["nudges"][-200:]; save_user(target)
    return {"ok": True}


@app.get("/api/nudges")
def get_nudges(user: dict[str, Any] = Depends(current_user)) -> list[dict[str, Any]]:
    return sorted(user.get("nudges", []), key=lambda x: x.get("createdAt", ""), reverse=True)


@app.post("/api/nudges/{nudge_id}/respond")
async def respond_nudge(nudge_id: str, request: Request, user: dict[str, Any] = Depends(current_user)) -> dict[str, bool]:
    body = await request.json(); accept = bool(body.get("accept", False))
    with LOCK:
        user = load_user(user["username"]) or user
        item = next((x for x in user.get("nudges", []) if x.get("id") == nudge_id), None)
        if not item: raise HTTPException(404, "Anstupser nicht gefunden")
        item["status"] = "accepted" if accept else "declined"
        item["respondedAt"] = iso(); save_user(user)
    return {"ok": True}


@app.exception_handler(Exception)
async def unhandled(_: Request, exc: Exception):
    if isinstance(exc, HTTPException):
        return JSONResponse({"detail": exc.detail}, status_code=exc.status_code)
    print(f"Unhandled backend error: {exc}", file=sys.stderr)
    return JSONResponse({"detail": "Interner Serverfehler"}, status_code=500)


def main() -> None:
    parser = argparse.ArgumentParser(description="RJ Furz-App private partner backend")
    parser.add_argument("--host", default=str(CONFIG.get("bind_host", "0.0.0.0")))
    parser.add_argument("--port", type=int, default=int(CONFIG.get("port", 8788)))
    args = parser.parse_args()
    purge_sessions()
    print(f"RJ Furz Backend v{APP_VERSION} on http://{args.host}:{args.port}")
    print(f"Data: {DATA}")
    print("For internet access, put this behind HTTPS. API docs: /docs")
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
