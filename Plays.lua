-- ProfitCraft: every money-making play open to this character right now, ranked.
--
-- A play is a complete plan with its numbers: what to buy (and the most to pay for each), what to do with it
-- (split/combine essences, disenchant, craft, sell to a vendor), what to post. Each one gets
--   * a certainty tier, by how much luck and selling risk is in it (see TIERS),
--   * profit after the AH cut and deposits, the gold it needs, and an estimate of the minutes of your time,
--   * at most two reasons for it and two against,
--   * a plain reason when it's locked (not enough gold to even out the luck, no Enchanting, ...).
-- Ranking: profit x tier factor / minutes, so a sure 10g in 5 minutes beats a lucky 15g in 20.
-- Plays only plan; buying happens in Buy.lua, one click per purchase.
local _, ns = ...

local Plays = {}
ns.Plays = Plays

Plays.TIERS = {
    safe        = { order = 1, label = "SAFE",   color = "ff33e0c8", factor = 0.97,
        help = "No luck involved and the output sells readily." },
    likely      = { order = 2, label = "LIKELY", color = "ff40ff40", factor = 0.90,
        help = "Wins on average, and the batch is big enough for the luck to even out." },
    timing      = { order = 3, label = "TIMING", color = "ffffb030", factor = 0.75,
        help = "Pays if it sells at a good moment, or to slow buyers: your gold is tied up for a while." },
    speculative = { order = 4, label = "RISKY",  color = "ffa0a0a0", factor = 0.50,
        help = "Slow sellers, or a batch too small for the luck to even out." },
    locked      = { order = 5, label = "LOCKED", color = "ff808080", factor = 0,
        help = "Not open to this character right now; the reason is on the play." },
}

-- Which tiers each "Plays offered" setting shows.
Plays.RISK = {
    safe = { safe = true, likely = true },
    balanced = { safe = true, likely = true, timing = true },
    aggressive = { safe = true, likely = true, timing = true, speculative = true },
}

local Z = { [90] = 1.282, [95] = 1.645, [99] = 2.326 } -- one-sided normal quantiles

-- Seconds of your time per action (estimates; the AH and casts set the pace).
local SEC = { buyItem = 3, buyCommodity = 5, mail = 2.5, convert = 1.5, disenchant = 3.6, craft = 3.2, post = 3, overhead = 60 }

local STALE = 2 * 3600 -- prices older than this are flagged and cost a tier

local cache, cacheAt = nil, -math.huge

function Plays.Invalidate() cache = nil end

local function Minutes(seconds) return math.max(1, seconds / 60) end

local function Downgrade(tier)
    if tier == "safe" then return "likely" end
    if tier == "likely" then return "timing" end
    if tier == "timing" then return "speculative" end
    return tier
end

-- Region sale rate as a tier and a short phrase.
local function Selling(itemID)
    local rate = ns.Prices.SaleRate(itemID)
    if not rate then return nil, nil end
    if rate >= 0.4 then return "fast", ("sells fast (sale rate %.2f)"):format(rate) end
    if rate >= 0.15 then return "ok", ("sells steadily (sale rate %.2f)"):format(rate) end
    return "slow", ("sells slowly (sale rate %.2f)"):format(rate)
end

local function Stale(itemIDs)
    local worst = 0
    for _, id in ipairs(itemIDs) do
        local age = ns.Prices.Age(id)
        if not age then return math.huge end
        worst = math.max(worst, age)
    end
    return worst
end

local function AgeText(seconds)
    if seconds == math.huge then return "never scanned" end
    if seconds >= 86400 then return ("%d days old"):format(math.floor(seconds / 86400)) end
    return ("%d hours old"):format(math.floor(seconds / 3600))
end

local function Add(list, text) if text and #list < 2 then list[#list + 1] = text end end

local function Finish(play)
    local t = Plays.TIERS[play.tier]
    play.minutes = play.minutes or 1
    play.perMinute = play.profit and play.profit / play.minutes or 0
    play.score = (play.profit or 0) * t.factor / play.minutes
    return play
end

local function Name(id) return ns.ItemName(id) end

---------------------------------------------------------------------------
-- Essences: split or combine (any character)
---------------------------------------------------------------------------
local function EssencePlays(budget, out)
    for _, o in ipairs(ns.Essences.Opportunities()) do
        local unitCost = o.cost / o.buyQty
        local perSet = o.kind == "split" and 1 or 3
        local sets = o.sets
        if o.cost > budget then sets = math.floor(budget / (unitCost * perSet)) end
        local play = { id = "ess:" .. o.kind .. ":" .. o.buyID, kind = "essence", tier = "safe", pros = {}, cons = {} }
        play.title = (o.kind == "split" and "Split %s essences" or "Combine %s essences"):format(o.pair.name)
        local scale = sets / o.sets
        play.buyQty, play.sellQty = sets * perSet, sets * (o.kind == "split" and 3 or 1)
        play.cost = o.cost * scale
        play.revenue = o.revenue * scale
        play.profit = o.profit * scale
        play.detail = ("Buy %d %s, %s, post %d %s"):format(play.buyQty, Name(o.buyID),
            o.kind == "split" and "split each into 3" or "combine each 3 into 1", play.sellQty, Name(o.sellID))
        play.steps = { ("Buy %d %s (at most %s each)"):format(play.buyQty, Name(o.buyID), ns.Money(o.maxUnit)),
            "Take them from the mailbox",
            (o.kind == "split" and "Split them: %d clicks" or "Combine them: %d clicks"):format(sets),
            ("Post %d %s at %s"):format(play.sellQty, Name(o.sellID), ns.Money(o.sellPrice)) }
        play.buys = { { itemID = o.buyID, maxUnit = o.maxUnit, want = play.buyQty,
            value = (o.revenue / o.buyQty) } }
        play.after = { kind = "convert", from = o.buyID, count = sets }
        play.sells = { o.sellID }
        play.minutes = Minutes(SEC.overhead + SEC.buyCommodity * 2 + SEC.mail * 2 + sets * SEC.convert + SEC.post)
        if sets <= 0 then
            play.tier = "locked"
            play.locked = ("Needs %s for one set; you can spend %s."):format(ns.Money(unitCost * perSet), ns.Money(budget))
            play.profit = o.profit / o.sets
        end
        Add(play.pros, "No luck involved: 3 lesser always make 1 greater, and back.")
        local speed, phrase = Selling(o.sellID)
        if speed == "slow" then play.tier = play.tier == "locked" and "locked" or "timing"; Add(play.cons, Name(o.sellID) .. " " .. phrase .. ".")
        elseif phrase then Add(play.pros, Name(o.sellID) .. " " .. phrase .. ".")
        else Add(play.cons, "No sale rate (TSM app data) for " .. Name(o.sellID) .. ".") end
        Add(play.cons, "Purchases arrive by mail; convert at the mailbox, post back at the AH.")
        out[#out + 1] = Finish(play)
    end
end

---------------------------------------------------------------------------
-- Vendor: AH listings cheaper than what a merchant pays (any character)
---------------------------------------------------------------------------
local function VendorPlay(budget, out)
    local buys, cost, profit = {}, 0, 0
    for _, row in ipairs(ns.OrderBook.BrowseRows()) do
        local id = row.itemKey.itemID
        local vendor = ns.Prices.VendorSell(id)
        if vendor and row.minPrice < vendor and cost + row.minPrice <= budget then
            buys[#buys + 1] = { itemID = id, itemKey = row.itemKey, maxUnit = vendor - 1, want = 1, value = vendor }
            cost, profit = cost + row.minPrice, profit + vendor - row.minPrice
        end
    end
    if #buys == 0 or profit < 20 then return end
    local play = { id = "vendor", kind = "vendor", tier = "safe", title = "Vendor flips", pros = {}, cons = {},
        cost = cost, revenue = cost + profit, profit = profit, buys = buys, after = { kind = "vendor" }, sells = {} }
    play.detail = ("Buy %d listing(s) under what a vendor pays, then sell them to any merchant"):format(#buys)
    play.steps = { ("Buy %d item(s), each below its vendor price"):format(#buys), "Take them from the mailbox",
        "Sell them to any merchant (right-click each)" }
    play.minutes = Minutes(SEC.overhead + #buys * (SEC.buyItem + SEC.mail + 1))
    Add(play.pros, "Guaranteed: a merchant always pays the vendor price.")
    Add(play.cons, "Small amounts; worth it only while you're at the AH anyway.")
    out[#out + 1] = Finish(play)
end

---------------------------------------------------------------------------
-- Disenchant: buy green/blue gear under what its mats sell for (Enchanters)
---------------------------------------------------------------------------
local function GearInfo(row)
    local id = row.itemKey.itemID
    local _, _, _, _, _, classID = ns.ItemInstant(id)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local quality, itemLevel
    if getInfo then
        local name, _, q, ilvl = getInfo(id)
        quality, itemLevel = q, ilvl
        if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    end
    if row.itemKey.itemLevel and row.itemKey.itemLevel > 0 then itemLevel = row.itemKey.itemLevel end
    return classID, quality, itemLevel
end

local function DisenchantPlays(budget, out)
    if not ns.Profile.EnchantingSkill() then return end
    local s = ns.settings
    local cut = ns.Cut()
    local z = Z[s.confidence] or Z[95]
    local brackets = {}
    for _, row in ipairs(ns.OrderBook.BrowseRows()) do
        local classID, quality, itemLevel = GearInfo(row)
        local key = classID and quality and itemLevel and ns.Disenchant.Bracket(classID, quality, itemLevel)
        if key then
            local b = brackets[key]
            if not b then
                b = { key = key, classID = classID, quality = quality, itemLevel = itemLevel, rows = {} }
                brackets[key] = b
            end
            b.rows[#b.rows + 1] = row
        end
    end

    local variants = { false }
    local mult, measuredN, source = ns.Telemetry.SalvagerMultiplier()
    if ns.Profile.CanSalvage() and mult > 1 then variants[2] = true end

    for _, b in pairs(brackets) do
        for _, salvager in ipairs(variants) do
            local stats = ns.Disenchant.Stats(b.classID, b.quality, b.itemLevel, { salvager = salvager })
            if stats and stats.ev then
                local net = stats.ev * (1 - cut)
                local maxBuy = math.floor(net / (1 + (s.deMargin or 0) / 100))
                local picked, cost, profit, sumPrice = {}, 0, 0, 0
                local listed = 0
                for _, row in ipairs(b.rows) do
                    if row.minPrice <= maxBuy then
                        listed = listed + 1
                        if #picked < s.maxBatch and cost + row.minPrice <= budget then
                            picked[#picked + 1] = { itemID = row.itemKey.itemID, itemKey = row.itemKey, maxUnit = maxBuy,
                                want = row.totalQuantity or 1, value = net }
                            cost, sumPrice = cost + row.minPrice, sumPrice + row.minPrice
                            profit = profit + net - row.minPrice
                        end
                    end
                end
                if listed > 0 then
                    local label = ns.Disenchant.BracketLabel(b.classID, b.quality, b.itemLevel)
                    local n = #picked
                    local avgPrice = n > 0 and sumPrice / n or (b.rows[1] and b.rows[1].minPrice or maxBuy)
                    local edge = net - avgPrice
                    local sd = stats.sd * (1 - cut)
                    local need = edge > 0 and math.max(1, math.ceil((z * sd / edge) ^ 2)) or math.huge
                    local play = { id = ("de:%s:%s"):format(b.key, tostring(salvager)), kind = "disenchant",
                        tier = "likely", pros = {}, cons = {}, salvager = salvager, bracket = b.key, need = need,
                        title = (salvager and "Salvager disenchant: " or "Disenchant: ") .. label,
                        cost = cost, profit = profit, revenue = cost + profit, buys = picked, limit = n,
                        after = { kind = "disenchant", salvager = salvager }, sells = {} }
                    play.detail = ("Buy %d at up to %s each, disenchant them, post the mats"):format(n, ns.Money(maxBuy))
                    play.steps = { ("Buy up to %d %s at most %s each"):format(n, label:lower(), ns.Money(maxBuy)),
                        "Take them from the mailbox" .. (salvager and ", next to your Arcane Salvager" or ""),
                        ("Disenchant them: %d clicks"):format(n), "Post the dust, essences and shards" }
                    play.minutes = Minutes(SEC.overhead + n * (SEC.buyItem + SEC.disenchant) + math.ceil(n / 12) * SEC.mail
                        + 3 * SEC.post)
                    if n == 0 then
                        play.tier, play.profit = "locked", nil
                        play.locked = ("Needs %s for the cheapest; you can spend %s."):format(ns.Money(avgPrice), ns.Money(budget))
                    elseif n < need then
                        if listed >= need then
                            play.tier = "locked"
                            play.locked = ("Needs about %d items (%s) for a %d%% chance of not losing; you can afford %d.")
                                :format(need, ns.Money(need * avgPrice), s.confidence, n)
                        else
                            play.tier = "speculative"
                            Add(play.cons, ("Only %d listed under %s; %d needed for the luck to even out."):format(listed,
                                ns.Money(maxBuy), need))
                        end
                    end
                    Add(play.pros, ("Mats average %s per item after the AH cut; you pay at most %s."):format(
                        ns.Money(net), ns.Money(maxBuy)))
                    if n > 0 and n >= need then
                        Add(play.pros, ("%d items is enough: %d needed for a %d%% chance of not losing."):format(n,
                            need, s.confidence))
                    end
                    if salvager then
                        Add(play.cons, source == "measured"
                            and ("Salvager bonus measured from %d buffed disenchants: x%.2f."):format(measuredN, mult)
                            or ("Salvager bonus is your setting (%d%%), not measured yet."):format(s.salvagerBonus))
                        Add(play.cons, "Needs a Campfire, then 15 minutes next to the Salvager; 1-hour camping cooldown.")
                    elseif stats.source == "measured" then
                        Add(play.pros, ("Rates measured from %d of your own disenchants."):format(stats.n))
                    else
                        Add(play.cons, "Drop rates are the published Classic ones, not yet measured on this server.")
                    end
                    out[#out + 1] = Finish(play)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Crafts: buy the reagents, craft, sell (recipes this character knows)
---------------------------------------------------------------------------
local function Collect(plan, crafts, buy)
    for _, part in ipairs(plan.parts) do
        local qty = part.qty * crafts
        if part.source == "craft" and part.plan then
            Collect(part.plan, math.ceil(qty / part.plan.yield - 1e-6), buy)
        elseif part.source == "ah" then
            local b = buy[part.item] or { qty = 0, unit = part.unit }
            buy[part.item] = b
            b.qty = b.qty + qty
        end
    end
end

local function CraftPlays(budget, out)
    local ids = {}
    for rid in pairs(ns.KnownSet()) do ids[#ids + 1] = rid end
    local ranked = ns.Engine:Rank(ids, true)
    for i = 1, math.min(5, #ranked) do
        local res = ranked[i]
        local each = res.plan.cost
        local n = each > 0 and math.min(10, math.floor(budget / each)) or 10
        local play = { id = "craft:" .. res.recipeID, kind = "craft", tier = "likely", pros = {}, cons = {},
            recipeID = res.recipeID, title = "Craft " .. Name(res.out), out = res.out }
        local buyMap, buys = {}, {}
        Collect(res.plan, math.max(1, n), buyMap)
        for item, b in pairs(buyMap) do
            local need = math.ceil(b.qty - 1e-6) - ns.ItemCount(item)
            if need > 0 then
                buys[#buys + 1] = { itemID = item, maxUnit = math.ceil(b.unit * 1.15), want = need, value = b.unit }
            end
        end
        play.buys = buys
        play.cost = each * math.max(1, n)
        play.profit = res.profit * math.max(1, n)
        play.revenue = play.cost + play.profit
        play.after = { kind = "craft", recipeID = res.recipeID, count = math.max(1, n), disenchant = res.outlet == "disenchant" }
        play.sells = res.outlet == "disenchant" and {} or { res.out }
        play.detail = ("Make %d, %s"):format(math.max(1, n), res.outlet == "disenchant" and "disenchant them" or "sell them")
        play.steps = { ("Buy the reagents (%d kind(s), at most 15%% over today's price)"):format(#buys),
            "Take them from the mailbox", ("Craft %d %s with the profession window open"):format(math.max(1, n), Name(res.out)),
            res.outlet == "disenchant" and "Disenchant them and post the mats" or ("Post them at about %s"):format(ns.Money(res.sell)) }
        play.minutes = Minutes(SEC.overhead + #buys * SEC.buyCommodity + math.max(1, n) * SEC.craft + SEC.post)
        if n == 0 then
            play.tier = "locked"
            play.locked = ("Needs %s for one craft; you can spend %s."):format(ns.Money(each), ns.Money(budget))
            play.profit = res.profit
        end
        Add(play.pros, ("%s profit per craft (%s return)."):format(ns.Money(res.profit), ns.Percent(res.roi)))
        if res.outlet == "disenchant" then
            Add(play.cons, "Pays only when disenchanted: luck applies.")
        else
            local speed, phrase = Selling(res.out)
            if not speed then
                if play.tier ~= "locked" then play.tier = "timing" end
                Add(play.cons, "No sale rate (TSM app data): it may sit on the AH.")
            elseif speed == "slow" then
                if play.tier ~= "locked" then play.tier = "speculative" end
                Add(play.cons, Name(res.out) .. " " .. phrase .. ".")
            elseif speed == "ok" then
                if play.tier ~= "locked" then play.tier = "timing" end
                Add(play.pros, Name(res.out) .. " " .. phrase .. ".")
            else
                Add(play.pros, Name(res.out) .. " " .. phrase .. ".")
            end
        end
        out[#out + 1] = Finish(play)
    end
end

---------------------------------------------------------------------------
-- Under-crafts: finished goods listed far below their materials, resold at their usual price (needs TSM data)
---------------------------------------------------------------------------
local function UnderCraftPlays(budget, out)
    if not ns.Prices.HasTSM() then return end
    local cut = ns.Cut()
    local found = {}
    for _, r in pairs(ns.db.recipes) do
        if r.out and r.reagents and #r.reagents > 0 and not found[r.out] then
            local price = ns.Prices.Get(r.out)
            local market = ns.Prices.Market(r.out)
            local rate = ns.Prices.SaleRate(r.out)
            local mats, complete = 0, true
            for _, reagent in ipairs(r.reagents) do
                local unit = ns.Prices.Get(reagent.item) or ns.VendorPrice(reagent.item)
                if not unit then complete = false; break end
                mats = mats + unit * reagent.qty
            end
            local yield = ns.Data.Yield(r)
            if complete and price and market and rate and rate >= 0.2 and yield > 0 then
                local matsEach = mats / yield
                local resale = market * (1 - cut)
                local maxBuy = math.floor(math.min(matsEach * 0.6, resale / 1.25))
                if price <= maxBuy then
                    local qty = ns.OrderBook.Get(r.out) and ns.OrderBook.Depth(r.out, maxBuy) or 1
                    qty = math.max(1, math.min(qty, math.floor(budget / price)))
                    local play = { id = "under:" .. r.out, kind = "flip", tier = "timing", pros = {}, cons = {},
                        title = "Resell " .. Name(r.out), cost = price * qty, profit = (resale - price) * qty,
                        buys = { { itemID = r.out, maxUnit = maxBuy, want = qty, value = resale } },
                        after = { kind = "resell" }, sells = { r.out } }
                    play.revenue = play.cost + play.profit
                    play.detail = ("Listed at %s; its materials cost %s and it usually sells for %s"):format(
                        ns.Money(price), ns.Money(matsEach), ns.Money(market))
                    play.steps = { ("Buy up to %d at most %s each"):format(qty, ns.Money(maxBuy)), "Take them from the mailbox",
                        ("Post them near %s"):format(ns.Money(market)) }
                    play.minutes = Minutes(SEC.overhead + qty * SEC.buyItem + SEC.post * qty)
                    if budget < price then
                        play.tier = "locked"
                        play.locked = ("Needs %s; you can spend %s."):format(ns.Money(price), ns.Money(budget))
                    end
                    Add(play.pros, ("Costs %s of its materials."):format(ns.Percent(price / matsEach)))
                    Add(play.pros, ("It sells (sale rate %.2f)."):format(rate))
                    Add(play.cons, "Your gold is tied up until it resells at the usual price.")
                    found[r.out] = true
                    out[#out + 1] = Finish(play)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- All together
---------------------------------------------------------------------------
local function Freshness(play)
    local ids = {}
    for _, b in ipairs(play.buys or {}) do ids[#ids + 1] = b.itemID end
    for _, id in ipairs(play.sells or {}) do ids[#ids + 1] = id end
    if #ids == 0 then return end
    local age = Stale(ids)
    if age > STALE then
        if play.tier ~= "locked" then play.tier = Downgrade(play.tier); Finish(play) end
        table.insert(play.cons, 1, "Prices are " .. AgeText(age) .. ": scan before buying.")
        if #play.cons > 2 then table.remove(play.cons) end
    end
end

local function Phase(play)
    local id = play.sells and play.sells[1]
    if not id then return end
    local price = ns.Prices.SellPrice(id)
    local phase = ns.Clock.Phase(id, price)
    if not phase then return end
    if phase.tag == "low" then
        Add(play.cons, ("%s is %d%% under its usual price now; it's usually highest %s."):format(Name(id),
            math.floor(-phase.vsUsual * 100 + 0.5), phase.sellAt))
    elseif phase.tag == "high" then
        Add(play.pros, ("%s is %d%% above its usual price right now."):format(Name(id), math.floor(phase.vsUsual * 100 + 0.5)))
    end
end

-- { plays = { ... best first }, hidden = count hidden by the "Plays offered" setting, budget, locked = { ... } }
function Plays.Build(force)
    if cache and not force and GetTime() - cacheAt < 2 then return cache end
    local budget = ns.Profile.Budget()
    local all = {}
    local builders = { EssencePlays, VendorPlay, DisenchantPlays, CraftPlays, UnderCraftPlays }
    for i, build in ipairs(builders) do ns.Safe("plays " .. i, build, budget, all) end

    local allowed = Plays.RISK[ns.settings.risk] or Plays.RISK.safe
    local shown, locked, hidden = {}, {}, 0
    for _, play in ipairs(all) do
        Freshness(play)
        Phase(play)
        if play.tier == "locked" then locked[#locked + 1] = play
        elseif allowed[play.tier] then shown[#shown + 1] = play
        else hidden = hidden + 1 end
    end
    table.sort(shown, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.id < b.id
    end)
    table.sort(locked, function(a, b) return (a.profit or 0) > (b.profit or 0) end)
    for _, play in ipairs(locked) do shown[#shown + 1] = play end
    cache = { plays = shown, hidden = hidden, budget = budget }
    cacheAt = GetTime()
    return cache
end

function Plays.Find(id)
    for _, play in ipairs(Plays.Build().plays) do
        if play.id == id then return play end
    end
end

ns.OrderBook.OnUpdate(Plays.Invalidate)
ns.OnDataChanged(Plays.Invalidate)
