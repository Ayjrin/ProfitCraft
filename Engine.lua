-- ProfitCraft: cost and profit of recipes, including multi-step chains.
--
-- Every reagent is valued at the cheapest of:
--   * buying it on the auction house (Auctionator's last scanned price)
--   * buying it from a vendor (recorded when you open a merchant)
--   * crafting it yourself with a recipe you know, valued recursively the same way
-- A product is valued sold on the AH or, for Enchanters, disenchanted and its mats sold: whichever pays more.
local _, ns = ...

local Engine = {}
ns.Engine = Engine

local MAX_DEPTH = 4 -- crafting steps below the final product
local EXPIRE = 60   -- seconds before prices are re-read from Auctionator

local memo, results, rankings = {}, {}, {}
local producers
local enchantingSkill -- nil unless you have Enchanting
local builtAt = 0
local visiting = {}
local impure = 0 -- bumped when a result depended on a cycle or depth cut, so it can't be memoized

function Engine:Invalidate()
    wipe(memo); wipe(results); wipe(rankings)
    producers = nil
    ns.FireDataChanged()
end

local function Ensure()
    if producers and GetTime() - builtAt < EXPIRE then return end
    wipe(memo); wipe(results); wipe(rankings)
    producers = {}
    enchantingSkill = ns.Disenchant and ns.Disenchant.PlayerSkill() or nil
    if ns.db then
        for rid in pairs(ns.KnownSet()) do
            local r = ns.db.recipes[rid]
            if r and r.out and r.reagents and #r.reagents > 0 then
                local list = producers[r.out]
                if not list then list = {}; producers[r.out] = list end
                list[#list + 1] = rid
            end
        end
    end
    builtAt = GetTime()
end

local RecipeCost

local function UnitCost(itemID, depth)
    local cached = memo[itemID]
    if cached ~= nil then return cached or nil end
    if visiting[itemID] then
        impure = impure + 1
        return nil
    end

    local best
    local ah = ns.AHPrice(itemID)
    if ah then best = { cost = ah, source = "ah" } end
    local vendor = ns.VendorPrice(itemID)
    if vendor and (not best or vendor <= best.cost) then best = { cost = vendor, source = "vendor" } end

    local before = impure
    local list = producers[itemID]
    if list then
        if depth < MAX_DEPTH then
            visiting[itemID] = true
            for _, rid in ipairs(list) do
                local plan = RecipeCost(rid, depth + 1)
                if plan and plan.complete and plan.yield > 0 then
                    local each = plan.cost / plan.yield
                    if not best or each < best.cost then
                        best = { cost = each, source = "craft", recipeID = rid, plan = plan }
                    end
                end
            end
            visiting[itemID] = nil
        else
            impure = impure + 1
        end
    end

    if impure == before then memo[itemID] = best or false end
    return best
end

RecipeCost = function(rid, depth)
    local r = ns.db and ns.db.recipes[rid]
    if not r or not r.reagents then return nil end
    local plan = { recipeID = rid, cost = 0, yield = ns.Data.Yield(r), parts = {}, complete = true }
    for i, reagent in ipairs(r.reagents) do
        local part = { item = reagent.item, qty = reagent.qty }
        local unit = UnitCost(reagent.item, depth)
        if unit then
            part.unit, part.source, part.recipeID, part.plan = unit.cost, unit.source, unit.recipeID, unit.plan
            plan.cost = plan.cost + unit.cost * reagent.qty
        else
            part.missing = true
            plan.complete = false
        end
        plan.parts[i] = part
    end
    return plan
end

local function ProfitAndReturn(value, cost)
    local profit = value - cost
    if cost > 0 then return profit, profit / cost end
    return profit, profit > 0 and math.huge or 0
end

-- Your Enchanting skill (nil without Enchanting). Read on each rebuild; only Enchanters see disenchant values.
function Engine:EnchantingSkill()
    Ensure()
    return enchantingSkill
end

-- Full evaluation of one recipe as a final product sold on the AH (or, for Enchanters, disenchanted).
-- Returns nil for recipes that don't make an item.
function Engine:Evaluate(rid)
    if not ns.db then return nil end
    Ensure()
    local cached = results[rid]
    if cached ~= nil then return cached or nil end

    local r = ns.db.recipes[rid]
    if not r or not r.out then
        results[rid] = false
        return nil
    end

    visiting[r.out] = true -- never "make" the product out of itself
    local plan = RecipeCost(rid, 0)
    visiting[r.out] = nil

    -- res fields (copper unless noted):
    --   sell       AH price of one product
    --   sellGross  what the crafted batch lists for (sell x number made)
    --   sellCut    what the auction house keeps of that
    --   sellValue  sellGross - sellCut
    --   sellProfit sellValue - reagent cost
    --   sellRoi    sellProfit / reagent cost (fraction; 0.9 = 90% return)
    --   de         Enchanters only: the batch disenchanted and its mats sold (see Disenchant.Evaluate),
    --              plus gross / cut / value / profit / roi like the sell side
    --   outlet     "sell" or "disenchant": whichever makes more
    --   gross, cut, value, profit, roi   the outlet's numbers; ranking and glows use these
    --   breakEven  lowest listing price per item that still covers reagents + cut
    local res = { recipeID = rid, out = r.out, plan = plan, sell = ns.AHPrice(r.out), outlet = "sell" }
    local cut = ns.Cut()
    if res.sell then
        res.sellGross = res.sell * plan.yield
        res.sellCut = res.sellGross * cut
        res.sellValue = res.sellGross - res.sellCut
        if plan.complete then res.sellProfit, res.sellRoi = ProfitAndReturn(res.sellValue, plan.cost) end
    end

    local de = enchantingSkill and ns.Disenchant.Evaluate(r.out)
    if de then
        if de.each then
            de.gross = de.each * plan.yield
            de.cut = de.gross * cut
            de.value = de.gross - de.cut
            if plan.complete then de.profit, de.roi = ProfitAndReturn(de.value, plan.cost) end
        end
        res.de = de
    end

    if de and de.profit and (not res.sellProfit or de.profit > res.sellProfit) then
        res.outlet = "disenchant"
        res.gross, res.cut, res.value, res.profit, res.roi = de.gross, de.cut, de.value, de.profit, de.roi
    else
        res.gross, res.cut, res.value = res.sellGross, res.sellCut, res.sellValue
        res.profit, res.roi = res.sellProfit, res.sellRoi
    end

    if plan.complete and plan.yield > 0 and cut < 1 then
        res.breakEven = plan.cost / (plan.yield * (1 - cut))
    end
    results[rid] = res
    return res
end

local function ByProfit(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    return a.recipeID < b.recipeID
end

local function ByReturn(a, b)
    if a.roi ~= b.roi then return a.roi > b.roi end
    return ByProfit(a, b)
end

-- Best-first order according to the "Rank glows by" setting.
function Engine.Compare(a, b)
    if ns.settings and ns.settings.rankBy == "profit" then return ByProfit(a, b) end
    return ByReturn(a, b)
end

-- Can this result glow? Needs the minimum profit and minimum return from the settings.
-- returnOnly: check only the minimum return (see GlowRanks).
function Engine.Qualifies(res, returnOnly)
    if not (res and res.profit and res.profit > 0) then return false end
    local s = ns.settings or ns.DEFAULTS
    if (res.roi or 0) * 100 < (s.minReturn or 0) then return false end
    return returnOnly or res.profit >= (s.minProfit or 0)
end

-- Results among `recipeIDs` that make a profit, best first.
-- filter: nil keeps every profitable craft, true keeps those that pass both glow thresholds,
--         "return" keeps those that pass the minimum return.
function Engine:Rank(recipeIDs, filter)
    local list = {}
    for _, rid in ipairs(recipeIDs) do
        local res = self:Evaluate(rid)
        if res and res.profit and res.profit > 0 and (not filter or Engine.Qualifies(res, filter == "return")) then
            list[#list + 1] = res
        end
    end
    table.sort(list, Engine.Compare)
    return list
end

-- recipeID -> 1/2/3 for the gold/silver/bronze picks among `recipeIDs`, plus the ranked list.
-- The minimum profit stops copper wins from topping a list that has real ones. When nothing in the
-- list clears it (normal at low skill, where every craft is worth copper), the best crafts that still
-- clear the minimum return glow instead, and the third result (`relaxed`) is true.
function Engine:GlowRanks(recipeIDs)
    local list, relaxed = self:Rank(recipeIDs, true), false
    if #list == 0 then
        list = self:Rank(recipeIDs, "return")
        relaxed = #list > 0
    end
    local ranks = {}
    for i = 1, math.min(ns.Display.MAX_RANK, #list) do ranks[list[i].recipeID] = i end
    return ranks, list, relaxed
end

-- Intermediate recipes used by a plan ("this is a step in your best craft").
local function CollectSteps(plan, rank, topID, steps)
    if not plan then return end
    for _, part in ipairs(plan.parts) do
        if part.source == "craft" and part.recipeID then
            if not steps[part.recipeID] or steps[part.recipeID].rank > rank then
                steps[part.recipeID] = { rank = rank, top = topID }
            end
            CollectSteps(part.plan, rank, topID, steps)
        end
    end
end

-- Gold/silver/bronze picks among the recipes you know in one profession.
function Engine:ProfessionRanking(profID)
    Ensure()
    local cached = rankings[profID]
    if cached then return cached end
    local ids = {}
    for rid in pairs(ns.char and ns.char.known[profID] or {}) do ids[#ids + 1] = rid end
    local ranks, list, relaxed = self:GlowRanks(ids)
    local steps = {}
    for i = 1, math.min(ns.Display.MAX_RANK, #list) do
        CollectSteps(list[i].plan, i, list[i].recipeID, steps)
    end
    cached = { list = list, ranks = ranks, steps = steps, relaxed = relaxed, known = #ids }
    rankings[profID] = cached
    return cached
end
