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

local function same(v) return v end
local function silverToCopper(v) return v * 100 end
local function copperToSilver(v) return math.floor((v or 0) / 100) end

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
end

function Options.Refresh()
    if not panel or not ns.settings then return end
    for _, radio in ipairs(controls.radios) do radio:SetChecked(ns.settings.rankBy == radio.value) end
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
