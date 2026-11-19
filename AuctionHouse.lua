-- ProfitCraft: auction house integration.
--   * "Profit" tab (next to Auctionator's tabs): your profitable crafts with sortable columns; tick the
--     ones you want and turn their reagents into an Auctionator shopping list.
--   * Browse results (e.g. the Recipes category): gold/silver/bronze on the best recipe items you can
--     learn at your current skill and don't know yet.
local ADDON, ns = ...

local AH = {}
ns.AuctionHouse = AH

local TAB_ID = "ProfitCraft"
local LIST_NAME = "ProfitCraft"
local ROW_HEIGHT = 22
local NAME_LEFT = 52 -- checkbox + icon

-- Right-hand columns, right to left. "Disenchant" is laid out only for Enchanters.
local COLUMNS = {
    { key = "roi", title = "Return", width = 50 },
    { key = "profit", title = "Profit", width = 84 },
    { key = "cut", title = "AH cut", width = 72 },
    { key = "de", title = "Disenchant", width = 84, enchanting = true },
    { key = "sells", title = "Sells for", width = 84 },
    { key = "cost", title = "Reagent cost", width = 84 },
    { key = "prof", title = "Profession", width = 84, left = true },
}
local FIRST_RIGHT, GAP = -8, 6
local offsets = {}    -- column key -> right edge offset from the row's right edge (nil = hidden)
local layoutDE        -- whether the Disenchant column is currently laid out

local function AuctionatorAPI() return Auctionator and Auctionator.API and Auctionator.API.v1 end
local function TabLib() return LibStub and LibStub("LibAHTab-1-0", true) end

---------------------------------------------------------------------------
-- Shopping list
---------------------------------------------------------------------------
-- Walks a plan down to what you actually buy: crafted steps become their own reagents.
local function Collect(plan, crafts, buy, vendor)
    for _, part in ipairs(plan.parts) do
        local qty = part.qty * crafts
        if part.source == "craft" and part.plan then
            Collect(part.plan, math.ceil(qty / part.plan.yield - 1e-6), buy, vendor)
        elseif part.source == "vendor" then
            vendor[part.item] = (vendor[part.item] or 0) + qty
        else
            buy[part.item] = (buy[part.item] or 0) + qty
        end
    end
end

local function OpenShoppingTab()
    local lib = TabLib()
    local state = lib and lib.internalState
    if not state or not state.usedIDs then return false end
    for id, button in pairs(state.usedIDs) do
        local text = (button.GetText and button:GetText() or ""):lower()
        if id ~= TAB_ID and (id:lower():find("shopping") or text:find("shopping")) then
            return (pcall(lib.SetSelected, lib, id))
        end
    end
    return false
end

-- Returns a status message, or nil + true when item names are still loading (call again shortly).
function AH.CreateShoppingList(recipeResults, crafts, attempt)
    attempt = attempt or 1
    local api = AuctionatorAPI()
    if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
        return "This version of Auctionator can't make shopping lists for other addons."
    end
    if #recipeResults == 0 then return "Tick at least one craft first." end

    local buy, vendor = {}, {}
    for _, res in ipairs(recipeResults) do Collect(res.plan, crafts, buy, vendor) end

    local terms, owned, loading = {}, 0, false
    local nameOf = C_Item and C_Item.GetItemNameByID or GetItemInfo
    for itemID, qty in pairs(buy) do
        local need = math.ceil(qty - 1e-6) - ns.ItemCount(itemID)
        if need <= 0 then
            owned = owned + 1
        else
            local name = nameOf(itemID)
            if not name then
                loading = true
                if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
            else
                local ok, term = pcall(api.ConvertToSearchString, ADDON, { searchString = name, isExact = true, quantity = need })
                if ok and term then terms[#terms + 1] = { name = name, term = term } end
            end
        end
    end
    if loading and attempt < 4 then return nil, true end

    table.sort(terms, function(a, b) return a.name < b.name end)
    local strings = {}
    for i, t in ipairs(terms) do strings[i] = t.term end

    local vendorText = {}
    for itemID, qty in pairs(vendor) do
        local need = math.ceil(qty - 1e-6) - ns.ItemCount(itemID)
        if need > 0 then vendorText[#vendorText + 1] = need .. "x " .. ns.ItemName(itemID) end
    end
    table.sort(vendorText)

    local message
    if #strings == 0 then
        message = "You already have every auction house reagent in your bags or bank."
    else
        local ok, err = pcall(api.CreateShoppingList, ADDON, LIST_NAME, strings)
        if not ok then return "Couldn't create the shopping list: " .. tostring(err) end
        message = ("Shopping list \"%s\" created with %d item(s)."):format(LIST_NAME, #strings)
        if owned > 0 then message = message .. (" Skipped %d you already have."):format(owned) end
        if not OpenShoppingTab() then message = message .. " Find it in Auctionator's Shopping tab." end
    end
    if #vendorText > 0 then message = message .. "\nBuy from a vendor: " .. table.concat(vendorText, ", ") end
    return message
end

---------------------------------------------------------------------------
-- Profit tab
---------------------------------------------------------------------------
local panel
local rows, results, glowRanks, selected = {}, {}, {}, {}
local offset, defaultsPicked = 0, false
local sortKey, sortAscending -- nil = follow the "Rank glows by" setting

local function ProfName(res)
    local r = ns.db.recipes[res.recipeID]
    local prof = r and r.prof and ns.char.profs[r.prof]
    return prof and prof.name or ""
end

local SORT_VALUE = {
    name = function(res) return ns.ItemName(res.out):lower() end,
    prof = function(res) return ProfName(res):lower() end,
    cost = function(res) return res.plan.cost end,
    sells = function(res) return res.sellGross or 0 end,
    de = function(res) return res.de and res.de.gross or 0 end,
    cut = function(res) return res.cut or 0 end,
    profit = function(res) return res.profit end,
    roi = function(res) return res.roi or 0 end,
}

local function ActiveSort()
    if sortKey then return sortKey, sortAscending end
    return (ns.settings.rankBy == "profit") and "profit" or "roi", false
end

local function SortResults()
    local key, ascending = ActiveSort()
    local value = SORT_VALUE[key]
    table.sort(results, function(a, b)
        local va, vb = value(a), value(b)
        if va ~= vb then
            if ascending then return va < vb end
            return va > vb
        end
        return ns.Engine.Compare(a, b)
    end)
end

local function Rebuild()
    local ids = {}
    for rid in pairs(ns.KnownSet()) do ids[#ids + 1] = rid end
    results = ns.Engine:Rank(ids)
    glowRanks = ns.Engine:GlowRanks(ids)
    if not defaultsPicked and #results > 0 then
        for rid in pairs(glowRanks) do selected[rid] = true end
        defaultsPicked = true
    end
    SortResults()
    offset = math.max(0, math.min(offset, #results - #rows))
end

local function SelectedResults()
    local list = {}
    for _, res in ipairs(results) do
        if selected[res.recipeID] then list[#list + 1] = res end
    end
    return list
end

local function UpdateFooter()
    if not panel then return end
    local picked = SelectedResults()
    local crafts = ns.settings.crafts
    if #picked == 0 then
        panel.summary:SetText("Tick the crafts you want to buy reagents for.")
    else
        local cost, profit = 0, 0
        for _, res in ipairs(picked) do
            cost = cost + res.plan.cost * crafts
            profit = profit + res.profit * crafts
        end
        panel.summary:SetText(("%d craft(s) x%d:  reagents %s   profit |cff40ff40%s|r (%s)"):format(
            #picked, crafts, ns.Money(cost), ns.Money(profit), ns.Percent(cost > 0 and profit / cost or math.huge)))
    end
    panel.create:SetEnabled(#picked > 0)
end

local function Scroll(delta)
    local maxOffset = math.max(0, #results - #rows)
    offset = math.max(0, math.min(offset - delta * 3, maxOffset))
    AH.Refresh()
end

local function PlaceCells(row)
    for _, col in ipairs(COLUMNS) do
        local fs, right = row.cells[col.key], offsets[col.key]
        fs:ClearAllPoints()
        if right then
            fs:SetPoint("RIGHT", row, "RIGHT", right, 0)
            fs:Show()
        else
            fs:Hide()
        end
    end
end

local function PlaceHeader(header, col)
    local right = offsets[col.key]
    header:ClearAllPoints()
    if right then
        header:SetPoint("BOTTOMRIGHT", header:GetParent(), "TOPRIGHT", right, 4)
        header:Show()
    else
        header:Hide()
    end
end

-- Lays the columns out with or without "Disenchant" (shown only when you have Enchanting).
local function ApplyLayout(showDE)
    layoutDE = showDE
    wipe(offsets)
    local right = FIRST_RIGHT
    for _, col in ipairs(COLUMNS) do
        if showDE or not col.enchanting then
            offsets[col.key] = right
            right = right - col.width - GAP
        end
    end
    for _, col in ipairs(COLUMNS) do PlaceHeader(panel.headers[col.key], col) end
    for _, row in ipairs(rows) do PlaceCells(row) end
    if not showDE and sortKey == "de" then sortKey, sortAscending = nil, nil end
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.03)
    end

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.check:SetScript("OnClick", function(self)
        if row.res then selected[row.res.recipeID] = self:GetChecked() and true or nil end
        UpdateFooter()
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 4, 0)

    row.cells = {}
    for _, col in ipairs(COLUMNS) do
        local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetWidth(col.width)
        fs:SetJustifyH(col.left and "LEFT" or "RIGHT")
        fs:SetWordWrap(false)
        row.cells[col.key] = fs
    end
    PlaceCells(row)
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row, "LEFT", NAME_LEFT, 0)
    row.name:SetPoint("RIGHT", row.cells.prof, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnClick", function() row.check:Click() end)
    row:SetScript("OnEnter", function(self)
        if self.res then
            ns.Display.ShowForRow(self, ns.ItemName(self.res.out), self.res.recipeID, { rank = self.rank })
        end
    end)
    row:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
    return row
end

local function EnsureRows()
    local height = panel.list:GetHeight() or 0
    local count = height > ROW_HEIGHT and math.floor((height - 8) / ROW_HEIGHT) or 16
    for i = #rows + 1, count do rows[i] = CreateRow(panel.list.content, i) end
end

local function PaintHeaders()
    local key, ascending = ActiveSort()
    for headerKey, header in pairs(panel.headers) do
        local active = headerKey == key
        header.label:SetTextColor(1, active and 1 or 0.82, active and 1 or 0) -- white when sorted, gold otherwise
        header.arrow:SetShown(active)
        if active then
            if ascending then header.arrow:SetTexCoord(0, 0.5625, 0, 1) else header.arrow:SetTexCoord(0, 0.5625, 1, 0) end
        end
    end
end

local DIM = "|cff808080"

-- "Sells for" and "Disenchant" cells: the one that makes more (the craft's outlet) bright, the other dimmed.
local function OutletCells(row, res)
    local sold = res.outlet ~= "disenchant"
    if res.sellGross then
        row.cells.sells:SetText((sold and "" or DIM) .. ns.Money(res.sellGross) .. (sold and "" or "|r"))
    else
        row.cells.sells:SetText(DIM .. "no price|r")
    end
    local de = res.de
    if not de then
        row.cells.de:SetText("")
    elseif de.unknown then
        row.cells.de:SetText(DIM .. "unknown|r")
    elseif not de.gross then
        row.cells.de:SetText(DIM .. "no price|r")
    elseif sold then
        row.cells.de:SetText(DIM .. ns.Money(de.gross) .. "|r")
    else
        row.cells.de:SetText("|cffc799ff" .. ns.Money(de.gross) .. "|r")
    end
end

AH.rows = rows -- for the offline tests

function AH.Refresh()
    if not panel or not panel:IsShown() or not ns.IsReady() then return end
    local showDE = ns.Engine:EnchantingSkill() ~= nil
    if showDE ~= layoutDE then ApplyLayout(showDE) end
    EnsureRows()
    Rebuild()
    local minReturn = ns.settings.minReturn or 0
    for i, row in ipairs(rows) do
        local res = results[i + offset]
        row.res = res
        if res then
            local r = ns.db.recipes[res.recipeID]
            row.icon:SetTexture(ns.ItemIcon(res.out) or (r and r.icon))
            row.name:SetText(ns.ItemColoredName(res.out))
            row.cells.prof:SetText(ProfName(res))
            row.cells.cost:SetText(ns.Money(res.plan.cost))
            OutletCells(row, res)
            row.cells.cut:SetText("|cffff8c8c" .. ns.Money(-res.cut) .. "|r")
            row.cells.profit:SetText("|cff40ff40" .. ns.Money(res.profit) .. "|r")
            local thin = (res.roi or 0) * 100 < minReturn
            row.cells.roi:SetText((thin and "|cffff9933" or "|cff40ff40") .. ns.Percent(res.roi) .. "|r")
            row.check:SetChecked(selected[res.recipeID] or false)
            row.rank = glowRanks[res.recipeID]
            ns.Display.SetGlow(row, row.rank)
            row:Show()
        else
            row.rank = nil
            ns.Display.SetGlow(row, nil)
            row:Hide()
        end
    end
    if #results == 0 then
        panel.empty:SetText(ns.HasAuctionator()
            and "Nothing profitable yet.\nScan the auction house with Auctionator and open each of your profession windows once."
            or "Auctionator isn't loaded, so there are no prices.")
        panel.empty:Show()
    else
        panel.empty:Hide()
    end
    panel.more:SetText(#results > #rows and ("%d-%d of %d, scroll for more"):format(offset + 1,
        math.min(offset + #rows, #results), #results) or "")
    PaintHeaders()
    UpdateFooter()
end

local HEADER_HELP = {
    sells = "What the crafted item sells for on the AH. Dimmed when disenchanting it pays more.",
    de = "Enchanting: what the item's disenchanted mats sell for on the AH, on average. Dimmed when selling the item "
        .. "pays more.",
    profit = "From selling the item, or disenchanting it when that pays more.",
}

local function CreateHeader(parent, key, title, col)
    local header = CreateFrame("Button", nil, parent)
    header:SetHeight(16)
    if col then
        header:SetWidth(col.width) -- placed by ApplyLayout
    else
        header:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", NAME_LEFT, 4)
        header:SetWidth(160)
    end
    header.label = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header.label:SetText(title)
    header.arrow = header:CreateTexture(nil, "ARTWORK")
    header.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    header.arrow:SetSize(9, 8)
    header.arrow:Hide()
    if col and not col.left then
        header.label:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        header.arrow:SetPoint("RIGHT", header.label, "LEFT", -2, 0)
    else
        header.label:SetPoint("LEFT", header, "LEFT", 0, 0)
        header.arrow:SetPoint("LEFT", header.label, "RIGHT", 2, 0)
    end
    header:SetScript("OnClick", function()
        local current, ascending = ActiveSort()
        if current == key then
            sortKey, sortAscending = key, not ascending
        else
            -- text columns start A-Z, numbers start biggest first
            sortKey, sortAscending = key, (key == "name" or key == "prof")
        end
        offset = 0
        AH.Refresh()
    end)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if HEADER_HELP[key] then GameTooltip:AddLine(HEADER_HELP[key], 1, 0.82, 0, true) end
        GameTooltip:AddLine("Click to sort, click again to flip", 1, 1, 1)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.headers[key] = header
end

local function SetStatus(text)
    panel.status:SetText(text or "")
end

local function OnCreateClicked(attempt)
    local message, retry = AH.CreateShoppingList(SelectedResults(), ns.settings.crafts, attempt)
    if retry then
        SetStatus("Loading item names...")
        C_Timer.After(0.5, function() OnCreateClicked((attempt or 1) + 1) end)
        return
    end
    SetStatus(message)
end

local function BuildPanel()
    panel = CreateFrame("Frame", "ProfitCraftAuctionPanel", AuctionHouseFrame)
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 12, -52)
    panel:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -12, 30)
    panel:Hide()
    panel.headers = {}

    local okInset, list = pcall(CreateFrame, "Frame", nil, panel, "InsetFrameTemplate")
    if not okInset or not list then list = CreateFrame("Frame", nil, panel) end
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 44)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
    list.content = CreateFrame("Frame", nil, list)
    list.content:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4)
    list.content:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, 4)
    panel.list = list

    CreateHeader(list.content, "name", "Craft")
    for _, col in ipairs(COLUMNS) do CreateHeader(list.content, col.key, col.title, col) end

    panel.empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.empty:SetPoint("CENTER")
    panel.empty:SetWidth(420)

    panel.more = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.more:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -4, -2)

    -- footer
    local countLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    countLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 12)
    countLabel:SetText("Crafts of each:")

    local count = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    count:SetSize(36, 20)
    count:SetPoint("LEFT", countLabel, "RIGHT", 10, 0)
    count:SetAutoFocus(false)
    count:SetNumeric(true)
    count:SetMaxLetters(3)
    count:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    count:SetScript("OnEditFocusLost", function(self)
        local n = math.max(1, tonumber(self:GetText()) or 1)
        ns.settings.crafts = n
        self:SetText(tostring(n))
        UpdateFooter()
    end)
    count:SetScript("OnTextChanged", function(self, userInput)
        local n = tonumber(self:GetText())
        if userInput and n then
            ns.settings.crafts = math.max(1, n)
            UpdateFooter()
        end
    end)
    panel.count = count

    panel.create = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.create:SetSize(180, 22)
    panel.create:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 10)
    panel.create:SetText("Create Shopping List")
    panel.create:SetScript("OnClick", function() OnCreateClicked(1) end)

    local refresh = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refresh:SetSize(90, 22)
    refresh:SetPoint("RIGHT", panel.create, "LEFT", -6, 0)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function()
        ns.Engine:Invalidate()
        SetStatus("")
        AH.Refresh()
    end)

    panel.summary = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.summary:SetPoint("TOPLEFT", count, "TOPRIGHT", 16, 6)
    panel.summary:SetPoint("RIGHT", refresh, "LEFT", -10, 0)
    panel.summary:SetJustifyH("LEFT")

    panel.status = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    panel.status:SetPoint("TOPLEFT", panel.summary, "BOTTOMLEFT", 0, -3)
    panel.status:SetPoint("RIGHT", refresh, "LEFT", -10, 0)
    panel.status:SetJustifyH("LEFT")

    panel:SetScript("OnShow", function()
        count:SetText(tostring(ns.settings.crafts))
        AH.Refresh()
    end)
end

function AH.TryCreateTab()
    if panel or not AuctionHouseFrame or not ns.IsReady() then return end
    local lib = TabLib()
    if not lib or lib:DoesIDExist(TAB_ID) then return end
    BuildPanel()
    local ok, err = pcall(lib.CreateTab, lib, TAB_ID, panel, "Profit", "ProfitCraft - Most Profitable Crafts")
    if not ok and ns.debug then ns.Print("couldn't add the AH tab:", err) end
    AH.tabCreated = ok
end

-- Called when the "Rank glows by" setting changes: the tab follows it again.
function AH.ResetSort()
    sortKey, sortAscending = nil, nil
    offset = 0
end

---------------------------------------------------------------------------
-- Browse results: highlight learnable, profitable recipe items
---------------------------------------------------------------------------
local browseRanks, browseDirty, browseHooked = {}, true, false

local function BrowseBox()
    local frame = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
    return frame and frame.ItemList and frame.ItemList.ScrollBox
end

local function RowItemID(row)
    local data
    if row.GetElementData then
        local ok, d = pcall(row.GetElementData, row)
        if ok then data = d end
    end
    if type(data) ~= "table" then data = row.rowData end
    local key = type(data) == "table" and data.itemKey
    return key and key.itemID or nil
end

local function RecomputeBrowse()
    browseDirty = false
    wipe(browseRanks)
    if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return end
    local ranks = ns.RecipeItems.ProfessionRanks()
    local candidates, seen = {}, {}
    for _, result in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        local itemID = result.itemKey and result.itemKey.itemID
        if itemID and not seen[itemID] then
            seen[itemID] = true
            local rid = ns.RecipeItems.Lookup(itemID)
            if rid and ns.RecipeItems.LearnStatus(itemID, rid, ranks) == "learnable" then
                local res = ns.Engine:Evaluate(rid)
                if ns.Engine.Qualifies(res) then candidates[#candidates + 1] = { item = itemID, res = res } end
            end
        end
    end
    table.sort(candidates, function(a, b) return ns.Engine.Compare(a.res, b.res) end)
    for i = 1, math.min(ns.Display.MAX_RANK, #candidates) do browseRanks[candidates[i].item] = i end
end

function AH.BrowseRank(itemID)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return nil end
    return browseRanks[itemID]
end

function AH.PaintBrowse()
    local box = BrowseBox()
    if not box or not box:IsVisible() or not ns.IsReady() then return end
    if browseDirty then RecomputeBrowse() end
    box:ForEachFrame(function(row)
        local itemID = RowItemID(row)
        ns.Display.SetGlow(row, itemID and browseRanks[itemID] or nil)
    end)
end

local function BrowseChanged()
    browseDirty = true
    C_Timer.After(0, AH.PaintBrowse)
    -- item tooltips (skill requirements) may still be loading; look again shortly
    ns.Debounce("browse-late", 1, function()
        browseDirty = true
        AH.PaintBrowse()
    end)
end

function AH.TryHookBrowse()
    if browseHooked then return end
    local box = BrowseBox()
    if not box or type(box.Update) ~= "function" then return end
    browseHooked = true
    AH.browseHooked = true
    hooksecurefunc(box, "Update", AH.PaintBrowse)
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
ns.On("AUCTION_HOUSE_SHOW", function()
    C_Timer.After(0, function()
        AH.TryCreateTab()
        AH.TryHookBrowse()
        BrowseChanged()
    end)
end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", BrowseChanged)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", BrowseChanged)
ns.OnDataChanged(function()
    browseDirty = true
    AH.PaintBrowse()
    AH.Refresh()
end)
