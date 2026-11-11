# Bestiary Forever

A free, open-source bestiary addon for **World of Warcraft: Forever**.
Target a creature and a small borderless window shows its 3D portrait, level, health and the loot it can drop. Expand it to see every drop with its rate and where that rate comes from. Every creature you meet is saved to your personal **bestiary**.

**Loot data from [ForeverDB.net](https://foreverdb.net).**

> **Status: beta (v0.2.0).** All the features below are implemented. WoW Forever's addon API (the Midnight client, interface 16001) restricts some values during combat, so please [report anything that looks wrong](https://github.com/soyelchecho/BestiaryForever/issues).

*[Leer en español](#español)*

## Features

- **Target frame**: borderless, movable window with the creature's 3D portrait, name (coloured by reaction), level, elite/rare/boss status, type and health bar. Below it are the top 8 drops with their rates.
- **Expanded view** (the **+** button): a rotatable 3D model and the full loot list. Each item shows its rate, the source of that rate and a tooltip with every source side by side. Shift-click an item to link it in chat.
- **Bestiary book** (`/bf`, or the book button on the target frame), like a Pokédex:
  - Organised by **continent, zone and dungeon**. Each region shows how many of its creatures you have discovered (`12/57`), plus how many you've looted and the rares, elites and bosses you've found.
  - Every creature of the zone has its number (`#001`, ordered by level). **Creatures you haven't discovered appear as a black silhouette** with `???`: you can see that something is there and its shape, but not what it is.
  - Click one for its full page: rotatable 3D model, level, rank, type, zones, times met, looted kills, gold, first and last seen, and its **whole loot list**.
- **Item search (reverse lookup)**: the *Items* tab finds any item by name (English or Spanish) and lists every creature that drops it. Sort by **highest drop %** (default), **A-Z** or **zone**; click a creature to open it in the bestiary.
- **Your own drop rates**: every corpse you loot is recorded once, and each item counts once per corpse. Your rates are merged with the database ones.

## Where the drop rates come from

Each item shows a **best estimate**, chosen in this order:

| Tag | Meaning |
|---|---|
| **You** (green) | Your own rate, once you have looted at least 20 corpses of that creature (`/bf minkills <n>` to change it) |
| **Forever** (blue) | Rate measured in WoW Forever by ForeverDB |
| **Classic\*** (orange) | Classic rate (CMaNGOS classic-db) that ForeverDB uses until there is a Forever one. It may differ in Forever |
| **You (n)** (yellow) | Your own rate with few samples (n looted corpses) |
| **seen N** (grey) | No rate yet, only how many times ForeverDB players saw it drop |

The tooltip always shows all of them, not only the chosen one. Your rates are counted over the corpses you looted: a creature that dropped nothing and that you didn't open isn't counted.

## Install

1. Download `BestiaryForever-<version>.zip` from [Releases](https://github.com/soyelchecho/BestiaryForever/releases).
2. Extract the `BestiaryForever` folder into `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game, or type `/reload`.

## Commands

| Command | |
|---|---|
| `/bf` (or `/bestiary`, `/bestiario`) | Open or close the bestiary. It is also in the addon compartment, next to the minimap |
| `/bf frame` | Show or hide the target frame |
| `/bf lock` | Lock or unlock the frames' position |
| `/bf reset` | Reset the frames' position |
| `/bf minkills <n>` | Looted corpses needed before your own rate is trusted (default 20) |
| `/bf about` | Version and data credits |

## Updating the data

```bash
gh release download latest --repo cmangos/classic-db --pattern classic-sqlite-db.zip --dir data/raw/cmangos
python tools/build_bestiary_data.py --refresh
```

The first command is optional: it downloads the CMaNGOS classic-db SQLite release (unzip it in `data/raw/cmangos/`). The script reads levels, rank, type, model and spawn points from it, and places each creature in its zone with ForeverDB's zone outlines. The script also downloads ForeverDB's public data, rate-limited and cached in `data/raw/`: item sources, zones, dungeons and English/Spanish item names. It writes `BestiaryForever/Data/Loot.lua`, `BestiaryForever/Data/Items.lua` and `data/creatures.json`.

Current data: **3,161 creatures** (2,761 placed in a zone or dungeon), **22,852 drops**, **50 zones**, **47 dungeons and raids** and **5,833 item names**.

## Credits and license

- Loot, zone and item-name data: **[Data from ForeverDB.net](https://foreverdb.net)**.
- Levels, rank, type, models, spawn points and part of the drop rates: [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL-3.0), Classic data that may differ in Forever. See [NOTICE.txt](NOTICE.txt).
- Code: GPL-3.0-or-later. See [LICENSE](LICENSE).
- Not affiliated with Blizzard Entertainment or ForeverDB.net. World of Warcraft is a trademark of Blizzard Entertainment, Inc.

---

## Español

**Bestiary Forever** es un addon gratuito y de código abierto para **World of Warcraft: Forever**. Al seleccionar una criatura aparece una ventana pequeña sin bordes con su retrato 3D, nivel, vida y el botín que puede soltar. Con **+** se expande y muestra todo el botín, con el porcentaje de cada ítem y de dónde sale ese porcentaje.

- **Libro del bestiario** (`/bf` o el botón del libro en la ventana del objetivo), como una Pokédex: organizado por **continentes, zonas y mazmorras**, con el contador de descubiertos de cada zona. Cada criatura tiene su número (`#001`), y **las que aún no has descubierto aparecen como una silueta negra** con `???`. Al pulsar una ves su ficha completa y todo su botín.
- **Búsqueda de objetos**: en la pestaña *Objetos* buscas un objeto (en español o inglés) y ves todas las criaturas que lo sueltan, ordenadas por **mayor %** (por defecto), **A-Z** o **zona**.

- **Instalación**: descarga el zip de [Releases](https://github.com/soyelchecho/BestiaryForever/releases) y extrae la carpeta `BestiaryForever` en `World of Warcraft\_forever_\Interface\AddOns\`.
- **Porcentajes**: el addon combina los datos de ForeverDB con los drops que tú registras. Usa tus porcentajes cuando tienes al menos 20 cadáveres saqueados; si no, el de Forever; si no, el de Classic (marcado con \*). El tooltip muestra todas las fuentes.
- **Comandos**: `/bf`, `/bf frame`, `/bf lock`, `/bf reset`, `/bf minkills <n>`, `/bf about`.
- **Créditos**: datos de botín de [ForeverDB.net](https://foreverdb.net). Licencia GPL-3.0.
