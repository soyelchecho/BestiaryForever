![Bestiary Forever](https://soyelchecho.github.io/BestiaryForever/logo.png)

# Bestiary Forever

**Know what a creature drops before you pull it, and collect every creature in Azeroth like a Pokédex.**

Target any creature and a small window shows its level, health and the loot it can drop, with drop rates. Everything you meet goes into your **bestiary book**, organised by zone. Creatures you haven't found yet are **black silhouettes**.

*Español abajo.*

---

## How to open it

| What | How |
|---|---|
| **Target window** | Target any creature. It appears on its own. |
| **Bestiary book** | Type **`/bf`**, click the **bear button** on the target window, or use the addon menu next to the minimap. |
| **Item search** | Open the bestiary and go to the **Items** tab. |

---

## The parts

### 1. Target window
![Target window](https://soyelchecho.github.io/BestiaryForever/screenshots/target-window.png)

A small borderless window: 3D portrait, name, level, elite/rare/boss, type and health bar. Below it are the **top 8 drops** with their %. Hover an item to see where the % comes from.

- **+** opens the **expanded view**: a big rotatable model and the full loot list.
- The **bear button** opens this creature in the bestiary.
- Drag it to move it. `/bf lock` locks it.

### 2. Bestiary book (`/bf`)
![Bestiary book](https://soyelchecho.github.io/BestiaryForever/screenshots/bestiary.png)

- **Left**: your progress with bars and %: the whole bestiary, each continent, and each zone and dungeon (`10/102 · 9%`). Bars turn green when you complete a zone.
- **Top**: the zone's progress bar and counter, plus how many you've looted and the rares, elites and bosses you've found.
- **Grid**: every creature of the zone, numbered by level (`#001`). The ones you haven't found are **black silhouettes with `???`**. Target one once and it's yours.
- **Click a creature** for its full page: rotatable model, level, rank, type, zones, times met, looted kills, gold, dates and its **whole loot list**.
- **Show on map** opens the world map at the creature's zone (dungeons: at the entrance).

### 3. Item search (Items tab)
![Item search](https://soyelchecho.github.io/BestiaryForever/screenshots/item-search.png)

- Type an item name (**English or Spanish**) and pick it: you get **every creature that drops it**.
- Sort by **Highest %** (default), **A-Z** or **Zone**.
- **Shift-click any item** in the game (bags, chat, character sheet) while the tab is open to search for it.
- Click a creature to open it in the bestiary, or its **zone** to open the map there.

---

## Where the % comes from

Each item shows its rate with a coloured tag. **The documented rate always comes first**:

| Tag | Meaning |
|---|---|
| **Forever** (blue) | Measured in WoW Forever (ForeverDB) |
| **Classic\*** (orange) | Classic rate: may differ in Forever |
| **You** (green) | Only for items with no documented rate: your own rate, after 20+ looted kills |
| **seen N** (grey) | No rate yet: how many times players saw it drop |

The addon also **records every corpse you loot**: your own drops always show in the tooltip, and fill in the gaps where there is no documented rate.

---

## Commands

`/bf` bestiary · `/bf frame` show/hide the target window · `/bf lock` lock/unlock · `/bf reset` reset positions · `/bf minkills 20` kills needed to use your own rate when there is no documented one · `/bf about` version and credits

---

## Data and credits

**3,161 creatures, 50 zones, 47 dungeons and raids, 22,852 drops.**

- Loot, zones and item names: **[Data from ForeverDB.net](https://foreverdb.net)**
- Levels, spawns and part of the rates: [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL-3.0)

Free and open source (GPL-3.0): [GitHub](https://github.com/soyelchecho/BestiaryForever) · [Website](https://soyelchecho.github.io/BestiaryForever/) · Bugs and ideas: [Issues](https://github.com/soyelchecho/BestiaryForever/issues)

Not affiliated with Blizzard Entertainment or ForeverDB.net.

---

## Español

**Sabe qué suelta una criatura antes de atacarla y colecciona todas las criaturas de Azeroth como en una Pokédex.**

- **Ventana del objetivo**: selecciona una criatura y verás su nivel, vida y botín con %. **+** la expande; el **botón del oso** la abre en el bestiario.
- **Bestiario** (**`/bf`**): por continentes, zonas y mazmorras, con **barras de progreso y %** de todo el bestiario, cada continente y cada zona. Las criaturas que no has encontrado son **siluetas negras**. Pulsa una para ver su ficha y todo su botín, y **Ver en el mapa** para abrir su zona.
- **Búsqueda de objetos** (pestaña **Objetos**): busca un objeto (en español o inglés) y ve qué criaturas lo sueltan, ordenadas por **mayor %**, **A-Z** o **zona**. Con la pestaña abierta, **mayús+clic** en cualquier objeto del juego lo busca.
- **Porcentajes**: el addon registra lo que saqueas y combina tus datos con los de ForeverDB. Primero se usa el % documentado (Forever, luego Classic\*); tus datos solo cubren lo que no está documentado, a partir de 20 cadáveres.
