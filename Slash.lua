-- ProfitCraft: /craftprofit (alias /cprofit)
--   /craftprofit          top 5 crafts across your professions (ranked by the "Rank glows by" setting)
--   /craftprofit options  open the settings page
--   /craftprofit status   what ProfitCraft has learned so far (for troubleshooting)
--   /craftprofit why      per profession: why crafts glow or don't (prices, profit, the glow bar)
--   /craftprofit errors   errors recorded this and earlier sessions ("errors clear" forgets them)
--   /craftprofit reset    forget this character's known recipes (re-open profession windows after)
--   /craftprofit plays    the top plays right now (the AH Plays tab has the details and the buttons)
--   /craftprofit ledger   last 7 days: bought, predicted, sold, deposits, disenchant accuracy
--   /craftprofit de       your disenchant measurements and the Arcane Salvager bonus
--   /craftprofit dryrun   turn dry run on or off
--   /craftprofit work     show or hide the Work button
--   /craftprofit wheel    scroll-down over the step buttons presses them (on/off)
--   /craftprofit selling  what plays will post; "selling clear" forgets the list
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
    ns.Print("TradeSkillMaster data: " .. (ns.Prices.HasTSM() and "found (sale rates and market values)" or "not loaded"))
    ns.Print(("Plays tab: %s   Dry run: %s   Scroll-down on step buttons: %s"):format(tostring(ns.PlaysTab.tabCreated or false),
        ns.settings.dryRun and "on" or "off", ns.settings.wheel and "on" or "off"))
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

local function Plays()
    local result = ns.Plays.Build(true)
    if #result.plays == 0 then
        ns.Print("No plays yet. Open the auction house and press Scan on the Plays tab.")
        return
    end
    ns.Print(("You can spend %s. Top plays:"):format(ns.Money(result.budget)))
    for i = 1, math.min(5, #result.plays) do
        local p = result.plays[i]
        local t = ns.Plays.TIERS[p.tier]
        if p.tier == "locked" then
            ns.Print(("%d. |c%s%s|r %s: %s"):format(i, t.color, t.label, p.title, p.locked or ""))
        else
            ns.Print(("%d. |c%s%s|r %s  |cff40ff40%s|r  (%s/min, needs %s)"):format(i, t.color, t.label, p.title,
                ns.Money(p.profit), ns.Money(p.perMinute), ns.Money(p.cost)))
        end
    end
    if result.hidden > 0 then ns.Print(("%d riskier play(s) hidden by your \"Plays offered\" setting."):format(result.hidden)) end
end

local function Ledger()
    local s = ns.Ledger.Summary(7)
    ns.Print("Last 7 days with ProfitCraft:")
    ns.Print(("  Bought %d for %s; predicted worth %s."):format(s.buys, ns.Money(s.spent), ns.Money(s.predicted)))
    ns.Print(("  Sold (AH mail taken): %d sale(s), %s.   Deposits paid: %s."):format(s.sales, ns.Money(s.sold),
        ns.Money(s.deposits)))
    if s.deCount > 0 then
        ns.Print(("  Disenchanted %d: mats worth %s now, expected %s (%s)."):format(s.deCount, ns.Money(s.deActual),
            ns.Money(s.deExpected), s.deExpected > 0 and ns.Percent(s.deActual / s.deExpected) or "?"))
    end
    ns.Print(("  This session: spent %s of your %s cap."):format(ns.Money(ns.Ledger.SessionSpent()),
        ns.settings.sessionCap > 0 and ns.Money(ns.settings.sessionCap) or "unlimited"))
end

local function DE()
    local list = ns.Telemetry.Summary()
    if #list == 0 then
        ns.Print("No disenchants recorded yet. Disenchant with the Work button and they're measured.")
    end
    for _, b in ipairs(list) do
        ns.Print(("  %s: %d normal, %d next to a Salvager%s"):format(b.key, b.base, b.buffed,
            b.base >= ns.Telemetry.MIN_SAMPLES and "  (measured rates in use)" or ""))
    end
    local mult, n, source = ns.Telemetry.SalvagerMultiplier()
    ns.Print(("Arcane Salvager: %s"):format(source == "measured" and ("x%.2f dust and essences, from %d buffed disenchants"):format(mult, n)
        or ("not measured yet (%d of %d buffed disenchants); %s"):format(n, ns.Telemetry.MIN_SALVAGER,
            source == "setting" and ("using your %d%% setting"):format(ns.settings.salvagerBonus) or "no bonus counted")))
end

local function Selling(clear)
    if clear then
        wipe(ns.char.toSell)
        ns.Print("Forgot the list of things to post.")
        return
    end
    local names = {}
    for id in pairs(ns.char.toSell) do names[#names + 1] = ns.ItemName(id) .. " (" .. ns.ItemCount(id) .. ")" end
    table.sort(names)
    ns.Print(#names > 0 and ("Plays will post: " .. table.concat(names, ", ")) or "Nothing marked for posting.")
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
    elseif msg == "plays" then
        Plays()
    elseif msg == "ledger" then
        Ledger()
    elseif msg == "de" or msg == "disenchant" then
        DE()
    elseif msg == "dryrun" or msg == "dry run" then
        ns.settings.dryRun = not ns.settings.dryRun
        ns.Print("Dry run " .. (ns.settings.dryRun and "on: buttons rehearse and spend nothing." or "|cffff6060off: buttons buy and post for real.|r"))
        ns.Options.Refresh()
    elseif msg == "wheel" then
        ns.settings.wheel = not ns.settings.wheel
        ns.Print("Scroll-down over ProfitCraft's step buttons " .. (ns.settings.wheel
            and "now presses them (only while the cursor is on one; zoom works everywhere else)." or "is off."))
        ns.Options.Refresh()
    elseif msg == "work" then
        ns.Print("Work button " .. (ns.Work.Toggle() and "shown." or "shows only when it has something to do."))
    elseif msg == "selling" then
        Selling(false)
    elseif msg == "selling clear" then
        Selling(true)
    elseif msg == "debug" then
        ns.debug = not ns.debug
        ns.Print("Debug errors " .. (ns.debug and "on" or "off"))
    else
        Top()
    end
end
