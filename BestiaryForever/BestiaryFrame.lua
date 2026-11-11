-- Bestiary Forever - el libro del bestiario.
--   Pestaña Bestiario: barra lateral con continentes, zonas y mazmorras (descubiertas/total); cuadrícula tipo Pokédex
--   de la zona con siluetas negras de lo no descubierto; detalle completo de cada criatura con todo su botín.
--   Pestaña Objetos: búsqueda inversa, un objeto -> criaturas que lo sueltan (orden por %, A-Z o zona).
local _, ns = ...
local L = ns.L

local W, H = 820, 590
local SIDEBAR_W = 210
local MAIN_X = SIDEBAR_W + 22
local MAIN_W = W - MAIN_X - 14
local COLS = 4
local CELL_W = math.floor((MAIN_W - 26) / COLS)
local CELL_H = 156
local HEADER_H = 74
local QUESTION_ICON = 134400

local frame
local state = { tab = "bestiary", region = nil, detail = nil, item = nil, sort = "pct" }

---------------------------------------------------------------------------------------------- utilidades

local function FormatDate(t)
    return t and date("%Y-%m-%d %H:%M", t) or "-"
end

local function Background(parent, r, g, b, a)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    return t
end

local function Font(parent, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function NewScroll(parent, width, height)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetSize(width - 26, height)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(width - 26, 1)
    sf:SetScrollChild(content)
    sf.content = content
    return sf
end

-- Silueta: el modelo se ilumina en negro. Se prueban la API de luces actual y la antigua, y la niebla como respaldo.
local DARK, NORMAL
local function MakeLights()
    if DARK or not CreateVector3D or not CreateColor then return end
    DARK = { omnidirectional = false, point = CreateVector3D(0, 0, 0), ambientIntensity = 0, ambientColor = CreateColor(0, 0, 0),
             diffuseIntensity = 0, diffuseColor = CreateColor(0, 0, 0) }
    NORMAL = { omnidirectional = false, point = CreateVector3D(-1, 1, -1), ambientIntensity = 0.8, ambientColor = CreateColor(1, 1, 1),
               diffuseIntensity = 0.8, diffuseColor = CreateColor(1, 1, 1) }
end

local function SetSilhouette(model, dark)
    MakeLights()
    local light = dark and DARK or NORMAL
    local ok = light and pcall(model.SetLight, model, true, light)
    if not ok then
        if dark then
            pcall(model.SetLight, model, true, false, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        else
            pcall(model.SetLight, model, true, false, -1, 1, -1, 0.8, 1, 1, 1, 0.8, 1, 1, 1)
        end
    end
    if dark then
        pcall(model.SetFogColor, model, 0, 0, 0, 1)
        pcall(model.SetFogNear, model, 0)
        pcall(model.SetFogFar, model, 0.01)
    else
        pcall(model.ClearFog, model)
    end
end

local function SetCreatureModel(model, npc, discovered)
    model:ClearModel()
    -- Las partículas (fuego, brillos, auras) no responden a la luz: apagadas mientras no se ha descubierto.
    pcall(model.SetParticlesEnabled, model, discovered and true or false)
    local e = ns.creatureDB[npc]
    if discovered then
        if not pcall(model.SetCreature, model, npc) and e and e.d then pcall(model.SetDisplayInfo, model, e.d) end
    elseif e and e.d then
        pcall(model.SetDisplayInfo, model, e.d)
    else
        pcall(model.SetCreature, model, npc)
    end
    SetSilhouette(model, not discovered)
end

local function MakeRotatable(model)
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
    model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    model:SetScript("OnUpdate", function(self)
        if self.dragX then
            local x = GetCursorPosition()
            self.facing = (self.facing or 0) + (x - self.dragX) * 0.02
            self.dragX = x
            self:SetFacing(self.facing)
        end
    end)
end

local function RankText(npc)
    local e = ns.creatureDB[npc]
    local label = e and e.r and ns.RANK_LABELS[e.r]
    if not label and e and e.boss then label = L.BOSS end
    return label
end

local function LevelText(npc)
    local c = BestiaryForeverDB.creatures[npc]
    if c and c.skull then return "??" end
    if c and c.minLevel then
        return c.minLevel == c.maxLevel and tostring(c.minLevel) or (c.minLevel .. "-" .. c.maxLevel)
    end
    local e = ns.creatureDB[npc]
    return e and e.lv or "?"
end

local function TypeText(npc)
    local c = BestiaryForeverDB.creatures[npc]
    if c and c.ctype then return c.ctype .. (c.family and (" (" .. c.family .. ")") or "") end
    local e = ns.creatureDB[npc]
    return e and e.t and ns.CREATURE_TYPES[e.t]
end

---------------------------------------------------------------------------------------------- pestaña Bestiario

local RenderSidebar, RenderHeader, RenderGrid, ShowDetail, HideDetail

local function FilteredCreatures()
    local list = ns.GetRegionCreatures(state.region)
    local q = frame.search:GetText():lower()
    if q == "" then return list end
    local out = {}
    for i, npc in ipairs(list) do
        if ns.IsDiscovered(npc) then
            if ns.CreatureName(npc):lower():find(q, 1, true) or ("#%03d"):format(i):find(q, 1, true) then out[#out + 1] = npc end
        end
    end
    return out
end

local function SelectRegion(key)
    state.region = key
    frame.search:SetText("")
    frame.grid:SetVerticalScroll(0)
    HideDetail()
    RenderSidebar()
    RenderHeader()
    RenderGrid()
end

function RenderSidebar()
    local regions = ns.GetRegions()
    local content = frame.sidebar.content
    frame.sideRows = frame.sideRows or {}
    for i, reg in ipairs(regions) do
        local row = frame.sideRows[i]
        if not row then
            row = CreateFrame("Button", nil, content)
            row:SetSize(SIDEBAR_W - 26, 18)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 18)
            row.sel = row:CreateTexture(nil, "BACKGROUND")
            row.sel:SetAllPoints()
            row.sel:SetColorTexture(0.89, 0.71, 0.36, 0.22)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.name = Font(row, "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", 10, 0)
            row.name:SetPoint("RIGHT", -44, 0)
            row.count = Font(row, "GameFontDisableSmall", "RIGHT")
            row.count:SetPoint("RIGHT", -2, 0)
            row:SetScript("OnClick", function(self) if self.key then SelectRegion(self.key) end end)
            frame.sideRows[i] = row
        end
        if reg.header then
            row.key = nil
            row.name:SetFontObject("GameFontNormal")
            row.name:SetPoint("LEFT", 2, 0)
            row.name:SetText(reg.header)
            row.count:SetText("")
            row.sel:Hide()
            row:GetHighlightTexture():SetAlpha(0)
        else
            row.key = reg.key
            row.name:SetFontObject("GameFontHighlightSmall")
            row.name:SetPoint("LEFT", 10, 0)
            row.name:SetText(ns.RegionName(reg.key))
            local s = ns.RegionStats(reg.key)
            row.count:SetText(("%d/%d"):format(s.discovered, s.total))
            if s.total > 0 and s.discovered == s.total then row.count:SetTextColor(0.4, 1, 0.4) else row.count:SetTextColor(0.6, 0.6, 0.6) end
            row.sel:SetShown(reg.key == state.region)
            row:GetHighlightTexture():SetAlpha(1)
        end
        row:Show()
    end
    for i = #regions + 1, #frame.sideRows do frame.sideRows[i]:Hide() end
    content:SetHeight(math.max(1, #regions * 18))
end

function RenderHeader()
    local h = frame.header
    local s = ns.RegionStats(state.region)
    h.title:SetText(ns.RegionName(state.region))
    local lv = ns.RegionLevels(state.region)
    h.levels:SetText(lv and L.LEVEL:format(lv) or "")
    h.counter:SetText(("%d / %d"):format(s.discovered, s.total))
    h.mapBtn:SetShown(ns.RegionMap(state.region) ~= nil)
    h.stats[1].value:SetText(s.looted)
    h.stats[2].value:SetText(("%d/%d"):format(s.rares, s.raresTotal))
    h.stats[3].value:SetText(("%d/%d"):format(s.elites, s.elitesTotal))
    h.stats[4].value:SetText(("%d/%d"):format(s.bosses, s.bossesTotal))
end

-- Silueta, segunda parte: algunos modelos tienen materiales que brillan por sí mismos (fantasmas, elementales,
-- escorpiones) y la luz negra no los apaga. Encima del modelo va una capa que multiplica por SHADE: el negro sigue
-- negro y lo que brilla queda muy oscuro. Para que la capa no se vea como un recuadro, el fondo que hay debajo se
-- aclara en la misma proporción (fondo / SHADE), de modo que el resultado final es el color de fondo normal.
local SHADE = 0.22
local CELL_BG = { 0.09, 0.10, 0.14 }

local function CreateShade(parent, anchor)
    local shade = CreateFrame("Frame", nil, parent)
    shade:SetAllPoints(anchor or parent)
    shade:SetFrameLevel(parent:GetFrameLevel() + 3)
    local t = shade:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetColorTexture(SHADE, SHADE, SHADE, 1)
    t:SetBlendMode("MOD")
    shade:Hide()
    return shade
end

local function CreateCell(i)
    local cell = CreateFrame("Button", nil, frame.grid.content)
    cell:SetSize(CELL_W - 6, CELL_H - 6)
    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetAllPoints()
    cell.model = CreateFrame("PlayerModel", nil, cell)
    cell.model:SetPoint("TOPLEFT", 4, -4)
    cell.model:SetPoint("TOPRIGHT", -4, -4)
    cell.model:SetHeight(CELL_H - 50)
    cell.model:SetFrameLevel(cell:GetFrameLevel() + 1)
    cell.shade = CreateShade(cell)
    -- Textos y resaltado por encima de la capa de sombra, para que no se oscurezcan
    local top = CreateFrame("Frame", nil, cell)
    top:SetAllPoints()
    top:SetFrameLevel(cell:GetFrameLevel() + 5)
    cell.hover = top:CreateTexture(nil, "OVERLAY")
    cell.hover:SetAllPoints()
    cell.hover:SetColorTexture(0.89, 0.71, 0.36, 0.10)
    cell.hover:Hide()
    cell.name = Font(top, "GameFontHighlightSmall", "CENTER")
    cell.name:SetPoint("BOTTOMLEFT", 4, 22)
    cell.name:SetPoint("BOTTOMRIGHT", -4, 22)
    cell.num = Font(top, "GameFontDisableSmall")
    cell.num:SetPoint("BOTTOMLEFT", 6, 6)
    cell.tag = Font(top, "GameFontDisableSmall", "RIGHT")
    cell.tag:SetPoint("BOTTOMRIGHT", -6, 6)
    cell:SetScript("OnEnter", function(self) self.hover:Show() end)
    cell:SetScript("OnLeave", function(self) self.hover:Hide() end)
    cell:SetScript("OnClick", function(self) if self.npc then ShowDetail(self.npc) end end)
    frame.cells[i] = cell
    return cell
end

local function SetCellShaded(cell, shaded)
    if shaded then
        cell.bg:SetColorTexture(CELL_BG[1] / SHADE, CELL_BG[2] / SHADE, CELL_BG[3] / SHADE, 1)
        cell.shade:Show()
    else
        cell.bg:SetColorTexture(CELL_BG[1], CELL_BG[2], CELL_BG[3], 1)
        cell.shade:Hide()
    end
end

function RenderGrid()
    local list = FilteredCreatures()
    local all = ns.GetRegionCreatures(state.region)
    local numbers = {}
    for i, npc in ipairs(all) do numbers[npc] = i end
    local rows = math.ceil(#list / COLS)
    frame.grid.content:SetHeight(math.max(1, rows * CELL_H))
    local first = math.floor(frame.grid:GetVerticalScroll() / CELL_H)
    local visibleRows = math.ceil(frame.grid:GetHeight() / CELL_H) + 1
    local used = 0
    for r = 0, visibleRows - 1 do
        for col = 0, COLS - 1 do
            local i = (first + r) * COLS + col + 1
            local npc = list[i]
            if npc then
                used = used + 1
                local cell = frame.cells[used] or CreateCell(used)
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", col * CELL_W, -(first + r) * CELL_H)
                local discovered = ns.IsDiscovered(npc)
                if cell.npc ~= npc or cell.discovered ~= discovered then
                    cell.npc, cell.discovered = npc, discovered
                    SetCreatureModel(cell.model, npc, discovered)
                    SetCellShaded(cell, not discovered)
                end
                cell.num:SetText(("#%03d"):format(numbers[npc] or 0))
                if discovered then
                    cell.name:SetText(ns.CreatureName(npc))
                    cell.name:SetTextColor(1, 1, 1)
                    local rank = RankText(npc)
                    cell.tag:SetText(rank and ("|cffffd100" .. rank .. "|r") or ("|cff9a9cab" .. LevelText(npc) .. "|r"))
                else
                    cell.name:SetText(L.UNDISCOVERED)
                    cell.name:SetTextColor(0.45, 0.45, 0.5)
                    cell.tag:SetText("")
                end
                cell:Show()
            end
        end
    end
    for i = used + 1, #(frame.cells) do
        frame.cells[i]:Hide()
        frame.cells[i].npc = nil
    end
    frame.gridEmpty:SetShown(#list == 0)
end

function ShowDetail(npc)
    state.detail = npc
    local d = frame.detail
    local discovered = ns.IsDiscovered(npc)
    local region = state.region
    local number = region and ns.RegionNumber(region, npc)
    if not number then
        region = ns.PrimaryRegion(npc)
        number = ns.RegionNumber(region, npc)
    end
    d.num:SetText(number and ("#%03d"):format(number) or "")
    SetCreatureModel(d.model, npc, discovered)
    if discovered then
        d.mbg:SetColorTexture(0, 0, 0, 0.45)
        d.shade:Hide()
    else
        -- el fondo del modelo (~0.038, 0.041, 0.054 una vez compuesto) aclarado por SHADE, ver CreateShade
        d.mbg:SetColorTexture(0.038 / SHADE, 0.041 / SHADE, 0.054 / SHADE, 1)
        d.shade:Show()
    end
    d.model.facing = 0
    d.model:SetFacing(0)

    local zoneList = ns.CreatureZones(npc)
    d.mapBtn.map = zoneList[1] and zoneList[1].map
    d.mapBtn:SetShown(d.mapBtn.map ~= nil)
    local zones = table.concat(ns.CreatureZoneNames(npc), ", ")
    if discovered then
        local c = BestiaryForeverDB.creatures[npc]
        d.name:SetText(ns.CreatureName(npc))
        local lines = {}
        local rank = RankText(npc)
        lines[#lines + 1] = L.LEVELS:format(LevelText(npc)) .. (rank and ("   |cffffd100" .. rank .. "|r") or "")
        local t = TypeText(npc)
        if t then lines[#lines + 1] = L.TYPE:format(t) end
        if zones ~= "" then lines[#lines + 1] = L.ZONES:format(zones) end
        lines[#lines + 1] = L.SEEN_TIMES:format(c.seen or 0) .. "    " .. L.KILLS:format(c.kills or 0)
        if (c.money or 0) > 0 and GetMoneyString then lines[#lines + 1] = GetMoneyString(c.money, true) end
        lines[#lines + 1] = L.FIRST_SEEN:format(FormatDate(c.firstSeen))
        lines[#lines + 1] = L.LAST_SEEN:format(FormatDate(c.lastSeen))
        lines[#lines + 1] = "|cff7f7f7f" .. L.NPC_ID:format(npc) .. "|r"
        d.info:SetText(table.concat(lines, "\n"))
        d.list:SetData(npc)
        local _, kills = ns.GetMergedLoot(npc)
        d.lootHeader:SetText(L.LOOT .. "  |cff9a9cab" .. L.KILLS:format(kills) .. "|r")
    else
        d.name:SetText(L.UNDISCOVERED)
        local lines = {}
        if zones ~= "" then lines[#lines + 1] = L.ZONES:format(zones) end
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cff9a9cab" .. L.UNDISCOVERED_INFO .. "|r"
        d.info:SetText(table.concat(lines, "\n"))
        d.list:SetData(nil, L.UNDISCOVERED_LOOT)
        d.lootHeader:SetText(L.LOOT)
    end
    frame.header:Hide()
    frame.search:Hide()
    frame.grid:Hide()
    d:Show()
end

function HideDetail()
    state.detail = nil
    if not frame then return end
    frame.detail:Hide()
    frame.header:Show()
    frame.search:Show()
    frame.grid:Show()
end

local function BuildBestiaryPage(page)
    frame.sidebar = NewScroll(page, SIDEBAR_W, H - 36 - 40)
    frame.sidebar:SetPoint("TOPLEFT", 12, 0)
    local sideBg = page:CreateTexture(nil, "BACKGROUND")
    sideBg:SetPoint("TOPLEFT", frame.sidebar, -4, 4)
    sideBg:SetPoint("BOTTOMRIGHT", frame.sidebar, 22, -4)
    sideBg:SetColorTexture(0, 0, 0, 0.25)

    -- Cabecera de la región (como la tarjeta de región de una Pokédex)
    local h = CreateFrame("Frame", nil, page)
    h:SetPoint("TOPLEFT", MAIN_X, 0)
    h:SetSize(MAIN_W, HEADER_H)
    Background(h, 0.12, 0.13, 0.18, 0.95)
    h.title = Font(h, "GameFontNormalLarge")
    h.title:SetPoint("TOPLEFT", 12, -10)
    h.title:SetPoint("RIGHT", h, "RIGHT", -270, 0)
    h.levels = Font(h, "GameFontDisableSmall")
    h.levels:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -2)
    local pill = CreateFrame("Frame", nil, h)
    pill:SetSize(120, 26)
    pill:SetPoint("TOPRIGHT", -12, -10)
    Background(pill, 0.89, 0.71, 0.36, 0.9)
    h.counter = Font(pill, "GameFontHighlightLarge", "CENTER")
    h.counter:SetPoint("CENTER")
    h.counter:SetTextColor(0.08, 0.06, 0.02)
    h.mapBtn = CreateFrame("Button", nil, h, "UIPanelButtonTemplate")
    h.mapBtn:SetSize(112, 22)
    h.mapBtn:SetPoint("RIGHT", pill, "LEFT", -8, 0)
    h.mapBtn:SetText(L.OPEN_MAP)
    h.mapBtn:SetScript("OnClick", function() ns.OpenMap(ns.RegionMap(state.region)) end)
    h.stats = {}
    local labels = { L.LOOTED_SHORT, L.RARES_SHORT, L.ELITES_SHORT, L.BOSSES_SHORT }
    local statW = (MAIN_W - 24) / #labels
    for i, label in ipairs(labels) do
        local st = CreateFrame("Frame", nil, h)
        st:SetSize(statW, 30)
        st:SetPoint("BOTTOMLEFT", 12 + (i - 1) * statW, 6)
        st.value = Font(st, "GameFontNormal", "LEFT")
        st.value:SetPoint("LEFT", 0, 0)
        st.label = Font(st, "GameFontDisableSmall", "LEFT")
        st.label:SetPoint("LEFT", st.value, "RIGHT", 6, 0)
        st.label:SetText(label)
        h.stats[i] = st
    end
    frame.header = h

    frame.search = CreateFrame("EditBox", nil, page, "SearchBoxTemplate")
    frame.search:SetSize(220, 20)
    frame.search:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 6, -6)
    frame.search.Instructions:SetText(L.FILTER_ZONE)
    frame.search:HookScript("OnTextChanged", function()
        frame.grid:SetVerticalScroll(0)
        RenderGrid()
    end)

    frame.grid = NewScroll(page, MAIN_W, H - 36 - 40 - HEADER_H - 32)
    frame.grid:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -32)
    frame.grid:HookScript("OnVerticalScroll", function() RenderGrid() end)
    frame.cells = {}
    frame.gridEmpty = Font(frame.grid.content, "GameFontDisable", "LEFT")
    frame.gridEmpty:SetPoint("TOPLEFT", 8, -8)
    frame.gridEmpty:SetText(L.ITEM_NO_RESULTS)

    -- Detalle de una criatura
    local d = CreateFrame("Frame", nil, page)
    d:SetPoint("TOPLEFT", MAIN_X, 0)
    d:SetSize(MAIN_W, H - 36 - 40)
    Background(d, 0.07, 0.075, 0.10, 0.98)
    d.back = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.back:SetSize(90, 22)
    d.back:SetPoint("TOPLEFT", 8, -8)
    d.back:SetText("< " .. L.BACK)
    d.back:SetScript("OnClick", function()
        HideDetail()
        RenderGrid()
    end)
    d.num = Font(d, "GameFontDisable")
    d.num:SetPoint("LEFT", d.back, "RIGHT", 12, 0)
    d.name = Font(d, "GameFontNormalHuge")
    d.name:SetPoint("LEFT", d.num, "RIGHT", 8, 0)
    d.name:SetPoint("RIGHT", d, "RIGHT", -10, 0)

    d.model = CreateFrame("PlayerModel", nil, d)
    d.model:SetSize(230, 300)
    d.model:SetPoint("TOPLEFT", 8, -40)
    MakeRotatable(d.model)
    d.mapBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.mapBtn:SetSize(230, 22)
    d.mapBtn:SetPoint("TOPLEFT", d.model, "BOTTOMLEFT", 0, -6)
    d.mapBtn:SetText(L.OPEN_MAP)
    d.mapBtn:SetScript("OnClick", function(self) ns.OpenMap(self.map) end)
    d.mbg = d:CreateTexture(nil, "BORDER")
    d.mbg:SetAllPoints(d.model)
    d.mbg:SetColorTexture(0, 0, 0, 0.45)
    d.shade = CreateShade(d, d.model)

    d.info = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.info:SetPoint("TOPLEFT", d.model, "TOPRIGHT", 14, 0)
    d.info:SetPoint("RIGHT", d, "RIGHT", -10, 0)
    d.info:SetJustifyH("LEFT")
    d.info:SetJustifyV("TOP")
    d.info:SetSpacing(4)
    d.info:SetHeight(150)

    d.lootHeader = Font(d, "GameFontNormal")
    d.lootHeader:SetPoint("TOPLEFT", d.model, "TOPRIGHT", 14, -158)
    local listW = MAIN_W - 230 - 30
    d.list = ns.CreateLootList(d, listW, H - 36 - 40 - 40 - 158 - 30)
    d.list.frame:SetPoint("TOPLEFT", d.lootHeader, "BOTTOMLEFT", 0, -6)
    d:Hide()
    frame.detail = d
end

---------------------------------------------------------------------------------------------- pestaña Objetos

local RenderItemResults, RenderDroppers

local function SelectItem(item)
    state.item = item
    RenderItemResults()
    RenderDroppers()
end

function RenderItemResults()
    local ip = frame.itemsPage
    local q = ip.search:GetText()
    local results = ns.SearchItems(q, 300)
    ip.results = results
    ip.count:SetText(#q >= 2 and L.ITEM_RESULTS:format(#results) or "")
    ip.rows = ip.rows or {}
    for i, item in ipairs(results) do
        local row = ip.rows[i]
        if not row then
            row = CreateFrame("Button", nil, ip.list.content)
            row:SetSize(ip.list.content:GetWidth(), 20)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
            row.sel = row:CreateTexture(nil, "BACKGROUND")
            row.sel:SetAllPoints()
            row.sel:SetColorTexture(0.89, 0.71, 0.36, 0.22)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", 2, 0)
            row.count = Font(row, "GameFontDisableSmall", "RIGHT")
            row.count:SetPoint("RIGHT", -2, 0)
            row.name = Font(row, "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.name:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
            row:SetScript("OnClick", function(self) SelectItem(self.item) end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.item)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            ip.rows[i] = row
        end
        row.item = item
        row.icon:SetTexture(ns.ItemIcon(item) or QUESTION_ICON)
        row.name:SetText(ns.ItemDisplayName(item))
        row.name:SetTextColor(ns.ItemQualityColor(item))
        row.count:SetText(#ns.GetItemDroppers(item))
        row.sel:SetShown(item == state.item)
        row:Show()
    end
    for i = #results + 1, #ip.rows do ip.rows[i]:Hide() end
    ip.list.content:SetHeight(math.max(1, #results * 20))
    if #q < 2 then
        ip.empty:SetText(L.ITEM_SEARCH_HINT)
    else
        ip.empty:SetText(L.ITEM_NO_RESULTS)
    end
    ip.empty:SetShown(#results == 0)
end

local function DropperRows(item)
    local rows = {}
    for _, npc in ipairs(ns.GetItemDroppers(item)) do
        local merged, kills = ns.GetMergedLoot(npc)
        local found
        for _, r in ipairs(merged) do
            if r.item == item then found = r break end
        end
        local zones = ns.CreatureZones(npc)
        local zone = zones[1]
        local name = ns.CreatureName(npc)
        rows[#rows + 1] = {
            npc = npc, r = found, kills = kills, pct = found and found.pct,
            name = name, zone = zone and zone.name or L.UNKNOWN_ZONE, zoneMap = zone and zone.map,
            -- criaturas sin nombre conocido ("#123") y sin zona, al final de su orden
            sortName = (name:sub(1, 1) == "#" and "\255" or "") .. name:lower(),
            sortZone = (zone and "" or "\255") .. (zone and zone.name or ""):lower(),
            discovered = ns.IsDiscovered(npc),
        }
    end
    local mode = state.sort
    table.sort(rows, function(a, b)
        if mode == "name" then
            if a.sortName ~= b.sortName then return a.sortName < b.sortName end
        elseif mode == "zone" then
            if a.sortZone ~= b.sortZone then return a.sortZone < b.sortZone end
        end
        local pa, pb = a.pct or -1, b.pct or -1
        if pa ~= pb then return pa > pb end
        return a.sortName < b.sortName
    end)
    return rows
end

function RenderDroppers()
    local ip = frame.itemsPage
    local item = state.item
    for key, btn in pairs(ip.sortButtons) do
        if key == state.sort then btn:LockHighlight() else btn:UnlockHighlight() end
    end
    if not item then
        ip.itemIcon:SetTexture(nil)
        ip.itemName:SetText(L.SELECT_ITEM)
        ip.itemName:SetTextColor(0.6, 0.6, 0.6)
        ip.itemSub:SetText("")
        for _, row in ipairs(ip.drows or {}) do row:Hide() end
        return
    end
    ip.itemIcon:SetTexture(ns.ItemIcon(item) or QUESTION_ICON)
    ip.itemName:SetText(ns.ItemDisplayName(item))
    ip.itemName:SetTextColor(ns.ItemQualityColor(item))
    local rows = DropperRows(item)
    ip.itemSub:SetText(L.DROPPED_BY:format(#rows))
    ip.drows = ip.drows or {}
    local content = ip.dlist.content
    for i, data in ipairs(rows) do
        local row = ip.drows[i]
        if not row then
            row = CreateFrame("Button", nil, content)
            row:SetSize(content:GetWidth(), 20)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.pct = Font(row, "GameFontHighlightSmall", "RIGHT")
            row.pct:SetPoint("RIGHT", -2, 0)
            row.pct:SetWidth(44)
            row.tag = Font(row, "GameFontDisableSmall", "RIGHT")
            row.tag:SetPoint("RIGHT", row.pct, "LEFT", -4, 0)
            row.tag:SetWidth(62)
            -- Zona: botón que abre el mapa del mundo en esa zona
            row.zoneBtn = CreateFrame("Button", nil, row)
            row.zoneBtn:SetSize(140, 18)
            row.zoneBtn:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
            row.zone = Font(row.zoneBtn, "GameFontDisableSmall")
            row.zone:SetAllPoints()
            row.zoneBtn:SetScript("OnClick", function() ns.OpenMap(row.data and row.data.zoneMap) end)
            row.zoneBtn:SetScript("OnEnter", function(self)
                local data = row.data
                if not (data and data.zoneMap) then return end
                row.zone:SetTextColor(1, 0.82, 0)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L.OPEN_MAP_TT:format(data.zone))
                GameTooltip:Show()
            end)
            row.zoneBtn:SetScript("OnLeave", function()
                if row.zoneColor then row.zone:SetTextColor(unpack(row.zoneColor)) end
                GameTooltip:Hide()
            end)
            row.name = Font(row, "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", 4, 0)
            row.name:SetPoint("RIGHT", row.zoneBtn, "LEFT", -6, 0)
            row:SetScript("OnClick", function(self) ns.OpenBestiaryAt(self.npc) end)
            row:SetScript("OnEnter", function(self)
                if self.data.r then ns.ShowLootTooltip(self, self.data.r, self.data.kills) end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            ip.drows[i] = row
        end
        row.npc, row.data = data.npc, data
        if data.discovered then
            row.name:SetText(data.name)
            row.name:SetTextColor(1, 1, 1)
        else
            row.name:SetText(data.name .. "  |cff6f6f7a(" .. L.NOT_DISCOVERED_TAG .. ")|r")
            row.name:SetTextColor(0.6, 0.6, 0.65)
        end
        row.zone:SetText(data.zone)
        -- las zonas que abren el mapa, más claras; al pasar el ratón, doradas
        row.zoneColor = data.zoneMap and { 0.72, 0.74, 0.82 } or { 0.45, 0.45, 0.5 }
        row.zone:SetTextColor(unpack(row.zoneColor))
        row.zoneBtn:EnableMouse(data.zoneMap ~= nil)
        local r = data.r
        local c = ns.TIER_COLORS[r and r.tier or "seen"] or ns.TIER_COLORS.seen
        row.pct:SetText(data.pct and (ns.FormatPct(data.pct) .. "%") or "-")
        row.pct:SetTextColor(c[1], c[2], c[3])
        row.tag:SetText(r and ns.TierLabel(r, data.kills) or "")
        row:Show()
    end
    for i = #rows + 1, #ip.drows do ip.drows[i]:Hide() end
    content:SetHeight(math.max(1, #rows * 20))
    ip.dlist:SetVerticalScroll(0)
end

local function BuildItemsPage(page)
    local ip = {}
    frame.itemsPage = ip
    local leftW = 300
    ip.search = CreateFrame("EditBox", nil, page, "SearchBoxTemplate")
    ip.search:SetSize(leftW - 20, 20)
    ip.search:SetPoint("TOPLEFT", 20, -2)
    local pending
    ip.search:HookScript("OnTextChanged", function()
        if pending then pending:Cancel() end
        pending = C_Timer.NewTimer(0.25, function()
            pending = nil
            ip.list:SetVerticalScroll(0)
            RenderItemResults()
        end)
    end)
    ip.count = Font(page, "GameFontDisableSmall")
    ip.count:SetPoint("TOPLEFT", ip.search, "BOTTOMLEFT", -6, -6)
    ip.list = NewScroll(page, leftW, H - 36 - 40 - 52)
    ip.list:SetPoint("TOPLEFT", 12, -50)
    ip.empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    ip.empty:SetPoint("TOPLEFT", ip.list, "TOPLEFT", 6, -6)
    ip.empty:SetWidth(leftW - 40)
    ip.empty:SetJustifyH("LEFT")
    local listBg = page:CreateTexture(nil, "BACKGROUND")
    listBg:SetPoint("TOPLEFT", ip.list, -4, 4)
    listBg:SetPoint("BOTTOMRIGHT", ip.list, 22, -4)
    listBg:SetColorTexture(0, 0, 0, 0.25)

    local rx = leftW + 24
    local rw = W - rx - 14
    local head = CreateFrame("Frame", nil, page)
    head:SetPoint("TOPLEFT", rx, 0)
    head:SetSize(rw, 74)
    Background(head, 0.12, 0.13, 0.18, 0.95)
    ip.itemIcon = head:CreateTexture(nil, "ARTWORK")
    ip.itemIcon:SetSize(36, 36)
    ip.itemIcon:SetPoint("TOPLEFT", 10, -10)
    ip.itemName = Font(head, "GameFontNormalLarge")
    ip.itemName:SetPoint("TOPLEFT", ip.itemIcon, "TOPRIGHT", 10, -2)
    ip.itemName:SetPoint("RIGHT", head, "RIGHT", -10, 0)
    ip.itemSub = Font(head, "GameFontDisableSmall")
    ip.itemSub:SetPoint("TOPLEFT", ip.itemName, "BOTTOMLEFT", 0, -4)

    ip.sortButtons = {}
    local sorts = { { "pct", L.SORT_PCT }, { "name", L.SORT_NAME }, { "zone", L.SORT_ZONE } }
    for i, s in ipairs(sorts) do
        local b = CreateFrame("Button", nil, head, "UIPanelButtonTemplate")
        b:SetSize(86, 20)
        b:SetPoint("BOTTOMRIGHT", -10 - (#sorts - i) * 90, 8)
        b:SetText(s[2])
        b:SetScript("OnClick", function()
            state.sort = s[1]
            RenderDroppers()
        end)
        ip.sortButtons[s[1]] = b
    end
    ip.dlist = NewScroll(page, rw, H - 36 - 40 - 84)
    ip.dlist:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
end

---------------------------------------------------------------------------------------------- ventana

local function SetTab(tab)
    state.tab = tab
    frame.pageBestiary:SetShown(tab == "bestiary")
    frame.pageItems:SetShown(tab == "items")
    for key, b in pairs(frame.tabs) do
        if key == tab then
            b.text:SetTextColor(0.08, 0.06, 0.02)
            b.bg:SetColorTexture(0.89, 0.71, 0.36, 0.95)
        else
            b.text:SetTextColor(0.85, 0.85, 0.85)
            b.bg:SetColorTexture(1, 1, 1, 0.08)
        end
    end
    if tab == "items" then
        RenderItemResults()
        RenderDroppers()
        frame.itemsPage.search:SetFocus()
    end
end

local function CreateTab(key, label, x)
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(110, 22)
    b:SetPoint("TOPLEFT", x, -10)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.text = Font(b, "GameFontNormal", "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnClick", function() SetTab(key) end)
    frame.tabs[key] = b
end

local function Build()
    frame = CreateFrame("Frame", "BestiaryForeverFrame", UIParent, "BackdropTemplate")
    frame:SetSize(W, H)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.04, 0.045, 0.06, 0.96)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.25, 1)
    ns.MakeDraggable(frame, "bestiaryPoint")
    ns.RestorePoint(frame, "bestiaryPoint", { "CENTER", UIParent, "CENTER", 0, 30 })
    tinsert(UISpecialFrames, "BestiaryForeverFrame")

    local book = frame:CreateTexture(nil, "ARTWORK")
    book:SetSize(22, 22)
    book:SetPoint("TOPLEFT", 12, -10)
    book:SetTexture(ns.ICON)
    local title = Font(frame, "GameFontNormalLarge")
    title:SetPoint("LEFT", book, "RIGHT", 8, 0)
    title:SetText("Bestiary Forever")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    frame.tabs = {}
    CreateTab("bestiary", L.BESTIARY, MAIN_X)
    CreateTab("items", L.ITEMS, MAIN_X + 116)

    frame.pageBestiary = CreateFrame("Frame", nil, frame)
    frame.pageBestiary:SetPoint("TOPLEFT", 0, -40)
    frame.pageBestiary:SetPoint("BOTTOMRIGHT", 0, 34)
    frame.pageItems = CreateFrame("Frame", nil, frame)
    frame.pageItems:SetPoint("TOPLEFT", 0, -40)
    frame.pageItems:SetPoint("BOTTOMRIGHT", 0, 34)
    BuildBestiaryPage(frame.pageBestiary)
    BuildItemsPage(frame.pageItems)

    frame.credit = Font(frame, "GameFontDisableSmall", "RIGHT")
    frame.credit:SetPoint("BOTTOMRIGHT", -14, 12)
    frame.credit:SetText(L.CREDIT)

    frame:SetScript("OnShow", function()
        if not state.region then state.region = ns.CurrentRegion() or (ns.GetRegions()[2] and ns.GetRegions()[2].key) or "unknown" end
        RenderSidebar()
        RenderHeader()
        if state.detail then ShowDetail(state.detail) else RenderGrid() end
        SetTab(state.tab)
    end)
    frame:Hide()
end

function ns.ToggleBestiary()
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- Abre el bestiario en la ficha de una criatura (desde la ventana del objetivo o la búsqueda de objetos).
function ns.OpenBestiaryAt(npc)
    if not npc then return ns.ToggleBestiary() end
    if not frame then Build() end
    state.region = ns.PrimaryRegion(npc)
    state.tab = "bestiary"
    state.detail = npc
    if frame:IsShown() then
        SetTab("bestiary")
        RenderSidebar()
        RenderHeader()
        ShowDetail(npc)
    else
        frame:Show()
    end
end

function ns.ResetBestiaryPosition()
    if frame then ns.RestorePoint(frame, "bestiaryPoint", { "CENTER", UIParent, "CENTER", 0, 30 }) end
end

function ns.OnBestiaryChanged()
    if not (frame and frame:IsShown()) then return end
    RenderSidebar()
    RenderHeader()
    if state.detail then
        if frame.detail:IsShown() then ShowDetail(state.detail) end
    else
        RenderGrid()
    end
end

-- Busca un ítem en la pestaña Objetos y lo selecciona.
function ns.SearchItemInBestiary(item)
    if not frame then Build() end
    if not frame:IsShown() then frame:Show() end
    if state.tab ~= "items" then SetTab("items") end
    state.item = item
    frame.itemsPage.search:SetText(ns.ItemDisplayName(item))
    frame.itemsPage.search:ClearFocus()
    RenderItemResults()
    RenderDroppers()
end

---------------------------------------------------------------------------------------------- mayús+clic en un ítem

-- Con la pestaña Objetos abierta, mayús+clic en cualquier ítem del juego (bolsas, chat, personaje, botín...) lo busca.
-- Se engancha después de las funciones del juego (hooksecurefunc): no cambia lo que hacen, solo se entera del clic.
local lastLink = { id = nil, t = 0 }
local function OnItemLinkClicked(link)
    if not (frame and frame:IsShown() and state.tab == "items") then return end
    if not IsShiftKeyDown() then return end
    local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if not item then return end
    local now = GetTime()
    if lastLink.id == item and now - lastLink.t < 0.3 then return end -- un mismo clic puede llegar por dos ganchos
    lastLink.id, lastLink.t = item, now
    ns.SearchItemInBestiary(item)
end

if HandleModifiedItemClick then hooksecurefunc("HandleModifiedItemClick", OnItemLinkClicked) end
if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnItemLinkClicked) end
if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", OnItemLinkClicked) end
