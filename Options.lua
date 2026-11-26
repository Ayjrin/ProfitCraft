-- ProfitCraft: settings page in the game's Options > AddOns list.
local _, ns = ...

local Options = {}
ns.Options = Options

local panel
local controls = {}

local function Changed()
    if ns.AuctionHouse and ns.AuctionHouse.ResetSort then ns.AuctionHouse.ResetSort() end
    ns.Engine:Invalidate() -- re-ranks and repaints every open window
end

local function Note(parent, anchor, text, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -4)
    fs:SetWidth(560)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(0.7, 0.7, 0.7)
    fs:SetText(text)
    return fs
end

local function Radio(parent, label, value)
    local radio = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
    radio.label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    radio.label:SetPoint("LEFT", radio, "RIGHT", 4, 1)
    radio.label:SetText(label)
    radio.value = value
    radio:SetScript("OnClick", function()
        ns.settings.rankBy = value
        Options.Refresh()
        Changed()
    end)
    return radio
end

-- A labelled whole-number box. toSetting/fromSetting convert between what you type and what's stored.
local function NumberBox(parent, label, suffix, key, minValue, maxValue, toSetting, fromSetting)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetText(label)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(50, 20)
    box:SetPoint("LEFT", fs, "RIGHT", 12, 0)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(5)
    local unit = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    unit:SetPoint("LEFT", box, "RIGHT", 6, 0)
    unit:SetText(suffix)
    local function Load() box:SetText(tostring(fromSetting(ns.settings[key]))) end
    local function Save()
        local n = tonumber(box:GetText()) or fromSetting(ns.DEFAULTS[key])
        n = math.max(minValue, math.min(maxValue, n))
        local stored = toSetting(n)
        box:SetText(tostring(n))
        if ns.settings[key] ~= stored then
            ns.settings[key] = stored
            Changed()
        end
    end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) Load(); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", Save)
    controls[#controls + 1] = Load
    return fs, box
end

-- A radio button for any setting: clicking stores `value` under `key`.
local function RadioFor(parent, label, key, value, group)
    local radio = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
    radio.label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    radio.label:SetPoint("LEFT", radio, "RIGHT", 4, 1)
    radio.label:SetText(label)
    radio:SetScript("OnClick", function()
        ns.settings[key] = value
        for _, r in ipairs(group) do r:SetChecked(r == radio) end
        Changed()
    end)
    group[#group + 1] = radio
    controls[#controls + 1] = function() radio:SetChecked(ns.settings[key] == value) end
    return radio
end

local function Check(parent, label, key, onChange)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box.label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    box.label:SetPoint("LEFT", box, "RIGHT", 2, 1)
    box.label:SetText(label)
    box:SetScript("OnClick", function(self)
        ns.settings[key] = self:GetChecked() and true or false
        if onChange then onChange() end
        Changed()
    end)
    controls[#controls + 1] = function() box:SetChecked(ns.settings[key]) end
    return box
end

local function same(v) return v end
local function silverToCopper(v) return v * 100 end
local function copperToSilver(v) return math.floor((v or 0) / 100) end
local function goldToCopper(v) return v * 10000 end
local function copperToGold(v) return math.floor((v or 0) / 10000) end

-- Options > AddOns > ProfitCraft > Buying & selling
local function BuildTrading(parentCategory)
    local page = CreateFrame("Frame")
    page.name = "Buying & selling"
    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -16)
    title:SetText("ProfitCraft: buying & selling")
    local intro = Note(page, title,
        "The Plays tab on the auction house buys, posts and disenchants for you one press at a time: every purchase, post, "
        .. "cast and mail is a separate click or key press, never a timer.", -8)

    local dry = Check(page, "Dry run: buttons rehearse and spend nothing (turn off to trade for real)", "dryRun")
    dry:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -4, -10)

    local reserve = NumberBox(page, "Keep back", "% of your gold (deposits, repairs)", "reservePct", 0, 90, same, same)
    reserve:SetPoint("TOPLEFT", dry, "BOTTOMLEFT", 4, -12)
    local cap = NumberBox(page, "Spend at most", "gold per session (0 = no cap)", "sessionCap", 0, 1000000, goldToCopper,
        copperToGold)
    cap:SetPoint("TOPLEFT", reserve, "BOTTOMLEFT", 0, -14)

    local riskLabel = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    riskLabel:SetPoint("TOPLEFT", cap, "BOTTOMLEFT", 0, -18)
    riskLabel:SetText("Plays offered")
    local riskGroup = {}
    local r1 = RadioFor(page, "Safe: no luck, or enough items for the luck to even out", "risk", "safe", riskGroup)
    r1:SetPoint("TOPLEFT", riskLabel, "BOTTOMLEFT", 0, -4)
    local r2 = RadioFor(page, "Balanced: also plays that depend on selling at a good moment", "risk", "balanced", riskGroup)
    r2:SetPoint("TOPLEFT", r1, "BOTTOMLEFT", 0, -2)
    local r3 = RadioFor(page, "Aggressive: also slow sellers and small lucky batches", "risk", "aggressive", riskGroup)
    r3:SetPoint("TOPLEFT", r2, "BOTTOMLEFT", 0, -2)

    local confLabel = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    confLabel:SetPoint("TOPLEFT", r3, "BOTTOMLEFT", 0, -14)
    confLabel:SetText("Disenchant batches must have this chance of not losing money")
    local confGroup = {}
    local c90 = RadioFor(page, "90%", "confidence", 90, confGroup)
    c90:SetPoint("TOPLEFT", confLabel, "BOTTOMLEFT", 0, -4)
    local c95 = RadioFor(page, "95%", "confidence", 95, confGroup)
    c95:SetPoint("LEFT", c90, "RIGHT", 60, 0)
    local c99 = RadioFor(page, "99%", "confidence", 99, confGroup)
    c99:SetPoint("LEFT", c95, "RIGHT", 60, 0)

    local margin = NumberBox(page, "Buy gear to disenchant only if its mats beat its price by", "%", "deMargin", 0, 200,
        same, same)
    margin:SetPoint("TOPLEFT", c90, "BOTTOMLEFT", 0, -14)
    local batch = NumberBox(page, "Most items in one disenchant play", "", "maxBatch", 1, 1000, same, same)
    batch:SetPoint("TOPLEFT", margin, "BOTTOMLEFT", 0, -14)
    local bonus = NumberBox(page, "Arcane Salvager bonus until measured", "% more dust and essences", "salvagerBonus", 0, 100,
        same, same)
    bonus:SetPoint("TOPLEFT", batch, "BOTTOMLEFT", 0, -14)
    local bonusNote = Note(page, bonus, "Nobody has published the real bonus. 0 counts none; after 50 disenchants next to a "
        .. "Salvager, your own results replace this.")

    local durLabel = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    durLabel:SetPoint("TOPLEFT", bonusNote, "BOTTOMLEFT", 0, -14)
    durLabel:SetText("Auction length when posting")
    local durGroup = {}
    local d1 = RadioFor(page, AUCTION_DURATION_ONE or "Short", "duration", 1, durGroup)
    d1:SetPoint("TOPLEFT", durLabel, "BOTTOMLEFT", 0, -4)
    local d2 = RadioFor(page, AUCTION_DURATION_TWO or "Medium", "duration", 2, durGroup)
    d2:SetPoint("LEFT", d1, "RIGHT", 80, 0)
    local d3 = RadioFor(page, AUCTION_DURATION_THREE or "Long", "duration", 3, durGroup)
    d3:SetPoint("LEFT", d2, "RIGHT", 80, 0)

    local wheel = Check(page, "Scroll down over ProfitCraft's step buttons presses them (zoom still works everywhere else)",
        "wheel")
    wheel:SetPoint("TOPLEFT", d1, "BOTTOMLEFT", -4, -12)
    local deAny = Check(page, "Disenchant button also takes unbound greens ProfitCraft didn't buy", "deAny")
    deAny:SetPoint("TOPLEFT", wheel, "BOTTOMLEFT", 0, -4)
    Note(page, deAny, "Key bindings: Game Menu > Options > Keybindings > ProfitCraft has \"Next auction house "
        .. "step\" and \"Work button\". Pick any key; each press does one step.", -8)

    page:SetScript("OnShow", Options.Refresh)
    if Settings and Settings.RegisterCanvasLayoutSubcategory and parentCategory then
        local ok, sub = pcall(Settings.RegisterCanvasLayoutSubcategory, parentCategory, page, "Buying & selling")
        if ok then Options.tradingCategory = sub end
    end
    Options.tradingPage = page
end

local function Build()
    panel = CreateFrame("Frame")
    panel.name = "ProfitCraft"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("ProfitCraft")
    local intro = Note(panel, title,
        "Decides which crafts get the gold, silver and bronze glows in the profession window, at trainers, " ..
        "on auction house recipes and in the AH Profit tab. Prices come from Auctionator.", -8)

    -- Rank glows by
    local rankLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rankLabel:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -20)
    rankLabel:SetText("Rank glows by")
    local roi = Radio(panel, "Return %  (profit / reagent cost, best when gold is what limits you)", "roi")
    roi:SetPoint("TOPLEFT", rankLabel, "BOTTOMLEFT", 0, -6)
    local profit = Radio(panel, "Profit per craft  (best when buyers are what limits you)", "profit")
    profit:SetPoint("TOPLEFT", roi, "BOTTOMLEFT", 0, -4)
    controls.radios = { roi, profit }

    -- Glow thresholds
    local thresholds = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    thresholds:SetPoint("TOPLEFT", profit, "BOTTOMLEFT", 0, -20)
    thresholds:SetText("Only glow crafts that clear both of these")

    local returnLabel = NumberBox(panel, "Minimum return", "%", "minReturn", 0, 10000, same, same)
    returnLabel:SetPoint("TOPLEFT", thresholds, "BOTTOMLEFT", 0, -12)
    local returnNote = Note(panel, returnLabel,
        "Thin margins are risky: a craft that returns 4.5% loses money after one 5% undercut. Default 15%.")

    local profitLabel = NumberBox(panel, "Minimum profit per craft", "silver", "minProfit", 0, 100000,
        silverToCopper, copperToSilver)
    profitLabel:SetPoint("TOPLEFT", returnNote, "BOTTOMLEFT", 0, -14)
    local profitNote = Note(panel, profitLabel,
        "Keeps tiny wins from topping the list (buy for 1 copper, sell for 3 is a 200% return). Default 1 silver.")

    -- AH cut
    local cutLabel = NumberBox(panel, "Auction house cut", "%", "ahCut", 0, 50, same, same)
    cutLabel:SetPoint("TOPLEFT", profitNote, "BOTTOMLEFT", 0, -20)
    local cutNote = Note(panel, cutLabel, "Share of the sale price the auction house keeps. Default 5%.")

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(140, 22)
    reset:SetPoint("TOPLEFT", cutNote, "BOTTOMLEFT", 0, -20)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", function()
        for _, key in ipairs({ "rankBy", "minReturn", "minProfit", "ahCut" }) do ns.settings[key] = ns.DEFAULTS[key] end
        Options.Refresh()
        Changed()
    end)

    panel:SetScript("OnShow", Options.Refresh)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "ProfitCraft")
        Settings.RegisterAddOnCategory(category)
        Options.category = category
    end
    BuildTrading(Options.category)
end

function Options.Refresh()
    if not panel or not ns.settings then return end
    for _, radio in ipairs(controls.radios) do radio:SetChecked(ns.settings.rankBy == radio.value) end
    if ns.Work then ns.Work.Refresh() end
    if ns.PlaysTab then ns.PlaysTab.Later() end
    for _, load in ipairs(controls) do load() end
end

function Options.Open()
    if Options.category and Settings and Settings.OpenToCategory then
        local id = Options.category.GetID and Options.category:GetID() or Options.category
        if not pcall(Settings.OpenToCategory, id) then pcall(Settings.OpenToCategory, Options.category) end
    end
end

ns.On("PLAYER_LOGIN", function()
    if not panel and ns.IsReady() then Build() end
end)
