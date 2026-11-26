-- ProfitCraft: enchanting essences, 3 lesser <-> 1 greater.
--
-- WoW Forever's item tables (build 1.60.1.71139): using a Greater essence from your bags turns it into 3 Lesser
-- (e.g. item 10939 casts spell 13362, which creates 3x 10938), and using a Lesser turns 3 of them into 1 Greater
-- (spell 13361 uses the clicked one plus 2 more). No profession or skill needed, so every character can do this.
-- Buyers split between the two listings, so their prices drift apart; when they do, one side is a sure trade:
--   split:   buy greater, sell 3 lesser     profit = 3 x lesser x (1 - cut) - greater
--   combine: buy 3 lesser, sell greater     profit = greater x (1 - cut) - 3 x lesser
local _, ns = ...

local Essences = {}
ns.Essences = Essences

Essences.PAIRS = {
    { lesser = 10938, greater = 10939, name = "Magic" },
    { lesser = 10998, greater = 11082, name = "Astral" },
    { lesser = 11134, greater = 11135, name = "Mystic" },
    { lesser = 11174, greater = 11175, name = "Nether" },
    { lesser = 16202, greater = 16203, name = "Eternal" },
}

local byItem = {}
for _, pair in ipairs(Essences.PAIRS) do
    byItem[pair.lesser] = { pair = pair, role = "lesser" }
    byItem[pair.greater] = { pair = pair, role = "greater" }
end

-- The pair an essence belongs to, and whether it's the "lesser" or "greater".
function Essences.Pair(itemID)
    local e = byItem[itemID]
    if e then return e.pair, e.role end
end

-- What one is worth to sell in its better form (a lesser is a third of a greater, and the other way round).
function Essences.BestValue(itemID)
    local pair, role = Essences.Pair(itemID)
    if not pair then return nil end
    local lesser = ns.Prices.SellPrice(pair.lesser)
    local greater = ns.Prices.SellPrice(pair.greater)
    if role == "lesser" then
        if lesser and greater then return math.max(lesser, greater / 3) end
        return lesser or (greater and greater / 3)
    end
    if lesser and greater then return math.max(greater, lesser * 3) end
    return greater or (lesser and lesser * 3)
end

-- Deposit for posting `qty` of an item: the game's own figure when the AH is open, else nil.
function Essences.Deposit(itemID, qty)
    local AH = C_AuctionHouse
    if not (AH and AH.CalculateCommodityDeposit) then return nil end
    local ok, deposit = pcall(AH.CalculateCommodityDeposit, itemID, ns.settings.duration, qty)
    if ok and type(deposit) == "number" then return deposit end
end

-- Walks the buy side tier by tier while each extra set still makes money.
--   buyID/perSet: what you buy and how many make one set; sellID/outPerSet: what you sell and how many a set gives.
-- Returns { sets, cost, revenue (after cut), profit, maxUnit, sellPrice } or nil.
local function Walk(buyID, perSet, sellID, outPerSet)
    local buyBook = ns.OrderBook.Get(buyID)
    local sell = ns.OrderBook.SellPrice(sellID)
    local sellBook = ns.OrderBook.Get(sellID)
    if not buyBook or not sell or not sellBook then return nil end
    local cut = ns.Cut()
    local netPerOut = sell * (1 - cut)
    -- don't plan to post more than is already listed: past that the price would drop under us
    local maxOut = math.max(outPerSet * 5, sellBook.total)
    local tiers = buyBook.tiers
    local ti, left = 1, tiers[1] and tiers[1].qty or 0
    local sets, cost, maxUnit = 0, 0, nil
    while (sets + 1) * outPerSet <= maxOut and sets < 1000 do
        -- price the next set from what's left in the tiers
        local need, setCost, top, i, l = perSet, 0, nil, ti, left
        while need > 0 and tiers[i] do
            local take = math.min(l, need)
            setCost, need, top, l = setCost + take * tiers[i].price, need - take, tiers[i].price, l - take
            if l == 0 then i = i + 1; l = tiers[i] and tiers[i].qty or 0 end
        end
        if need > 0 or outPerSet * netPerOut - setCost <= 0 then break end
        sets, cost, maxUnit, ti, left = sets + 1, cost + setCost, top, i, l
    end
    if sets == 0 then return nil end
    local revenue = sets * outPerSet * netPerOut
    return { sets = sets, cost = cost, revenue = revenue, profit = revenue - cost, maxUnit = maxUnit, sellPrice = sell }
end

-- Every profitable split or combine with fresh prices, best first:
--   { pair, kind = "split"/"combine", buyID, sellID, buyQty, sellQty, sets, cost, revenue, profit, deposit, maxUnit, sellPrice }
function Essences.Opportunities()
    local list = {}
    for _, pair in ipairs(Essences.PAIRS) do
        for _, kind in ipairs({ "split", "combine" }) do
            local buyID, perSet, sellID, outPerSet
            if kind == "split" then buyID, perSet, sellID, outPerSet = pair.greater, 1, pair.lesser, 3
            else buyID, perSet, sellID, outPerSet = pair.lesser, 3, pair.greater, 1 end
            local w = Walk(buyID, perSet, sellID, outPerSet)
            if w then
                local sellQty = w.sets * outPerSet
                local deposit = Essences.Deposit(sellID, sellQty) or 0
                local profit = w.profit - deposit
                if profit >= 1 then
                    list[#list + 1] = { pair = pair, kind = kind, buyID = buyID, sellID = sellID, buyQty = w.sets * perSet,
                        sellQty = sellQty, sets = w.sets, cost = w.cost, revenue = w.revenue, profit = profit,
                        deposit = deposit, maxUnit = w.maxUnit, sellPrice = w.sellPrice }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.profit > b.profit end)
    return list
end
