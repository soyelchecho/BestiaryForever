# Bestiary Forever

A free, open-source bestiary addon for **World of Warcraft: Forever**.
Target a creature and a small borderless window shows its 3D portrait, level, health and the loot it can drop. Expand it to see every drop with its rate and where that rate comes from. Every creature you meet is saved to your personal **bestiary**.

**Loot data from [ForeverDB.net](https://foreverdb.net).**

> **Status: beta (v0.1.0).** All the features below are implemented. WoW Forever's addon API (the Midnight client, interface 16001) restricts some values during combat, so please [report anything that looks wrong](https://github.com/soyelchecho/BestiaryForever/issues).

*[Leer en español](#español)*

## Features

- **Target frame**: borderless, movable window with the creature's 3D portrait, name (coloured by reaction), level, elite/rare/boss status, type and health bar. Below it are the top 8 drops with their rates.
- **Expanded view** (the **+** button): a rotatable 3D model and the full loot list. Each item shows its rate, the source of that rate and a tooltip with every source side by side. Shift-click an item to link it in chat.
- **Bestiary** (`/bf`): every creature you have targeted, with search, levels seen, zone, how many times you met it, your looted kills, gold looted, first and last seen, and its full loot table.
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

## Updating the loot data

```bash
python tools/build_bestiary_data.py --refresh
```

This downloads ForeverDB's public item-source files (64 small JSON files, rate-limited and cached in `data/raw/`). It turns "item → creatures" into "creature → loot" and writes `BestiaryForever/Data/Loot.lua`, plus `data/creatures.json` for inspection. Current data: **3,161 creatures and 22,852 drops**.

## Credits and license

- Loot data: **[Data from ForeverDB.net](https://foreverdb.net)**. Part of the rates are Classic data from CMaNGOS classic-db (GPL-3.0). See [NOTICE.txt](NOTICE.txt).
- Code: GPL-3.0-or-later. See [LICENSE](LICENSE).
- Not affiliated with Blizzard Entertainment or ForeverDB.net. World of Warcraft is a trademark of Blizzard Entertainment, Inc.

---

## Español

**Bestiary Forever** es un addon gratuito y de código abierto para **World of Warcraft: Forever**. Al seleccionar una criatura aparece una ventana pequeña sin bordes con su retrato 3D, nivel, vida y el botín que puede soltar. Con **+** se expande y muestra todo el botín, con el porcentaje de cada ítem y de dónde sale ese porcentaje. Cada criatura que encuentras queda guardada en tu **bestiario** (`/bf`).

- **Instalación**: descarga el zip de [Releases](https://github.com/soyelchecho/BestiaryForever/releases) y extrae la carpeta `BestiaryForever` en `World of Warcraft\_forever_\Interface\AddOns\`.
- **Porcentajes**: el addon combina los datos de ForeverDB con los drops que tú registras. Usa tus porcentajes cuando tienes al menos 20 cadáveres saqueados; si no, el de Forever; si no, el de Classic (marcado con \*). El tooltip muestra todas las fuentes.
- **Comandos**: `/bf`, `/bf frame`, `/bf lock`, `/bf reset`, `/bf minkills <n>`, `/bf about`.
- **Créditos**: datos de botín de [ForeverDB.net](https://foreverdb.net). Licencia GPL-3.0.
