"""Construye los datos del addon BestiaryForever.

Fuentes:
  * ForeverDB.net (https://foreverdb.net), crédito obligatorio "Data from ForeverDB.net":
      - /data/sources/{0..63}.json   ítem -> criaturas que lo sueltan (con % y "visto N veces")
      - /data/maps/zones.json        zonas: continente, nombre en inglés/español, contorno, niveles
      - /data/maps/index.json        plano del mundo (para pasar coordenadas del mundo a zonas)
      - /data/dungeons.json          mazmorras y bandas
      - /data/translator/*.json      nombres de ítems y mazmorras en inglés y español
  * CMaNGOS classic-db (GPL-3.0, https://github.com/cmangos/classic-db): niveles, rango, tipo, modelo y
    puntos de aparición de cada criatura, para ubicarla en su zona o mazmorra. Se descarga aparte:
        gh release download latest --repo cmangos/classic-db --pattern classic-sqlite-db.zip --dir data/raw/cmangos
    y se descomprime ahí (classicmangos.sqlite). Si no está, el script funciona sin ella (menos zonas).

Genera:
  * BestiaryForever/Data/Loot.lua   criaturas (nivel, rango, tipo, zonas, botín), zonas, continentes, mazmorras
  * BestiaryForever/Data/Items.lua  nombres de ítems en inglés y español (búsqueda inversa)
  * data/creatures.json             lo mismo en JSON, para inspeccionarlo

Uso:
    python tools/build_bestiary_data.py            # usa la caché de data/raw si existe
    python tools/build_bestiary_data.py --refresh  # vuelve a descargar los datos de ForeverDB
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path

BASE = "https://foreverdb.net"
SHARDS = 64
DELAY_S = 0.75  # pausa entre peticiones, para no cargar el servidor
USER_AGENT = "BestiaryForever-databuilder/0.2 (WoW addon data build; credits ForeverDB.net)"

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "data" / "raw" / "foreverdb"
CMANGOS_DB = ROOT / "data" / "raw" / "cmangos" / "classicmangos.sqlite"
OUT_JSON = ROOT / "data" / "creatures.json"
OUT_LUA = ROOT / "BestiaryForever" / "Data" / "Loot.lua"
OUT_ITEMS = ROOT / "BestiaryForever" / "Data" / "Items.lua"

CONTINENT_ES = {0: "Reinos del Este", 1: "Kalimdor", 2991: "Isla Zephras", 2997: "Islas Lanza Negra"}
MIN_ZONE_SHARE = 0.10  # una criatura aparece en una zona si allí está al menos el 10 % de sus spawns


# ---------------------------------------------------------------------------------------------- descarga

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


def cached(path: str, name: str, refresh: bool):
    """Descarga `path` de ForeverDB una vez y lo guarda en data/raw/foreverdb/`name`."""
    CACHE.mkdir(parents=True, exist_ok=True)
    f = CACHE / name
    if refresh or not f.exists():
        print(f"Descargando {path}")
        f.write_text(json.dumps(fetch_json(path), ensure_ascii=False), encoding="utf-8")
        time.sleep(DELAY_S)
    return json.loads(f.read_text(encoding="utf-8"))


def load_sources(refresh: bool) -> dict[str, list[dict]]:
    merged: dict[str, list[dict]] = {}
    for i in range(SHARDS):
        merged.update(cached(f"/data/sources/{i}.json", f"sources_{i}.json", refresh))
    return merged


def load_search_names(meta: dict, refresh: bool) -> dict[int, str]:
    """Nombres de ítems en inglés del addon de ForeverDB (Data/SearchNames.lua), para los que no están en el traductor."""
    f = CACHE / "SearchNames.lua"
    if refresh or not f.exists():
        entry = next((x for x in meta["data"]["files"] if x["path"] == "Data/SearchNames.lua"), None)
        if not entry:
            return {}
        print("Descargando Data/SearchNames.lua")
        req = urllib.request.Request(f"{BASE}/{entry['url']}", headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=60) as resp:
            f.write_bytes(resp.read())
        time.sleep(DELAY_S)
    import re
    text = f.read_text(encoding="utf-8")
    return {int(i): s.encode("latin-1", "backslashreplace").decode("unicode_escape") if "\\" in s else s
            for i, s in re.findall(r'\[(\d+)\]="((?:[^"\\]|\\.)*)"', text)}


def load_translator(refresh: bool) -> list[list]:
    index = cached("/data/translator/index.json", "translator_index.json", refresh)
    rows: list[list] = []
    for chunk in index["chunks"]:
        if chunk == "core.json" or chunk.startswith("items-"):
            rows.extend(cached(f"/data/translator/{chunk}", f"translator_{chunk}", refresh))
    return rows


# ---------------------------------------------------------------------------------------------- botín

def invert(sources: dict[str, list[dict]]) -> dict[int, dict]:
    """ítem -> fuentes  ==>  criatura -> {nombre, instancia, zona vista en Forever, botín[]}"""
    creatures: dict[int, dict] = {}
    for item_id, entries in sources.items():
        for e in entries:
            if e.get("t") != "drop" or not e.get("npc"):
                continue
            npc = int(e["npc"])
            c = creatures.setdefault(npc, {"id": npc, "name": None, "loot": [], "seenZones": Counter()})
            name = e.get("n") or ""
            if name and not name.startswith("NPC ") and not c["name"]:
                c["name"] = name
            if e.get("inst") and "instance" not in c:
                c["instance"] = int(e["inst"])
            if e.get("boss"):
                c["boss"] = True
            if e.get("m"):
                c["seenZones"][int(e["m"])] += 1
            c["loot"].append({
                "item": int(item_id),
                "pct": e.get("pct"),
                "rateSrc": e.get("rateSrc") or e.get("src"),
                "seen": e.get("seen", 0),
                "forever": bool(e.get("fv")),
                "quest": "q" in e,
            })
    for c in creatures.values():
        c["loot"].sort(key=lambda d: (-(d["pct"] or 0), -d["seen"], d["item"]))
    return creatures


# ---------------------------------------------------------------------------------------------- zonas

def flat_rings(poly) -> list[list[float]]:
    """El contorno viene como polígonos -> anillos -> [x1, y1, x2, y2, ...]: devuelve solo los anillos."""
    if poly and isinstance(poly[0], (int, float)):
        return [poly]
    rings = []
    for part in poly:
        rings.extend(flat_rings(part))
    return rings


def point_in_rings(px: float, py: float, rings: list[list[float]]) -> bool:
    inside = False
    for ring in rings:
        pts = list(zip(ring[0::2], ring[1::2]))
        j = len(pts) - 1
        for i in range(len(pts)):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
                inside = not inside
            j = i
    return inside


class ZoneLocator:
    """Pasa una posición del mundo (mapa, X, Y) a la zona (UiMap) de ForeverDB que la contiene."""

    def __init__(self, zones_json: dict, index_json: dict):
        plane = index_json["plane"]
        self.tp, self.tile = plane["tp"], plane["tileYards"]
        self.cont = {int(k): v for k, v in index_json["continents"].items()}
        self.zones = [dict(z, rings=flat_rings(z["poly"])) for z in zones_json["zones"] if z.get("type") == 3 and z.get("poly")]

    def locate(self, cmap: int, x: float, y: float) -> int | None:
        cont = self.cont.get(cmap)
        if not cont:
            return None
        px = (32 - y / self.tile + cont["dx"]) * self.tp
        py = (32 - x / self.tile + cont["dy"]) * self.tp
        best, best_area = None, None
        for z in self.zones:
            if z["c"] != cmap:
                continue
            x0, y0, x1, y1 = z["rect"]
            if not (x0 <= px <= x1 and y0 <= py <= y1):
                continue
            if point_in_rings(px, py, z["rings"]):
                area = (x1 - x0) * (y1 - y0)
                if best_area is None or area < best_area:
                    best, best_area = z["m"], area
        return best


def enrich_from_cmangos(creatures: dict[int, dict], locator: ZoneLocator, instance_ids: set[int]) -> int:
    """Añade nivel, rango, tipo, modelo y zonas (por puntos de aparición) desde CMaNGOS classic-db."""
    if not CMANGOS_DB.exists():
        print(f"Aviso: no está {CMANGOS_DB.relative_to(ROOT)}; las criaturas solo tendrán las zonas vistas en Forever.")
        return 0
    db = sqlite3.connect(f"file:{CMANGOS_DB.as_posix()}?mode=ro", uri=True)
    ids = list(creatures)
    found = 0
    for chunk in (ids[i:i + 500] for i in range(0, len(ids), 500)):
        q = ",".join("?" * len(chunk))
        for entry, name, lmin, lmax, rank, ctype, family, display in db.execute(
            f"SELECT Entry, Name, MinLevel, MaxLevel, Rank, CreatureType, Family, DisplayId1 "
            f"FROM creature_template WHERE Entry IN ({q})", chunk):
            c = creatures[entry]
            c["name"] = c["name"] or name
            c["minLevel"], c["maxLevel"] = lmin, lmax
            c["rank"], c["ctype"], c["family"], c["display"] = rank, ctype, family, display
            found += 1
    # Spawns: los de creature.id directo y los de creature_spawn_entry (spawns que eligen entre varias criaturas)
    spawns: dict[int, Counter] = {}
    rows = db.execute(
        "SELECT c.id, c.map, c.position_x, c.position_y FROM creature c WHERE c.id <> 0 "
        "UNION ALL SELECT e.entry, c.map, c.position_x, c.position_y FROM creature c "
        "JOIN creature_spawn_entry e ON e.guid = c.guid")
    for npc, cmap, x, y in rows:
        if npc not in creatures:
            continue
        where = None
        if cmap in (0, 1):
            zone = locator.locate(cmap, x, y)
            where = ("z", zone) if zone else None
        elif cmap in instance_ids:
            where = ("i", cmap)
        if where:
            spawns.setdefault(npc, Counter())[where] += 1
    for npc, counter in spawns.items():
        c = creatures[npc]
        total = sum(counter.values())
        zones = [w for w, n in counter.most_common() if w[0] == "z" and n >= max(1, total * MIN_ZONE_SHARE)]
        c["classicZones"] = [z for _, z in zones]
        inst = [w for w, _ in counter.most_common() if w[0] == "i"]
        if inst and "instance" not in c:
            c["instance"] = inst[0][1]
        c["spawns"] = total
    db.close()
    return found


def final_zones(c: dict) -> list[int]:
    zones = [z for z, _ in c["seenZones"].most_common()]  # vistas en Forever primero
    for z in c.get("classicZones", []):
        if z not in zones:
            zones.append(z)
    return zones


# ---------------------------------------------------------------------------------------------- salida

def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def fmt_pct(p) -> str:
    if p is None:
        return ""
    return f"{p:.2f}".rstrip("0").rstrip(".")


def level_range(lo, hi) -> str | None:
    if not lo:
        return None
    return str(lo) if lo == hi or not hi else f"{lo}-{hi}"


def write_lua(creatures, zones, continents, instances, version) -> None:
    OUT_LUA.parent.mkdir(parents=True, exist_ok=True)
    out = [
        "-- Generado por tools/build_bestiary_data.py: no editar a mano.",
        "-- Data from ForeverDB.net (https://foreverdb.net), datos del addon " + version + ".",
        "-- Niveles, rango, tipo, modelo y zonas de Classic: CMaNGOS classic-db (GPL-3.0); pueden variar en Forever.",
        "-- Criatura: n nombre (inglés), lv niveles, r rango (0 normal 1 élite 2 raro élite 3 jefe 4 raro), t tipo,",
        "--   d modelo, z zonas (UiMap), inst mazmorra, boss jefe de mazmorra,",
        '--   loot = "item:pct:src:seen:flags;..."  pct vacío = desconocido; src f=Forever c=Classic; flags q=misión',
        "local _, ns = ...",
        f"ns.lootMeta = {{ source = \"ForeverDB.net\", version = {lua_str(version)}, creatures = {len(creatures)} }}",
        "ns.continentDB = {",
    ]
    for cid, cont in continents.items():
        out.append(f"[{cid}]={{n={lua_str(cont['n'])},es={lua_str(cont['es'])},o={cont['o']}}},")
    out.append("}")
    out.append("ns.zoneDB = {")
    for zid, z in sorted(zones.items()):
        parts = [f"n={lua_str(z['n'])}", f"es={lua_str(z['es'])}", f"c={z['c']}"]
        if z.get("lv"):
            parts.append(f"lv={lua_str(z['lv'])}")
        out.append(f"[{zid}]={{{','.join(parts)}}},")
    out.append("}")
    out.append("ns.instanceDB = {")
    for iid, d in sorted(instances.items()):
        parts = [f"n={lua_str(d['n'])}", f"es={lua_str(d['es'])}", f"kind={lua_str(d['kind'])}"]
        if d.get("lv"):
            parts.append(f"lv={lua_str(d['lv'])}")
        out.append(f"[{iid}]={{{','.join(parts)}}},")
    out.append("}")
    out.append("ns.creatureDB = {")
    for npc in sorted(creatures):
        c = creatures[npc]
        parts = []
        if c.get("name"):
            parts.append("n=" + lua_str(c["name"]))
        lv = level_range(c.get("minLevel"), c.get("maxLevel"))
        if lv:
            parts.append("lv=" + lua_str(lv))
        if c.get("rank"):
            parts.append(f"r={c['rank']}")
        if c.get("ctype"):
            parts.append(f"t={c['ctype']}")
        if c.get("display"):
            parts.append(f"d={c['display']}")
        if c.get("zones"):
            parts.append("z=" + lua_str(",".join(str(z) for z in c["zones"])))
        if c.get("instance"):
            parts.append(f"inst={c['instance']}")
        if c.get("boss"):
            parts.append("boss=true")
        loot = ";".join(
            f"{d['item']}:{fmt_pct(d['pct'])}:{'c' if d['rateSrc'] == 'classic' else 'f'}:{d['seen'] or 0}:{'q' if d['quest'] else ''}"
            for d in c["loot"])
        parts.append("loot=" + lua_str(loot))
        out.append(f"[{npc}]={{{','.join(parts)}}},")
    out.append("}")
    OUT_LUA.write_text("\n".join(out) + "\n", encoding="utf-8")


def write_items(names: dict[int, tuple[str, str]], version: str) -> None:
    out = [
        "-- Generado por tools/build_bestiary_data.py: no editar a mano.",
        "-- Nombres de ítems en inglés y español para la búsqueda inversa. Data from ForeverDB.net (https://foreverdb.net), " + version + ".",
        '-- [id] = "inglés\\tespañol" (sin español si es igual)',
        "local _, ns = ...",
        "ns.itemNames = {",
    ]
    line = []
    for item in sorted(names):
        en, es = names[item]
        val = en if not es or es == en else en + "\t" + es
        line.append(f"[{item}]={lua_str(val)}")
        if len(line) == 20:
            out.append(",".join(line) + ",")
            line = []
    if line:
        out.append(",".join(line) + ",")
    out.append("}")
    OUT_ITEMS.write_text("\n".join(out) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------------------------- main

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true", help="ignora la caché y vuelve a descargar ForeverDB")
    args = ap.parse_args()

    meta = cached("/downloads/addon-manifest.json", "addon-manifest.json", args.refresh)
    version = meta.get("data", {}).get("version", "?")
    sources = load_sources(args.refresh)
    zones_json = cached("/data/maps/zones.json", "zones.json", args.refresh)
    index_json = cached("/data/maps/index.json", "maps_index.json", args.refresh)
    dungeons_json = cached("/data/dungeons.json", "dungeons.json", args.refresh)
    translator = load_translator(args.refresh)

    creatures = invert(sources)

    # Nombres en español (translator): ítems "i" y mazmorras "d"
    item_es: dict[int, tuple[str, str]] = {}
    dungeon_es: dict[str, str] = {}
    for row in translator:
        kind = row[0]
        if kind == "i" and isinstance(row[1], int):
            item_es[row[1]] = (row[2], row[3] or row[4] or "")
        elif kind == "d":
            dungeon_es[row[2]] = row[3] or row[4] or row[2]

    instances = {}
    for d in dungeons_json:
        lo_hi = d.get("range") or []
        instances[int(d["id"])] = {
            "n": d["n"], "es": dungeon_es.get(d["n"], d["n"]), "kind": d.get("kind", "dungeon"),
            "lv": f"{lo_hi[0]}-{lo_hi[1]}" if len(lo_hi) == 2 else None,
        }

    locator = ZoneLocator(zones_json, index_json)
    found = enrich_from_cmangos(creatures, locator, set(instances))

    zones, continents = {}, {}
    for z in zones_json["zones"]:
        if z.get("type") != 3:
            continue
        lv = z.get("lv")
        zones[z["m"]] = {"n": z["n"], "es": z.get("es") or z["n"], "c": z["c"],
                         "lv": f"{lv[0]}-{lv[1]}" if lv and len(lv) == 2 else None}
    order_of = {0: 0, 1: 1}  # Reinos del Este, Kalimdor y luego las islas
    for cid, cont in index_json["continents"].items():
        cid = int(cid)
        continents[cid] = {"n": cont["n"], "es": CONTINENT_ES.get(cid, cont["n"]), "o": order_of.get(cid, 2 + cid % 100)}

    for c in creatures.values():
        c["zones"] = [z for z in final_zones(c) if z in zones]
        del c["seenZones"]

    # Nombres de los ítems que aparecen en algún botín
    search_names = load_search_names(meta, args.refresh)
    names: dict[int, tuple[str, str]] = {}
    for c in creatures.values():
        for d in c["loot"]:
            if d["item"] in item_es:
                names[d["item"]] = item_es[d["item"]]
            elif d["item"] in search_names:
                names[d["item"]] = (search_names[d["item"]], "")

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(creatures, ensure_ascii=False, indent=1), encoding="utf-8")
    write_lua(creatures, zones, continents, instances, version)
    write_items(names, version)

    located = sum(1 for c in creatures.values() if c["zones"] or c.get("instance"))
    print(f"Ítems con fuentes: {len(sources)}  ·  nombres de ítems: {len(names)}")
    print(f"Criaturas: {len(creatures)}  ·  con datos de CMaNGOS: {found}  ·  ubicadas en zona o mazmorra: {located}")
    print(f"Zonas: {len(zones)}  ·  mazmorras y bandas: {len(instances)}")
    for f in (OUT_LUA, OUT_ITEMS):
        print(f"Escrito: {f.relative_to(ROOT)} ({f.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
