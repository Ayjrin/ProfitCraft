-- ProfitCraft offline test harness: stubs the WoW API, loads the addon in TOC order, checks behaviour.
-- Run from the addon folder:  luajit Tests/harness.lua .
-- (WoW never loads this file; it isn't listed in ProfitCraft.toc.)
local DIR = arg[1] or "."
local failures = 0
local function check(cond, msg)
    if cond then print("PASS " .. msg) else failures = failures + 1; print("FAIL " .. msg) end
end
local function has(lines, needle) for _, l in ipairs(lines) do if l:find(needle, 1, true) then return true end end return false end
-- turn coin icons back into g/s/c and drop colour codes so lines are easy to assert on
local function strip(s) return (s:gsub("|T[^|]*UI%-GoldIcon[^|]*|t", "g"):gsub("|T[^|]*UI%-SilverIcon[^|]*|t", "s")
    :gsub("|T[^|]*UI%-CopperIcon[^|]*|t", "c"):gsub("|T[^|]*|t ?", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

---------------------------------------------------------------------------
-- WoW API stubs
---------------------------------------------------------------------------
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function flush() for _ = 1, 20 do local t = timers; timers = {}; if #t == 0 then return end; for _, f in ipairs(t) do f() end end end

local clock = 100 -- advanced by the trading tests
function GetTime() return clock end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function hooksecurefunc(a, b, c)
    if type(a) == "table" then local orig = a[b]; a[b] = function(...) local r = orig(...); c(...); return r end
    else local orig = _G[a]; _G[a] = function(...) local r = orig(...); b(...); return r end end
end
Enum = { CraftingReagentType = { Basic = 1, Modifying = 0 }, ItemClass = { Recipe = 9 }, TooltipDataType = { Item = 0, Spell = 1 } }
ITEM_MIN_SKILL = "Requires %s (%d)"

-- frames: real behaviour for what the tests look at, no-op methods for everything else
local eventFrames = {}
local noop = function() end
local Region = {}
Region.__index = function(_, k) return rawget(Region, k) or (type(k) == "string" and k:match("^%u") and noop) or nil end
function Region:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Region:Hide() self.shown = false end
function Region:IsShown() return self.shown end
function Region:IsVisible() return self.shown end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:GetFrameLevel() return 1 end
function Region:GetName() return self.name end
function Region:SetAttribute(k, v) self.attrs = self.attrs or {}; self.attrs[k] = v end
function Region:GetAttribute(k) return self.attrs and self.attrs[k] end
function Region:GetHeight() return self.height or 0 end
function Region:CreateTexture() return setmetatable({ scripts = {} }, Region) end
function Region:CreateFontString() return setmetatable({ scripts = {} }, Region) end
function Region:SetText(t) self.text = t end
function Region:GetText() return self.text end
function Region:SetChecked(v) self.checked = v and true or false end
function Region:GetChecked() return self.checked end
function Region:Click() if self.isCheck then self.checked = not self.checked end; if self.scripts.OnClick then self.scripts.OnClick(self) end end
function Region:SetEnabled(v) self.enabled = v end
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:HookScript(name, fn) local o = self.scripts[name]; self.scripts[name] = function(...) if o then o(...) end fn(...) end end
function Region:RegisterEvent(e) eventFrames[e] = eventFrames[e] or {}; table.insert(eventFrames[e], self) end
function Region:CreateAnimationGroup()
    local ag = setmetatable({ scripts = {} }, Region)
    function ag:Play() self.playing = true end; function ag:Stop() self.playing = false end; function ag:IsPlaying() return self.playing end
    function ag:CreateAnimation() return setmetatable({ scripts = {} }, Region) end
    return ag
end
local function NewRegion(kind) local r = setmetatable({ scripts = {}, shown = true }, Region); if kind == "CheckButton" then r.isCheck = true; r.checked = false end; return r end
function CreateFrame(kind, name) local r = NewRegion(kind); if name then r.name = name; _G[name] = r end; return r end
local function Fire(event, ...) for _, f in ipairs(eventFrames[event] or {}) do f.scripts.OnEvent(f, event, ...) end; flush() end

-- items & prices (copper)
local ITEMS = {
    [2589] = "Linen Cloth", [2996] = "Bolt of Linen Cloth", [2320] = "Coarse Thread", [2569] = "Linen Robe",
    [10938] = "Lesser Magic Essence", [10939] = "Greater Magic Essence", [9999] = "Mystery Dust", [8888] = "Dusty Cloak",
    [3333] = "Fancy Hat", [4444] = "Silk Hat", [6001] = "Gold Bar", [6002] = "Gold Ring", [6003] = "Copper Bar", [6004] = "Copper Wire",
    [5000] = "Pattern: Linen Robe", [5001] = "Pattern: Dusty Cloak", [5002] = "Pattern: Silk Hat", [5003] = "Pattern: Fancy Hat",
}
local REQ = { [5000] = 10, [5002] = 50, [5003] = 100 }
local BAGS = { [2589] = 5 }
local AHP = { [2589] = 10, [2996] = 50, [2569] = 200, [10938] = 100, [10939] = 250, [8888] = 30, [5000] = 1000, [5001] = 400,
    [3333] = 900, [4444] = 200,
    [6001] = 100000, [6002] = 110000, -- example A: 10g of reagents, sells for 11g
    [6003] = 200, [6004] = 400 }      -- example B: 2s of reagents, sells for 4s
C_Item = {
    GetItemNameByID = function(id) return ITEMS[id] end,
    GetItemIconByID = function() return 134400 end,
    GetItemQualityByID = function() return 1 end,
    RequestLoadItemDataByID = noop,
    GetItemInfoInstant = function(id)
        if id >= 5000 and id < 6000 then return id, "Recipe", "Tailoring", "", 0, 9, 2 end
        return id, "Trade Goods", "Cloth", "", 0, 7, 5
    end,
    GetItemSpell = function() return nil end,
    GetItemCount = function(id) return BAGS[id] or 0 end,
}
ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }

local created
Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function(caller, id) assert(type(caller) == "string"); return AHP[id] end,
    GetAuctionAgeByItemID = function() return 0 end,
    ConvertToSearchString = function(_, term) assert(term.isExact); return ('"%s";;;;;;;;;;;;;%d'):format(term.searchString, term.quantity) end,
    CreateShoppingList = function(caller, name, strings) created = { caller = caller, name = name, strings = strings } end,
} } }

-- professions
local RECIPES = {
    [2963] = { name = "Bolt of Linen Cloth", out = 2996, reagents = { { 2589, 2 } }, learned = true },
    [7623] = { name = "Linen Robe", out = 2569, reagents = { { 2996, 3 }, { 2320, 1 } }, learned = true },
    [100] = { name = "Greater Magic Essence", out = 10939, reagents = { { 10938, 3 } }, learned = true },
    [101] = { name = "Lesser Magic Essence", out = 10938, reagents = { { 10939, 1 } }, learned = true, qmin = 3 },
    [102] = { name = "Dusty Cloak", out = 8888, reagents = { { 9999, 1 } }, learned = true },
    [103] = { name = "Gold Ring", out = 6002, reagents = { { 6001, 1 } }, learned = true },
    [104] = { name = "Copper Wire", out = 6004, reagents = { { 6003, 1 } }, learned = true },
    [200] = { name = "Silk Hat", out = 4444, reagents = { { 2589, 4 } }, learned = false },
    [201] = { name = "Fancy Hat", out = 3333, reagents = { { 2589, 4 } }, learned = false },
}
local function Schematic(rid)
    local r = RECIPES[rid]; if not r then return nil end
    local slots = {}
    for _, x in ipairs(r.reagents) do slots[#slots + 1] = { required = true, reagentType = 1, quantityRequired = x[2], reagents = { { itemID = x[1] } } } end
    slots[#slots + 1] = { required = false, reagentType = 0, quantityRequired = 1, reagents = { { itemID = 77777 } } }
    return { name = r.name, outputItemID = r.out, quantityMin = r.qmin or 1, quantityMax = r.qmin or 1, reagentSlotSchematics = slots }
end
C_TradeSkillUI = {
    IsTradeSkillReady = function() return true end, IsDataSourceChanging = function() return false end,
    GetBaseProfessionInfo = function() return { professionID = 197, professionName = "Tailoring", skillLevel = 75, maxSkillLevel = 150 } end,
    GetAllRecipeIDs = function() local t = {}; for k in pairs(RECIPES) do t[#t + 1] = k end; table.sort(t); return t end,
    GetRecipeInfo = function(rid) local r = RECIPES[rid]; return r and { recipeID = rid, name = r.name, learned = r.learned } end,
    GetRecipeSchematic = Schematic,
    IsTradeSkillLinked = function() return false end, IsTradeSkillGuild = function() return false end, IsNPCCrafting = function() return false end,
}
function GetProfessions() return 1, nil, nil, nil, 2, nil end
function GetProfessionInfo(i)
    if i == 1 then return "Tailoring", 0, 75, 150, 0, 0, 197 end
    return "Cooking", 0, 1, 75, 0, 0, 185
end
function GetMerchantNumItems() return 1 end
function GetMerchantItemID() return 2320 end
C_MerchantFrame = { GetItemInfo = function() return { price = 10, stackCount = 1, numAvailable = -1, hasExtendedCost = false } end }

-- tooltips
local function NewTooltip()
    local tt = NewRegion(); tt.lines = {}
    function tt:IsOwned(o) return self.owner == o end
    function tt:GetOwner() return self.owner end
    function tt:SetOwner(o) self.owner = o; self.lines = {} end
    function tt:AddLine(t) self.lines[#self.lines + 1] = t end
    function tt:AddDoubleLine(a, b) self.lines[#self.lines + 1] = a .. "  ||  " .. b end
    return tt
end
GameTooltip = NewTooltip(); ItemRefTooltip = NewTooltip()
local postCalls, spellPostCalls = {}, {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
    if kind == Enum.TooltipDataType.Spell then spellPostCalls[#spellPostCalls + 1] = fn else postCalls[#postCalls + 1] = fn end
end }
C_TooltipInfo = {
    GetItemByID = function(id)
        local lines = { { leftText = ITEMS[id] or "?" } }
        if REQ[id] then lines[#lines + 1] = { leftText = ("Requires Tailoring (%d)"):format(REQ[id]) } end
        lines[#lines + 1] = { leftText = "Use: Teaches you." }
        return { lines = lines }
    end,
}

-- Settings (Options > AddOns) stub
local opened
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name, GetID = function() return name end } end,
    RegisterAddOnCategory = noop,
    OpenToCategory = function(id) opened = id end,
}

-- LibAHTab stub (+ a fake Auctionator Shopping tab)
local libtab = { internalState = { usedIDs = {} } }
function libtab:DoesIDExist(id) return self.internalState.usedIDs[id] ~= nil end
function libtab:CreateTab(id, frame, text) local b = NewRegion(); b.text = text; b.frameRef = frame; self.internalState.usedIDs[id] = b; frame:Hide() end
function libtab:SetSelected(id) for _, b in pairs(self.internalState.usedIDs) do b.frameRef:Hide() end; self.internalState.usedIDs[id].frameRef:Show(); self.selected = id end
LibStub = function(name) if name == "LibAHTab-1-0" then return libtab end end
libtab:CreateTab("AuctionatorShopping", NewRegion(), "Shopping")

SlashCmdList = {}
local realPrint = print
local printed = {}
local function capture() printed = {}; print = function(...) local t = {}; for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end; printed[#printed + 1] = table.concat(t, " ") end end

---------------------------------------------------------------------------
-- Load the addon
---------------------------------------------------------------------------
local ns = {}
capture()
for line in io.lines(DIR .. "/ProfitCraft.toc") do
    if line:match("%.lua$") then assert(loadfile(DIR .. "/" .. line))("ProfitCraft", ns) end
end
Fire("ADDON_LOADED", "ProfitCraft")
Fire("PLAYER_LOGIN")
print = realPrint

---------------------------------------------------------------------------
-- Formatting & defaults
---------------------------------------------------------------------------
check(strip(ns.Money(12345)) == "1g 23s 45c", "money uses coin icons (1g 23s 45c)")
check(ns.Money(12345):find("UI-GoldIcon", 1, true) and not ns.Money(12345):find("1g", 1, true), "no letter abbreviations")
check(strip(ns.Money(0)) == "0c" and strip(ns.Money(-250)) == "-2s 50c", "zero and negative money")
check(strip(ns.Money(123456)) == "12g 34s", "copper hidden above 10 gold")
check(ns.Percent(0.045) == "4.5%" and ns.Percent(0.9) == "90%" and ns.Percent(0.05) == "5%", "percent formatting")
check(ns.settings.rankBy == "roi" and ns.settings.minReturn == 15 and ns.settings.minProfit == 100 and ns.settings.ahCut == 5,
    "defaults: rank by return, 15% min return, 1s min profit, 5% AH cut")

---------------------------------------------------------------------------
-- Profession window + the math
---------------------------------------------------------------------------
local function Row(data) local r = NewRegion(); function r:GetElementData() return data end; return r end
local function Box(rows) local b = NewRegion(); b.rows = rows
    function b:ForEachFrame(fn) for _, r in ipairs(self.rows) do fn(r) end end
    b.Update = noop; return b end
local function RecipeNode(rid) return { GetData = function() return { recipeInfo = { recipeID = rid, name = RECIPES[rid].name, learned = RECIPES[rid].learned } } end } end
local profRows = { Row(RecipeNode(7623)), Row(RecipeNode(2963)), Row(RecipeNode(101)), Row(RecipeNode(103)), Row(RecipeNode(104)), Row(RecipeNode(200)) }
local ROBE, BOLT, LESSER, RING, WIRE = 1, 2, 3, 4, 5
ProfessionsFrame = NewRegion(); ProfessionsFrame.CraftingPage = { RecipeList = { ScrollBox = Box(profRows) } }
Fire("MERCHANT_SHOW")
Fire("TRADE_SKILL_SHOW")

local A, B = ns.Engine:Evaluate(103), ns.Engine:Evaluate(104)
check(A.gross == 110000 and A.cut == 5500 and A.profit == 4500, "example A: sells 11g, AH cut 55s, profit 45s")
check(math.abs(A.roi - 0.045) < 1e-9, "example A: 4.5% return")
check(math.abs(B.profit - 180) < 1e-9 and math.abs(B.roi - 0.9) < 1e-9, "example B: profit 1s 80c, 90% return")
check(math.abs(A.breakEven - 100000 / 0.95) < 1e-6, "example A: break-even 10g 52s 63c")
check(math.abs(ns.Engine:Evaluate(7623).profit - 120) < 1e-9, "multi-step: robe profit 1s 20c via crafted bolts + vendor thread")
check(math.abs(ns.Engine:Evaluate(101).profit - 35) < 1e-9, "essence cycle handled")

-- Return mode (default): robe 171%, bolt 137% but only 27c (< 1s floor), wire 90%, lesser 14% and ring 4.5% (< 15%).
ns.Professions.Paint()
check(ns.Display.GlowRank(profRows[ROBE]) == 1, "return mode: robe (171%) gold")
check(ns.Display.GlowRank(profRows[WIRE]) == 2, "return mode: copper wire (90%) silver")
check(ns.Display.GlowRank(profRows[BOLT]) == nil, "return mode: bolt skipped, profit under the 1s floor")
check(ns.Display.GlowRank(profRows[RING]) == nil and ns.Display.GlowRank(profRows[LESSER]) == nil, "return mode: thin margins skipped")

local function Rerank() ns.Engine:Invalidate(); flush(); ns.Professions.Paint() end
ns.settings.rankBy = "profit"; Rerank()
check(ns.Display.GlowRank(profRows[WIRE]) == 1 and ns.Display.GlowRank(profRows[ROBE]) == 2, "profit mode: wire 1s 80c gold, robe 1s 20c silver")
check(ns.Display.GlowRank(profRows[RING]) == nil, "profit mode: ring's 45s still skipped (4.5% < 15%)")
ns.settings.minReturn = 0; Rerank()
check(ns.Display.GlowRank(profRows[RING]) == 1, "min return 0: ring's 45s takes gold in profit mode")
ns.settings.minProfit = 0; ns.settings.rankBy = "roi"; Rerank()
check(ns.Display.GlowRank(profRows[BOLT]) == 2, "min profit 0: bolt (137%) silver in return mode")
ns.settings.rankBy, ns.settings.minReturn, ns.settings.minProfit = "roi", 15, 100; Rerank()

profRows[RING].scripts.OnEnter(profRows[RING])
local ringTip = {}; for _, l in ipairs(GameTooltip.lines) do ringTip[#ringTip + 1] = strip(l) end
print("\n--- tooltip: example A (10g -> 11g) ---"); for _, l in ipairs(ringTip) do print(l) end
check(has(ringTip, "Profit per craft  ||  45s  (4.5% return)"), "tooltip: profit with return %")
check(has(ringTip, "Sells for  ||  11g"), "tooltip: listed price")
check(has(ringTip, "AH cut (5%)  ||  -55s"), "tooltip: AH cut line")
check(has(ringTip, "Don't sell below  ||  10g 53s each"), "tooltip: break-even rounded up")
check(has(ringTip, "Thin margin"), "tooltip: thin margin warning")
check(not has(ringTip, "after AH cut"), "old 'after AH cut' wording gone")

-- Low skill: nothing clears the minimum profit, so the best crafts that clear the minimum return glow.
ns.settings.minProfit = 100000; Rerank()
check(ns.Display.GlowRank(profRows[ROBE]) == 1 and ns.Display.GlowRank(profRows[BOLT]) == 2
    and ns.Display.GlowRank(profRows[WIRE]) == 3, "fallback: nothing clears 10g profit, best by return still glow")
check(ns.Display.GlowRank(profRows[RING]) == nil and ns.Display.GlowRank(profRows[LESSER]) == nil,
    "fallback: thin margins still never glow")
profRows[ROBE].scripts.OnEnter(profRows[ROBE])
local robeTip = {}; for _, l in ipairs(GameTooltip.lines) do robeTip[#robeTip + 1] = strip(l) end
check(has(robeTip, "Nothing here clears your 10g minimum profit yet"), "fallback: tooltip says why it glows")
ns.settings.minProfit = 100; Rerank()
check(ns.Display.GlowRank(profRows[BOLT]) == nil, "fallback off again once something clears the bar")

---------------------------------------------------------------------------
-- Trainer
---------------------------------------------------------------------------
local trainerRows = { Row({ skillIndex = 1 }), Row({ skillIndex = 2 }), Row({ skillIndex = 3 }) }
ClassTrainerFrame = NewRegion(); ClassTrainerFrame.ScrollBox = Box(trainerRows)
function IsTradeskillTrainer() return true end
function GetNumTrainerServices() return 3 end
local SERVICES = { { "Silk Hat", "available", 4444, 200 }, { "Fancy Hat", "available", 3333, 201 }, { "Linen Robe", "used", 2569, 7623 } }
function GetTrainerServiceInfo(i) return SERVICES[i][1], "", SERVICES[i][2] end
function GetTrainerServiceItemLink(i) return "|Hitem:" .. SERVICES[i][3] .. ":::|h" end
function GetTrainerServiceCost() return 500 end
C_TooltipInfo.GetTrainerService = function(i) return { type = 1, id = SERVICES[i][4] } end
Fire("TRAINER_SHOW")
-- fancy hat: 40c -> 855c (2037%), silk hat: 40c -> 190c (375%)
check(ns.Display.GlowRank(trainerRows[2]) == 1 and ns.Display.GlowRank(trainerRows[1]) == 2, "trainer: fancy hat gold, silk hat silver")
check(ns.Display.GlowRank(trainerRows[3]) == nil, "trainer: known recipe no glow")

---------------------------------------------------------------------------
-- What's Training's recipe list (the tab it adds to the profession window)
---------------------------------------------------------------------------
local function WTRow(data)
    local r = NewRegion(); r.data = data
    -- What's Training's own OnEnter: owns the tooltip and shows the recipe as a spell (which runs spell post-calls)
    r.scripts.OnEnter = function(self)
        GameTooltip:SetOwner(self); GameTooltip:AddLine("WT: " .. (data.name or "header"))
        for _, fn in ipairs(spellPostCalls) do fn(GameTooltip, { id = data.recipe and data.recipe.spell }) end
    end
    return r
end
local wtSilk = { name = "Silk Hat", category = 1, professionID = 197, profession = "Tailoring", recipe = { spell = 200, creates = 4444, cost = 500 } }
local wtFancy = { name = "Fancy Hat", category = 1, professionID = 197, profession = "Tailoring", recipe = { spell = 201, creates = 3333, cost = 500 } }
local wtRows = { WTRow({ profession = "Tailoring", professionID = 197 }), WTRow(wtSilk), WTRow(wtFancy) }
local wtView = NewRegion()
wtView.scrollBox = Box(wtRows)
local wtAvailable = { wtSilk, wtFancy }
wtView.categoryNodes = { { GetData = function() return { items = wtAvailable } end } }
function wtView:Filter() end
WhatsTrainingCraftingRecipeList = wtView
Fire("ADDON_LOADED", "WhatsTraining")
check(ns.WhatsTraining.hooked, "What's Training list hooked")
check(ns.Display.GlowRank(wtRows[3]) == 1 and ns.Display.GlowRank(wtRows[2]) == 2, "WT: fancy hat gold, silk hat silver")
check(ns.Display.GlowRank(wtRows[1]) == nil, "WT: profession header doesn't glow")
wtRows[3].scripts.OnEnter(wtRows[3])
local wtTip = {}; for _, l in ipairs(GameTooltip.lines) do wtTip[#wtTip + 1] = strip(l) end
print("\n--- tooltip: What's Training row ---"); for _, l in ipairs(wtTip) do print(l) end
check(wtTip[1] == "WT: Fancy Hat", "WT: its own tooltip kept, ours appended")
check(has(wtTip, "Most profitable to learn now"), "WT: rank label")
check(has(wtTip, "Training cost  ||  5s") and has(wtTip, "Pays for itself after 1 craft(s)."), "WT: training cost and payback")
wtAvailable = { wtSilk }; wtView:Filter()
check(ns.Display.GlowRank(wtRows[2]) == 1 and ns.Display.GlowRank(wtRows[3]) == nil, "WT: ranking follows its filter")

---------------------------------------------------------------------------
-- Auction house: browse highlights
---------------------------------------------------------------------------
local browseRows = { Row({ itemKey = { itemID = 5000 } }), Row({ itemKey = { itemID = 5002 } }), Row({ itemKey = { itemID = 5003 } }), Row({ itemKey = { itemID = 2589 } }) }
AuctionHouseFrame = NewRegion()
AuctionHouseFrame.BrowseResultsFrame = { ItemList = { ScrollBox = Box(browseRows) } }
C_AuctionHouse = { GetBrowseResults = function() local t = {}; for _, r in ipairs(browseRows) do t[#t + 1] = r:GetElementData() end; return t end }
Fire("AUCTION_HOUSE_SHOW")
check(ns.AuctionHouse.tabCreated and libtab.internalState.usedIDs.ProfitCraft.text == "Profit", "Profit tab created through LibAHTab")
check(ns.Display.GlowRank(browseRows[2]) == 1, "browse: learnable pattern (req 50, you 75) gold")
check(ns.Display.GlowRank(browseRows[1]) == nil, "browse: known pattern skipped")
check(ns.Display.GlowRank(browseRows[3]) == nil, "browse: pattern above your skill skipped")
check(ns.Display.GlowRank(browseRows[4]) == nil, "browse: non-recipe skipped")

local function HoverItem(id)
    GameTooltip.lines = {}; GameTooltip.scripts.OnTooltipCleared(GameTooltip)
    for _, fn in ipairs(postCalls) do fn(GameTooltip, { id = id }) end
    return GameTooltip.lines
end
check(has(HoverItem(5002), "Most profitable recipe you can learn here"), "pattern tooltip: rank label")
local fancy = HoverItem(5003)
check(has(fancy, "Needs Tailoring 100 to learn (you have 75).") and has(fancy, "Worth learning once you reach that skill."),
    "pattern tooltip: skill too low explained")

---------------------------------------------------------------------------
-- Auction house: Profit tab
---------------------------------------------------------------------------
libtab:SetSelected("ProfitCraft")
local panel = libtab.internalState.usedIDs.ProfitCraft.frameRef
check(panel.shown, "Profit tab panel shown on select")
check(panel.summary.text and panel.summary.text:find("2 craft"), "glowing crafts ticked by default (robe + wire): " .. strip(panel.summary.text or ""))
check(panel.headers.roi.arrow.shown and not panel.headers.profit.arrow.shown, "default sort column is Return")
panel.headers.profit.scripts.OnClick(panel.headers.profit)
check(panel.headers.profit.arrow.shown and not panel.headers.roi.arrow.shown, "clicking Profit header sorts by profit")
check(panel.headers.cut and panel.headers.sells and panel.headers.cost, "AH cut / Sells for / Reagent cost columns exist")
panel.count.text = "2"; panel.count.scripts.OnEditFocusLost(panel.count)
check(panel.summary.text:find("x2"), "crafts-of-each = 2 reflected in summary")
panel.create.scripts.OnClick(panel.create)
flush()
print("\n--- shopping list (robe + wire, x2) ---"); print(strip(panel.status.text)); for _, s in ipairs(created and created.strings or {}) do print("  " .. s) end
check(created and created.name == "ProfitCraft" and created.caller == "ProfitCraft", "shopping list created via Auctionator API")
local s = table.concat(created.strings, "|")
-- robe x2 -> 6 bolts crafted -> 12 linen, minus 5 owned = 7; wire x2 -> 2 copper bars
check(s:find('"Linen Cloth";;;;;;;;;;;;;7', 1, true), "linen: 12 needed - 5 owned = 7")
check(s:find('"Copper Bar";;;;;;;;;;;;;2', 1, true), "copper bar x2")
check(not s:find("Bolt of Linen", 1, true), "crafted intermediate broken down, not bought")
check(panel.status.text:find("Buy from a vendor: 2x Coarse Thread", 1, true), "vendor reagents listed separately")
check(libtab.selected == "AuctionatorShopping", "switched to Auctionator's Shopping tab")

---------------------------------------------------------------------------
-- Options page + slash
---------------------------------------------------------------------------
check(ns.Options.category and ns.Options.category.name == "ProfitCraft", "options page registered under Options > AddOns")
capture(); SlashCmdList.PROFITCRAFT("options"); SlashCmdList.PROFITCRAFT(""); SlashCmdList.PROFITCRAFT("status")
SlashCmdList.PROFITCRAFT("why"); print = realPrint
check(opened == "ProfitCraft", "/craftprofit options opens the page")
print("\n--- /craftprofit + status + why ---"); for _, l in ipairs(printed) do print(strip(l)) end
check(has(printed, "What's Training: hooked"), "status reports What's Training")
check(has(printed, "7 known, 7 make items, 6 priced, 5 profitable, 3 clear the return, 2 clear both"), "why: counts per profession")
check(#ns.db.errors == 0, "no errors recorded during any of the above")

---------------------------------------------------------------------------
-- Errors are recorded, announced, and can't take hover down with them
---------------------------------------------------------------------------
local realRanking = ns.Engine.ProfessionRanking
ns.Engine.ProfessionRanking = function() error("boom") end
local profBox = ProfessionsFrame.CraftingPage.RecipeList.ScrollBox
local freshRow = Row(RecipeNode(7623)); table.insert(profBox.rows, freshRow)
capture(); ns.Professions.Paint(); print = realPrint
check(freshRow.scripts.OnEnter ~= nil, "rows get hover even when the ranking fails")
check(ns.db.errors[1] and ns.db.errors[1].where == "profession glows" and ns.db.errors[1].err:find("boom"),
    "error kept in saved variables")
check(has(printed, "hit an error in profession glows"), "error announced in chat")
freshRow.scripts.OnEnter(freshRow)
check(has(GameTooltip.lines, "Profit per craft"), "tooltip still works when the ranking fails")
capture(); SlashCmdList.PROFITCRAFT("errors"); print = realPrint
check(has(printed, "profession glows (x"), "/craftprofit errors lists it")
ns.Engine.ProfessionRanking = realRanking
table.remove(profBox.rows)
capture(); SlashCmdList.PROFITCRAFT("errors clear"); print = realPrint
check(#ns.db.errors == 0, "/craftprofit errors clear")

---------------------------------------------------------------------------
-- Disenchanting (Enchanters only)
---------------------------------------------------------------------------
-- gear: armor (class 4) / weapon (class 2), quality, item level
local GEAR = {
    [7001] = { class = 4, q = 2, ilvl = 22 }, -- Green Gloves: green armor 21-25
    [7002] = { class = 2, q = 2, ilvl = 22 }, -- Green Staff: green weapon 21-25 (mostly essences)
    [7003] = { class = 4, q = 3, ilvl = 28 }, -- Blue Cloak: rare 26-30 (no skill needed in Forever)
    [7004] = { class = 4, q = 2, ilvl = 10, slow = true }, -- Slow Boots: item info not loaded at first
    [7005] = { class = 4, q = 3, ilvl = 12 }, -- Low Blue Vest: Forever's new blue bracket, mats unknown
    [7006] = { class = 2, q = 4, ilvl = 30 }, -- Low Epic Sword: epics start at item level 40
    [7007] = { class = 4, q = 2, ilvl = 3 },  -- Tiny Green Cap: greens start at item level 5
}
ITEMS[7001], ITEMS[7002], ITEMS[7003], ITEMS[7004] = "Green Gloves", "Green Staff", "Blue Cloak", "Slow Boots"
ITEMS[7005], ITEMS[7006], ITEMS[7007] = "Low Blue Vest", "Low Epic Sword", "Tiny Green Cap"
ITEMS[10940], ITEMS[10998], ITEMS[10978], ITEMS[11084] = "Strange Dust", "Lesser Astral Essence", "Small Glimmering Shard", "Large Glimmering Shard"
AHP[10940], AHP[10998], AHP[10978], AHP[11084] = 50, 400, 300, 1000
AHP[7001], AHP[7002] = 150, 1000 -- gloves sell for 1s 50c, the staff for 10s; the cloak has no AH price
local instant = C_Item.GetItemInfoInstant
C_Item.GetItemInfoInstant = function(id)
    local g = GEAR[id]
    if g then return id, "Gear", "Cloth", "", 0, g.class, 1 end
    return instant(id)
end
C_Item.GetItemInfo = function(id)
    local g = GEAR[id]
    if g and g.slow then return nil end
    return ITEMS[id], nil, g and g.q or 1, g and g.ilvl or 1
end
RECIPES[300] = { name = "Green Gloves", out = 7001, reagents = { { 2589, 4 } }, learned = true }
RECIPES[301] = { name = "Green Staff", out = 7002, reagents = { { 2589, 4 } }, learned = true }
RECIPES[302] = { name = "Blue Cloak", out = 7003, reagents = { { 2589, 4 } }, learned = true }
RECIPES[303] = { name = "Slow Boots", out = 7004, reagents = { { 2589, 4 } }, learned = true }
Fire("TRADE_SKILL_SHOW")
local function Tip(rid)
    GameTooltip:SetOwner(nil); ns.Display.AddRecipeLines(GameTooltip, rid)
    local t = {}; for _, l in ipairs(GameTooltip.lines) do t[#t + 1] = strip(l) end
    return t
end

check(ns.Disenchant.Evaluate(7006) == nil and ns.Disenchant.Evaluate(7007) == nil,
    "outside Forever's brackets (epic under 40, green under 5): can't be disenchanted")
check(ns.Disenchant.Evaluate(7005).unknown and ns.Disenchant.Evaluate(7005).each == nil, "blue under item level 21: mats unknown")

-- no Enchanting: nothing changes
local gloves = ns.Engine:Evaluate(300)
check(gloves.de == nil and gloves.outlet == "sell" and math.abs(gloves.profit - 102.5) < 1e-9, "no Enchanting: no disenchant values")
check(not has(Tip(300), "Disenchant"), "no Enchanting: tooltip has no disenchant lines")
check(not panel.headers.de.shown, "no Enchanting: Profit tab has no Disenchant column")

-- learn Enchanting (30)
local enchantSkill = 30
local professions, professionInfo = GetProfessions, GetProfessionInfo
GetProfessions = function() return 1, 3, nil, nil, 2, nil end
GetProfessionInfo = function(i)
    if i == 3 then return "Enchanting", 0, enchantSkill, 75, 0, 0, 333 end
    return professionInfo(i)
end
ns.Engine:Invalidate(); flush()
check(ns.Engine:EnchantingSkill() == 30, "Enchanting skill read from the game")

-- gloves: 75% 4-6 dust (187.5c) + 15% 1-2 lesser astral (90c) + 10% shard (30c) = 307.5c; sell 150c
gloves = ns.Engine:Evaluate(300)
check(gloves.de and math.abs(gloves.de.each - 307.5) < 1e-9, "green armor 21-25: mats average 3s 7.5c")
check(gloves.outlet == "disenchant" and math.abs(gloves.profit - (307.5 * 0.95 - 40)) < 1e-9, "gloves: disenchanting wins, profit from mats")
check(math.abs(gloves.sellProfit - 102.5) < 1e-9, "gloves: selling profit kept alongside")
local gloveTip = Tip(300)
print("\n--- tooltip: green gloves, Enchanter ---"); for _, l in ipairs(gloveTip) do print(l) end
check(has(gloveTip, "Profit per craft (disenchanted)  ||  2s 52c"), "tooltip: profit says disenchanted")
check(has(gloveTip, "Disenchant it: the mats beat selling by 1s 50c."), "tooltip: disenchant verdict")
check(has(gloveTip, "Disenchants into (average)  ||  3s 8c"), "tooltip: mats total")
check(has(gloveTip, "75%  4-6x Strange Dust  ||  1s 88c") and has(gloveTip, "15%  1-2x Lesser Astral Essence  ||  90c")
    and has(gloveTip, "10%  1x Small Glimmering Shard  ||  30c"), "tooltip: each mat with chance, count and value")
check(has(gloveTip, "AH cut on mats (5%)  ||  -15c"), "tooltip: AH cut on the mats")
check(has(gloveTip, "Don't sell below  ||  3s 8c each") and has(gloveTip, "below that, disenchanting it pays more"),
    "tooltip: floor raised to the mats' value")

-- staff: weapon, mostly essences: 15% dust 37.5c + 75% essence 450c + 10% shard 30c = 517.5c; sells for 10s
local staff = ns.Engine:Evaluate(301)
check(staff.de.mats[1].item == 10998 and staff.de.mats[1].chance == 0.75, "green weapon: essence is the 75% mat")
check(math.abs(staff.de.each - 517.5) < 1e-9 and staff.outlet == "sell", "staff: selling beats disenchanting")
check(has(Tip(301), "Sell it: beats disenchanting by 4s 58c."), "tooltip: sell verdict")

-- cloak: rare, 100% Large Glimmering Shard; no AH price for the cloak itself. Enchanting 30 is enough in Forever.
local cloak = ns.Engine:Evaluate(302)
check(cloak.de.mats[1].item == 11084 and cloak.de.mats[1].chance == 1, "rare 26-30: one large glimmering shard")
check(cloak.outlet == "disenchant" and math.abs(cloak.profit - 910) < 1e-9, "any skill disenchants anything: cloak valued at Enchanting 30")
check(not has(Tip(302), "Needs Enchanting"), "tooltip: no skill requirement")

-- low blue vest: shown as unknown, never counted
RECIPES[304] = { name = "Low Blue Vest", out = 7005, reagents = { { 2589, 4 } }, learned = true }
AHP[7005] = 100
Fire("TRADE_SKILL_SHOW")
local vest = ns.Engine:Evaluate(304)
check(vest.de.unknown and vest.outlet == "sell", "unknown mats: valued by selling only")
check(has(Tip(304), "Disenchants into  ||  not known yet"), "tooltip: unknown mats said plainly")

-- slow boots: item info arrives later
check(ns.Engine:Evaluate(303).de == nil, "item info not loaded yet: no disenchant value")
GEAR[7004].slow = nil
Fire("GET_ITEM_INFO_RECEIVED", 7004)
check(ns.Engine:Evaluate(303).de ~= nil, "item info arrived: disenchant value appears")

-- Profit tab: Disenchant column, the better outlet bright
libtab:SetSelected("ProfitCraft")
check(panel.headers.de.shown, "Enchanter: Profit tab shows the Disenchant column")
local function TabRow(rid) for _, r in ipairs(ns.AuctionHouse.rows) do if r.res and r.res.recipeID == rid then return r end end end
local gloveRow, staffRow = TabRow(300), TabRow(301)
check(gloveRow and strip(gloveRow.cells.de.text) == "3s 8c" and gloveRow.cells.sells.text:find("|cff808080", 1, true),
    "tab: gloves' Disenchant bright, Sells for dimmed")
check(staffRow and staffRow.cells.de.text:find("|cff808080", 1, true) and not staffRow.cells.sells.text:find("|cff808080", 1, true),
    "tab: staff's Sells for bright, Disenchant dimmed")
check(strip(gloveRow.cells.profit.text) == "2s 52c", "tab: gloves' profit is the disenchant profit")

check(strip(TabRow(304).cells.de.text) == "unknown", "tab: unknown mats")
capture(); SlashCmdList.PROFITCRAFT("why"); SlashCmdList.PROFITCRAFT("status"); print = realPrint
check(has(printed, "pay more disenchanted"), "why: counts crafts that pay more disenchanted")
check(has(printed, "Disenchant values: on (Enchanting 30)"), "status: disenchant values on")

-- drop Enchanting: everything goes back
GetProfessions, GetProfessionInfo = professions, professionInfo
ns.Engine:Invalidate(); flush()
check(ns.Engine:Evaluate(300).de == nil and ns.Engine:Evaluate(300).outlet == "sell", "Enchanting gone: no disenchant values")
check(not panel.headers.de.shown, "Enchanting gone: Disenchant column hidden")
check(#ns.db.errors == 0, "no errors recorded in the disenchant tests")


---------------------------------------------------------------------------
-- 2.0: live prices, plays, buying, posting, disenchanting, the Work button
---------------------------------------------------------------------------
-- Every hardware-event or protected call is recorded. Any made outside a simulated press is a violation:
-- the addon must never buy, post, cast or take mail from an event, a timer or a loop.
local hw, restricted, violations = false, {}, 0
local function Restricted(name, ...)
    restricted[#restricted + 1] = { name = name, args = { ... } }
    if not hw then violations = violations + 1; print("VIOLATION: " .. name .. " called outside a press") end
end
local function Press(fn, ...) hw = true; local ok, err = pcall(fn, ...); hw = false; if not ok then error(err, 2) end end
local function Calls(name) local n = 0; for _, c in ipairs(restricted) do if c.name == name then n = n + 1 end end; return n end
local function LastArgs(name) for i = #restricted, 1, -1 do if restricted[i].name == name then return restricted[i].args end end end

function Region:GetFontString() return self.font end
function Region:SetEnabled(v) self.enabled = v end
date = os.date
Enum.AuctionHouseSortOrder = { Price = 0 }
Enum.AuctionHouseFilter = { UncommonQuality = 8, RareQuality = 9 }

-- money, bags, combat, auras, bindings, spells, loot, mail
local money = 1000000 -- 100 gold
function GetMoney() return money end
local bags = {}
local function BagClear() for b = 0, 4 do bags[b] = {} end end
BagClear()
local function BagPut(id, count, extra)
    for b = 0, 4 do for slot = 1, 16 do
        if not bags[b][slot] then bags[b][slot] = { id = id, count = count, q = extra and extra.q, bound = extra and extra.bound }; return b, slot end
    end end
end
local function BagCount(id) local n = 0; for b = 0, 4 do for _, it in pairs(bags[b]) do if it.id == id then n = n + it.count end end end; return n end
local function BagTake(id, count)
    for b = 0, 4 do for slot, it in pairs(bags[b]) do
        if it.id == id then local take = math.min(count, it.count); it.count = it.count - take; count = count - take
            if it.count == 0 then bags[b][slot] = nil end
            if count == 0 then return end end
    end end
end
C_Container = {
    GetContainerNumSlots = function() return 16 end,
    GetContainerNumFreeSlots = function(b) local used = 0; for _ in pairs(bags[b]) do used = used + 1 end; return 16 - used, 0 end,
    GetContainerItemInfo = function(b, slot) local it = bags[b][slot]; if not it then return nil end
        return { itemID = it.id, stackCount = it.count, quality = it.q or 1, isBound = it.bound or false, isLocked = false } end,
    GetItemCooldown = function() return 0, 0, 1 end,
}
C_Item.GetItemCount = function(id, bank) return BagCount(id) + (bank and (BAGS[id] or 0) or 0) end
ItemLocation = { CreateFromBagAndSlot = function(_, b, slot) return { bag = b, slot = slot } end }
local combat = false
function InCombatLockdown() return combat end
local salvagerBuff = false
C_UnitAuras = { GetPlayerAuraBySpellID = function(id) if id == 1283701 and salvagerBuff then return { spellId = id } end end }
local overrides = {}
function SetOverrideBindingClick(_, _, key, name) overrides[key] = name end
function ClearOverrideBindings() wipe(overrides) end
C_Spell = { GetSpellName = function(id) if id == 13262 then return "Disenchant" end end }
local loot = {}
function GetNumLootItems() return #loot end
function GetLootSlotLink(i) return "|Hitem:" .. loot[i][1] .. "::|h" end
function GetLootSlotInfo(i) return 0, "loot", loot[i][2] end
local inbox = {}
function GetInboxNumItems() return #inbox end
function GetInboxHeaderInfo(i) local m = inbox[i]
    return nil, nil, m.sender, m.subject, m.money or 0, m.cod or 0, 30, m.items or 0, false, false, false, m.canReply or false, false end
function GetInboxInvoiceInfo(i) return inbox[i] and inbox[i].invoice end
function AutoLootMailItem(i) Restricted("AutoLootMailItem", i) end
function TakeInboxMoney(i) Restricted("TakeInboxMoney", i) end
function IsShiftKeyDown() return false end
C_TradeSkillUI.CraftRecipe = function(...) Restricted("CraftRecipe", ...) end
C_TradeSkillUI.GetCraftableCount = function() return 0 end

-- TradeSkillMaster's public API
local tsm = {}
TSM_API = { GetCustomPriceValue = function(source, itemString) return tsm[source] and tsm[source][itemString] end }
local function TSM(source, id, value) tsm[source] = tsm[source] or {}; tsm[source]["i:" .. id] = value end

-- the auction house
local AHs = C_AuctionHouse
local commodity, itemResults, sent = {}, {}, {}
local function KS(key) return ("%d:%d:%d"):format(key.itemID, key.itemLevel or 0, key.itemSuffix or 0) end
local throttleReady, cancelled, postConfirm, depositPer = true, 0, false, 1
local browseList, browseFull = {}, true
AHs.IsThrottledMessageSystemReady = function() return throttleReady end
AHs.MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end
AHs.SendSearchQuery = function(key) sent[#sent + 1] = { kind = "search", key = key } end
AHs.SendBrowseQuery = function(q) sent[#sent + 1] = { kind = "browse", q = q } end
AHs.RequestMoreBrowseResults = function() sent[#sent + 1] = { kind = "more" } end
AHs.HasFullBrowseResults = function() return browseFull end
AHs.GetBrowseResults = function() return browseList end
AHs.GetNumCommoditySearchResults = function(id) return #(commodity[id] or {}) end
AHs.GetCommoditySearchResultInfo = function(id, i) local r = commodity[id][i]
    return { itemID = id, unitPrice = r[1], quantity = r[2], numOwnerItems = r[3] or 0, containsOwnerItem = (r[3] or 0) > 0, auctionID = i } end
AHs.HasFullCommoditySearchResults = function() return true end
AHs.GetNumItemSearchResults = function(key) return #(itemResults[KS(key)] or {}) end
AHs.GetItemSearchResultInfo = function(key, i) return itemResults[KS(key)][i] end
AHs.SupportsCopperValues = function() return true end
AHs.PlaceBid = function(...) Restricted("PlaceBid", ...) end
AHs.StartCommoditiesPurchase = function(...) Restricted("StartCommoditiesPurchase", ...) end
AHs.ConfirmCommoditiesPurchase = function(...) Restricted("ConfirmCommoditiesPurchase", ...) end
AHs.CancelCommoditiesPurchase = function() cancelled = cancelled + 1 end
AHs.GetQuoteDurationRemaining = function() return 30 end
AHs.PostCommodity = function(...) Restricted("PostCommodity", ...); return postConfirm end
AHs.PostItem = function(...) Restricted("PostItem", ...); return postConfirm end
AHs.ConfirmPostCommodity = function(...) Restricted("ConfirmPostCommodity", ...) end
AHs.ConfirmPostItem = function(...) Restricted("ConfirmPostItem", ...) end
local commodities = {}
AHs.GetItemCommodityStatus = function(loc) return commodities[bags[loc.bag][loc.slot].id] and 2 or 1 end
AHs.GetAvailablePostCount = function(loc) return BagCount(bags[loc.bag][loc.slot].id) end
AHs.CalculateCommodityDeposit = function(_, _, qty) return depositPer * qty end
AHs.CalculateItemDeposit = function() return 10 end

-- answers the latest query the way the AH would, then lets the scanner send the next one
local function Answer()
    local q = sent[#sent]
    if not q then return end
    if q.kind == "search" then
        local id = q.key.itemID
        if commodity[id] then Fire("COMMODITY_SEARCH_RESULTS_UPDATED", id) else Fire("ITEM_SEARCH_RESULTS_UPDATED", q.key) end
    else
        Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    end
end
local function Drain(max)
    for _ = 1, max or 80 do
        clock = clock + 1.1
        local before = #sent
        ns.Scanner.Pump()
        if #sent == before then return end
        Answer()
    end
end

Fire("AUCTION_HOUSE_SHOW") -- installs the query hooks now that the AH API is complete
Fire("PLAYER_LOGIN")       -- the ledger's mail hooks, now that the mail API exists
check(violations == 0, "setup: nothing restricted called")

---------------------------------------------------------------------------
-- Prices: live > Auctionator > TSM
---------------------------------------------------------------------------
ns.OrderBook.Reset()
TSM("DBMinBuyout", 4444, 180); TSM("DBMarket", 10938, 100)
TSM("DBRegionSaleRate * 1000", 10938, 620); TSM("DBRegionSoldPerDay * 1000", 10938, 3872000)
check(ns.Prices.Get(10938) == 100 and select(2, ns.Prices.Get(10938)) == "auctionator", "prices: Auctionator when nothing live")
AHP[4444] = nil
check(ns.Prices.Get(4444) == 180 and select(2, ns.Prices.Get(4444)) == "tsm", "prices: TSM min buyout when Auctionator has none")
AHP[4444] = 200
check(math.abs(ns.Prices.SaleRate(10938) - 0.62) < 1e-9 and math.abs(ns.Prices.SoldPerDay(10938) - 3872) < 1e-9,
    "prices: TSM sale rate and daily sales unscaled from x1000")

---------------------------------------------------------------------------
-- Order book and scanner
---------------------------------------------------------------------------
commodity[10939] = { { 200, 10 } }                -- Greater Magic Essence: 10 at 2s
commodity[10938] = { { 90, 3 }, { 100, 40 }, { 120, 60 }, { 95, 5, 5 } } -- Lesser: 3 thin at 90c, wall at 1s, 5 of ours at 95c
commodities[10939], commodities[10938] = true, true
local before = #sent
ns.Scanner.Search(10939); ns.Scanner.Search(10938); ns.Scanner.Search(10939)
check(#ns.Scanner and true, "scanner: queued")
ns.Scanner.Pump(); ns.Scanner.Pump()
check(#sent == before + 1, "scanner: one search at a time, duplicates merged")
throttleReady = false; Answer(); clock = clock + 5; ns.Scanner.Pump()
check(#sent == before + 1, "scanner: waits while the game's query throttle isn't ready")
throttleReady = true; clock = clock + 0.5; ns.Scanner.Pump()
check(#sent == before + 2, "scanner: sends once the throttle is ready")
local t0 = clock; ns.Scanner.Search(2589); Answer(); ns.Scanner.Pump()
check(#sent == before + 2 and clock == t0, "scanner: at least a second between searches (60 a minute, the game allows 100)")
Drain()
local lesser = ns.OrderBook.Get(10938)
check(lesser and lesser.min == 90 and lesser.total == 103 and lesser.own == 5, "book: tiers from search results, our own listings set apart")
check(ns.OrderBook.Wall(10938) == 100, "book: wall is the first price with 10% of the listings (thin 90c undercut ignored)")
check(ns.OrderBook.SellPrice(10938) == 99, "book: post a copper under the wall")
local cost, got, top = ns.OrderBook.CostFor(10938, 50, 110)
check(cost == 3 * 90 + 40 * 100 and got == 43 and top == 100, "book: cost of 50 under 1s 10c: takes the 43 that qualify")
cost, got = ns.OrderBook.CostFor(10938, 50, 200, nil, 1000)
check(got == 10 and cost == 3 * 90 + 7 * 100, "book: budget-capped sweep")
check(ns.Prices.Get(10938) == 90 and select(2, ns.Prices.Get(10938)) == "live", "prices: live search beats Auctionator")
AHs.SupportsCopperValues = function() return false end
check(ns.OrderBook.SellPrice(10939) == 100, "book: whole silver when the AH takes no copper (2s wall -> 1s)")
AHs.SupportsCopperValues = function() return true end

---------------------------------------------------------------------------
-- Essences: 3 lesser <-> 1 greater
---------------------------------------------------------------------------
local opps = ns.Essences.Opportunities()
local split = opps[1]
-- buy 10 greater at 2s, sell 30 lesser at 99c: 30 x 99 x 0.95 = 28s 21.5c, minus 2s x 10 and a 30c deposit
check(split and split.kind == "split" and split.sets == 10 and split.cost == 2000, "essences: split 10 greater (all listed)")
check(split and math.abs(split.profit - (30 * 99 * 0.95 - 2000 - 30)) < 1e-6, "essences: profit after cut and the game's deposit")
check(#opps == 1, "essences: combine skipped (3 lesser cost more than a greater sells for)")

---------------------------------------------------------------------------
-- Disenchant statistics and plays (Enchanting 30)
---------------------------------------------------------------------------
GetProfessions = function() return 1, 3, nil, nil, 2, nil end
GetProfessionInfo = function(i) if i == 3 then return "Enchanting", 0, 30, 75, 0, 0, 333 end return professionInfo(i) end
ns.Engine:Invalidate(); flush()
commodity[10940] = { { 50, 200 } }; commodity[10998] = { { 400, 50 } }; commodity[10978] = { { 300, 30 } }
for _, id in ipairs({ 10940, 10998, 10978 }) do commodities[id] = true; ns.Scanner.Search(id) end
Drain()
local st = ns.Disenchant.Stats(4, 2, 22)
-- 75% 4-6 dust at 49c, 15% 1-2 lesser astral at 3s 99c, 10% a shard at 2s 99c
local ev = 0.75 * 5 * 49 + 0.15 * 1.5 * 399 + 0.10 * 299
local sq = 0.75 * (2 / 3 + 25) * 49 ^ 2 + 0.15 * 2.5 * 399 ^ 2 + 0.10 * 299 ^ 2
check(st and math.abs(st.ev - ev) < 1e-6, "stats: expected mats value per green (sell prices)")
check(st and math.abs(st.sd - math.sqrt(sq - ev * ev)) < 1e-6, "stats: standard deviation from each outcome")
check(ns.Disenchant.Bracket(4, 2, 22) == "2:4:21-25" and ns.Disenchant.BracketLabel(4, 2, 22) == "Green armor, item level 21-25",
    "stats: bracket key and label")

GEAR[7011] = { class = 4, q = 2, ilvl = 23 }; GEAR[7012] = { class = 4, q = 2, ilvl = 24 }; GEAR[7013] = { class = 4, q = 2, ilvl = 25 }
ITEMS[7011], ITEMS[7012], ITEMS[7013] = "Green Belt", "Green Boots", "Green Bracers"
local function GearKey(id) return { itemID = id, itemLevel = GEAR[id].ilvl, itemSuffix = 0, battlePetSpeciesID = 0 } end
browseList = {
    { itemKey = GearKey(7001), minPrice = 100, totalQuantity = 1 }, { itemKey = GearKey(7011), minPrice = 110, totalQuantity = 1 },
    { itemKey = GearKey(7012), minPrice = 120, totalQuantity = 1 }, { itemKey = GearKey(7013), minPrice = 130, totalQuantity = 1 },
    { itemKey = GearKey(7002), minPrice = 5000, totalQuantity = 1 }, -- staff: dearer than its mats
}
ns.Scanner.Browse("gear", ns.Scanner.GearQuery()); Drain()
check(sent[#sent].kind == "browse" and sent[#sent].q.filters[1] == 8, "scanner: gear browse (green and blue armor/weapons)")
local result = ns.Plays.Build(true)
local function FindPlay(id) for _, p in ipairs(result.plays) do if p.id == id then return p end end end
local dePlay = FindPlay("de:2:4:21-25:false")
local essPlay = FindPlay("ess:split:10939")
check(essPlay and essPlay.tier == "safe" and essPlay.buys[1].want == 10, "plays: essence split is SAFE (no luck, lesser sells fast)")
check(dePlay and dePlay.tier == "likely" and #dePlay.buys == 4, "plays: 4 greens under the max price, LIKELY")
check(dePlay and dePlay.need <= 4, "plays: batch big enough for 95% (" .. tostring(dePlay and dePlay.need) .. " needed)")
check(dePlay and math.abs(dePlay.profit - (4 * ev * 0.95 - 460)) < 1e-6, "plays: disenchant profit after the AH cut")
check(not FindPlay("de:2:2:21-25:false"), "plays: the dear staff isn't offered")
check(result.plays[1].score >= result.plays[2].score, "plays: ranked by profit per minute x certainty")
print("\n--- plays ---"); for _, p in ipairs(result.plays) do
    print(("%s %s  profit %s  needs %s  %s"):format(p.tier, p.title, strip(ns.Money(p.profit or 0)), strip(ns.Money(p.cost or 0)), p.locked or ""))
    for _, x in ipairs(p.pros) do print("   + " .. x) end; for _, x in ipairs(p.cons) do print("   ! " .. strip(x)) end end

-- a small batch: luck can't even out
browseList = { browseList[1] }
OrderBookResetBrowse = nil
ns.OrderBook.Reset(); for _, id in ipairs({ 10939, 10938, 10940, 10998, 10978 }) do ns.Scanner.Search(id) end
ns.Scanner.Browse("gear", ns.Scanner.GearQuery()); Drain()
result = ns.Plays.Build(true)
check(not FindPlay("de:2:4:21-25:false") and result.hidden >= 1, "plays: one green isn't enough for 95%: RISKY, hidden in Safe mode")
ns.settings.risk = "aggressive"; result = ns.Plays.Build(true)
local small = FindPlay("de:2:4:21-25:false")
check(small and small.tier == "speculative" and has(small.cons, "needed for the luck to even out"), "plays: shown as RISKY in Aggressive mode")
ns.settings.risk = "safe"

-- not enough gold for a safe batch: locked, with the reason
browseList = {
    { itemKey = GearKey(7001), minPrice = 100, totalQuantity = 1 }, { itemKey = GearKey(7011), minPrice = 110, totalQuantity = 1 },
    { itemKey = GearKey(7012), minPrice = 120, totalQuantity = 1 }, { itemKey = GearKey(7013), minPrice = 130, totalQuantity = 1 } }
ns.Scanner.Browse("gear2", ns.Scanner.GearQuery()); Drain()
money = 120 / 0.85 + 1 -- 1s 20c above the reserve
result = ns.Plays.Build(true)
local lockedDE = FindPlay("de:2:4:21-25:false")
check(lockedDE and lockedDE.tier == "locked" and lockedDE.locked:find("chance of not losing", 1, true), "plays: locked when gold can't buy a safe batch")
check(result.plays[#result.plays].tier == "locked", "plays: locked plays listed last")
money = 1000000
result = ns.Plays.Build(true)
dePlay = FindPlay("de:2:4:21-25:false")
essPlay = FindPlay("ess:split:10939")

---------------------------------------------------------------------------
-- Buying: one click = one purchase call, re-checked at the click
---------------------------------------------------------------------------
check(ns.settings.dryRun == true, "buy: dry run is on by default")
ns.Buy.Start(dePlay)
local action = ns.Buy.Next()
check(action and action.kind == "wait" and action.label:find("Checking prices"), "buy: searches the listing first")
Drain()
itemResults[KS(GearKey(7001))] = { { auctionID = 501, buyoutAmount = 100, quantity = 1, containsOwnerItem = false, itemLink = "[Green Gloves]" } }
itemResults[KS(GearKey(7011))] = { { auctionID = 502, buyoutAmount = 110, quantity = 1, containsOwnerItem = false, itemLink = "[Green Belt]" } }
itemResults[KS(GearKey(7012))] = { { auctionID = 503, buyoutAmount = 999, quantity = 1, containsOwnerItem = false, itemLink = "[Green Boots]" } }
itemResults[KS(GearKey(7013))] = { { auctionID = 504, buyoutAmount = 130, quantity = 1, containsOwnerItem = true, itemLink = "[Green Bracers]" } }
ns.Buy.Stop(); ns.Buy.Start(dePlay); ns.Buy.Next(); Drain()
action = ns.Buy.Next()
check(action and action.kind == "item" and action.auction.auctionID == 501, "buy: cheapest listing under the max offered: " .. strip(action and action.label or ""))
Press(ns.Buy.Click, action)
check(Calls("PlaceBid") == 0 and ns.Buy.Message():find("Dry run"), "buy: dry run spends nothing")
check((ns.char.deQueue[7001] or 0) == 0, "buy: dry run queues nothing to disenchant")

ns.settings.dryRun = false
ns.Buy.Stop(); ns.Buy.Start(dePlay); ns.Buy.Next(); Drain()
action = ns.Buy.Next()
itemResults[KS(GearKey(7001))][1].buyoutAmount = 150 -- someone relisted it dearer between the search and the click
Press(ns.Buy.Click, action)
check(Calls("PlaceBid") == 0 and ns.Buy.Message():find("sold or changed"), "buy: listing changed since the search: nothing bought")
itemResults[KS(GearKey(7001))][1].buyoutAmount = 100
ns.Buy.Stop(); ns.Buy.Start(dePlay); ns.Buy.Next(); Drain()
action = ns.Buy.Next()
Press(ns.Buy.Click, action)
check(Calls("PlaceBid") == 1 and LastArgs("PlaceBid")[1] == 501 and LastArgs("PlaceBid")[2] == 100, "buy: one click, one PlaceBid at the listed buyout")
check(ns.Buy.Next().kind == "wait", "buy: next press waits until the AH answers")
Press(ns.Buy.Click, ns.Buy.Next())
check(Calls("PlaceBid") == 1, "buy: pressing again while waiting does nothing")
Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 501)
check(ns.char.deQueue[7001] == 1, "buy: bought green queued for the Disenchant button")
check(ns.db.ledger[#ns.db.ledger].kind == "buy" and ns.db.ledger[#ns.db.ledger].money == 100, "buy: purchase in the ledger")
ns.Buy.Next(); Drain()
action = ns.Buy.Next()
check(action and action.kind == "item" and action.auction.auctionID == 502, "buy: next listing after the purchase")
Press(ns.Buy.Click, action); Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 502)
for _ = 1, 4 do ns.Buy.Next(); Drain() end
action = ns.Buy.Next()
check(action == nil or action.kind ~= "item" or (action.auction.auctionID ~= 503 and action.auction.auctionID ~= 504),
    "buy: never over the max price, never our own listing")
check(Calls("PlaceBid") == 2, "buy: exactly two purchases for two clicks")
ns.Buy.Stop()

-- commodities: quote, then confirm; a dearer quote is cancelled
ns.Buy.Start(essPlay); ns.Buy.Next(); Drain()
action = ns.Buy.Next()
check(action and action.kind == "commodity" and action.qty == 10 and action.total == 2000, "buy: 10 greater essences for 20s")
Press(ns.Buy.Click, action)
check(Calls("StartCommoditiesPurchase") == 1 and LastArgs("StartCommoditiesPurchase")[2] == 10, "buy: first click asks for a quote")
Fire("COMMODITY_PRICE_UPDATED", 260, 2600)
check(cancelled == 1 and ns.Buy.State() == "idle" and ns.Buy.Message():find("went up"), "buy: quote over the maximum is cancelled")
ns.Buy.Next(); Drain(); action = ns.Buy.Next()
Press(ns.Buy.Click, action)
Fire("COMMODITY_PRICE_UPDATED", 200, 2000)
action = ns.Buy.Next()
check(action.kind == "confirm" and Calls("ConfirmCommoditiesPurchase") == 0, "buy: good quote waits for a second click")
Press(ns.Buy.Click, action)
check(Calls("ConfirmCommoditiesPurchase") == 1, "buy: second click confirms")
check(ns.Buy.Stop() == false and ns.Buy.Active(), "buy: can't stop a play while its purchase is in flight")
Fire("COMMODITY_PURCHASE_SUCCEEDED")
check(ns.char.convert[10939] == 10 and ns.char.toSell[10938], "buy: 10 splits queued and the lesser essences marked for posting")
ns.Buy.Stop()

-- a quote whose total grew is refused even if the average is under the maximum
commodity[10939] = { { 200, 20 } }
ns.Buy.Start(essPlay); ns.Buy.Next(); Drain(); action = ns.Buy.Next()
Press(ns.Buy.Click, action)
Fire("COMMODITY_PRICE_UPDATED", 199, 2010) -- 1c more than planned in total: some units are dearer
check(ns.Buy.State() == "idle" and Calls("ConfirmCommoditiesPurchase") == 1, "buy: quote above the planned total is cancelled")
-- dry run switched on while a quote waits: the confirming press buys nothing
ns.Buy.Next(); Drain(); action = ns.Buy.Next()
Press(ns.Buy.Click, action)
Fire("COMMODITY_PRICE_UPDATED", 200, 2000)
ns.settings.dryRun = true
Press(ns.Buy.Click, ns.Buy.Next())
check(Calls("ConfirmCommoditiesPurchase") == 1 and ns.Buy.Message():find("Dry run"), "buy: dry run turned on mid-quote: nothing bought")
ns.settings.dryRun = false
-- a purchase the AH answers late is still counted
ns.Buy.Next(); Drain(); action = ns.Buy.Next()
Press(ns.Buy.Click, action); Fire("COMMODITY_PRICE_UPDATED", 200, 2000); Press(ns.Buy.Click, ns.Buy.Next())
local spentBefore = ns.Ledger.SessionSpent()
clock = clock + 40; ns.Buy.Tick()
check(ns.Buy.State() == "idle", "buy: gives up waiting after 30s")
Fire("COMMODITY_PURCHASE_SUCCEEDED")
check(ns.Ledger.SessionSpent() == spentBefore + 2000, "buy: late success still counted against the session cap")
ns.Buy.Stop()
commodity[10939] = { { 200, 10 } }
check(violations == 0, "buy: no purchase call outside a press")

-- budget: never past the session cap
ns.settings.sessionCap = 2100 -- 21s, of which 23s 10c already spent this session
check(ns.Profile.Budget() == 0, "budget: session cap reached, nothing more to spend")
ns.settings.sessionCap = 500000

---------------------------------------------------------------------------
-- The Work button: mail, convert, disenchant (with the Salvager lock)
---------------------------------------------------------------------------
local work = ns.Work.button
local function WorkPress() Press(work.scripts.PreClick, work, "LeftButton"); clock = clock + 1 end
check(work and work.attrs and work.attrs.useOnKeyDown == false, "work: acts on release only (one press = one action)")
inbox = { { sender = "Alliance Auction House", subject = "Auction won: Greater Magic Essence", items = 1, invoice = "buyer" },
    { sender = "Friend", subject = "hi", items = 1, canReply = true } }
Fire("MAIL_SHOW")
local step = ns.Work.NextStep()
check(step and step.kind == "mail" and step.label:find("1 left"), "work: takes auction house mail only")
WorkPress()
check(Calls("AutoLootMailItem") == 1 and LastArgs("AutoLootMailItem")[1] == 1, "work: one press takes one mail")
WorkPress()
check(Calls("AutoLootMailItem") == 1, "work: no second take until the inbox updates")
Fire("MAIL_INBOX_UPDATE")
inbox = {}; Fire("MAIL_CLOSED")
BagPut(10939, 10)
step = ns.Work.NextStep()
check(step.kind == "convert" and step.label:find("Split"), "work: split the bought greater essences")
WorkPress()
check(work.attrs.type1 == "macro" and work.attrs.macrotext1 == "/use item:10939", "work: the press uses one essence")
local convertsBefore = ns.char.convert[10939]
BagTake(10939, 1); BagPut(10938, 3); Fire("BAG_UPDATE_DELAYED")
check(ns.char.convert[10939] == convertsBefore - 1, "work: one conversion counted")
ns.char.convert[10939] = nil; BagTake(10939, 9)

local glovesBag, glovesSlot = BagPut(7001, 1, { q = 2 }); BagPut(7011, 1, { q = 2 }); BagPut(7012, 1, { q = 2, bound = true })
ns.char.deQueue[7012] = 1
step = ns.Work.NextStep()
check(step.kind == "disenchant" and step.itemID == 7001, "work: disenchants a bought green")
WorkPress()
check(work.attrs.macrotext1 == ("/cast Disenchant\n/use %d %d"):format(glovesBag, glovesSlot), "work: /cast Disenchant on that bag slot")
Press(work.scripts.PostClick, work)
check(work.attrs.macrotext1 == nil and work.attrs.type1 == nil, "work: cleared after the press, so nothing stale can fire later")
local preDE = work.attrs.macrotext1
WorkPress() -- still casting: nothing new
Fire("UNIT_SPELLCAST_START", "player", "guid", 13262)
WorkPress()
check(work.attrs.type1 == nil, "work: presses during the cast do nothing")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 13262)
loot = { { 10940, 5 } }; Fire("LOOT_READY"); loot = {}
BagTake(7001, 1); BagPut(10940, 5)
check(ns.char.deQueue[7001] == nil and ns.char.toSell[10940], "work: disenchanted item off the list, its dust marked for posting")
check(ns.Telemetry.Count("2:4:21-25", false) == 1, "telemetry: result recorded without the Salvager")
ns.char.salvager[7011] = true
clock = clock + 5
step = ns.Work.NextStep()
check(step.kind == "locked" and step.warn and step.label:find("Salvager buff missing"), "work: Salvager buys wait for the buff")
salvagerBuff = true
step = ns.Work.NextStep()
check(step.kind == "disenchant" and step.itemID == 7011, "work: buff on: disenchants")
check(not (step.itemID == 7012), "work: never soulbound gear")
WorkPress(); Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 13262); loot = { { 10940, 6 } }; Fire("LOOT_READY"); loot = {}
check(ns.Telemetry.Count("2:4:21-25", true) == 1, "telemetry: buffed result kept apart")
salvagerBuff = false
Press(work.scripts.PostClick, work) -- the game runs PostClick after every press
combat = true
local beforeCombat = #restricted
WorkPress()
check(work.attrs.type1 == nil and #restricted == beforeCombat and ns.Work.NextStep().label == "In combat", "work: nothing in combat")
combat = false

-- scroll-down only when you ask for it, only over the button
work.scripts.OnEnter(work)
check(next(overrides) == nil, "wheel: off by default, zoom untouched")
ns.settings.wheel = true
work.scripts.OnEnter(work)
check(overrides.MOUSEWHEELDOWN == "ProfitCraftWorkKey" and overrides.MOUSEWHEELUP == nil, "wheel: scroll-down over the button presses its key twin")
local keyTwin = ns.Work.keyButton
check(keyTwin and keyTwin.attrs.useOnKeyDown == true and keyTwin.scripts.PreClick == work.scripts.PreClick,
    "wheel/keys: the twin acts on key-down with the same press logic")
combat = true; work.scripts.OnLeave(work); combat = false
check(overrides.MOUSEWHEELDOWN ~= nil, "wheel: can't be cleared in combat...")
Fire("PLAYER_REGEN_ENABLED")
check(next(overrides) == nil, "wheel: ...so it's cleared as soon as combat ends")
work.scripts.OnEnter(work)
work.scripts.OnLeave(work)
check(next(overrides) == nil, "wheel: leaving the button gives zoom back")
combat = true; work.scripts.OnEnter(work); combat = false
check(next(overrides) == nil, "wheel: never set in combat")
ns.settings.wheel = false

---------------------------------------------------------------------------
-- Telemetry: measured rates and the Salvager bonus
---------------------------------------------------------------------------
check(select(3, ns.Telemetry.SalvagerMultiplier()) == "none" and ns.Telemetry.SalvagerMultiplier() == 1, "salvager: no bonus counted until measured")
ns.settings.salvagerBonus = 20
check(math.abs(ns.Telemetry.SalvagerMultiplier() - 1.2) < 1e-9, "salvager: your setting until measured")
for _ = 1, 49 do ns.Telemetry.Record("2:4:21-25", true, { [10940] = 6 }) end
local mult, n, source = ns.Telemetry.SalvagerMultiplier()
-- table: 75% x 5 dust + 15% x 1.5 essences = 3.975 per disenchant; measured 6
check(source == "measured" and n == 50 and math.abs(mult - 6 / 3.975) < 1e-9, ("salvager: measured x%.2f from 50 buffed disenchants"):format(mult))
ns.settings.salvagerBonus = 0
for _ = 1, 40 do ns.Telemetry.Record("3:0:5-20", false, { [10940] = 2, [10978] = 1 }) end
local vest = ns.Disenchant.Evaluate(7005)
check(not vest.unknown and vest.measured == 40 and vest.mats[1].avg == 2, "telemetry: 40 results fill in Forever's unknown blue bracket")

---------------------------------------------------------------------------
-- Posting: at the wall, never under the floor, one click each
---------------------------------------------------------------------------
BagClear(); BagPut(10938, 30); ns.char.toSell = { [10938] = true }
ns.OrderBook.Reset(); ns.Scanner.Search(10938); Drain()
local post = ns.Post.Next()
check(post and post.kind == "post" and post.qty == 30 and post.price == 99 and post.deposit == 30, "post: 30 lesser at 99c (deposit 30c)")
Press(ns.Post.Click, post)
check(Calls("PostCommodity") == 1 and LastArgs("PostCommodity")[3] == 30 and LastArgs("PostCommodity")[4] == 99, "post: one click, one PostCommodity")
Fire("AUCTION_HOUSE_AUCTION_CREATED", 9001)
check(ns.db.ledger[#ns.db.ledger].kind == "post", "post: in the ledger")
TSM("DBMarket", 10938, 1000) -- usually 10s: 99c is under the 60% floor
ns.OrderBook.Reset(); ns.Scanner.Search(10938); Drain()
post = ns.Post.Next()
check(post == nil and ns.Post.Held()[10938] and ns.Post.Held()[10938]:find("floor"), "post: held when the going price is under the floor")
TSM("DBMarket", 10938, 100)
Fire("AUCTION_HOUSE_CLOSED"); Fire("AUCTION_HOUSE_SHOW")
postConfirm = true
ns.Scanner.Search(10938); Drain()
post = ns.Post.Next()
Press(ns.Post.Click, post)
local confirm = ns.Post.Next()
check(confirm.kind == "confirmPost" and Calls("ConfirmPostCommodity") == 0, "post: the AH asked for confirmation: waits for the next click")
Press(ns.Post.Click, confirm)
check(Calls("ConfirmPostCommodity") == 1, "post: second click confirms")
postConfirm = false
Fire("AUCTION_HOUSE_AUCTION_CREATED", 9002)

---------------------------------------------------------------------------
-- Ledger, clock, Plays tab, slash
---------------------------------------------------------------------------
inbox = { { sender = "Alliance Auction House", subject = "Auction successful: Lesser Magic Essence", money = 2800, invoice = "seller" } }
Press(TakeInboxMoney, 1)
local sum = ns.Ledger.Summary(7)
check(sum.sold == 2800 and sum.sales == 1 and sum.buys == 22 and sum.spent == ns.Ledger.SessionSpent() and sum.spent == 4210,
    "ledger: bought 22 for 42s 10c, sold 28s")
inbox = {}

local day, base = 86400, os.time({ year = 2026, month = 11, day = 9, hour = 0 }) -- a week with no clock change
for d = 0, 7 do for h = 0, 21, 3 do ns.Clock.Record(10939, (h >= 18) and 300 or 200, base + d * day + h * 3600) end end
local phase = ns.Clock.Phase(10939, 150)
check(phase and phase.tag == "low" and (phase.sellAt:find("18%-21") or phase.sellAt:find("21%-24")),
    "clock: a week of prices says now is cheap and evenings sell highest (" .. tostring(phase and phase.sellAt) .. ")")

BagClear()
ns.OrderBook.Reset()
for _, id in ipairs({ 10939, 10938, 10940, 10998, 10978 }) do ns.Scanner.Search(id) end
browseList = { { itemKey = GearKey(7001), minPrice = 100, totalQuantity = 1 }, { itemKey = GearKey(7011), minPrice = 110, totalQuantity = 1 },
    { itemKey = GearKey(7012), minPrice = 120, totalQuantity = 1 }, { itemKey = GearKey(7013), minPrice = 130, totalQuantity = 1 } }
ns.Scanner.Browse("gear", ns.Scanner.GearQuery()); Drain()
flush()
check(ns.PlaysTab.tabCreated and libtab.internalState.usedIDs.ProfitCraftPlays.text == "Plays", "Plays tab created through LibAHTab")
libtab:SetSelected("ProfitCraftPlays")
local tab = ns.PlaysTab.panel
check(tab.shown and ns.PlaysTab.rows[1].play ~= nil, "Plays tab: ranked plays listed")
print("\n--- Plays tab ---"); for i, row in ipairs(ns.PlaysTab.rows) do if row.play then print(i .. ". " .. strip(row.tier.text) .. "  " .. row.title.text .. "  " .. strip(row.info.text)) end end
print(strip(tab.detail.body.text or ""))
check(tab.detail.start.text == "Start this play", "Plays tab: start button (dry run off)")
local scanAction = ns.PlaysTab.CurrentAction()
check(scanAction.kind == "scan", "Plays tab: step button offers a scan with nothing started")
ns.PlaysTab.Select("ess:split:10939")
ns.settings.dryRun = true
tab.detail.start.scripts.OnClick(tab.detail.start)
ns.PlaysTab.Refresh()
check(ns.Buy.Active() and ns.Buy.Active().id == "ess:split:10939", "Plays tab: Start runs the selected play")
Drain()
local stepAction = ns.PlaysTab.CurrentAction()
check(stepAction.kind == "commodity", "Plays tab: step button offers the purchase: " .. strip(stepAction.label))
local startsBefore = Calls("StartCommoditiesPurchase")
ns.PlaysTab.Refresh()
local shown = tab.action.text
money = 1177 -- the budget drops to 10s without the tab repainting: the offer is now 5, not 10
local msgBefore = ns.Buy.Message()
Press(ns.PlaysTab.Press, "LeftButton")
check(ns.Buy.Message() == msgBefore and tab.action.text ~= shown and tab.action.text:find("Buy 5", 1, true),
    "Plays tab: a press only does what the button showed (offer changed: it repainted instead)")
money = 1000000; ns.PlaysTab.Refresh()
combat = true; Press(ns.PlaysTab.Press, "LeftButton"); combat = false
check(ns.Buy.Message() == msgBefore, "Plays tab: nothing in combat")
check(tab.key and tab.key.name == "ProfitCraftAHKey", "Plays tab: key twin for bindings and the wheel")
Press(tab.key.scripts.OnClick, tab.key)
check(Calls("StartCommoditiesPurchase") == startsBefore and (ns.Buy.Message() or ""):find("Dry run"), "Plays tab: key press (dry run) rehearses")
local ahButton = tab.action
ns.settings.wheel = true
ahButton.scripts.OnEnter(ahButton)
check(overrides.MOUSEWHEELDOWN == "ProfitCraftAHKey", "wheel: scroll-down over the AH step button presses its key twin")
ahButton.scripts.OnLeave(ahButton)
check(next(overrides) == nil, "wheel: zoom back when leaving it")
ns.settings.wheel = false
ns.Buy.Stop()

-- crafting for disenchanting: the crafted items join the Disenchant button's list
ns.char.craft = { recipeID = 300, count = 2, disenchant = true }
ProfessionsFrame.shown = true
C_TradeSkillUI.GetCraftableCount = function(rid) return rid == 300 and 5 or 0 end
local craftStep = ns.Work.NextStep()
check(craftStep and craftStep.kind == "craft" and craftStep.count == 2, "work: craft the play's 2 gloves")
local queuedBefore = ns.char.deQueue[7001] or 0
WorkPress()
check(Calls("CraftRecipe") == 1 and LastArgs("CraftRecipe")[1] == 300 and LastArgs("CraftRecipe")[2] == 2, "work: one press, one craft call")
WorkPress()
check(Calls("CraftRecipe") == 1 and ns.Work.NextStep().kind == "wait", "work: pressing again while crafting does nothing")
check((ns.char.deQueue[7001] or 0) == queuedBefore, "work: nothing counted before a craft finishes")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 300); Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 300)
check(ns.char.deQueue[7001] == queuedBefore + 2 and ns.char.craft == nil, "work: each finished craft queued for disenchanting")
C_TradeSkillUI.GetCraftableCount = function() return 0 end

capture(); SlashCmdList.PROFITCRAFT("plays"); SlashCmdList.PROFITCRAFT("ledger"); SlashCmdList.PROFITCRAFT("de")
SlashCmdList.PROFITCRAFT("dryrun"); SlashCmdList.PROFITCRAFT("dryrun"); SlashCmdList.PROFITCRAFT("selling"); SlashCmdList.PROFITCRAFT("status")
SlashCmdList.PROFITCRAFT("wheel"); local wheelOn = ns.settings.wheel; SlashCmdList.PROFITCRAFT("wheel")
print = realPrint
print("\n--- /craftprofit plays, ledger, de, status ---"); for _, l in ipairs(printed) do print(strip(l)) end
check(has(printed, "Top plays:") and has(printed, "Last 7 days") and has(printed, "Arcane Salvager: x1.51"), "slash: plays, ledger, de")
check(has(printed, "TradeSkillMaster data: found"), "status: TSM found")
check(wheelOn == true and ns.settings.wheel == false, "/craftprofit wheel toggles scroll-down")
check(ns.Options.tradingPage ~= nil, "options: Buying & selling page built")
check(violations == 0, "no purchase, post, cast or mail call ever ran outside a press")
check(#ns.db.errors == 0, "no errors recorded in the trading tests" .. (ns.db.errors[1] and (": " .. ns.db.errors[1].where .. " " .. ns.db.errors[1].err) or ""))

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
