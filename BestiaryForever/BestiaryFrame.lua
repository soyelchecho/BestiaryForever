-- Bestiary Forever - ventana del bestiario: criaturas vistas, búsqueda y detalle con su botín.
local _, ns = ...
local L = ns.L

local W, H = 600, 440
local LIST_W = 220
local ROW_H = 20

local frame, rowsPool, filtered, selected = nil, {}, {}, nil

local CLASS_LABEL = {
    elite = L.ELITE, rare = L.RARE, rareelite = L.RAREELITE, worldboss = L.WORLDBOSS, boss = L.BOSS,
}

local function LevelText(c)
    if c.skull then return "??" end
    if not c.minLevel then return "?" end
    if c.minLevel == c.maxLevel then return tostring(c.minLevel) end
    return c.minLevel .. "-" .. c.maxLevel
end

local function FormatDate(t)
    return t and date("%Y-%m-%d %H:%M", t) or "-"
end

local function Rebuild()
    wipe(filtered)
    local query = frame.search:GetText():lower()
    for npc, c in pairs(BestiaryForeverDB.creatures) do
        local name = c.name or ("#" .. npc)
        if query == "" or name:lower():find(query, 1, true) or (c.zone and c.zone:lower():find(query, 1, true)) then
            filtered[#filtered + 1] = npc
        end
    end
    local db = BestiaryForeverDB.creatures
    table.sort(filtered, function(a, b)
        local na, nb = db[a].name or "", db[b].name or ""
        if na ~= nb then return na < nb end
        return a < b
    end)
    frame.count:SetText(L.DISCOVERED:format(#filtered))
end

local function ShowDetail(npc)
    selected = npc
    local d = frame.detail
    local c = npc and BestiaryForeverDB.creatures[npc]
    if not c then
        d.name:SetText("")
        d.info:SetText(L.SELECT_CREATURE)
        d.model:ClearModel()
        d.list:SetData(nil, " ")
        return
    end
    d.name:SetText(c.name or ("#" .. npc))
    local lines = { L.LEVELS:format(LevelText(c)) .. (c.class and CLASS_LABEL[c.class] and ("  ·  |cffffd100" .. CLASS_LABEL[c.class] .. "|r") or "") }
    if c.ctype then lines[#lines + 1] = L.TYPE:format(c.ctype .. (c.family and (" (" .. c.family .. ")") or "")) end
    if c.zone then lines[#lines + 1] = L.ZONE:format(c.zone) end
    lines[#lines + 1] = L.SEEN_TIMES:format(c.seen or 0) .. "   " .. L.KILLS:format(c.kills or 0)
    if (c.money or 0) > 0 and GetMoneyString then lines[#lines + 1] = GetMoneyString(c.money, true) end
    lines[#lines + 1] = L.FIRST_SEEN:format(FormatDate(c.firstSeen))
    lines[#lines + 1] = L.LAST_SEEN:format(FormatDate(c.lastSeen))
    d.info:SetText(table.concat(lines, "\n"))
    d.model:ClearModel()
    if d.model.SetCreature then pcall(d.model.SetCreature, d.model, npc) end
    d.list:SetData(npc)
end

local function RenderList()
    local offset = math.floor(frame.scroll:GetVerticalScroll() / ROW_H)
    local visible = math.ceil(frame.scroll:GetHeight() / ROW_H) + 1
    frame.content:SetHeight(math.max(1, #filtered * ROW_H))
    for i = 1, visible do
        local row = rowsPool[i]
        if not row then
            row = CreateFrame("Button", nil, frame.content)
            row:SetSize(LIST_W - 26, ROW_H)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.sel = row:CreateTexture(nil, "BACKGROUND")
            row.sel:SetAllPoints()
            row.sel:SetColorTexture(1, 0.82, 0, 0.18)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", 4, 0)
            row.name:SetPoint("RIGHT", -34, 0)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
            row.level = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.level:SetPoint("RIGHT", -2, 0)
            row:SetScript("OnClick", function(self) ShowDetail(self.npc); RenderList() end)
            rowsPool[i] = row
        end
        local npc = filtered[offset + i]
        if npc then
            local c = BestiaryForeverDB.creatures[npc]
            row.npc = npc
            row:SetPoint("TOPLEFT", 0, -(offset + i - 1) * ROW_H)
            row.name:SetText(c.name or ("#" .. npc))
            row.level:SetText(LevelText(c))
            row.sel:SetShown(npc == selected)
            row:Show()
        else
            row.npc = nil
            row:Hide()
        end
    end
    frame.empty:SetShown(#filtered == 0)
end

local function Build()
    frame = CreateFrame("Frame", "BestiaryForeverFrame", UIParent, "BackdropTemplate")
    frame:SetSize(W, H)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.03, 0.03, 0.05, 0.92)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.25, 1)
    ns.MakeDraggable(frame, "bestiaryPoint")
    ns.RestorePoint(frame, "bestiaryPoint", { "CENTER", UIParent, "CENTER", 0, 40 })
    tinsert(UISpecialFrames, "BestiaryForeverFrame")

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 14, -12)
    frame.title:SetText(L.BESTIARY)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    frame.search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    frame.search:SetSize(LIST_W - 14, 20)
    frame.search:SetPoint("TOPLEFT", 18, -40)
    frame.search:HookScript("OnTextChanged", function()
        Rebuild()
        frame.scroll:SetVerticalScroll(0)
        RenderList()
    end)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 12, -66)
    frame.scroll:SetSize(LIST_W - 26, H - 66 - 40)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(LIST_W - 26, 1)
    frame.scroll:SetScrollChild(frame.content)
    frame.scroll:HookScript("OnVerticalScroll", RenderList)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", frame.scroll, "TOPLEFT", 4, -4)
    frame.empty:SetWidth(LIST_W - 34)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetText(L.EMPTY_BESTIARY)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.6, 0.5, 0.25, 0.5)
    divider:SetSize(1, H - 50)
    divider:SetPoint("TOPLEFT", LIST_W + 4, -36)

    local d = CreateFrame("Frame", nil, frame)
    d:SetPoint("TOPLEFT", LIST_W + 12, -36)
    d:SetPoint("BOTTOMRIGHT", -12, 34)
    frame.detail = d

    d.model = CreateFrame("PlayerModel", nil, d)
    d.model:SetSize(150, 170)
    d.model:SetPoint("TOPLEFT", 0, 0)
    local modelBg = d:CreateTexture(nil, "BACKGROUND")
    modelBg:SetAllPoints(d.model)
    modelBg:SetColorTexture(0, 0, 0, 0.45)

    d.name = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.name:SetPoint("TOPLEFT", d.model, "TOPRIGHT", 10, -2)
    d.name:SetPoint("RIGHT", d, "RIGHT", 0, 0)
    d.name:SetJustifyH("LEFT")

    d.info = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.info:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -6)
    d.info:SetPoint("RIGHT", d, "RIGHT", 0, 0)
    d.info:SetJustifyH("LEFT")
    d.info:SetSpacing(3)

    local lootHeader = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lootHeader:SetPoint("TOPLEFT", d.model, "BOTTOMLEFT", 0, -8)
    lootHeader:SetText(L.LOOT)

    local listW = W - LIST_W - 24
    d.list = ns.CreateLootList(d, listW, H - 36 - 34 - 170 - 30)
    d.list.frame:SetPoint("TOPLEFT", lootHeader, "BOTTOMLEFT", 0, -4)

    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.count:SetPoint("BOTTOMLEFT", 16, 14)

    frame.credit = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.credit:SetPoint("BOTTOMRIGHT", -14, 14)
    frame.credit:SetText(L.CREDIT)

    frame:SetScript("OnShow", function()
        Rebuild()
        RenderList()
        ShowDetail(selected)
    end)
    frame:Hide()
end

function ns.ToggleBestiary()
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
    else
        local target = ns.IsMonster("target") and ns.NpcIDFromGUID(UnitGUID("target"))
        if target and BestiaryForeverDB.creatures[target] then selected = target end
        frame:Show()
    end
end

function ns.ResetBestiaryPosition()
    if frame then ns.RestorePoint(frame, "bestiaryPoint", { "CENTER", UIParent, "CENTER", 0, 40 }) end
end

function ns.OnBestiaryChanged()
    if frame and frame:IsShown() then
        Rebuild()
        RenderList()
        if selected then ShowDetail(selected) end
    end
end
