-- ProfitCraft: gold/silver/bronze in What's Training's recipe list (the tab it adds to the side of the
-- profession window), so you can see which recipe to go train or buy first. Hovering a recipe there
-- adds the usual breakdown plus what it costs to learn and how many crafts pay that back.
--
-- Uses only What's Training's frames (it has no public API): WhatsTrainingCraftingRecipeList and its
-- scrollBox, whose recipe rows carry `row.data = { recipe = { spell, creates, cost, teach }, category,
-- professionID, profession }`. Everything is looked up defensively so a What's Training update can only
-- turn this feature off, never break the rest of ProfitCraft.
local _, ns = ...

local WT = { hooked = false }
ns.WhatsTraining = WT

local AVAILABLE = 1 -- What's Training's "Available now" section (its RecipeCategory.AVAILABLE)
local ROW_ATLAS = "Professions_Recipe_Hover"

local rowHooked = setmetatable({}, { __mode = "k" })
local ranks, resolved = {}, {} -- [spellID] = 1/2/3, [spellID] = our recipeID
local relaxed, dirty = false, true
local hookedBox

local function View() return _G.WhatsTrainingCraftingRecipeList end

local function ScrollBox()
    local view = View()
    return (view and view.scrollBox) or _G.WhatsTrainingCraftingScrollBox
end

-- What's Training's data for a recipe row (nil for section and profession headers).
local function RowData(row)
    local data = row.data
    if type(data) == "table" and type(data.recipe) == "table" and data.recipe.spell then return data end
end

-- Our recipe for a What's Training entry. Recipes the profession window never listed (vendor and drop
-- patterns) are read straight from the game, like the trainer does.
local function Resolve(data)
    local spell = data.recipe.spell
    if resolved[spell] then return resolved[spell] end
    local rid
    if ns.db.recipes[spell] then
        rid = spell -- seen before (one that makes no item, like an enchant, says so in its tooltip)
    else
        local def = ns.Data.ReadSchematic(spell)
        if def and (def.out or def.name) then -- an unknown spell comes back as an empty schematic
            def.prof = data.professionID
            ns.db.recipes[spell] = def
            ns.Data.MarkIndexDirty()
            rid = spell
        elseif data.recipe.creates then
            local list = ns.Data.RecipesByOutput(data.recipe.creates)
            rid = list and list[1]
        end
    end
    resolved[spell] = rid
    return rid
end

-- The "Available now" entries as currently filtered; falls back to every entry What's Training has.
local function AvailableEntries(view)
    local ok, items = pcall(function()
        return view.categoryNodes[AVAILABLE]:GetData().items
    end)
    if ok and type(items) == "table" then return items end
    local entries = {}
    for _, node in ipairs(view.recipeNodes or {}) do
        local data = node.GetData and node:GetData()
        if data and data.category == AVAILABLE then entries[#entries + 1] = data end
    end
    return entries
end

local function Recompute()
    dirty = false
    relaxed = false
    wipe(ranks)
    wipe(resolved)
    local view = View()
    if not view or not ns.IsReady() then return end
    local candidates, spellOf = {}, {}
    for _, data in ipairs(AvailableEntries(view)) do
        if type(data) == "table" and type(data.recipe) == "table" and data.recipe.spell then
            local rid = Resolve(data)
            if rid and not ns.IsKnown(rid) and not spellOf[rid] then
                spellOf[rid] = data.recipe.spell
                candidates[#candidates + 1] = rid
            end
        end
    end
    local byRecipe, _, isRelaxed = ns.Engine:GlowRanks(candidates)
    for rid, rank in pairs(byRecipe) do ranks[spellOf[rid]] = rank end
    relaxed = isRelaxed
    ns.db.diag.whatsTraining = { available = #candidates, relaxed = relaxed }
end

local function AppendLines(tt, data)
    local rid = Resolve(data)
    tt:AddLine(" ")
    if not rid then
        tt:AddLine("|cffffd100ProfitCraft|r")
        tt:AddLine(("Open your %s window once so I can read this recipe's reagents."):format(data.profession or "profession"),
            0.6, 0.6, 0.6, true)
        tt:Show()
        return
    end
    local recipe, rank = data.recipe, ranks[data.recipe.spell]
    local style = rank and ns.Display.RANKS[rank]
    local title = "|cffffd100ProfitCraft|r"
    if style then title = title .. "   |c" .. style.hex .. style.label .. " to learn now|r" end
    tt:AddLine(title)
    ns.Display.AddRecipeLines(tt, rid, {
        header = false,
        rank = rank,
        relaxed = rank and relaxed,
        trainCost = recipe.cost,
        recipeCost = not recipe.cost and recipe.teach and ns.AHPrice(recipe.teach) or nil,
    })
    tt:Show()
end

-- What's Training's rows show the recipe as a spell tooltip. Adding our lines from a spell-tooltip
-- post-call (registered after What's Training's own) keeps them below its source and cost lines, and
-- they come back when the game rebuilds the tooltip once the spell's data loads.
local function OnSpellTooltip(tt, tooltipData)
    if tt ~= GameTooltip or not ns.IsReady() then return end
    local owner = tt.GetOwner and tt:GetOwner()
    local data = owner and RowData(owner)
    local box = ScrollBox()
    if not data or not box or not box:IsVisible() then return end
    if tooltipData and tooltipData.id and tooltipData.id ~= data.recipe.spell then return end
    AppendLines(tt, data)
end

-- Fallback for a client without TooltipDataProcessor: append after the row's own OnEnter.
local function OnEnter(row)
    local data = RowData(row)
    if data and ns.IsReady() and GameTooltip:IsOwned(row) then AppendLines(GameTooltip, data) end
end

local usePostCall = false

function WT.Paint()
    local box = ScrollBox()
    if not box or not box:IsVisible() or not ns.IsReady() then return end
    if dirty then ns.Safe("What's Training glows", Recompute) end
    box:ForEachFrame(function(row)
        local data = RowData(row)
        if data and not usePostCall and not rowHooked[row] then
            rowHooked[row] = true
            row:HookScript("OnEnter", function(self) ns.Safe("What's Training tooltip", OnEnter, self) end)
        end
        ns.Display.SetGlow(row, data and ranks[data.recipe.spell] or nil, ROW_ATLAS)
    end)
end

local function Repaint()
    dirty = true
    WT.Paint()
end

function WT.TryHook()
    local box = ScrollBox()
    if not box or box == hookedBox or type(box.Update) ~= "function" then return end
    hookedBox = box
    WT.hooked = true
    -- What's Training registered its spell-tooltip post-call when it built this list, so ours runs after it.
    if not usePostCall and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
        usePostCall = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tt, tooltipData)
            ns.Safe("What's Training tooltip", OnSpellTooltip, tt, tooltipData)
        end)
    end
    hooksecurefunc(box, "Update", WT.Paint)
    local view = View()
    if view then
        -- Filter runs on every search, filter, ignore and data change
        if type(view.Filter) == "function" then hooksecurefunc(view, "Filter", Repaint) end
        view:HookScript("OnShow", function() C_Timer.After(0, Repaint) end)
    end
    Repaint()
end

function WT.Loaded()
    return (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("WhatsTraining"))
        or (IsAddOnLoaded and IsAddOnLoaded("WhatsTraining")) or false
end

ns.OnDataChanged(Repaint)
-- What's Training builds its list when the profession window's code loads; look right after.
ns.On("ADDON_LOADED", function() C_Timer.After(0, WT.TryHook) end)
ns.On("PLAYER_LOGIN", WT.TryHook)
ns.On("TRADE_SKILL_SHOW", function() C_Timer.After(0, WT.TryHook) end)
