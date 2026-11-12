-- Bestiary Forever - combina el botín de la base de datos (ForeverDB) con el que registra el propio jugador.
--
-- Regla para el "% estimado" de cada ítem: primero lo documentado.
--   1. El % medido en Forever por ForeverDB.
--   2. El % de Classic (CMaNGOS) que ForeverDB usa mientras no hay dato de Forever: puede variar.
--   3. Solo si el ítem no tiene % documentado: tus propios datos, y solo con al menos settings.minKills
--      cadáveres saqueados de esa criatura (con menos, una muestra pequeña da cifras absurdas: 1 de 1 = 100 %).
--   4. Sin %: solo "visto caer N veces" por jugadores de ForeverDB.
-- Tus propios datos se ven siempre en el tooltip ("Tus drops: 1 de 1"), pero no sustituyen al % documentado.
local _, ns = ...

local parsed = {}
local merged = {}

-- loot = "item:pct:src:seen:flags;..."  (ver tools/build_bestiary_data.py)
function ns.GetDBLoot(npc)
    local cached = parsed[npc]
    if cached ~= nil then return cached or nil end
    local e = ns.creatureDB and ns.creatureDB[npc]
    if not e or not e.loot or e.loot == "" then
        parsed[npc] = false
        return nil
    end
    local list = {}
    for entry in e.loot:gmatch("[^;]+") do
        local item, pct, src, seen, flags = strsplit(":", entry)
        item = tonumber(item)
        if item then
            list[#list + 1] = {
                item = item,
                pct = tonumber(pct),
                src = src,
                seen = tonumber(seen) or 0,
                quest = flags == "q",
            }
        end
    end
    parsed[npc] = list
    return list
end

function ns.InvalidateMerged(npc)
    if npc then merged[npc] = nil else wipe(merged) end
end

local function SortRows(a, b)
    local pa, pb = a.pct or -1, b.pct or -1
    if pa ~= pb then return pa > pb end
    local sa, sb = (a.dbSeen or 0) + (a.own or 0), (b.dbSeen or 0) + (b.own or 0)
    if sa ~= sb then return sa > sb end
    return a.item < b.item
end

-- Devuelve las filas combinadas y el número de cadáveres saqueados por el jugador.
function ns.GetMergedLoot(npc)
    if not npc then return {}, 0 end
    local cached = merged[npc]
    if cached then return cached.rows, cached.kills end

    local rows, byItem = {}, {}
    for _, d in ipairs(ns.GetDBLoot(npc) or {}) do
        local r = { item = d.item, dbPct = d.pct, dbSrc = d.src, dbSeen = d.seen, quest = d.quest }
        rows[#rows + 1] = r
        byItem[d.item] = r
    end

    local own = BestiaryForeverDB.creatures[npc]
    local kills = own and own.kills or 0
    if own and own.drops then
        for item, n in pairs(own.drops) do
            local r = byItem[item]
            if not r then
                r = { item = item, dbSeen = 0 }
                rows[#rows + 1] = r
                byItem[item] = r
            end
            r.own = n
        end
    end

    local minKills = ns.settings and ns.settings.minKills or 20
    for _, r in ipairs(rows) do
        if kills > 0 then r.ownPct = (r.own or 0) / kills * 100 end
        if r.dbPct and r.dbSrc ~= "c" then
            r.pct, r.tier = r.dbPct, "forever"
        elseif r.dbPct then
            r.pct, r.tier = r.dbPct, "classic"
        elseif r.own and kills >= minKills then
            r.pct, r.tier = r.ownPct, "own"
        else
            r.pct, r.tier = nil, "seen"
        end
    end
    table.sort(rows, SortRows)
    merged[npc] = { rows = rows, kills = kills }
    return rows, kills
end

function ns.FormatPct(p)
    if not p then return "?" end
    if p >= 10 then return ("%d"):format(math.floor(p + 0.5)) end
    if p >= 1 then return (("%.1f"):format(p):gsub("%.0$", "")) end
    return (("%.2f"):format(p):gsub("0$", ""))
end

-- Versión corta para los iconos pequeños de la ventana del objetivo: "<1" o número entero.
function ns.FormatPctShort(p)
    if not p then return "?" end
    if p < 1 then return "<1" end
    return ("%d"):format(math.floor(p + 0.5))
end

ns.TIER_COLORS = {
    own = { 0.40, 1.00, 0.40 },
    forever = { 0.35, 0.75, 1.00 },
    classic = { 1.00, 0.65, 0.25 },
    ownlow = { 1.00, 0.90, 0.35 },
    seen = { 0.65, 0.65, 0.65 },
}

function ns.TierLabel(r, kills)
    local L = ns.L
    if r.tier == "own" then return L.TIER_OWN end
    if r.tier == "forever" then return L.TIER_FOREVER end
    if r.tier == "classic" then return L.TIER_CLASSIC end
    if r.tier == "ownlow" then return L.TIER_OWNLOW:format(kills or 0) end
    return L.TIER_SEEN:format(r.dbSeen or 0)
end
