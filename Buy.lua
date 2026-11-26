-- ProfitCraft: buys what a play needs, one click per purchase.
--
-- Rules this file keeps (so nothing is ever bought without you pressing a button for it):
--   * Each click makes at most one purchase call. Nothing here runs from a timer or an event.
--   * Gear: the listing is re-read from the live search result at the moment of the click; if it sold, changed
--     price, or costs more than the play's maximum, it's skipped and nothing is bought.
--   * Commodities: two clicks, like the game's own Buy window. The first asks the AH for a quote; if the quoted
--     total is over the play's maximum the quote is cancelled. The second click confirms.
--   * Never below your gold reserve, never past the session cap (Profile.Budget), and "Dry run" (on until you
--     turn it off) makes every click a rehearsal that spends nothing.
local _, ns = ...

local Buy = {}
ns.Buy = Buy

Buy.FRESH = 30       -- seconds a search result stays good enough to buy from
Buy.WAIT_QUOTE = 10  -- seconds to wait for a price quote
Buy.WAIT_BUY = 30    -- seconds to wait for a purchase before letting you go on

local play
local state = "idle" -- idle | quote | confirm | pending
local pending
local late = {}      -- purchases the AH hadn't answered in time: still counted if they went through
local message
local listeners = {}

function Buy.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed()
    for _, fn in ipairs(listeners) do ns.Safe("buy listener", fn) end
end

function Buy.Active() return play end
function Buy.State() return state end
function Buy.Message() return message end

local function Name(id) return ns.ItemName(id) end
local function Money(c) return ns.Money(c) end

local function CopperOK()
    return not (C_AuctionHouse and C_AuctionHouse.SupportsCopperValues) or C_AuctionHouse.SupportsCopperValues()
end

---------------------------------------------------------------------------
-- Starting and stopping
---------------------------------------------------------------------------
local function Busy()
    if state ~= "pending" then return false end
    message = "Wait for the last purchase to go through first."
    Changed()
    return true
end

function Buy.Start(source)
    if not source or source.tier == "locked" or Busy() then return false end
    if state == "quote" or state == "confirm" then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
    play = { id = source.id, kind = source.kind, title = source.title, limit = source.limit, bought = 0, spent = 0,
        simulated = 0, after = source.after or {}, sells = source.sells or {}, entries = {} }
    for _, b in ipairs(source.buys or {}) do
        play.entries[#play.entries + 1] = { itemID = b.itemID, itemKey = b.itemKey, maxUnit = b.maxUnit, want = b.want or 1,
            value = b.value, got = 0 }
    end
    state, pending = "idle", nil
    if ns.Scanner.Busy() then ns.Scanner.Cancel() end -- purchases follow their own fresh searches
    if play.after.kind == "craft" and not ns.settings.dryRun then
        ns.char.craft = { recipeID = play.after.recipeID, count = play.after.count, disenchant = play.after.disenchant }
    end
    message = (ns.settings.dryRun and "Dry run: " or "Started: ") .. play.title
    Changed()
    return true
end

function Buy.Stop()
    if Busy() then return false end
    if state == "quote" or state == "confirm" then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
    play, state, pending, message = nil, "idle", nil, nil
    Changed()
end

local function Remaining()
    if play.limit then return play.limit - play.bought end
    return math.huge
end

---------------------------------------------------------------------------
-- What the next click would do
---------------------------------------------------------------------------
local function LastQueryIs(itemKey)
    local last = ns.Scanner.LastQuery()
    if last.kind ~= "search" or last.itemID ~= itemKey.itemID then return false end
    -- a search by plain item ID (level 0) covers every key of that item
    return not last.key or last.key:match(":0:0$") ~= nil or not itemKey.itemLevel
        or last.key == ns.OrderBook.KeyString(itemKey)
end

local function Search(entry)
    if entry.searching then return end
    entry.searching = true
    ns.Scanner.Search(entry.itemKey or entry.itemID, function(ok)
        entry.searching = false
        if ok then
            entry.searchedAt = GetTime()
        else
            entry.failures = (entry.failures or 0) + 1
            if entry.failures >= 2 then entry.done = "the AH didn't answer" end
        end
        Changed()
    end, true)
end

local function NextForEntry(entry, budget)
    if not entry.searchedAt or GetTime() - entry.searchedAt > Buy.FRESH then
        Search(entry)
        return { kind = "wait", label = "Checking prices: " .. Name(entry.itemID), enabled = false }
    end
    local book = ns.OrderBook.Get(entry.itemID, Buy.FRESH)
    local want = math.min(entry.want - entry.got, Remaining())
    if book and book.commodity then
        local total, got = ns.OrderBook.CostFor(entry.itemID, want, entry.maxUnit, Buy.FRESH, budget)
        if not got or got == 0 then
            entry.done = budget < (book.min or 0) and "over your budget" or "none left under the maximum price"
            return nil
        end
        return { kind = "commodity", entry = entry, qty = got, total = total, enabled = true,
            label = ("Buy %d %s for %s"):format(got, Name(entry.itemID), Money(total)) }
    end
    for _, a in ipairs(ns.OrderBook.Auctions(entry.itemID, Buy.FRESH)) do
        local sameKey = not entry.itemKey or ns.OrderBook.KeyString(a.itemKey) == ns.OrderBook.KeyString(entry.itemKey)
        if sameKey and not a.tried and a.unit <= entry.maxUnit and a.quantity <= want then
            if a.buyout > budget then
                entry.done = "over your budget"
                return nil
            end
            if not LastQueryIs(a.itemKey) then
                entry.searchedAt = nil -- another search ran since; the AH wants this item's own search to be the latest
                Search(entry)
                return { kind = "wait", label = "Checking prices: " .. Name(entry.itemID), enabled = false }
            end
            local count = a.quantity > 1 and (a.quantity .. "x ") or ""
            return { kind = "item", entry = entry, auction = a, enabled = true,
                label = ("Buy %s%s for %s"):format(count, a.link or Name(entry.itemID), Money(a.buyout)) }
        end
    end
    entry.done = "none left under the maximum price"
    return nil
end

-- The next purchase as { kind, label, enabled, ... }, or nil when this play has nothing left to buy.
function Buy.Next()
    if not play then return nil end
    Buy.Tick()
    if state == "quote" then return { kind = "wait", label = "Asking the AH for a price...", enabled = false } end
    if state == "pending" then return { kind = "wait", label = "Buying...", enabled = false } end
    if state == "confirm" then
        return { kind = "confirm", enabled = true, label = ("Confirm: buy %d %s for %s"):format(pending.qty,
            Name(pending.entry.itemID), Money(pending.total)) }
    end
    if Remaining() <= 0 then return nil end
    local budget = ns.Profile.Budget()
    for _, entry in ipairs(play.entries) do
        if not entry.done and entry.got < entry.want then
            local action = NextForEntry(entry, budget)
            if action then return action end
        end
    end
    return nil
end

-- What's been bought so far and what stopped each entry (for the Plays tab).
function Buy.Progress()
    if not play then return nil end
    local reasons = {}
    for _, e in ipairs(play.entries) do
        if e.done then reasons[e.done] = (reasons[e.done] or 0) + 1 end
    end
    return { bought = play.bought, spent = play.spent, simulated = play.simulated, limit = play.limit, reasons = reasons }
end

---------------------------------------------------------------------------
-- After a purchase: queue the next steps for the Work button and the poster
---------------------------------------------------------------------------
local function Apply(owner, entry, qty)
    local after, char = owner.after, ns.char
    if after.kind == "disenchant" then
        char.deQueue[entry.itemID] = (char.deQueue[entry.itemID] or 0) + qty
        if after.salvager then char.salvager[entry.itemID] = true end
    elseif after.kind == "convert" then
        local _, role = ns.Essences.Pair(after.from)
        local conversions = role == "lesser" and math.floor(qty / 3) or qty
        char.convert[after.from] = (char.convert[after.from] or 0) + conversions
    end
    for _, id in ipairs(owner.sells) do char.toSell[id] = true end
end

-- A purchase went through: count it (even if it was late, or its play has been stopped since).
local function Bought(p)
    local entry, owner = p.entry, p.play
    entry.got = entry.got + p.qty
    owner.bought, owner.spent = owner.bought + p.qty, owner.spent + p.total
    ns.Ledger.Buy(entry.itemID, p.qty, p.total, (entry.value or 0) * p.qty, owner.kind)
    Apply(owner, entry, p.qty)
    ns.OrderBook.Invalidate(entry.itemID)
    entry.searchedAt = nil
    if pending == p then state, pending = "idle", nil end
    message = ("Bought %d %s for %s."):format(p.qty, Name(entry.itemID), Money(p.total))
    Changed()
end

local function TakeLate(match)
    for i, p in ipairs(late) do
        if match(p) then table.remove(late, i); return p end
    end
end

local function Simulated(entry, qty, total)
    entry.got = entry.got + qty
    play.bought, play.simulated = play.bought + qty, play.simulated + total
    message = ("Dry run: would have bought %d %s for %s. Nothing spent."):format(qty, Name(entry.itemID), Money(total))
    Changed()
end

local function Cancel(text)
    if state == "quote" or state == "confirm" then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
    if pending and pending.entry then pending.entry.searchedAt = nil end
    state, pending, message = "idle", nil, text
    Changed()
end

-- Gives up waiting for an answer that never came. A purchase stays on a "late" list, so it's still counted
-- (ledger, session cap, what to disenchant) if the AH confirms it afterwards.
function Buy.Tick()
    if not pending then return end
    if state == "quote" and GetTime() - pending.at > Buy.WAIT_QUOTE then
        Cancel("The auction house didn't quote a price; checking again.")
    elseif state == "pending" and GetTime() - pending.at > Buy.WAIT_BUY then
        late[#late + 1] = pending
        pending.entry.searchedAt = nil
        state, pending = "idle", nil
        message = "The auction house hasn't answered. If that purchase went through it will still be counted."
        Changed()
    end
end

---------------------------------------------------------------------------
-- The click (one purchase call at most)
---------------------------------------------------------------------------
-- The listing's buyout right now, from the game's current search result (nil = gone).
local function LiveBuyout(a)
    local AH = C_AuctionHouse
    for i = 1, AH.GetNumItemSearchResults(a.itemKey) or 0 do
        local r = AH.GetItemSearchResultInfo(a.itemKey, i)
        if r and r.auctionID == a.auctionID then return r.buyoutAmount end
    end
end

local function EnoughGold(cost)
    return ns.Profile.Money() - cost >= ns.Profile.Reserve() and cost <= ns.Profile.Budget()
end

function Buy.Click(action)
    if not (play and action and action.enabled) then return end
    local AH = C_AuctionHouse
    if action.kind == "item" then
        local a, entry = action.auction, action.entry
        a.tried = true
        local live = LiveBuyout(a)
        if live ~= a.buyout then
            ns.OrderBook.Forget(a.auctionID)
            message = "That listing sold or changed price; nothing bought."
        elseif not EnoughGold(a.buyout) then
            entry.done, message = "over your budget", "That would dip into your gold reserve; nothing bought."
        elseif ns.settings.dryRun then
            ns.OrderBook.Forget(a.auctionID)
            Simulated(entry, a.quantity, a.buyout)
            return
        else
            state = "pending"
            pending = { kind = "item", auctionID = a.auctionID, entry = entry, qty = a.quantity, total = a.buyout,
                at = GetTime(), play = play }
            AH.PlaceBid(a.auctionID, a.buyout)
        end
    elseif action.kind == "commodity" then
        local entry = action.entry
        if not EnoughGold(action.total) then
            entry.done, message = "over your budget", "That would dip into your gold reserve; nothing bought."
        elseif ns.settings.dryRun then
            ns.OrderBook.Invalidate(entry.itemID)
            entry.searchedAt = nil
            Simulated(entry, action.qty, action.total)
            return
        else
            local unit = math.ceil(action.total / action.qty)
            if not CopperOK() then unit = math.ceil(unit / 100) * 100 end
            state = "quote"
            pending = { kind = "commodity", entry = entry, qty = action.qty, expected = action.total, at = GetTime(),
                play = play }
            AH.StartCommoditiesPurchase(entry.itemID, action.qty, unit)
        end
    elseif action.kind == "confirm" then
        if ns.settings.dryRun then
            Cancel("Dry run is on: quote cancelled, nothing bought.")
            return
        elseif AH.GetQuoteDurationRemaining and AH.GetQuoteDurationRemaining() <= 0 then
            Cancel("The price quote ran out; checking again.")
            return
        elseif not EnoughGold(pending.total) then
            Cancel("That would dip into your gold reserve; nothing bought.")
            return
        end
        state, pending.at = "pending", GetTime()
        AH.ConfirmCommoditiesPurchase(pending.entry.itemID, pending.qty)
    end
    Changed()
end

-- Right-click on the step button: skip what it's offering.
function Buy.Skip(action)
    if not action then return end
    if action.kind == "item" then action.auction.tried = true
    elseif action.kind == "commodity" then action.entry.done = "skipped"
    elseif action.kind == "confirm" then Cancel("Skipped; nothing bought.") return end
    Changed()
end

---------------------------------------------------------------------------
-- The AH's answers
---------------------------------------------------------------------------
-- The quote must not exceed what was planned from listings at or under the maximum price: a total that
-- grew means some units now cost more, so it's cancelled (the average could still look fine).
ns.On("COMMODITY_PRICE_UPDATED", function(_, unitPrice, totalPrice)
    if state ~= "quote" or not pending then return end
    if ns.settings.dryRun then
        Cancel("Dry run is on: quote cancelled, nothing bought.")
    elseif totalPrice <= pending.expected and EnoughGold(totalPrice) then
        pending.total, state = totalPrice, "confirm"
        message = ("Quoted %s (%s each). Press again to buy."):format(Money(totalPrice), Money(unitPrice))
        Changed()
    else
        Cancel(("The price went up to %s; nothing bought."):format(Money(totalPrice)))
    end
end)
ns.On("COMMODITY_PRICE_UNAVAILABLE", function()
    if state == "quote" then Cancel("Those sold before the quote; nothing bought.") end
end)
local function IsCommodity(p) return p.kind == "commodity" end
ns.On("COMMODITY_PURCHASE_SUCCEEDED", function()
    if state == "pending" and pending and pending.kind == "commodity" then Bought(pending)
    else local p = TakeLate(IsCommodity); if p then Bought(p) end end
end)
ns.On("COMMODITY_PURCHASE_FAILED", function()
    if state == "pending" and pending and pending.kind == "commodity" then Cancel("The purchase failed; nothing bought.")
    else TakeLate(IsCommodity) end
end)
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(_, auctionID)
    ns.OrderBook.Forget(auctionID)
    if state == "pending" and pending and pending.kind == "item" and pending.auctionID == auctionID then Bought(pending)
    else local p = TakeLate(function(x) return x.auctionID == auctionID end); if p then Bought(p) end end
end)
ns.On("AUCTION_HOUSE_SHOW_ERROR", function()
    if state == "pending" or state == "quote" then
        if pending and pending.auctionID then ns.OrderBook.Forget(pending.auctionID) end
        Cancel("The auction house refused that purchase; nothing bought.")
    end
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
    if state == "pending" then late[#late + 1] = pending; state, pending = "idle", nil
    elseif state ~= "idle" then Cancel(nil) end
end)
