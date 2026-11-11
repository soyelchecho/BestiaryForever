"""Construye la base de datos de loot por monstruo para el addon BestiaryForever.

Fuente: ForeverDB.net (https://foreverdb.net). Sus datos de "dónde cae cada ítem" están en
/data/sources/{0..63}.json (ítem -> lista de fuentes). Este script los descarga (64 peticiones,
con pausa y caché local), los invierte a monstruo -> loot y genera BestiaryForever/Data/Loot.lua.

Licencia de los datos: ForeverDB pide crédito visible ("Data from ForeverDB.net"); los datos de su
addon son GPL-3.0 con cláusula de atribución, y parte de los porcentajes son datos de Classic
(CMaNGOS classic-db, GPL-3.0). Por eso el addon se distribuye como GPL-3.0 y muestra el crédito.

Uso:
    python tools/build_bestiary_data.py            # usa la caché si existe
    python tools/build_bestiary_data.py --refresh  # vuelve a descargar todo
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = "https://foreverdb.net"
SHARDS = 64
DELAY_S = 0.75  # pausa entre peticiones, para no cargar el servidor
USER_AGENT = "BestiaryForever-databuilder/0.1 (WoW addon data build; credits ForeverDB.net)"

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "data" / "raw" / "foreverdb"
OUT_JSON = ROOT / "data" / "creatures.json"
OUT_LUA = ROOT / "BestiaryForever" / "Data" / "Loot.lua"


def fetch_json(path: str) -> object:
    req = urllib.request.Request(BASE + path, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 429 or e.code >= 500:
                wait = int(e.headers.get("Retry-After", "0") or 0) or 5 * (attempt + 1)
                print(f"  {path}: HTTP {e.code}, reintento en {wait}s", file=sys.stderr)
                time.sleep(wait)
                continue
            raise
        except urllib.error.URLError as e:
            print(f"  {path}: {e.reason}, reintento", file=sys.stderr)
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"No se pudo descargar {path}")


def load_meta(refresh: bool) -> dict:
    """La versión de los datos del addon de ForeverDB (build del cliente y fecha)."""
    cache = CACHE / "addon-manifest.json"
    if refresh or not cache.exists():
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(fetch_json("/downloads/addon-manifest.json")), encoding="utf-8")
        time.sleep(DELAY_S)
    return json.loads(cache.read_text(encoding="utf-8"))


def load_sources(refresh: bool) -> dict[str, list[dict]]:
    CACHE.mkdir(parents=True, exist_ok=True)
    merged: dict[str, list[dict]] = {}
    for i in range(SHARDS):
        cache = CACHE / f"sources_{i}.json"
        if refresh or not cache.exists():
            print(f"Descargando /data/sources/{i}.json")
            cache.write_text(json.dumps(fetch_json(f"/data/sources/{i}.json")), encoding="utf-8")
            time.sleep(DELAY_S)
        merged.update(json.loads(cache.read_text(encoding="utf-8")))
    return merged


def invert(sources: dict[str, list[dict]]) -> dict[int, dict]:
    """ítem -> fuentes  ==>  monstruo -> {nombre, nivel, instancia, ubicación, loot[]}"""
    creatures: dict[int, dict] = {}
    for item_id, entries in sources.items():
        for e in entries:
            if e.get("t") != "drop" or not e.get("npc"):
                continue
            npc = int(e["npc"])
            c = creatures.setdefault(npc, {"id": npc, "name": None, "loot": []})
            name = e.get("n") or ""
            if name and not name.startswith("NPC ") and not c["name"]:
                c["name"] = name
            for key_src, key_dst in (("lv", "level"), ("inst", "instance"), ("boss", "boss")):
                if key_src in e and key_dst not in c:
                    c[key_dst] = e[key_src]
            if "m" in e and "map" not in c:
                c["map"], c["x"], c["y"] = e["m"], e.get("x"), e.get("y")
            c["loot"].append({
                "item": int(item_id),
                "pct": e.get("pct"),            # % de drop (medido en Forever o, si rateSrc=classic, de Classic)
                "rateSrc": e.get("rateSrc") or e.get("src"),
                "seen": e.get("seen", 0),       # veces que jugadores lo vieron caer en Forever
                "forever": bool(e.get("fv")),   # confirmado en Forever
                "quest": "q" in e,              # objeto de misión
            })
    for c in creatures.values():
        c["loot"].sort(key=lambda d: (-(d["pct"] or 0), -d["seen"], d["item"]))
    return creatures


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def fmt_pct(p) -> str:
    if p is None:
        return ""
    return f"{p:.2f}".rstrip("0").rstrip(".")


def write_lua(creatures: dict[int, dict], meta: dict) -> None:
    """Formato compacto: loot = "item:pct:src:seen:flags;..."  (src f=Forever c=Classic; flags q=misión)."""
    OUT_LUA.parent.mkdir(parents=True, exist_ok=True)
    version = meta.get("data", {}).get("version", "?")
    lines = [
        "-- Generado por tools/build_bestiary_data.py: no editar a mano.",
        "-- Data from ForeverDB.net (https://foreverdb.net), datos del addon " + version + ".",
        "-- Parte de los porcentajes son datos de Classic (CMaNGOS classic-db, GPL-3.0) y pueden diferir en Forever.",
        '-- loot = "item:pct:src:seen:flags;..."  pct vacío = desconocido; src f=Forever c=Classic; flags q=misión',
        "local _, ns = ...",
        "ns.lootMeta = { source = \"ForeverDB.net\", version = " + lua_str(version) + ", creatures = " + str(len(creatures)) + " }",
        "ns.creatureDB = {",
    ]
    for npc in sorted(creatures):
        c = creatures[npc]
        parts = []
        if c.get("name"):
            parts.append("n=" + lua_str(c["name"]))
        if c.get("level") is not None:
            parts.append("lv=" + lua_str(str(c["level"])))
        if c.get("instance"):
            parts.append("inst=" + str(int(c["instance"])))
        if c.get("boss"):
            parts.append("boss=true")
        if c.get("map"):
            parts.append(f"m={int(c['map'])},x={c.get('x') or 0},y={c.get('y') or 0}")
        loot = ";".join(
            f"{d['item']}:{fmt_pct(d['pct'])}:{'c' if d['rateSrc'] == 'classic' else 'f'}:{d['seen'] or 0}:{'q' if d['quest'] else ''}"
            for d in c["loot"]
        )
        parts.append("loot=" + lua_str(loot))
        lines.append(f"[{npc}]={{{','.join(parts)}}},")
    lines.append("}")
    OUT_LUA.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true", help="ignora la caché y vuelve a descargar")
    args = ap.parse_args()

    meta = load_meta(args.refresh)
    sources = load_sources(args.refresh)
    creatures = invert(sources)

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(creatures, ensure_ascii=False, indent=1), encoding="utf-8")
    write_lua(creatures, meta)

    total_loot = sum(len(c["loot"]) for c in creatures.values())
    with_pct = sum(1 for c in creatures.values() for d in c["loot"] if d["pct"])
    named = sum(1 for c in creatures.values() if c["name"])
    print(f"Ítems con fuentes: {len(sources)}")
    print(f"Monstruos: {len(creatures)} ({named} con nombre)")
    print(f"Entradas de loot: {total_loot} ({with_pct} con % de drop)")
    print(f"Escrito: {OUT_LUA.relative_to(ROOT)} ({OUT_LUA.stat().st_size // 1024} KB) y {OUT_JSON.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
