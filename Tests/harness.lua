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

function GetTime() return 100 end
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
function CreateFrame(kind) return NewRegion(kind) end
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

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
