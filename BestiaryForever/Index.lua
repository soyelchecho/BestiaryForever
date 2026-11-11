-- Bestiary Forever - índices: criaturas por zona/continente/mazmorra (con número tipo Pokédex) e índice inverso
-- ítem -> criaturas que lo sueltan.
local _, ns = ...
local L = ns.L

local zoneIndex, regions, dirty = nil, nil, true
local itemIndex = nil

function ns.MarkIndexDirty()
    dirty = true
end

-- Nivel para ordenar: el de la base de datos o el visto en el juego; sin nivel conocido, al final.
local function LevelOf(npc)
    local e = ns.creatureDB[npc]
    local lv = e and e.lv
    if lv then return tonumber(lv:match("^(%d+)")) or 999 end
    local c = BestiaryForeverDB.creatures[npc]
    return c and c.minLevel or 999
end

function ns.DBName(npc)
    local e = ns.creatureDB[npc]
    return e and e.n
end

function ns.IsDiscovered(npc)
    return BestiaryForeverDB.creatures[npc] ~= nil
end

-- Nombre que ve el jugador: el del juego si la ha descubierto (en su idioma), el de la base de datos si no.
function ns.CreatureName(npc)
    local c = BestiaryForeverDB.creatures[npc]
    return (c and c.name) or ns.DBName(npc) or ("#" .. npc)
end

function ns.ZoneName(zoneID)
    local z = ns.zoneDB[zoneID]
    if not z then return L.UNKNOWN_ZONE end
    return ns.isSpanish and z.es or z.n
end

function ns.InstanceName(id)
    local d = ns.instanceDB[id]
    if not d then return "#" .. id end
    return ns.isSpanish and d.es or d.n
end

function ns.RegionName(key)
    if type(key) == "number" then return ns.ZoneName(key) end
    if key == "unknown" then return L.UNKNOWN_ZONE end
    local inst = tonumber(tostring(key):match("^i(%d+)$"))
    return inst and ns.InstanceName(inst) or tostring(key)
end

function ns.RegionLevels(key)
    if type(key) == "number" then return ns.zoneDB[key] and ns.zoneDB[key].lv end
    local inst = tonumber(tostring(key):match("^i(%d+)$"))
    return inst and ns.instanceDB[inst] and ns.instanceDB[inst].lv
end

-- Zona (UiMap) de ns.zoneDB que contiene un mapa del juego: sube por los padres hasta encontrarla.
function ns.ZoneForMap(mapID)
    local guard = 0
    while mapID and guard < 8 do
        if ns.zoneDB[mapID] then return mapID end
        local info = C_Map and C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID
        guard = guard + 1
    end
    return nil
end

-- Primera región (zona o mazmorra) de una criatura, para abrirla en el bestiario.
function ns.PrimaryRegion(npc)
    local e = ns.creatureDB[npc]
    if e then
        if e.z then
            local z = tonumber(e.z:match("^(%d+)"))
            if z and ns.zoneDB[z] then return z end
        end
        if e.inst and ns.instanceDB[e.inst] then return "i" .. e.inst end
    end
    local c = BestiaryForeverDB.creatures[npc]
    if c then
        if c.instanceID and ns.instanceDB[c.instanceID] then return "i" .. c.instanceID end
        local z = ns.ZoneForMap(c.mapID)
        if z then return z end
    end
    return "unknown"
end

-- Zonas de una criatura: { {name = "Bosque de Elwynn", map = 1429}, ... }. Para una mazmorra, `map` es la zona
-- donde está su entrada (para abrir el mapa del mundo ahí).
function ns.CreatureZones(npc)
    local e, zones = ns.creatureDB[npc], {}
    if e and e.z then
        for z in e.z:gmatch("%d+") do
            z = tonumber(z)
            zones[#zones + 1] = { name = ns.ZoneName(z), map = z }
        end
    end
    if e and e.inst and ns.instanceDB[e.inst] then
        zones[#zones + 1] = { name = ns.InstanceName(e.inst), map = ns.instanceDB[e.inst].zone }
    end
    if #zones == 0 then
        local c = BestiaryForeverDB.creatures[npc]
        if c and c.zone then zones[1] = { name = c.zone, map = c.mapID } end
    end
    return zones
end

function ns.CreatureZoneNames(npc)
    local names = {}
    for i, z in ipairs(ns.CreatureZones(npc)) do names[i] = z.name end
    return names
end

-- Mapa (UiMap) que se abre para una región del bestiario: la zona, o la entrada de la mazmorra.
function ns.RegionMap(key)
    if type(key) == "number" then return key end
    local inst = tonumber(tostring(key):match("^i(%d+)$"))
    return inst and ns.instanceDB[inst] and ns.instanceDB[inst].zone
end

-- Abre el mapa del mundo en una zona. En combate el juego no deja abrirlo desde un addon.
function ns.OpenMap(mapID)
    if not mapID then return end
    if InCombatLockdown and InCombatLockdown() then
        ns.Print(L.MAP_COMBAT)
        return
    end
    if OpenWorldMap and pcall(OpenWorldMap, mapID) then return end
    if WorldMapFrame then
        if not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) end
        pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID)
    end
end

local function Rebuild()
    zoneIndex = {}
    local function add(key, npc)
        local list = zoneIndex[key]
        if not list then
            list = {}
            zoneIndex[key] = list
        end
        list[#list + 1] = npc
    end
    for npc, e in pairs(ns.creatureDB) do
        local placed = false
        if e.inst and ns.instanceDB[e.inst] then
            add("i" .. e.inst, npc)
            placed = true
        end
        if e.z then
            for z in e.z:gmatch("%d+") do
                z = tonumber(z)
                if ns.zoneDB[z] then
                    add(z, npc)
                    placed = true
                end
            end
        end
        if not placed then add("unknown", npc) end
    end
    -- Criaturas descubiertas que no están en la base de datos (sin botín conocido): a la zona donde se vieron.
    for npc in pairs(BestiaryForeverDB.creatures) do
        if not ns.creatureDB[npc] then add(ns.PrimaryRegion(npc), npc) end
    end
    -- Orden y número dentro de cada región: por nivel y nombre.
    for _, list in pairs(zoneIndex) do
        table.sort(list, function(a, b)
            local la, lb = LevelOf(a), LevelOf(b)
            if la ~= lb then return la < lb end
            local na, nb = ns.DBName(a) or "", ns.DBName(b) or ""
            if na ~= nb then return na < nb end
            return a < b
        end)
    end

    -- Regiones para la barra lateral: continentes con sus zonas, luego mazmorras, luego desconocida.
    regions = {}
    local conts = {}
    for cid, cont in pairs(ns.continentDB) do conts[#conts + 1] = { id = cid, o = cont.o } end
    table.sort(conts, function(a, b) return a.o < b.o end)
    local function zoneLevel(z)
        local lv = ns.zoneDB[z].lv
        return lv and tonumber(lv:match("^(%d+)")) or 99
    end
    for _, cont in ipairs(conts) do
        local zones = {}
        for z, info in pairs(ns.zoneDB) do
            if info.c == cont.id and zoneIndex[z] then zones[#zones + 1] = z end
        end
        if #zones > 0 then
            table.sort(zones, function(a, b)
                local la, lb = zoneLevel(a), zoneLevel(b)
                if la ~= lb then return la < lb end
                return ns.ZoneName(a) < ns.ZoneName(b)
            end)
            local c = ns.continentDB[cont.id]
            regions[#regions + 1] = { header = ns.isSpanish and c.es or c.n }
            for _, z in ipairs(zones) do regions[#regions + 1] = { key = z } end
        end
    end
    local insts = {}
    for key in pairs(zoneIndex) do
        local id = type(key) == "string" and tonumber(key:match("^i(%d+)$"))
        if id then insts[#insts + 1] = id end
    end
    if #insts > 0 then
        local function instLevel(id) return tonumber((ns.instanceDB[id].lv or "99"):match("^(%d+)")) or 99 end
        table.sort(insts, function(a, b)
            local la, lb = instLevel(a), instLevel(b)
            if la ~= lb then return la < lb end
            return ns.InstanceName(a) < ns.InstanceName(b)
        end)
        regions[#regions + 1] = { header = L.DUNGEONS }
        for _, id in ipairs(insts) do regions[#regions + 1] = { key = "i" .. id } end
    end
    if zoneIndex.unknown then
        regions[#regions + 1] = { header = L.OTHER }
        regions[#regions + 1] = { key = "unknown" }
    end
    dirty = false
end

function ns.GetRegions()
    if dirty or not regions then Rebuild() end
    return regions
end

function ns.GetRegionCreatures(key)
    if dirty or not zoneIndex then Rebuild() end
    return zoneIndex[key] or {}
end

-- Número tipo Pokédex de una criatura dentro de una región.
function ns.RegionNumber(key, npc)
    for i, id in ipairs(ns.GetRegionCreatures(key)) do
        if id == npc then return i end
    end
    return nil
end

function ns.RegionStats(key)
    local s = { total = 0, discovered = 0, looted = 0, rares = 0, raresTotal = 0, elites = 0, elitesTotal = 0, bosses = 0, bossesTotal = 0 }
    for _, npc in ipairs(ns.GetRegionCreatures(key)) do
        local e = ns.creatureDB[npc]
        local c = BestiaryForeverDB.creatures[npc]
        local r = e and e.r or 0
        local isBoss = r == 3 or (e and e.boss) or false
        s.total = s.total + 1
        if r == 2 or r == 4 then s.raresTotal = s.raresTotal + 1 end
        if r == 1 then s.elitesTotal = s.elitesTotal + 1 end
        if isBoss then s.bossesTotal = s.bossesTotal + 1 end
        if c then
            s.discovered = s.discovered + 1
            if (c.kills or 0) > 0 then s.looted = s.looted + 1 end
            if r == 2 or r == 4 then s.rares = s.rares + 1 end
            if r == 1 then s.elites = s.elites + 1 end
            if isBoss then s.bosses = s.bosses + 1 end
        end
    end
    return s
end

-- Región por defecto al abrir el bestiario: la zona o mazmorra donde está el jugador.
function ns.CurrentRegion()
    if IsInInstance and IsInInstance() then
        local instanceID = select(8, GetInstanceInfo())
        if instanceID and ns.instanceDB[instanceID] then return "i" .. instanceID end
    end
    local mapID = C_Map and C_Map.GetBestMapForUnit("player")
    return ns.ZoneForMap(mapID)
end

---------------------------------------------------------------------------------------------- búsqueda inversa

local function BuildItemIndex()
    itemIndex = {}
    for npc, e in pairs(ns.creatureDB) do
        if e.loot then
            for entry in e.loot:gmatch("[^;]+") do
                local item = tonumber(entry:match("^(%d+)"))
                if item then
                    local list = itemIndex[item]
                    if not list then
                        list = {}
                        itemIndex[item] = list
                    end
                    list[#list + 1] = npc
                end
            end
        end
    end
end

-- Criaturas que sueltan un ítem: base de datos más lo que el jugador ha visto caer.
function ns.GetItemDroppers(item)
    if not itemIndex then BuildItemIndex() end
    local seen, list = {}, {}
    for _, npc in ipairs(itemIndex[item] or {}) do
        seen[npc] = true
        list[#list + 1] = npc
    end
    for npc, c in pairs(BestiaryForeverDB.creatures) do
        if not seen[npc] and c.drops and c.drops[item] then list[#list + 1] = npc end
    end
    return list
end

function ns.ItemSearchName(item)
    local raw = ns.itemNames and ns.itemNames[item]
    if not raw then return nil end
    local en, es = strsplit("\t", raw)
    return en, es
end

-- Nombre de ítem para mostrar: el del cliente si ya está cargado; si no, el de la base de datos en el idioma del jugador.
function ns.ItemDisplayName(item)
    local name = C_Item.GetItemNameByID(item)
    if name then return name end
    local en, es = ns.ItemSearchName(item)
    if ns.isSpanish and es and es ~= "" then return es end
    return en or ns.ItemName(item) or ("#" .. item)
end

-- Busca ítems por nombre (inglés o español) entre los que sueltan criaturas. Devuelve hasta `limit` ids.
function ns.SearchItems(query, limit)
    query = (query or ""):lower()
    if #query < 2 then return {} end
    if not itemIndex then BuildItemIndex() end
    local results, checked = {}, {}
    for item, raw in pairs(ns.itemNames or {}) do
        checked[item] = true
        if raw:lower():find(query, 1, true) then results[#results + 1] = item end
    end
    for _, c in pairs(BestiaryForeverDB.creatures) do
        for item in pairs(c.drops or {}) do
            if not checked[item] then
                checked[item] = true
                local name = C_Item.GetItemNameByID(item)
                if name and name:lower():find(query, 1, true) then results[#results + 1] = item end
            end
        end
    end
    local names = {}
    for _, item in ipairs(results) do names[item] = ns.ItemDisplayName(item) end
    table.sort(results, function(a, b) return names[a] < names[b] end)
    if limit and #results > limit then
        for i = #results, limit + 1, -1 do results[i] = nil end
    end
    return results
end
