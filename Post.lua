-- ProfitCraft: posts what a play produced, one click per auction.
--
--   * Only items a play marked for sale (mats from disenchanting ProfitCraft's buys, converted essences, crafted
--     products, resales). Right-click the step button to skip one for this session.
--   * Price: a copper under the volume wall from a search made seconds before (OrderBook.SellPrice), never under
--     a floor (what a vendor pays, or 60% of TSM's market value). Below the floor it's held, not dumped.
--   * The deposit is the game's own figure for this stack and duration; over 20% of the sale it's held too.
--   * One click posts one auction (a whole commodity stack at once). If the game asks for confirmation, the next
--     click confirms. Dry run posts nothing.
local _, ns = ...

local Post = {}
ns.Post = Post

Post.FRESH = 60       -- seconds a price search stays good enough to post from
Post.WAIT = 10
Post.MAX_DEPOSIT = 0.20

local state = "idle" -- idle | confirm | pending
local pending
local skip = {}      -- [itemID] = reason, this session
local message
local listeners = {}

function Post.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed()
    for _, fn in ipairs(listeners) do ns.Safe("post listener", fn) end
end
function Post.Message() return message end
function Post.Held() return skip end

local function Name(id) return ns.ItemName(id) end

local function BagSlot(itemID)
    if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and not info.isLocked and not info.isBound then return bag, slot, info end
        end
    end
end

-- Lowest price worth posting at: above what a vendor pays after the cut, and above 60% of TSM's market value.
function Post.Floor(itemID)
    local floor = 1
    local vendor = ns.Prices.VendorSell(itemID)
    if vendor then floor = math.max(floor, math.ceil(vendor / (1 - ns.Cut())) + 1) end
    local market = ns.Prices.Market(itemID)
    if market then floor = math.max(floor, math.floor(market * 0.6)) end
    return floor
end

local function Search(itemID)
    ns.Scanner.Search(itemID, function() Changed() end, true)
end

local function Deposit(commodity, itemID, loc, qty)
    local AH = C_AuctionHouse
    local fn = commodity and AH.CalculateCommodityDeposit or AH.CalculateItemDeposit
    if not fn then return nil end
    local ok, value
    if commodity then ok, value = pcall(fn, itemID, ns.settings.duration, qty)
    else ok, value = pcall(fn, loc, ns.settings.duration, qty) end
    if ok and type(value) == "number" then return value end
end

local function Plan(itemID)
    local bag, slot = BagSlot(itemID)
    if not bag then return nil end
    local book = ns.OrderBook.Get(itemID, Post.FRESH)
    if not book then
        Search(itemID)
        return { kind = "wait", label = "Checking the price of " .. Name(itemID), enabled = false }
    end
    local price = ns.OrderBook.SellPrice(itemID, Post.FRESH)
    if not price then
        -- nobody else is selling: list at the usual price instead of guessing
        price = ns.OrderBook.Sanitize(ns.Prices.Market(itemID) or ns.AuctionatorPrice(itemID))
        if not price then skip[itemID] = "no price to go by"; return false end
    end
    local floor = Post.Floor(itemID)
    if price < floor then
        skip[itemID] = ("the going price %s is under the floor %s"):format(ns.Money(price), ns.Money(floor))
        return false
    end
    local AH = C_AuctionHouse
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local commodity = AH.GetItemCommodityStatus and AH.GetItemCommodityStatus(loc) == 2
    local qty = commodity and (AH.GetAvailablePostCount and AH.GetAvailablePostCount(loc) or 1) or 1
    local deposit = Deposit(commodity, itemID, loc, qty)
    local net = price * qty * (1 - ns.Cut())
    if deposit and deposit > net * Post.MAX_DEPOSIT then
        skip[itemID] = ("the deposit %s is over 20%% of the sale"):format(ns.Money(deposit))
        return false
    end
    local label = ("Post %d %s at %s each"):format(qty, Name(itemID), ns.Money(price))
    if deposit and deposit > 0 then label = label .. (" (deposit %s)"):format(ns.Money(deposit)) end
    return { kind = "post", itemID = itemID, loc = loc, qty = qty, price = price, deposit = deposit, commodity = commodity,
        label = label, enabled = true }
end

-- The next auction to post as { kind, label, enabled, ... }, or nil when there's nothing to post.
function Post.Next()
    if pending and state == "pending" and GetTime() - pending.at > Post.WAIT then
        state, pending, message = "idle", nil, "The auction house didn't answer; check your auctions."
    end
    if state == "pending" then return { kind = "wait", label = "Posting...", enabled = false } end
    if state == "confirm" then
        return { kind = "confirmPost", label = "Confirm: " .. pending.label, enabled = true }
    end
    local ids = {}
    for id in pairs(ns.char.toSell) do
        if not skip[id] and ns.ItemCount(id) > 0 then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local action = Plan(id)
        if action then return action end
    end
    return nil
end

local function Submit(a, confirm)
    local AH = C_AuctionHouse
    local dur = ns.settings.duration
    if a.commodity then
        if confirm then AH.ConfirmPostCommodity(a.loc, dur, a.qty, a.price); return false end
        return AH.PostCommodity(a.loc, dur, a.qty, a.price)
    end
    if confirm then AH.ConfirmPostItem(a.loc, dur, a.qty, nil, a.price); return false end
    return AH.PostItem(a.loc, dur, a.qty, nil, a.price)
end

-- One post (or one confirmation) per click.
function Post.Click(action)
    if not (action and action.enabled) then return end
    if action.kind == "post" then
        if ns.settings.dryRun then
            skip[action.itemID] = "dry run"
            message = ("Dry run: would have posted %d %s at %s. Nothing posted."):format(action.qty, Name(action.itemID),
                ns.Money(action.price))
        else
            pending = action
            pending.at = GetTime()
            local needsConfirmation = Submit(action, false)
            state = needsConfirmation and "confirm" or "pending"
            if needsConfirmation then message = "The auction house wants a confirmation: press again." end
        end
    elseif action.kind == "confirmPost" then
        if ns.settings.dryRun then
            Post.Skip(action)
            message = "Dry run is on: post cancelled."
        else
            state, pending.at = "pending", GetTime()
            Submit(pending, true)
        end
    end
    Changed()
end

function Post.Skip(action)
    if not action then return end
    if action.kind == "confirmPost" then
        if pending then skip[pending.itemID] = "skipped" end
        state, pending = "idle", nil
        if C_AuctionHouse.CancelSell then pcall(C_AuctionHouse.CancelSell) end
    elseif action.itemID then
        skip[action.itemID] = "skipped"
    end
    Changed()
end

-- Stop posting an item from now on (it stays in your bags).
function Post.Forget(itemID) ns.char.toSell[itemID] = nil; Changed() end

local function Posted()
    if state ~= "pending" or not pending then return end
    ns.Ledger.Post(pending.itemID, pending.qty, pending.deposit, pending.price)
    ns.OrderBook.Invalidate(pending.itemID)
    message = ("Posted %d %s at %s."):format(pending.qty, Name(pending.itemID), ns.Money(pending.price))
    state, pending = "idle", nil
    Changed()
end
ns.On("AUCTION_HOUSE_AUCTION_CREATED", Posted)
ns.On("AUCTION_MULTISELL_UPDATE", function(_, created, totalToCreate) if created == totalToCreate then Posted() end end)
ns.On("AUCTION_HOUSE_POST_WARNING", function()
    if state == "pending" and pending then state, message = "confirm", "The auction house wants a confirmation: press again."; Changed() end
end)
ns.On("AUCTION_HOUSE_POST_ERROR", function()
    if pending then skip[pending.itemID] = "the auction house refused the post" end
    state, pending, message = "idle", nil, "The auction house refused that post."
    Changed()
end)
ns.On("AUCTION_HOUSE_CLOSED", function() state, pending = "idle", nil; wipe(skip) end)
