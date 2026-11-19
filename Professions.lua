-- ProfitCraft: glows + tooltips on the profession window's recipe list.
local _, ns = ...

local Professions = { hooked = false }
ns.Professions = Professions

local ROW_ATLAS = "Professions_Recipe_Hover" -- the list's own hover highlight, if this client has it
local rowHooked = setmetatable({}, { __mode = "k" })
local hookedBox, frameHooked

local function ScrollBox()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    return page and page.RecipeList and page.RecipeList.ScrollBox
end

local function RowRecipeInfo(row)
    if not row.GetElementData then return nil end
    local ok, node = pcall(row.GetElementData, row)
    if not ok or type(node) ~= "table" then return nil end
    local data = (node.GetData and node:GetData()) or node.data or node
    return type(data) == "table" and data.recipeInfo or nil
end

local function CurrentRanking()
    if ns.Data.IsForeign() then return nil end
    local profID = ns.Data.CurrentProfession()
    return profID and ns.Engine:ProfessionRanking(profID) or nil
end

-- Our definition of a row's recipe; reads it straight from the game if the scan hasn't caught it yet.
local function EnsureRecipe(info)
    if ns.db.recipes[info.recipeID] then return true end
    local def = ns.Data.ReadSchematic(info.recipeID)
    if not (def and def.out) then return false end
    def.name = info.name or def.name
    def.prof = ns.Data.CurrentProfession()
    ns.db.recipes[info.recipeID] = def
    ns.Data.MarkIndexDirty()
    return true
end

local function ShowTooltip(row)
    local info = RowRecipeInfo(row)
    if not info or not info.recipeID or not ns.IsReady() or not EnsureRecipe(info) then return end
    local ok, ranking = ns.Safe("profession glows", CurrentRanking)
    if not ok then ranking = nil end
    ns.Display.ShowForRow(row, info.name, info.recipeID, {
        rank = ranking and ranking.ranks[info.recipeID],
        relaxed = ranking and ranking.relaxed,
        step = ranking and ranking.steps[info.recipeID],
        notLearned = info.learned == false,
    })
end

local function OnEnter(row) ns.Safe("profession tooltip", ShowTooltip, row) end

local function OnLeave(row)
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function HookRow(row)
    if rowHooked[row] then return end
    rowHooked[row] = true
    row:HookScript("OnEnter", OnEnter)
    row:HookScript("OnLeave", OnLeave)
end

function Professions.Paint()
    local box = ScrollBox()
    if not box or not box:IsVisible() or not ns.IsReady() then return end
    -- Hover first: tooltips keep working even if the ranking below fails.
    box:ForEachFrame(HookRow)
    local ok, ranking = ns.Safe("profession glows", CurrentRanking)
    if not ok then ranking = nil end
    local rows, glowing = 0, 0
    box:ForEachFrame(function(row)
        local info = RowRecipeInfo(row)
        local rank = info and info.recipeID and ranking and ranking.ranks[info.recipeID] or nil
        if info then rows = rows + 1 end
        if rank then glowing = glowing + 1 end
        ns.Display.SetGlow(row, rank, ROW_ATLAS)
    end)
    ns.db.diag.professions = {
        prof = ns.Data.CurrentProfession(), foreign = ns.Data.IsForeign(), rows = rows, glowing = glowing,
        known = ranking and ranking.known, profitable = ranking and #ranking.list, relaxed = ranking and ranking.relaxed,
    }
end

function Professions.TryHook()
    local box = ScrollBox()
    if not box or box == hookedBox or type(box.Update) ~= "function" then return end
    hookedBox = box
    Professions.hooked = true
    hooksecurefunc(box, "Update", Professions.Paint)
    if not frameHooked then
        frameHooked = true
        ProfessionsFrame:HookScript("OnShow", function()
            ns.Data.ScheduleScan()
            C_Timer.After(0, Professions.Paint)
        end)
    end
    Professions.Paint()
end

local function HookAndPaint()
    Professions.TryHook()
    Professions.Paint()
end

ns.OnDataChanged(Professions.Paint)
ns.On("ADDON_LOADED", Professions.TryHook)
ns.On("PLAYER_LOGIN", Professions.TryHook)
ns.On("TRADE_SKILL_SHOW", function() C_Timer.After(0, HookAndPaint) end)
ns.On("TRADE_SKILL_LIST_UPDATE", function() ns.Debounce("professions-paint", 0.1, HookAndPaint) end)
