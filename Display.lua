-- ProfitCraft: row glows and the tooltip breakdown shared by every window.
local _, ns = ...

local Display = {}
ns.Display = Display

Display.RANKS = {
    [1] = { r = 1.00, g = 0.82, b = 0.00, from = 0.35, to = 0.90, hex = "ffffd100", label = "Most profitable" },
    [2] = { r = 0.80, g = 0.84, b = 0.92, from = 0.20, to = 0.60, hex = "ffc9d1dd", label = "2nd most profitable" },
    [3] = { r = 0.80, g = 0.48, b = 0.18, from = 0.20, to = 0.60, hex = "ffd08a4a", label = "3rd most profitable" },
}
Display.MAX_RANK = #Display.RANKS

---------------------------------------------------------------------------
-- Glow: the game's own row highlight, tinted gold/silver and gently pulsing
---------------------------------------------------------------------------
local FALLBACK_TEXTURE = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local glows = setmetatable({}, { __mode = "k" })

local function HasAtlas(atlas)
    return atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function CreateGlow(row, atlas)
    local glow = CreateFrame("Frame", nil, row)
    glow:SetAllPoints(row)
    glow:SetFrameLevel(row:GetFrameLevel() + 1)
    local tex = glow:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(glow)
    if HasAtlas(atlas) then tex:SetAtlas(atlas) else tex:SetTexture(FALLBACK_TEXTURE) end
    tex:SetBlendMode("ADD")
    glow.tex = tex

    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetDuration(0.9)
    fade:SetSmoothing("IN_OUT")
    glow.pulse, glow.fade = pulse, fade
    glow:Hide()
    return glow
end

function Display.SetGlow(row, rank, atlas)
    local glow = glows[row]
    local style = rank and Display.RANKS[rank]
    if not style then
        if glow then glow.pulse:Stop(); glow:Hide() end
        return
    end
    if not glow then
        glow = CreateGlow(row, atlas)
        glows[row] = glow
    end
    if glow.rank ~= rank then
        glow.pulse:Stop()
        glow.tex:SetVertexColor(style.r, style.g, style.b)
        glow.fade:SetFromAlpha(style.from)
        glow.fade:SetToAlpha(style.to)
        glow.rank = rank
    end
    glow:Show()
    if not glow.pulse:IsPlaying() then glow.pulse:Play() end
end

-- Current glow rank on a row (nil when not glowing).
function Display.GlowRank(row)
    local glow = glows[row]
    return glow and glow:IsShown() and glow.rank or nil
end

---------------------------------------------------------------------------
-- Tooltip breakdown
---------------------------------------------------------------------------
local GRAY, WHITE, PURPLE = { 0.6, 0.6, 0.6 }, { 1, 1, 1 }, { 0.78, 0.6, 1 }

-- What the batch disenchants into: each mat's chance and count, its average AH value, then the AH cut.
local function AddDisenchant(tt, de, yield)
    local items = yield ~= 1 and (" (" .. ns.Qty(yield) .. " items)") or ""
    if de.unknown then
        tt:AddDoubleLine("Disenchants into", "not known yet", 0.8, 0.8, 0.8, GRAY[1], GRAY[2], GRAY[3])
        tt:AddLine("Blue items under item level 21 are new in WoW Forever; nobody has published what they give.",
            GRAY[1], GRAY[2], GRAY[3], true)
        return
    end
    if de.gross then
        tt:AddDoubleLine("Disenchants into (average)" .. items, ns.Money(de.gross), 0.8, 0.8, 0.8, 1, 1, 1)
    else
        tt:AddDoubleLine("Disenchants into" .. items, "missing prices", 0.8, 0.8, 0.8, 1, 0.3, 0.3)
    end
    for _, m in ipairs(de.mats) do
        local count = m.min == m.max and tostring(m.min) or (m.min .. "-" .. m.max)
        local left = ("    %d%%  %sx %s"):format(math.floor(m.chance * 100 + 0.5), count, ns.ItemLabel(m.item))
        if m.unit then
            tt:AddDoubleLine(left, ns.Money(m.avg * m.unit * yield), 0.9, 0.9, 0.9, 1, 1, 1)
        else
            tt:AddDoubleLine(left, "no price", 0.9, 0.9, 0.9, 1, 0.3, 0.3)
        end
    end
    if de.gross then
        tt:AddDoubleLine("AH cut on mats (" .. ns.Percent(ns.Cut()) .. ")", ns.Money(-de.cut), 0.8, 0.8, 0.8, 1, 0.55, 0.55)
    end
end

local function AddPlan(tt, parts, multiplier, depth)
    local indent = ("    "):rep(depth)
    for _, p in ipairs(parts) do
        local qty = p.qty * multiplier
        local left = indent .. ns.Qty(qty) .. "x " .. ns.ItemLabel(p.item)
        if p.missing then
            tt:AddDoubleLine(left, "no price", 0.9, 0.9, 0.9, 1, 0.3, 0.3)
        else
            local total = ns.Money(p.unit * qty)
            if p.source == "craft" then
                tt:AddDoubleLine(left, "craft " .. total, 0.9, 0.9, 0.9, 0.45, 0.8, 1)
            elseif p.source == "vendor" then
                tt:AddDoubleLine(left, "vendor " .. total, 0.9, 0.9, 0.9, 1, 1, 0.6)
            else
                tt:AddDoubleLine(left, "AH " .. total, 0.9, 0.9, 0.9, 1, 1, 1)
            end
            if p.source == "craft" and p.plan and depth < 3 then
                AddPlan(tt, p.plan.parts, qty / p.plan.yield, depth + 1)
            end
        end
    end
end

-- Adds the ProfitCraft section for recipe `rid` to tooltip `tt`.
-- opts: rank, relaxed (rank came from the low-skill fallback), step, notLearned, header,
--       trainCost (trainer fee) or recipeCost (AH price of the recipe item),
--       patternItem, patternStatus ("known"/"other"/nil), patternNeed ({prof, level, rank} when skill is too low)
function Display.AddRecipeLines(tt, rid, opts)
    opts = opts or {}
    if opts.header ~= false then
        tt:AddLine(" ")
        local title = "|cffffd100ProfitCraft|r"
        local style = opts.rank and Display.RANKS[opts.rank]
        if style then title = title .. "   |c" .. style.hex .. style.label .. "|r" end
        tt:AddLine(title)
    end

    if not ns.HasAuctionator() then
        tt:AddLine("Auctionator isn't loaded, so there are no prices.", 1, 0.3, 0.3, true)
        return
    end

    local res = ns.Engine:Evaluate(rid)
    if not res then
        tt:AddLine("Doesn't make an item you can sell.", GRAY[1], GRAY[2], GRAY[3], true)
        return
    end
    local plan = res.plan

    if opts.notLearned then tt:AddLine("You haven't learned this yet.", GRAY[1], GRAY[2], GRAY[3]) end

    -- Profit and return (the better of selling the item and, for Enchanters, disenchanting it)
    local de = res.de
    if res.profit then
        local color = res.profit >= 0 and "|cff40ff40" or "|cffff4040"
        local right = color .. ns.Money(res.profit) .. "|r"
        if res.roi then right = right .. "  |cffaaaaaa(" .. ns.Percent(res.roi) .. " return)|r" end
        local label = res.outlet == "disenchant" and "Profit per craft (disenchanted)" or "Profit per craft"
        tt:AddDoubleLine(label, right, WHITE[1], WHITE[2], WHITE[3])
    end
    if de and de.profit and res.sellProfit then
        local diff = math.abs(de.profit - res.sellProfit)
        if diff < 1 then
            tt:AddLine("Selling it and disenchanting it come out even.", GRAY[1], GRAY[2], GRAY[3])
        elseif res.outlet == "disenchant" then
            tt:AddLine("Disenchant it: the mats beat selling by " .. ns.Money(diff) .. ".", PURPLE[1], PURPLE[2], PURPLE[3], true)
        else
            tt:AddLine("Sell it: beats disenchanting by " .. ns.Money(diff) .. ".", 0.9, 0.9, 0.9, true)
        end
    end

    -- Sale side: listed price, then what the auction house keeps
    local makes = plan.yield ~= 1 and (" (makes " .. ns.Qty(plan.yield) .. ")") or ""
    if res.sell then
        tt:AddDoubleLine("Sells for" .. makes, ns.Money(res.sellGross), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("AH cut (" .. ns.Percent(ns.Cut()) .. ")", ns.Money(-res.sellCut), 0.8, 0.8, 0.8, 1, 0.55, 0.55)
        local age = ns.AHAge(res.out)
        if age and age >= 2 then
            tt:AddLine(("   price is %d days old, rescan the AH"):format(age), 1, 0.6, 0.2)
        end
    else
        tt:AddLine(ns.ItemName(res.out) .. " has no AH price yet. Scan with Auctionator.", 1, 0.6, 0.2, true)
    end

    -- Disenchant side (only Enchanters get res.de)
    if de then AddDisenchant(tt, de, plan.yield) end

    -- Cost side
    if plan.complete then
        tt:AddDoubleLine("Reagent cost (cheapest way)", ns.Money(-plan.cost), 0.8, 0.8, 0.8, 1, 0.55, 0.55)
    else
        tt:AddDoubleLine("Reagent cost", "missing prices", 0.8, 0.8, 0.8, 1, 0.3, 0.3)
    end
    AddPlan(tt, plan.parts, 1, 1)

    -- Posting guidance. Enchanters: below what the mats fetch, disenchanting pays more than the sale.
    if res.breakEven and res.sell then
        local floor, disenchantFloor = res.breakEven, false
        if de and de.each and de.each > floor then floor, disenchantFloor = de.each, true end
        -- round up so the shown price always covers costs (to the silver above 10g, where copper isn't shown)
        floor = math.ceil(floor - 1e-9)
        if floor >= 100000 then floor = math.ceil(floor / 100) * 100 end
        tt:AddDoubleLine("Don't sell below", ns.Money(floor) .. " each", 0.8, 0.8, 0.8, 1, 0.82, 0)
        if disenchantFloor then
            tt:AddLine("   below that, disenchanting it pays more", GRAY[1], GRAY[2], GRAY[3])
        end
    end
    local minReturn = (ns.settings or ns.DEFAULTS).minReturn or 0
    if res.profit and res.profit > 0 and res.roi and res.roi * 100 < minReturn then
        tt:AddLine(("Thin margin (under %d%% return): one undercut can wipe out the profit."):format(minReturn),
            1, 0.6, 0.2, true)
    end

    -- Glowing only because nothing here cleared the minimum profit (see Engine:GlowRanks)
    if opts.rank and opts.relaxed then
        local floor = (ns.settings or ns.DEFAULTS).minProfit or 0
        tt:AddLine(("Nothing here clears your %s minimum profit yet, so this is the best of the rest."):format(
            ns.Money(floor)), GRAY[1], GRAY[2], GRAY[3], true)
    end

    -- Trainer / buying the recipe: payback on what it costs to learn
    local learnCost = opts.trainCost or opts.recipeCost
    if learnCost and learnCost > 0 then
        tt:AddDoubleLine(opts.trainCost and "Training cost" or "Recipe on the AH", ns.Money(learnCost),
            0.8, 0.8, 0.8, 1, 1, 1)
        if res.profit and res.profit > 0 then
            tt:AddLine(("Pays for itself after %d craft(s)."):format(math.ceil(learnCost / res.profit)), 0.4, 1, 0.4)
        end
    end

    -- Recipe items: learn it or sell it?
    if opts.patternItem then
        local patternPrice = ns.AHPrice(opts.patternItem)
        local net = patternPrice and patternPrice * (1 - ns.Cut())
        if net then
            tt:AddDoubleLine("This recipe item sells for", ns.Money(net), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        local need = opts.patternNeed
        if need and opts.patternStatus ~= "known" and opts.patternStatus ~= "other" then
            tt:AddLine(("Needs %s %d to learn (you have %d)."):format(need.prof, need.level, need.rank), 1, 0.5, 0.25, true)
        end
        if opts.patternStatus == "known" then
            tt:AddLine("You already know this recipe" .. (net and ", so sell it." or "."), 1, 0.82, 0, true)
        elseif opts.patternStatus == "other" then
            tt:AddLine("Not one of your professions" .. (net and ", so sell it." or "."), 1, 0.82, 0, true)
        elseif res.profit and res.profit > 0 and need then
            tt:AddLine("Worth learning once you reach that skill.", 0.4, 1, 0.4, true)
        elseif res.profit and res.profit > 0 then
            if net then
                tt:AddLine(("Learning beats selling it after %d craft(s)."):format(math.ceil(net / res.profit)),
                    0.4, 1, 0.4, true)
            else
                tt:AddLine("Worth learning: every craft makes a profit.", 0.4, 1, 0.4, true)
            end
        elseif res.profit then
            tt:AddLine(net and "Crafting loses money, so sell the recipe instead."
                or "Crafting loses money, so don't bother learning it.", 1, 0.4, 0.4, true)
        end
    end

    -- Multi-step hint
    if opts.step then
        local top = ns.db.recipes[opts.step.top]
        local style = Display.RANKS[opts.step.rank]
        if top and style then
            tt:AddLine("Step in your |c" .. style.hex .. style.label:lower() .. "|r craft: " .. (top.name or "?"), 0.9, 0.9, 0.9, true)
        end
    end

    -- only nudge when it could fill a gap (a reagent we couldn't price)
    local missing = plan.complete and {} or ns.Data.UnscannedProfessions()
    if #missing > 0 then
        tt:AddLine("Open your " .. table.concat(missing, ", ") .. " window once to use it for multi-step crafts.",
            GRAY[1], GRAY[2], GRAY[3], true)
    end
end

-- Shows our section on a list row: append to Blizzard's tooltip if it already opened one.
function Display.ShowForRow(row, title, rid, opts)
    local tt = GameTooltip
    if not tt:IsOwned(row) then
        tt:SetOwner(row, "ANCHOR_RIGHT")
        if title then tt:AddLine(title, 1, 1, 1) end
    end
    Display.AddRecipeLines(tt, rid, opts)
    tt:Show()
end
