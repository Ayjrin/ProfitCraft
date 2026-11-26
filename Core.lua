-- ProfitCraft: shared namespace, saved variables, events, prices and formatting.
local ADDON, ns = ...

-- Defaults for everything on the Options > AddOns > ProfitCraft page.
ns.DEFAULTS = {
    rankBy = "roi",   -- what decides gold/silver/bronze: "roi" (return %) or "profit" (per craft)
    minReturn = 15,   -- % return a craft needs before it can glow
    minProfit = 100,  -- copper profit per craft a craft needs before it can glow (1 silver)
    ahCut = 5,        -- % of the sale price the auction house keeps
    crafts = 1,       -- Profit tab: crafts of each when building a shopping list

    -- Plays tab: buying, posting and disenchanting (Options > AddOns > ProfitCraft > Buying & selling)
    dryRun = true,        -- buttons say what they would do and spend nothing; turn off to trade for real
    reservePct = 15,      -- % of your gold never spent (deposits, repairs, postage)
    sessionCap = 500000,  -- copper ProfitCraft may spend per session (50 gold); 0 = only the reserve limits it
    risk = "safe",        -- which plays are offered: "safe", "balanced" or "aggressive"
    confidence = 95,      -- % chance a disenchant batch must have of not losing money (sets the batch size)
    deMargin = 10,        -- % profit a green must promise over its price before it's bought to disenchant
    salvagerBonus = 0,    -- % extra dust and essences assumed with the Arcane Salvager until it's measured
    maxBatch = 200,       -- most items bought for one disenchant play (one Arcane Salvager lasts about 200)
    duration = 3,         -- auction length when posting: 1, 2 or 3 (the AH's short, medium, long)
    wheel = false,        -- scroll-down over ProfitCraft's step buttons presses them (zoom works everywhere else)
    deAny = false,        -- the disenchant button also takes unbound greens ProfitCraft didn't buy
}

-- Fraction of the sale the auction house keeps.
function ns.Cut()
    return ((ns.settings and ns.settings.ahCut) or ns.DEFAULTS.ahCut) / 100
end

-- Skill lines that have a crafting window (used to nudge "open this window once").
ns.CRAFTING_SKILL_LINES = {
    [129] = true, -- First Aid
    [164] = true, -- Blacksmithing
    [165] = true, -- Leatherworking
    [171] = true, -- Alchemy
    [185] = true, -- Cooking
    [186] = true, -- Mining (smelting)
    [197] = true, -- Tailoring
    [202] = true, -- Engineering
    [333] = true, -- Enchanting
    [755] = true, -- Jewelcrafting
    [773] = true, -- Inscription
}

---------------------------------------------------------------------------
-- Errors: never silent. Each one is kept in ProfitCraftDB.errors (so it survives /reload and can be
-- read from the SavedVariables file) and announced in chat once per session per place.
---------------------------------------------------------------------------
local MAX_ERRORS = 10
local pendingErrors = {} -- errors raised before saved variables load
local announced = {}

local function Now() return (time and time()) or (os and os.time and os.time()) or 0 end
ns.Now = Now

function ns.ReportError(where, err, stack)
    err = tostring(err)
    local list = (ns.db and ns.db.errors) or pendingErrors
    for _, e in ipairs(list) do
        if e.where == where and e.err == err then
            e.count, e.at = (e.count or 1) + 1, Now()
            return
        end
    end
    table.insert(list, 1, { where = where, err = err, stack = stack, at = Now(), count = 1 })
    while #list > MAX_ERRORS do table.remove(list) end
    if ns.debug then
        print("|cffffd100ProfitCraft|r error in " .. where .. ": " .. err)
    elseif not announced[where] then
        announced[where] = true
        print("|cffffd100ProfitCraft|r |cffff6060hit an error in " .. where .. ".|r Type /craftprofit errors to see it.")
    end
end

-- Calls fn(...) and records any error under `where`. Returns ok, results...
function ns.Safe(where, fn, ...)
    local n, args = select("#", ...), { ... }
    return xpcall(function() return fn(unpack(args, 1, n)) end, function(err)
        ns.ReportError(where, err, debugstack and debugstack(2, 6, 0) or nil)
        return err
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event) -- tolerate events this client lacks
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do ns.Safe(event, list[i], event, ...) end
end)

local pending = {}
-- Run fn once after `delay` seconds no matter how many times this is called meanwhile.
function ns.Debounce(key, delay, fn)
    if pending[key] then return end
    pending[key] = true
    C_Timer.After(delay, function()
        pending[key] = nil
        fn()
    end)
end

-- Things that want to repaint when prices/recipes change.
local listeners = {}
function ns.OnDataChanged(fn) table.insert(listeners, fn) end
function ns.FireDataChanged()
    ns.Debounce("datachanged", 0.05, function()
        for i = 1, #listeners do pcall(listeners[i]) end
    end)
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    ProfitCraftDB = ProfitCraftDB or {}
    local db = ProfitCraftDB
    db.recipes = db.recipes or {} -- [recipeID] = { name, icon, out, qmin, qmax, reagents = {{item, qty}}, prof }
    db.vendor = db.vendor or {}   -- [itemID] = copper per unit, recorded when you open a merchant
    db.errors = db.errors or {}   -- most recent first, see ns.ReportError
    for i = #pendingErrors, 1, -1 do table.insert(db.errors, 1, pendingErrors[i]) end
    wipe(pendingErrors)
    while #db.errors > MAX_ERRORS do table.remove(db.errors) end
    db.diag = db.diag or {}       -- last thing each window did, for troubleshooting from the file
    db.telemetry = db.telemetry or {} -- what your disenchants actually gave (see Telemetry.lua)
    db.ledger = db.ledger or {}       -- what ProfitCraft bought, posted and sold (see Ledger.lua)
    db.clock = db.clock or {}         -- prices by weekday and time of day (see Clock.lua)
    db.settings = db.settings or {}
    for key, value in pairs(ns.DEFAULTS) do
        if db.settings[key] == nil then db.settings[key] = value end
    end
    ns.settings = db.settings

    ProfitCraftCharDB = ProfitCraftCharDB or {}
    local char = ProfitCraftCharDB
    char.known = char.known or {} -- [professionID] = { [recipeID] = true }
    char.profs = char.profs or {} -- [professionID] = { name, rank, max }
    char.deQueue = char.deQueue or {}   -- [itemID] = how many ProfitCraft bought to disenchant
    char.salvager = char.salvager or {} -- [itemID] = true when they were bought for an Arcane Salvager run
    char.toSell = char.toSell or {}     -- [itemID] = true for things a play will post (mats, products)
    char.convert = char.convert or {}   -- [fromItemID] = essence conversions still to do

    ns.db, ns.char = db, char
end)

function ns.IsReady() return ns.db ~= nil end

function ns.KnownSet()
    local flat = {}
    if not ns.char then return flat end
    for _, set in pairs(ns.char.known) do
        for rid in pairs(set) do flat[rid] = true end
    end
    return flat
end

function ns.IsKnown(rid)
    if not ns.char then return false end
    for _, set in pairs(ns.char.known) do
        if set[rid] then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Prices (Auctionator public API only)
---------------------------------------------------------------------------
local function API()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

function ns.HasAuctionator() return API() ~= nil end

-- Auctionator's last-scanned lowest price.
function ns.AuctionatorPrice(itemID)
    local api = API()
    if not api or not itemID or not api.GetAuctionPriceByItemID then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, itemID)
    if ok and type(price) == "number" and price > 0 then return price end
end

-- Price of one on the AH: a live search from this session, else Auctionator, else TSM (see Prices.lua).
function ns.AHPrice(itemID)
    if ns.Prices then return (ns.Prices.Get(itemID)) end
    return ns.AuctionatorPrice(itemID)
end

function ns.AHAge(itemID)
    local api = API()
    if not api or not itemID or not api.GetAuctionAgeByItemID then return nil end
    local ok, age = pcall(api.GetAuctionAgeByItemID, ADDON, itemID)
    if ok and type(age) == "number" then return age end
end

function ns.VendorPrice(itemID)
    return ns.db and ns.db.vendor[itemID] or nil
end

---------------------------------------------------------------------------
-- Items & formatting
---------------------------------------------------------------------------
function ns.ItemIDFromLink(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

function ns.ItemInstant(item)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(item) end
    if GetItemInfoInstant then return GetItemInfoInstant(item) end
end

function ns.ItemName(itemID)
    if not itemID then return "?" end
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if not name and GetItemInfo then name = GetItemInfo(itemID) end
    if name then return name end
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return "item #" .. itemID
end

function ns.ItemColoredName(itemID)
    local name = ns.ItemName(itemID)
    local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then name = color.hex .. name .. "|r" end
    return name
end

function ns.ItemIcon(itemID)
    return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or nil
end

function ns.ItemLabel(itemID)
    local icon = ns.ItemIcon(itemID)
    if icon then return "|T" .. icon .. ":0|t " .. ns.ItemColoredName(itemID) end
    return ns.ItemColoredName(itemID)
end

function ns.ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID, true) or 0 end
    if GetItemCount then return GetItemCount(itemID, true) or 0 end
    return 0
end

-- Money with the game's gold / silver / copper coin icons.
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

function ns.Money(copper)
    if not copper then return "?" end
    local negative = copper < 0
    copper = math.floor(math.abs(copper) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g) .. GOLD end
    if s > 0 then parts[#parts + 1] = s .. SILVER end
    if c > 0 and g < 10 then parts[#parts + 1] = c .. COPPER end -- copper is noise above 10 gold
    if #parts == 0 then parts[1] = "0" .. COPPER end
    return (negative and "-" or "") .. table.concat(parts, " ")
end

-- 0.045 -> "4.5%", 0.9 -> "90%", 0.05 -> "5%"
function ns.Percent(fraction)
    if not fraction then return "?" end
    if fraction == math.huge then return "free" end
    local p = fraction * 100
    if math.abs(p - math.floor(p + 0.5)) < 0.05 or math.abs(p) >= 10 then
        return ("%d%%"):format(math.floor(p + 0.5))
    end
    return ("%.1f%%"):format(p)
end

function ns.Qty(n)
    local rounded = math.floor(n + 0.5)
    if math.abs(n - rounded) < 0.05 then return tostring(rounded) end
    return ("%.1f"):format(n)
end

function ns.Print(...)
    print("|cffffd100ProfitCraft|r", ...)
end
