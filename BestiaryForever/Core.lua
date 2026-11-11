-- Bestiary Forever - núcleo: datos guardados, eventos, registro de criaturas vistas y de botín.
-- Las restricciones de addons de Midnight/Forever pueden convertir algunos valores en "secretos" durante
-- el combate (no se pueden leer ni comparar). Todo valor leído de una unidad pasa por ns.safe().
local ADDON, ns = ...
local L = ns.L

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "0.1.0"

local isSecret = issecretvalue or function() return false end
function ns.safe(v)
    if v == nil or isSecret(v) then return nil end
    return v
end
local safe = ns.safe

local LOOTED_TTL = 2 * 60 * 60 -- un cadáver saqueado se recuerda 2 h para no contarlo dos veces

local defaults = {
    showFrame = true,
    locked = false,
    expanded = false,
    minKills = 20,
}

local function now() return time() end

function ns.Print(msg)
    print("|cff8fd14fBestiary Forever|r: " .. tostring(msg))
end

-- "Creature-0-[server]-[instance]-[zone]-[npcID]-[spawn]" -> npcID
function ns.NpcIDFromGUID(guid)
    guid = safe(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then
        return tonumber(id)
    end
    return nil
end

function ns.IsMonster(unit)
    if not UnitExists(unit) then return false end
    local isPlayer = safe(UnitIsPlayer(unit))
    if isPlayer then return false end
    local canAttack = safe(UnitCanAttack("player", unit))
    return canAttack and true or false
end

local function CurrentZone()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil, nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil, nil end
    local info = C_Map.GetMapInfo(mapID)
    return mapID, info and info.name
end

function ns.GetCreature(npc, create)
    local db = BestiaryForeverDB.creatures
    local c = db[npc]
    if not c and create then
        local static = ns.creatureDB and ns.creatureDB[npc]
        c = { name = static and static.n, seen = 0, kills = 0, drops = {}, money = 0, firstSeen = now(), lastSeen = now() }
        db[npc] = c
        if ns.MarkIndexDirty then ns.MarkIndexDirty() end
    end
    return c
end

-- Se llama al seleccionar un objetivo: añade la criatura al bestiario o actualiza lo que sabemos de ella.
function ns.RecordTarget(unit)
    local npc = ns.NpcIDFromGUID(UnitGUID(unit))
    if not npc then return nil end
    local c = ns.GetCreature(npc, true)
    c.seen = (c.seen or 0) + 1
    c.lastSeen = now()
    local name = safe(UnitName(unit))
    if name then c.name = name end
    local level = safe(UnitLevel(unit))
    if type(level) == "number" then
        if level < 0 then
            c.skull = true
        else
            c.minLevel = math.min(c.minLevel or level, level)
            c.maxLevel = math.max(c.maxLevel or level, level)
        end
    end
    local class = safe(UnitClassification(unit))
    if class and class ~= "normal" and class ~= "trivial" and class ~= "minus" then c.class = class end
    local ctype = safe(UnitCreatureType(unit))
    if ctype then c.ctype = ctype end
    local family = safe(UnitCreatureFamily(unit))
    if family then c.family = family end
    local mapID, zone = CurrentZone()
    if mapID then c.mapID, c.zone = mapID, zone end
    if IsInInstance() then
        local instanceID = select(8, GetInstanceInfo())
        if instanceID then c.instanceID = instanceID end
    end
    if ns.OnBestiaryChanged then ns.OnBestiaryChanged() end
    return npc
end

-- Registro de botín: cada cadáver (GUID) cuenta una vez; cada ítem cuenta una vez por cadáver.
local function OnLootOpened()
    local looted = BestiaryForeverDB.looted
    local corpses = {}
    for slot = 1, GetNumLootItems() do
        local slotType = GetLootSlotType(slot)
        local link = safe(GetLootSlotLink(slot))
        local itemID = link and C_Item.GetItemInfoInstant(link)
        local sources = { GetLootSourceInfo(slot) }
        for i = 1, #sources, 2 do
            local guid, qty = safe(sources[i]), safe(sources[i + 1])
            local npc = guid and ns.NpcIDFromGUID(guid)
            if npc and not looted[guid] then
                local corpse = corpses[guid]
                if not corpse then
                    corpse = { npc = npc, items = {}, money = 0 }
                    corpses[guid] = corpse
                end
                if slotType == Enum.LootSlotType.Money then
                    corpse.money = corpse.money + (tonumber(qty) or 0)
                elseif itemID then
                    corpse.items[itemID] = true
                end
            end
        end
    end
    local changed = false
    for guid, corpse in pairs(corpses) do
        looted[guid] = now()
        local c = ns.GetCreature(corpse.npc, true)
        c.kills = (c.kills or 0) + 1
        c.money = (c.money or 0) + corpse.money
        c.drops = c.drops or {}
        for itemID in pairs(corpse.items) do
            c.drops[itemID] = (c.drops[itemID] or 0) + 1
        end
        c.lastSeen = now()
        changed = true
    end
    if changed then
        ns.InvalidateMerged()
        if ns.OnBestiaryChanged then ns.OnBestiaryChanged() end
        if ns.RefreshTarget then ns.RefreshTarget() end
    end
end

local function PruneLooted()
    local cutoff = now() - LOOTED_TTL
    for guid, t in pairs(BestiaryForeverDB.looted) do
        if t < cutoff then BestiaryForeverDB.looted[guid] = nil end
    end
end

local function InitDB()
    BestiaryForeverDB = BestiaryForeverDB or {}
    local db = BestiaryForeverDB
    db.version = 1
    db.creatures = db.creatures or {}
    db.looted = db.looted or {}
    db.settings = db.settings or {}
    for k, v in pairs(defaults) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    ns.settings = db.settings
    PruneLooted()
end

local pendingTarget = false
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        InitDB()
        if ns.InitTargetFrame then ns.InitTargetFrame() end
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
        self:RegisterEvent("LOOT_OPENED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterUnitEvent("UNIT_HEALTH", "target")
        self:RegisterUnitEvent("UNIT_MAXHEALTH", "target")
        self:RegisterUnitEvent("UNIT_LEVEL", "target")
        self:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", "target")
        self:RegisterUnitEvent("UNIT_FACTION", "target")
    elseif event == "PLAYER_TARGET_CHANGED" then
        local npc
        if ns.IsMonster("target") then
            npc = ns.RecordTarget("target")
            pendingTarget = (npc == nil) -- el GUID era secreto: reintentar al salir de combate
        else
            pendingTarget = false
        end
        if ns.UpdateTarget then ns.UpdateTarget(npc) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingTarget and ns.IsMonster("target") then
            local npc = ns.RecordTarget("target")
            pendingTarget = (npc == nil)
            if npc and ns.UpdateTarget then ns.UpdateTarget(npc) end
        end
    elseif event == "LOOT_OPENED" then
        OnLootOpened()
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if ns.UpdateHealth then ns.UpdateHealth() end
    else
        if ns.UpdateTargetInfo then ns.UpdateTargetInfo() end
    end
end)

-- Comandos
SLASH_BESTIARYFOREVER1 = "/bf"
SLASH_BESTIARYFOREVER2 = "/bestiary"
SLASH_BESTIARYFOREVER3 = "/bestiario"
SlashCmdList.BESTIARYFOREVER = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
    local s = ns.settings
    if cmd == "" then
        ns.ToggleBestiary()
    elseif cmd == "frame" then
        s.showFrame = not s.showFrame
        ns.Print(s.showFrame and L.FRAME_ON or L.FRAME_OFF)
        if ns.UpdateTarget then ns.UpdateTarget() end
    elseif cmd == "lock" then
        s.locked = not s.locked
        ns.Print(s.locked and L.LOCKED or L.UNLOCKED)
    elseif cmd == "reset" then
        s.targetPoint, s.bestiaryPoint = nil, nil
        if ns.ResetPositions then ns.ResetPositions() end
        ns.Print(L.RESET)
    elseif cmd == "minkills" and tonumber(arg) then
        s.minKills = math.max(1, math.floor(tonumber(arg)))
        ns.InvalidateMerged()
        ns.Print(L.MINKILLS:format(s.minKills))
    elseif cmd == "about" then
        local meta = ns.lootMeta or {}
        ns.Print(L.ABOUT:format(ns.VERSION, meta.creatures or 0, meta.version or "?"))
    else
        ns.Print(L.HELP)
    end
end

function BestiaryForever_OnAddonCompartmentClick()
    ns.ToggleBestiary()
end
