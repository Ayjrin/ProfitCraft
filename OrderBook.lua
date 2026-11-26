-- ProfitCraft: live auction listings, read from the game's search results.
--
-- Every commodity or item search the game answers this session (ProfitCraft's, Auctionator's, the AH window's)
-- is recorded here: how many are listed at each price. That gives
--   * the real cost of buying N (walking up the price tiers, not just the cheapest listing),
--   * the "wall": the price where a meaningful amount is listed. A few cheap listings below it sell first anyway,
--     so posting just under the wall earns more than undercutting the cheapest one,
--   * which listings are yours (never undercut yourself).
-- Reading search results is read-only; nothing here buys or posts.
local _, ns = ...

local OrderBook = {}
ns.OrderBook = OrderBook

OrderBook.TTL = 15 * 60       -- seconds a search stays usable for prices
OrderBook.WALL_MIN_UNITS = 5  -- the wall is the first price where at least this many...
OrderBook.WALL_SHARE = 0.10   -- ...and this share of everything listed is offered at or below it

local books = {}   -- [itemID] = { at, commodity, tiers = {{price, qty}} (others' listings, cheapest first), min, total, own, full }
local keys = {}    -- [keyString] = { at, itemKey, auctions = {{auctionID, unit, buyout, quantity, own, link}} }
local browse = {}  -- [keyString] = { at, itemKey, minPrice, totalQuantity }
local observers = {}

local function Now() return ns.Now() end

function OrderBook.KeyString(itemKey)
    return ("%d:%d:%d"):format(itemKey.itemID or 0, itemKey.itemLevel or 0, itemKey.itemSuffix or 0)
end

function OrderBook.OnUpdate(fn) observers[#observers + 1] = fn end

local function Notify(itemID)
    for _, fn in ipairs(observers) do ns.Safe("order book listener", fn, itemID) end
end

local function Aggregate(rows)
    table.sort(rows, function(a, b) return a.price < b.price end)
    local tiers, total = {}, 0
    for _, r in ipairs(rows) do
        if r.qty > 0 then
            local last = tiers[#tiers]
            if last and last.price == r.price then last.qty = last.qty + r.qty
            else tiers[#tiers + 1] = { price = r.price, qty = r.qty } end
            total = total + r.qty
        end
    end
    return tiers, total
end

---------------------------------------------------------------------------
-- Reading results
---------------------------------------------------------------------------
function OrderBook.ReadCommodity(itemID)
    local AH = C_AuctionHouse
    if not (AH and AH.GetNumCommoditySearchResults and itemID) then return end
    local rows, own = {}, 0
    for i = 1, AH.GetNumCommoditySearchResults(itemID) or 0 do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.quantity then
            local mine = r.numOwnerItems or (r.containsOwnerItem and r.quantity) or 0
            own = own + mine
            rows[#rows + 1] = { price = r.unitPrice, qty = r.quantity - mine }
        end
    end
    local tiers, total = Aggregate(rows)
    books[itemID] = { at = Now(), commodity = true, tiers = tiers, total = total, own = own,
        min = tiers[1] and tiers[1].price or nil,
        full = not AH.HasFullCommoditySearchResults or AH.HasFullCommoditySearchResults(itemID) }
    Notify(itemID)
end

local function RebuildItem(itemID)
    local rows, own, at = {}, 0, 0
    for _, entry in pairs(keys) do
        if entry.itemKey.itemID == itemID and Now() - entry.at < OrderBook.TTL then
            at = math.max(at, entry.at)
            for _, a in ipairs(entry.auctions) do
                if a.own then own = own + a.quantity
                else rows[#rows + 1] = { price = a.unit, qty = a.quantity } end
            end
        end
    end
    local tiers, total = Aggregate(rows)
    books[itemID] = { at = at, commodity = false, tiers = tiers, total = total, own = own,
        min = tiers[1] and tiers[1].price or nil, full = true }
end

function OrderBook.ReadItem(itemKey)
    local AH = C_AuctionHouse
    if not (AH and AH.GetNumItemSearchResults and itemKey and itemKey.itemID) then return end
    local auctions = {}
    for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
        local r = AH.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 and r.auctionID then
            local qty = math.max(1, r.quantity or 1)
            auctions[#auctions + 1] = { auctionID = r.auctionID, buyout = r.buyoutAmount, quantity = qty,
                unit = r.buyoutAmount / qty, own = r.containsOwnerItem and true or false, link = r.itemLink,
                itemKey = itemKey }
        end
    end
    table.sort(auctions, function(a, b) return a.unit < b.unit end)
    keys[OrderBook.KeyString(itemKey)] = { at = Now(), itemKey = itemKey, auctions = auctions }
    RebuildItem(itemKey.itemID)
    Notify(itemKey.itemID)
end

-- Browse results (one row per item key: cheapest price and how many are listed).
function OrderBook.ReadBrowse(results)
    local now = Now()
    for _, r in ipairs(results or {}) do
        if r.itemKey and r.itemKey.itemID and r.minPrice then
            browse[OrderBook.KeyString(r.itemKey)] = { at = now, itemKey = r.itemKey, minPrice = r.minPrice,
                totalQuantity = r.totalQuantity or 1 }
        end
    end
end

---------------------------------------------------------------------------
-- Questions
---------------------------------------------------------------------------
-- The book for an item if it's younger than `ttl` seconds (default OrderBook.TTL).
function OrderBook.Get(itemID, ttl)
    local b = itemID and books[itemID]
    if b and Now() - b.at < (ttl or OrderBook.TTL) then return b end
end

-- Fresh browse rows, optionally only those matching `filter(row)`.
function OrderBook.BrowseRows(filter, ttl)
    local list, now = {}, Now()
    for _, row in pairs(browse) do
        if now - row.at < (ttl or OrderBook.TTL) and (not filter or filter(row)) then list[#list + 1] = row end
    end
    table.sort(list, function(a, b) return a.minPrice < b.minPrice end)
    return list
end

-- Cheapest browse price seen for an item (any of its item keys), or nil.
function OrderBook.BrowseMin(itemID, ttl)
    local best, now = nil, Now()
    for _, row in pairs(browse) do
        if row.itemKey.itemID == itemID and now - row.at < (ttl or OrderBook.TTL) and (not best or row.minPrice < best) then
            best = row.minPrice
        end
    end
    return best
end

-- When an item was last seen in a fresh browse (any of its keys), or nil.
function OrderBook.BrowseAt(itemID, ttl)
    local at, now = nil, Now()
    for _, row in pairs(browse) do
        if row.itemKey.itemID == itemID and now - row.at < (ttl or OrderBook.TTL) and (not at or row.at > at) then at = row.at end
    end
    return at
end

-- How many others are selling at or below `maxUnit`, and what buying all of them costs.
function OrderBook.Depth(itemID, maxUnit, ttl)
    local b = OrderBook.Get(itemID, ttl)
    if not b then return 0, 0 end
    local qty, cost = 0, 0
    for _, t in ipairs(b.tiers) do
        if t.price > maxUnit then break end
        qty, cost = qty + t.qty, cost + t.qty * t.price
    end
    return qty, cost
end

-- Cost of buying `qty` from the cheapest up, never above `maxUnit` each nor `budget` in total:
-- total, how many that gets, dearest unit paid.
function OrderBook.CostFor(itemID, qty, maxUnit, ttl, budget)
    local b = OrderBook.Get(itemID, ttl)
    if not b then return nil end
    local total, got, top = 0, 0, nil
    for _, t in ipairs(b.tiers) do
        if got >= qty or (maxUnit and t.price > maxUnit) then break end
        local take = math.min(t.qty, qty - got)
        if budget then take = math.min(take, math.floor((budget - total) / t.price)) end
        if take <= 0 then break end
        total, got, top = total + take * t.price, got + take, t.price
    end
    return total, got, top
end

-- The volume wall (see the top of this file), or nil without a fresh book.
function OrderBook.Wall(itemID, ttl)
    local b = OrderBook.Get(itemID, ttl)
    if not b or #b.tiers == 0 then return nil end
    local need = math.max(OrderBook.WALL_MIN_UNITS, b.total * OrderBook.WALL_SHARE)
    local cum = 0
    for _, t in ipairs(b.tiers) do
        cum = cum + t.qty
        if cum >= need then return t.price end
    end
    return b.tiers[#b.tiers].price
end

-- Rounds a listing price to what the AH accepts (whole silver when it doesn't take copper).
function OrderBook.Sanitize(price)
    if not price then return nil end
    local copper = not (C_AuctionHouse and C_AuctionHouse.SupportsCopperValues) or C_AuctionHouse.SupportsCopperValues()
    if copper then return math.floor(price) end
    return math.floor(price / 100) * 100
end

-- Where to list one: a copper under the wall (a silver when the AH has no copper). nil without a fresh book.
function OrderBook.SellPrice(itemID, ttl)
    local wall = OrderBook.Wall(itemID, ttl)
    if not wall then return nil end
    local copper = not (C_AuctionHouse and C_AuctionHouse.SupportsCopperValues) or C_AuctionHouse.SupportsCopperValues()
    local price = OrderBook.Sanitize(wall - (copper and 1 or 100))
    if not price or price < 1 then return nil end
    return price
end

-- Others' buyout auctions of an item from the latest item searches, cheapest per unit first.
function OrderBook.Auctions(itemID, ttl)
    local list, now = {}, Now()
    for _, entry in pairs(keys) do
        if entry.itemKey.itemID == itemID and now - entry.at < (ttl or OrderBook.TTL) then
            for _, a in ipairs(entry.auctions) do
                if not a.own and not a.gone then list[#list + 1] = a end
            end
        end
    end
    table.sort(list, function(a, b) return a.unit < b.unit end)
    return list
end

-- An auction we bought or that vanished: drop it until the next search.
function OrderBook.Forget(auctionID)
    for _, entry in pairs(keys) do
        for _, a in ipairs(entry.auctions) do
            if a.auctionID == auctionID then a.gone = true end
        end
    end
end

-- Drop what we know about an item (after buying or posting it), so the next look searches again.
function OrderBook.Invalidate(itemID)
    books[itemID] = nil
    for k, entry in pairs(keys) do
        if entry.itemKey.itemID == itemID then keys[k] = nil end
    end
end

function OrderBook.Reset() wipe(books); wipe(keys); wipe(browse) end

---------------------------------------------------------------------------
-- Events: record every answer the game gives
---------------------------------------------------------------------------
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, itemID) OrderBook.ReadCommodity(itemID) end)
ns.On("COMMODITY_SEARCH_RESULTS_ADDED", function(_, itemID) OrderBook.ReadCommodity(itemID) end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, itemKey) OrderBook.ReadItem(itemKey) end)
ns.On("ITEM_SEARCH_RESULTS_ADDED", function(_, itemKey) OrderBook.ReadItem(itemKey) end)

-- Prices feed every craft's cost, so re-rank (debounced) when a book changes.
OrderBook.OnUpdate(function()
    ns.Debounce("orderbook-engine", 1, function() if ns.Engine then ns.Engine:Invalidate() end end)
end)
