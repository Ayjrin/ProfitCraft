-- ProfitCraft: the "Plays" tab on the auction house.
--
--   left    every play open to this character, ranked (tier, profit, gold per minute of your time, gold needed)
--   right   the selected play: its steps, numbers, two reasons for, two against, or why it's locked
--   bottom  the step button: each press does the next single thing (search, buy one listing, confirm a
--           quote, post one auction). Right-click skips what it offers. Optional: scroll down over it.
-- Mailbox, disenchanting and essence conversions happen on the Work button (Work.lua), away from the AH.
local _, ns = ...

local Tab = {}
ns.PlaysTab = Tab

local TAB_ID = "ProfitCraftPlays"
local ROW_HEIGHT = 38
local LIST_WIDTH = 360

local panel
local rows = {}
local plays = {}
local selectedID
local offset = 0
local current -- the step button's current action

local function TabLib() return LibStub and LibStub("LibAHTab-1-0", true) end
local function Tier(play) return ns.Plays.TIERS[play.tier] end

local RISK_ORDER = { "safe", "balanced", "aggressive" }
local RISK_LABEL = { safe = "Safe plays", balanced = "Safe + timing plays", aggressive = "All plays, risky too" }

---------------------------------------------------------------------------
-- The step button
---------------------------------------------------------------------------
local function HasMarketData()
    for _, id in ipairs(ns.Disenchant.MAT_IDS) do
        if ns.OrderBook.Get(id) then return true end
    end
    return #ns.OrderBook.BrowseRows() > 0
end

local function CurrentAction()
    local buy = ns.Buy.Next()
    if buy then return buy, "buy" end
    local post = ns.Post.Next()
    if post then return post, "post" end
    if ns.Scanner.Busy() then
        local done, total = ns.Scanner.Progress()
        return { kind = "wait", label = ("Searching the auction house... %d of %d"):format(done, total), enabled = false }, "scan"
    end
    local active = ns.Buy.Active()
    if active and active.bought > 0 then
        return { kind = "finish", enabled = true,
            label = ("Done here: %d bought. Next: mailbox and the Work button"):format(active.bought) }, "finish"
    end
    return { kind = "scan", enabled = true, label = HasMarketData() and "Scan the market again" or "Scan the market" }, "scan"
end

local PaintAction

-- A press does what the button showed, or nothing: if things changed since it was painted (a new quantity, a
-- different listing), it just repaints so you see the new offer before anything happens.
local function Same(a, b) return a and b and a.kind == b.kind and a.label == b.label end

local function Press(mouse)
    if not (panel and panel:IsShown()) or ns.Profile.InCombat() then return end
    local action, source = CurrentAction()
    if not action then return end
    if mouse ~= "RightButton" and not Same(action, current) then
        PaintAction()
        return
    end
    if mouse == "RightButton" then
        if source == "buy" then ns.Buy.Skip(action) elseif source == "post" then ns.Post.Skip(action) end
        Tab.Refresh()
        return
    end
    if not action.enabled then return end
    if source == "buy" then ns.Buy.Click(action)
    elseif source == "post" then ns.Post.Click(action)
    elseif source == "finish" then ns.Buy.Stop()
    elseif source == "scan" then ns.Scanner.ScanMarket() end
    Tab.Refresh()
end

-- Scroll-down over the step button presses its key twin, only while the cursor is on the button.
local function SetWheel(self, on)
    if ns.Profile.InCombat() then return end
    if on and ns.settings.wheel then
        SetOverrideBindingClick(self, true, "MOUSEWHEELDOWN", "ProfitCraftAHKey", "LeftButton")
    else
        ClearOverrideBindings(self)
    end
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------
local function Selected()
    for _, play in ipairs(plays) do if play.id == selectedID then return play end end
end

local function PaintRow(row, play)
    row.play = play
    if not play then row:Hide(); return end
    local t = Tier(play)
    row.tier:SetText("|c" .. t.color .. t.label .. "|r")
    row.title:SetText(play.title)
    if play.tier == "locked" then
        row.info:SetText("|cff999999" .. (play.locked or "") .. "|r")
    else
        row.info:SetText(("|cff40ff40+%s|r   %s/min   needs %s"):format(ns.Money(play.profit), ns.Money(play.perMinute),
            ns.Money(play.cost)))
    end
    row.selected:SetShown(play.id == selectedID)
    local active = ns.Buy.Active()
    row.active:SetShown(active ~= nil and active.id == play.id)
    row:Show()
end

local function Lines(list, prefix, color)
    local out = {}
    for _, text in ipairs(list or {}) do out[#out + 1] = color .. prefix .. "|r " .. text end
    return table.concat(out, "\n")
end

local function PaintDetail()
    local d = panel.detail
    local play = Selected()
    if not play then
        d.title:SetText("Pick a play")
        d.body:SetText("Plays are ranked by profit for the time they take, after the AH cut, deposits and luck. "
            .. "Scan the market first so the numbers are live.")
        d.start:Hide()
        return
    end
    local t = Tier(play)
    d.title:SetText(play.title)
    local parts = {}
    parts[#parts + 1] = ("|c%s%s|r  %s"):format(t.color, t.label, t.help)
    parts[#parts + 1] = " "
    for i, step in ipairs(play.steps or {}) do parts[#parts + 1] = ("%d. %s"):format(i, step) end
    parts[#parts + 1] = " "
    if play.profit then
        parts[#parts + 1] = ("Gold needed: %s    Brings in: %s    |cff40ff40Profit: %s|r"):format(ns.Money(play.cost or 0),
            ns.Money(play.revenue or 0), ns.Money(play.profit))
        parts[#parts + 1] = ("About %d min of your time (%s a minute)"):format(math.floor(play.minutes + 0.5),
            ns.Money(play.perMinute))
    end
    if play.need and play.need < math.huge and play.kind == "disenchant" then
        parts[#parts + 1] = ("Luck check: %d items gives a %d%% chance of not losing."):format(play.need, ns.settings.confidence)
    end
    parts[#parts + 1] = " "
    if play.locked then parts[#parts + 1] = "|cffff6060Locked:|r " .. play.locked end
    if #(play.pros or {}) > 0 then parts[#parts + 1] = Lines(play.pros, "+", "|cff40ff40") end
    if #(play.cons or {}) > 0 then parts[#parts + 1] = Lines(play.cons, "!", "|cffff9933") end
    d.body:SetText(table.concat(parts, "\n"))

    local active = ns.Buy.Active()
    if active and active.id == play.id then
        d.start:SetText("Stop this play")
        d.start:SetEnabled(true)
    else
        d.start:SetText(ns.settings.dryRun and "Rehearse this play (dry run)" or "Start this play")
        d.start:SetEnabled(play.tier ~= "locked")
    end
    d.start:Show()
end

local function PaintTop(result)
    local budget = result and result.budget or ns.Profile.Budget()
    panel.budget:SetText(("You can spend %s  (%s kept back)"):format(ns.Money(budget), ns.Money(ns.Profile.Reserve())))
    panel.risk:SetText("Offering: " .. RISK_LABEL[ns.settings.risk])
    local bits = {}
    bits[#bits + 1] = ns.Prices.HasTSM() and "TSM data: on" or "|cffff9933TSM data: off (no sale rates)|r"
    if ns.settings.dryRun then bits[#bits + 1] = "|cffff9933Dry run: nothing is bought or posted|r" end
    local mult, n, source = ns.Telemetry.SalvagerMultiplier()
    if ns.Profile.CanSalvage() then
        bits[#bits + 1] = source == "measured" and ("Salvager x%.2f (from %d)"):format(mult, n)
            or ("Salvager bonus not measured yet (%d of %d disenchants)"):format(n, ns.Telemetry.MIN_SALVAGER)
    end
    if result and result.hidden > 0 then
        bits[#bits + 1] = ("%d riskier play(s) hidden by \"%s\""):format(result.hidden, RISK_LABEL[ns.settings.risk])
    end
    panel.market:SetText(table.concat(bits, "   "))
end

function PaintAction()
    local action = CurrentAction()
    current = action
    local b = panel.action
    b:SetText(action and action.label or "")
    b:SetEnabled(action ~= nil and action.enabled)
    local msg = ns.Buy.Message() or ns.Post.Message()
    local progress = ns.Buy.Progress()
    if progress then
        local spent = ns.settings.dryRun and ("rehearsed %s"):format(ns.Money(progress.simulated))
            or ("spent %s"):format(ns.Money(progress.spent))
        local reasons = {}
        for why, count in pairs(progress.reasons) do reasons[#reasons + 1] = ("%d %s"):format(count, why) end
        msg = ("%s\nThis play: %d bought, %s%s"):format(msg or "", progress.bought, spent,
            #reasons > 0 and ("; stopped: " .. table.concat(reasons, ", ")) or "")
    end
    panel.status:SetText(msg or "")
    panel.dry:SetChecked(ns.settings.dryRun)
end

function Tab.Refresh()
    if not panel or not panel:IsShown() then return end
    local result = ns.Plays.Build()
    plays = result.plays
    if not selectedID and plays[1] then selectedID = plays[1].id end
    offset = math.max(0, math.min(offset, #plays - #rows))
    for i, row in ipairs(rows) do PaintRow(row, plays[i + offset]) end
    panel.empty:SetShown(#plays == 0)
    panel.empty:SetText(HasMarketData() and "No plays at today's prices.\nTry \"Offering\" for riskier plays, or scan again later."
        or "Scan the market (button below) to find plays.")
    PaintTop(result)
    PaintDetail()
    PaintAction()
end

local function Later() ns.Debounce("plays-tab", 0.2, function() ns.Safe("plays tab", Tab.Refresh) end) end
Tab.Later = Later

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Inset(parent)
    local ok, f = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
    if ok and f then return f end
    return CreateFrame("Frame", nil, parent)
end

local function Scroll(delta)
    offset = math.max(0, math.min(offset - delta, math.max(0, #plays - #rows)))
    Tab.Refresh()
end

local function CreateRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4 - (i - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4 - (i - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(1, 0.82, 0, 0.12)
    row.tier = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.tier:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
    row.tier:SetWidth(52)
    row.tier:SetJustifyH("LEFT")
    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 60, -3)
    row.title:SetPoint("RIGHT", row, "RIGHT", -18, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.info = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.info:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.info:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.info:SetJustifyH("LEFT")
    row.info:SetWordWrap(false)
    row.active = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.active:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    row.active:SetText("|cff40ff40>|r")
    row:SetScript("OnClick", function(self)
        if self.play then selectedID = self.play.id; Tab.Refresh() end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.play then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.play.title, 1, 0.82, 0)
        GameTooltip:AddLine(Tier(self.play).help, 1, 1, 1, true)
        if self.play.detail then GameTooltip:AddLine(self.play.detail, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
    return row
end

local function Build()
    panel = CreateFrame("Frame", "ProfitCraftPlaysPanel", AuctionHouseFrame)
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 12, -52)
    panel:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -12, 30)
    panel:Hide()

    panel.budget = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.budget:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)

    local risk = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    risk:SetSize(200, 22)
    risk:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    risk:SetScript("OnClick", function()
        for i, key in ipairs(RISK_ORDER) do
            if key == ns.settings.risk then ns.settings.risk = RISK_ORDER[i % #RISK_ORDER + 1]; break end
        end
        ns.Plays.Invalidate()
        Tab.Refresh()
    end)
    risk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Click to change which plays are offered.", 1, 1, 1, true)
        GameTooltip:AddLine("Safe: no luck, or enough items for the luck to even out. Timing: pays if it sells at a good "
            .. "moment. Risky: slow sellers or small lucky batches.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    risk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.risk = risk

    panel.market = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.market:SetPoint("TOPLEFT", panel.budget, "BOTTOMLEFT", 0, -6)
    panel.market:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
    panel.market:SetJustifyH("LEFT")

    local list = Inset(panel)
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -44)
    list:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 84)
    list:SetWidth(LIST_WIDTH)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
    panel.list = list
    panel.empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.empty:SetPoint("CENTER")
    panel.empty:SetWidth(LIST_WIDTH - 30)

    local detail = Inset(panel)
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
    detail:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 84)
    detail.title = detail:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    detail.title:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -10)
    detail.title:SetPoint("RIGHT", detail, "RIGHT", -10, 0)
    detail.title:SetJustifyH("LEFT")
    detail.body = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    detail.body:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -8)
    detail.body:SetPoint("RIGHT", detail, "RIGHT", -10, 0)
    detail.body:SetJustifyH("LEFT")
    detail.body:SetJustifyV("TOP")
    detail.body:SetSpacing(2)
    detail.start = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detail.start:SetSize(220, 24)
    detail.start:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -8, 8)
    detail.start:SetScript("OnClick", function()
        local play, active = Selected(), ns.Buy.Active()
        if active and play and active.id == play.id then ns.Buy.Stop() elseif play then ns.Buy.Start(play) end
        Tab.Refresh()
    end)
    panel.detail = detail

    -- the step button
    local action = CreateFrame("Button", "ProfitCraftAHButton", panel, "UIPanelButtonTemplate")
    action:SetSize(460, 32)
    action:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 40)
    action:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    action:SetScript("OnClick", function(_, mouse) ns.Safe("plays step", Press, mouse) end)
    action:SetScript("OnEnter", function(self)
        SetWheel(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("ProfitCraft: next step", 1, 0.82, 0)
        GameTooltip:AddLine("Each press does one thing: one search, one purchase, one confirmation or one post. "
            .. "Right-click skips what it offers.", 1, 1, 1, true)
        GameTooltip:AddLine(ns.settings.wheel and "Scroll down here to press it (zoom works everywhere else)."
            or "Scroll-down can press it too: Options > AddOns > ProfitCraft > Buying & selling.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    action:SetScript("OnLeave", function(self) SetWheel(self, false); GameTooltip:Hide() end)
    action:SetScript("OnHide", function(self) SetWheel(self, false) end)
    panel.action = action

    -- key twin: key bindings and scroll-down press this hidden button; it acts on key-down only, so one press is
    -- one step whatever sends it (the visible button acts on mouse release)
    local key = CreateFrame("Button", "ProfitCraftAHKey", panel)
    key:RegisterForClicks("LeftButtonDown")
    key:SetScript("OnClick", function() ns.Safe("plays step", Press, "LeftButton") end)
    key:Hide()
    panel.key = key

    local dry = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    dry:SetSize(24, 24)
    dry:SetPoint("LEFT", action, "RIGHT", 12, 0)
    dry.label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    dry.label:SetPoint("LEFT", dry, "RIGHT", 2, 1)
    dry.label:SetText("Dry run (spend nothing)")
    dry:SetScript("OnClick", function(self)
        ns.settings.dryRun = self:GetChecked() and true or false
        Tab.Refresh()
    end)
    panel.dry = dry

    panel.status = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    panel.status:SetPoint("TOPLEFT", action, "BOTTOMLEFT", 2, -4)
    panel.status:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
    panel.status:SetJustifyH("LEFT")

    panel:SetScript("OnShow", function()
        local height = list:GetHeight() or 0
        local count = height > ROW_HEIGHT and math.floor((height - 8) / ROW_HEIGHT) or 7
        for i = #rows + 1, count do rows[i] = CreateRow(list, i) end
        Tab.Refresh()
    end)
    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed > 0.5 then elapsed = 0; ns.Buy.Tick(); PaintAction() end
    end)
end

function Tab.TryCreateTab()
    if panel or not AuctionHouseFrame or not ns.IsReady() then return end
    local lib = TabLib()
    if not lib or lib:DoesIDExist(TAB_ID) then return end
    Build()
    local ok, err = pcall(lib.CreateTab, lib, TAB_ID, panel, "Plays", "ProfitCraft - Ranked plays: buy, convert, disenchant, sell")
    if not ok and ns.debug then ns.Print("couldn't add the Plays tab:", err) end
    Tab.tabCreated = ok
    Tab.panel = panel
    Tab.rows = rows
end

-- for the offline tests
function Tab.CurrentAction() return CurrentAction() end
function Tab.Press(mouse) Press(mouse) end
function Tab.Select(id) selectedID = id; Tab.Refresh() end

ns.On("AUCTION_HOUSE_SHOW", function() C_Timer.After(0, Tab.TryCreateTab) end)
ns.Buy.OnChange(Later)
ns.Post.OnChange(Later)
ns.Scanner.OnChange(Later)
ns.OrderBook.OnUpdate(Later)
ns.OnDataChanged(Later)
ns.On("PLAYER_MONEY", Later)
ns.On("PLAYER_REGEN_ENABLED", function()
    local b = panel and panel.action
    if b and not (b.IsMouseOver and b:IsMouseOver()) then ClearOverrideBindings(b) end
end)
ns.On("BAG_UPDATE_DELAYED", Later)
