-- Bestiary Forever - lista de botín con scroll (vista expandida y detalle del bestiario) y utilidades de ítems.
local _, ns = ...
local L = ns.L

local ROW_H = 18
local QUESTION_ICON = 134400
local lists = {}

-- Los nombres de ítems llegan del servidor de forma asíncrona: se pide la carga y se refresca después.
local refreshQueued = false
function ns.ScheduleRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.25, function()
        refreshQueued = false
        for _, list in ipairs(lists) do
            if list.frame:IsVisible() then list:Render() end
        end
        if ns.RefreshTargetIcons then ns.RefreshTargetIcons() end
    end)
end

local requested = {}
function ns.ItemName(id)
    local name = C_Item.GetItemNameByID(id)
    if not name and not requested[id] then
        requested[id] = true
        if C_Item.DoesItemExistByID(id) then
            Item:CreateFromItemID(id):ContinueOnItemLoad(ns.ScheduleRefresh)
        end
    end
    return name
end

-- Icono y calidad: los del juego si ya cargó el ítem; si no, los de la base de datos (API de ForeverDB).
function ns.ItemIcon(id)
    local icon = C_Item.GetItemIconByID(id)
    if icon and icon ~= QUESTION_ICON then return icon end
    local meta = ns.itemMeta and ns.itemMeta[id]
    return (meta and meta[2] and meta[2] > 0 and meta[2]) or icon or QUESTION_ICON
end

function ns.ItemQualityColor(id)
    local q = C_Item.GetItemQualityByID(id)
    if q == nil then
        local meta = ns.itemMeta and ns.itemMeta[id]
        q = meta and meta[1]
    end
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

function ns.ShowLootTooltip(owner, r, kills)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(r.item)
    GameTooltip:AddLine(" ")
    if r.dbPct then
        local src = r.dbSrc == "c" and L.SRC_CLASSIC or L.SRC_FOREVER
        GameTooltip:AddLine(L.TT_DB:format(ns.FormatPct(r.dbPct), src), 0.35, 0.75, 1)
    end
    if (r.dbSeen or 0) > 0 then
        GameTooltip:AddLine(L.TT_DB_SEEN:format(r.dbSeen), 0.7, 0.7, 0.7)
    end
    if (kills or 0) > 0 then
        GameTooltip:AddLine(L.TT_OWN:format(r.own or 0, kills, ns.FormatPct(r.ownPct or 0)), 0.4, 1, 0.4)
    else
        GameTooltip:AddLine(L.TT_OWN_NONE, 0.6, 0.6, 0.6)
    end
    local c = ns.TIER_COLORS[r.tier] or ns.TIER_COLORS.seen
    local best = r.pct and (ns.FormatPct(r.pct) .. "% - " .. ns.TierLabel(r, kills)) or ns.TierLabel(r, kills)
    GameTooltip:AddLine(L.TT_BEST:format(best), c[1], c[2], c[3])
    if r.tier == "classic" then GameTooltip:AddLine(L.TT_CLASSIC_NOTE, 1, 0.65, 0.25, true) end
    if r.quest then GameTooltip:AddLine(L.TT_QUEST, 1, 0.82, 0) end
    GameTooltip:Show()
end

local function OnRowClick(self)
    if not self.data then return end
    local _, link = C_Item.GetItemInfo(self.data.item)
    if link then HandleModifiedItemClick(link) end
end

local function CreateRow(list, i)
    local b = CreateFrame("Button", nil, list.content)
    b:SetSize(list.width, ROW_H)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ROW_H - 2, ROW_H - 2)
    b.icon:SetPoint("LEFT", 2, 0)

    b.pct = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.pct:SetPoint("RIGHT", -2, 0)
    b.pct:SetWidth(40)
    b.pct:SetJustifyH("RIGHT")

    b.tag = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.tag:SetPoint("RIGHT", b.pct, "LEFT", -4, 0)
    b.tag:SetWidth(58)
    b.tag:SetJustifyH("RIGHT")

    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
    b.name:SetPoint("RIGHT", b.tag, "LEFT", -4, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)

    b:SetScript("OnEnter", function(self) if self.data then ns.ShowLootTooltip(self, self.data, self.kills) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", OnRowClick)
    list.rows[i] = b
    return b
end

function ns.CreateLootList(parent, width, height)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetSize(width - 26, height)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(width - 26, 1)
    sf:SetScrollChild(content)

    local list = { frame = sf, content = content, rows = {}, width = width - 26 }

    list.empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    list.empty:SetPoint("TOPLEFT", 4, -4)
    list.empty:SetWidth(width - 34)
    list.empty:SetJustifyH("LEFT")

    function list:SetData(npc, emptyText)
        self.npc, self.emptyText = npc, emptyText
        self:Render()
        self.frame:SetVerticalScroll(0)
    end

    function list:Render()
        local rows, kills = ns.GetMergedLoot(self.npc)
        for i, r in ipairs(rows) do
            local b = self.rows[i] or CreateRow(self, i)
            b.data, b.kills = r, kills
            b.icon:SetTexture(ns.ItemIcon(r.item))
            b.name:SetText(ns.ItemName(r.item) or ("#" .. r.item))
            b.name:SetTextColor(ns.ItemQualityColor(r.item))
            local c = ns.TIER_COLORS[r.tier] or ns.TIER_COLORS.seen
            b.pct:SetText(r.pct and (ns.FormatPct(r.pct) .. "%") or "-")
            b.pct:SetTextColor(c[1], c[2], c[3])
            b.tag:SetText(ns.TierLabel(r, kills))
            b:Show()
        end
        for i = #rows + 1, #self.rows do
            self.rows[i]:Hide()
            self.rows[i].data = nil
        end
        self.content:SetHeight(math.max(1, #rows * ROW_H))
        self.empty:SetText(self.emptyText or L.NO_LOOT_DATA)
        self.empty:SetShown(#rows == 0)
    end

    lists[#lists + 1] = list
    return list
end
