-- Bestiary Forever - ventana compacta sin bordes del objetivo y su vista expandida.
local _, ns = ...
local L = ns.L
local safe = ns.safe

local WIDTH = 250
local ICONS = 8
local ICON_SIZE = 24
local QUESTION_ICON = 134400

local f, exp

local CLASS_LABEL = {
    elite = L.ELITE, rare = L.RARE, rareelite = L.RAREELITE, worldboss = L.WORLDBOSS, boss = L.BOSS,
}

local function SavePoint(frame, key)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    ns.settings[key] = { point, relPoint, x, y }
end

local function RestorePoint(frame, key, default)
    frame:ClearAllPoints()
    local p = ns.settings[key]
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint(unpack(default))
    end
end

local function MakeDraggable(frame, key)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(self)
        if not ns.settings.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePoint(self, key)
    end)
end
ns.MakeDraggable = MakeDraggable
ns.RestorePoint = RestorePoint

local function AddBackground(frame, alpha)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.03, 0.05, alpha)
    return bg
end

local function CreateIcon(parent, i)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b:SetPoint("BOTTOMLEFT", 4 + (i - 1) * (ICON_SIZE + 6), 14)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetColorTexture(1, 1, 1, 0.25)
    b.border:SetDrawLayer("BACKGROUND")
    b.pct = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.pct:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b.pct:SetFont(b.pct:GetFont(), 9, "OUTLINE")
    b:SetScript("OnEnter", function(self) if self.data then ns.ShowLootTooltip(self, self.data, self.kills) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if not self.data then return end
        local _, link = C_Item.GetItemInfo(self.data.item)
        if link then HandleModifiedItemClick(link) end
    end)
    return b
end

local function BuildExpanded()
    exp = CreateFrame("Frame", nil, f)
    exp:SetSize(WIDTH, 352)
    exp:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
    exp:EnableMouse(true)
    AddBackground(exp, 0.85)

    local model = CreateFrame("PlayerModel", nil, exp)
    model:SetSize(WIDTH - 8, 130)
    model:SetPoint("TOP", 0, -4)
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
    exp.model = model

    exp.header = exp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exp.header:SetPoint("TOPLEFT", model, "BOTTOMLEFT", 2, -6)
    exp.header:SetText(L.LOOT)

    exp.kills = exp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    exp.kills:SetPoint("LEFT", exp.header, "RIGHT", 8, 0)

    exp.list = ns.CreateLootList(exp, WIDTH - 4, 166)
    exp.list.frame:SetPoint("TOPLEFT", exp.header, "BOTTOMLEFT", -2, -4)

    exp.credit = exp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    exp.credit:SetPoint("BOTTOMLEFT", 6, 6)
    exp.credit:SetPoint("BOTTOMRIGHT", -6, 6)
    exp.credit:SetJustifyH("LEFT")
    exp.credit:SetText(L.CREDIT)
    exp:Hide()
end

local function SetExpanded(expanded)
    ns.settings.expanded = expanded
    if expanded then
        if not exp then BuildExpanded() end
        exp:Show()
        f.expand:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
        f.expand:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
        f.expand.tip = L.COLLAPSE
        ns.RefreshExpanded()
    else
        if exp then exp:Hide() end
        f.expand:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
        f.expand:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
        f.expand.tip = L.EXPAND
    end
end

function ns.InitTargetFrame()
    f = CreateFrame("Frame", "BestiaryForeverTargetFrame", UIParent)
    f:SetSize(WIDTH, 112)
    f:SetFrameStrata("MEDIUM")
    MakeDraggable(f, "targetPoint")
    RestorePoint(f, "targetPoint", { "TOP", UIParent, "TOP", 0, -110 })
    AddBackground(f, 0.65)

    local portraitBg = f:CreateTexture(nil, "BORDER")
    portraitBg:SetSize(56, 56)
    portraitBg:SetPoint("TOPLEFT", 4, -4)
    portraitBg:SetColorTexture(0, 0, 0, 0.6)

    f.portrait = CreateFrame("PlayerModel", nil, f)
    f.portrait:SetAllPoints(portraitBg)

    f.expand = CreateFrame("Button", nil, f)
    f.expand:SetSize(16, 16)
    f.expand:SetPoint("TOPRIGHT", -4, -4)
    f.expand:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    f.expand:SetScript("OnClick", function() SetExpanded(not ns.settings.expanded) end)
    f.expand:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tip or L.EXPAND)
        GameTooltip:Show()
    end)
    f.expand:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Abrir esta criatura en el bestiario (ficha completa y todo su botín)
    f.book = CreateFrame("Button", nil, f)
    f.book:SetSize(16, 16)
    f.book:SetPoint("RIGHT", f.expand, "LEFT", -4, 0)
    f.book:SetNormalTexture(ns.MARK)
    f.book:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    f.book:SetScript("OnClick", function() ns.OpenBestiaryAt(f.npc) end)
    f.book:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.OPEN_IN_BESTIARY)
        GameTooltip:Show()
    end)
    f.book:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.name:SetPoint("TOPLEFT", portraitBg, "TOPRIGHT", 6, -2)
    f.name:SetPoint("RIGHT", f.book, "LEFT", -4, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)

    f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.info:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
    f.info:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    f.info:SetJustifyH("LEFT")
    f.info:SetWordWrap(false)

    f.hp = CreateFrame("StatusBar", nil, f)
    f.hp:SetPoint("TOPLEFT", f.info, "BOTTOMLEFT", 0, -5)
    f.hp:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    f.hp:SetHeight(13)
    f.hp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.hp:SetStatusBarColor(0.8, 0.15, 0.15)
    local hpBg = f.hp:CreateTexture(nil, "BACKGROUND")
    hpBg:SetAllPoints()
    hpBg:SetColorTexture(0, 0, 0, 0.6)
    f.hp.text = f.hp:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    f.hp.text:SetPoint("CENTER")
    f.hp.text:SetFont(f.hp.text:GetFont(), 10, "OUTLINE")

    f.icons = {}
    for i = 1, ICONS do f.icons[i] = CreateIcon(f, i) end

    f.noLoot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.noLoot:SetPoint("BOTTOMLEFT", 6, 20)
    f.noLoot:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    f.noLoot:SetJustifyH("LEFT")

    f:Hide()
    SetExpanded(ns.settings.expanded)
end

function ns.ResetPositions()
    if f then RestorePoint(f, "targetPoint", { "TOP", UIParent, "TOP", 0, -110 }) end
    if ns.ResetBestiaryPosition then ns.ResetBestiaryPosition() end
end

function ns.UpdateTargetInfo()
    if not (f and f:IsShown()) then return end
    local unit = "target"
    local stored = f.npc and BestiaryForeverDB.creatures[f.npc]
    local name = safe(UnitName(unit)) or (stored and stored.name) or L.UNKNOWN
    f.name:SetText(name)
    local reaction = safe(UnitReaction(unit, "player"))
    local color = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if color then
        f.name:SetTextColor(color.r, color.g, color.b)
        f.hp:SetStatusBarColor(color.r, color.g, color.b)
    else
        f.name:SetTextColor(1, 0.82, 0)
    end

    local level = safe(UnitLevel(unit))
    local levelText
    if type(level) ~= "number" then
        levelText = "?"
    elseif level < 0 then
        levelText = "??"
    else
        levelText = tostring(level)
        if GetCreatureDifficultyColor then
            local c = GetCreatureDifficultyColor(level)
            if c then levelText = ("|cff%02x%02x%02x%d|r"):format(c.r * 255, c.g * 255, c.b * 255, level) end
        end
    end
    local parts = { L.LEVEL:format(levelText) }
    local class = safe(UnitClassification(unit))
    if class and CLASS_LABEL[class] then parts[#parts + 1] = "|cffffd100" .. CLASS_LABEL[class] .. "|r" end
    local ctype = safe(UnitCreatureType(unit))
    if ctype then parts[#parts + 1] = ctype end
    f.info:SetText(table.concat(parts, "  ·  "))
end

function ns.UpdateHealth()
    if not (f and f:IsShown()) then return end
    local hp, maxHp = UnitHealth("target"), UnitHealthMax("target")
    -- Los widgets aceptan valores secretos: la barra funciona también en combate.
    pcall(f.hp.SetMinMaxValues, f.hp, 0, maxHp)
    pcall(f.hp.SetValue, f.hp, hp)
    local h, m = safe(hp), safe(maxHp)
    if h and m and m > 0 then
        f.hp.text:SetFormattedText("%s / %s  (%d%%)", AbbreviateLargeNumbers(h), AbbreviateLargeNumbers(m), math.floor(h / m * 100 + 0.5))
    elseif not pcall(f.hp.text.SetFormattedText, f.hp.text, "%s / %s", hp, maxHp) then
        f.hp.text:SetText("")
    end
end

function ns.RefreshTargetIcons()
    if not (f and f:IsShown()) then return end
    local rows, kills = ns.GetMergedLoot(f.npc)
    for i, b in ipairs(f.icons) do
        local r = rows[i]
        if r then
            b.data, b.kills = r, kills
            b.tex:SetTexture(ns.ItemIcon(r.item) or QUESTION_ICON)
            local qr, qg, qb = ns.ItemQualityColor(r.item)
            b.border:SetColorTexture(qr, qg, qb, 0.8)
            local c = ns.TIER_COLORS[r.tier] or ns.TIER_COLORS.seen
            b.pct:SetText(r.pct and (ns.FormatPctShort(r.pct) .. "%") or "")
            b.pct:SetTextColor(c[1], c[2], c[3])
            b:Show()
            b.pct:Show()
        else
            b.data = nil
            b:Hide()
            b.pct:Hide()
        end
    end
    if #rows == 0 then
        f.noLoot:SetText(f.npc and L.NO_LOOT_DATA or L.NO_ID)
        f.noLoot:Show()
    else
        f.noLoot:Hide()
    end
end

function ns.RefreshExpanded()
    if not (exp and exp:IsShown() and f:IsShown()) then return end
    local _, kills = ns.GetMergedLoot(f.npc)
    exp.kills:SetText(L.KILLS:format(kills))
    exp.list:SetData(f.npc, not f.npc and L.NO_ID or nil)
    exp.model:ClearModel()
    exp.model:SetUnit("target")
    exp.model:SetPortraitZoom(0)
    exp.model.facing = 0
    exp.model:SetFacing(0)
end

function ns.RefreshTarget()
    if not (f and f:IsShown()) then return end
    ns.RefreshTargetIcons()
    if exp and exp:IsShown() then
        local _, kills = ns.GetMergedLoot(f.npc)
        exp.kills:SetText(L.KILLS:format(kills))
        exp.list:Render()
    end
end

function ns.UpdateTarget(npc)
    if not f then return end
    if not ns.settings.showFrame or not ns.IsMonster("target") then
        f.npc = nil
        f:Hide()
        return
    end
    f.npc = npc or ns.NpcIDFromGUID(UnitGUID("target"))
    f:Show()
    f.portrait:ClearModel()
    f.portrait:SetUnit("target")
    f.portrait:SetPortraitZoom(1)
    ns.UpdateTargetInfo()
    ns.UpdateHealth()
    ns.RefreshTargetIcons()
    ns.RefreshExpanded()
end
