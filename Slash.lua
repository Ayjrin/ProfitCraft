-- ProfitCraft: /craftprofit (alias /cprofit)
--   /craftprofit          top 5 crafts across your professions (ranked by the "Rank glows by" setting)
--   /craftprofit options  open the settings page
--   /craftprofit status   what ProfitCraft has learned so far (for troubleshooting)
--   /craftprofit why      per profession: why crafts glow or don't (prices, profit, the glow bar)
--   /craftprofit errors   errors recorded this and earlier sessions ("errors clear" forgets them)
--   /craftprofit reset    forget this character's known recipes (re-open profession windows after)
local _, ns = ...

local function Top()
    local ids = {}
    for rid in pairs(ns.KnownSet()) do ids[#ids + 1] = rid end
    if #ids == 0 then
        ns.Print("Open your profession windows once so I can see your recipes.")
        return
    end
    local list = ns.Engine:Rank(ids)
    if #list == 0 then
        ns.Print("Nothing profitable right now. Scan the AH with Auctionator for fresh prices.")
        return
    end
    for i = 1, math.min(5, #list) do
        local res = list[i]
        local r = ns.db.recipes[res.recipeID]
        local prof = r.prof and ns.char.profs[r.prof]
        ns.Print(("%d. %s  |cff40ff40%s|r (%s)%s  |cff999999%s|r"):format(i, ns.ItemLabel(res.out), ns.Money(res.profit),
            ns.Percent(res.roi), res.outlet == "disenchant" and "  |cffc799ffdisenchanted|r" or "", prof and prof.name or ""))
    end
end

local function Status()
    local recipes, vendor = 0, 0
    for _ in pairs(ns.db.recipes) do recipes = recipes + 1 end
    for _ in pairs(ns.db.vendor) do vendor = vendor + 1 end
    ns.Print("Auctionator: " .. (ns.HasAuctionator() and "|cff40ff40found|r" or "|cffff4040missing|r"))
    ns.Print(("Recipes seen: %d   Vendor prices: %d"):format(recipes, vendor))
    for profID, p in pairs(ns.char.profs) do
        local count = 0
        for _ in pairs(ns.char.known[profID] or {}) do count = count + 1 end
        ns.Print(("  %s %s/%s: %d recipes known"):format(p.name or profID, tostring(p.rank), tostring(p.max), count))
    end
    local missing = ns.Data.UnscannedProfessions()
    if #missing > 0 then ns.Print("  Not opened yet: " .. table.concat(missing, ", ")) end
    ns.Print(("Profession window hooked: %s   Trainer hooked: %s   AH tab: %s   AH browse: %s"):format(
        tostring(ns.Professions.hooked), tostring(ns.Trainer.hooked), tostring(ns.AuctionHouse.tabCreated or false),
        tostring(ns.AuctionHouse.browseHooked or false)))
    ns.Print(("What's Training: %s"):format(ns.WhatsTraining.hooked and "hooked"
        or (ns.WhatsTraining.Loaded() and "loaded, open its profession tab once" or "not loaded")))
    ns.Print("LibAHTab: " .. ((LibStub and LibStub("LibAHTab-1-0", true)) and "found" or "missing"))
    local enchanting = ns.Disenchant.PlayerSkill()
    ns.Print("Disenchant values: " .. (enchanting and ("on (Enchanting " .. enchanting .. ")") or "off (no Enchanting)"))
    if #ns.db.errors > 0 then ns.Print(("|cffff6060%d error(s) recorded.|r /craftprofit errors"):format(#ns.db.errors)) end
end

-- Why each profession glows (or doesn't): how many known crafts have prices, make money, clear the bars.
local function Why()
    local s = ns.settings
    ns.Print(("Glow bar: %d%% return and %s profit per craft, ranked by %s."):format(s.minReturn, ns.Money(s.minProfit),
        s.rankBy == "profit" and "profit" or "return"))
    local any = false
    for profID, p in pairs(ns.char.profs) do
        local ids = {}
        for rid in pairs(ns.char.known[profID] or {}) do ids[#ids + 1] = rid end
        if #ids > 0 then
            any = true
            local items, priced, profitable, returnOK, both, disenchant = 0, 0, 0, 0, 0, 0
            for _, rid in ipairs(ids) do
                local res = ns.Engine:Evaluate(rid)
                if res then
                    items = items + 1
                    if res.profit then priced = priced + 1 end
                    if res.profit and res.profit > 0 then profitable = profitable + 1 end
                    if ns.Engine.Qualifies(res, true) then returnOK = returnOK + 1 end
                    if ns.Engine.Qualifies(res) then both = both + 1 end
                    if res.outlet == "disenchant" and res.profit > 0 then disenchant = disenchant + 1 end
                end
            end
            ns.Print(("|cffffd100%s|r %s: %d known, %d make items, %d priced, %d profitable, %d clear the return, %d clear both%s")
                :format(p.name or profID, tostring(p.rank), #ids, items, priced, profitable, returnOK, both,
                    disenchant > 0 and (", %d pay more disenchanted"):format(disenchant) or ""))
            local ranking = ns.Engine:ProfessionRanking(profID)
            for i = 1, math.min(3, #ranking.list) do
                local res = ranking.list[i]
                ns.Print(("   %d. %s  %s (%s)%s%s"):format(i, ns.ItemLabel(res.out), ns.Money(res.profit), ns.Percent(res.roi),
                    res.outlet == "disenchant" and "  |cffc799ffdisenchanted|r" or "",
                    ranking.relaxed and "  |cffaaaaaaunder your profit bar|r" or ""))
            end
            if #ranking.list == 0 then
                if priced < items then
                    ns.Print("   Nothing glows. Some products have no AH price: scan with Auctionator.")
                elseif profitable == 0 then
                    ns.Print("   Nothing glows: no known craft makes money at current prices.")
                else
                    ns.Print(("   Nothing glows: no profitable craft clears the %d%% return bar (lower it in /craftprofit options).")
                        :format(s.minReturn))
                end
            end
        end
    end
    if not any then ns.Print("No recipes yet. Open each profession window once.") end
    local d = ns.db.diag.professions
    if d then
        ns.Print(("Profession window last paint: %d recipe rows, %d glowing%s"):format(d.rows or 0, d.glowing or 0,
            d.foreign and " (viewing someone else's profession)" or ""))
    end
end

local function Errors()
    if #ns.db.errors == 0 then
        ns.Print("No errors recorded.")
        return
    end
    for i, e in ipairs(ns.db.errors) do
        local when = date and e.at and e.at > 0 and date("%b %d %H:%M", e.at) or "?"
        ns.Print(("%d. [%s] %s (x%d): %s"):format(i, when, e.where or "?", e.count or 1, e.err or "?"))
    end
    ns.Print("/craftprofit errors clear forgets them.")
end

SLASH_PROFITCRAFT1 = "/craftprofit"
SLASH_PROFITCRAFT2 = "/cprofit"
SlashCmdList.PROFITCRAFT = function(msg)
    if not ns.IsReady() then return end
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "status" then
        Status()
    elseif msg == "why" then
        Why()
    elseif msg == "errors" then
        Errors()
    elseif msg == "errors clear" then
        wipe(ns.db.errors)
        ns.Print("Errors cleared.")
    elseif msg == "options" or msg == "config" then
        ns.Options.Open()
    elseif msg == "reset" then
        wipe(ns.char.known)
        wipe(ns.char.profs)
        ns.Engine:Invalidate()
        ns.Print("Forgot this character's recipes. Open each profession window again.")
    elseif msg == "debug" then
        ns.debug = not ns.debug
        ns.Print("Debug errors " .. (ns.debug and "on" or "off"))
    else
        Top()
    end
end
