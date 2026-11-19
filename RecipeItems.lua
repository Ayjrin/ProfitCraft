-- ProfitCraft: recipe items (patterns, plans, formulas...): which recipe they teach, whether you can
-- learn them now, and the buy/sell breakdown on their tooltip wherever you hover them.
local _, ns = ...

local RecipeItems = {}
ns.RecipeItems = RecipeItems

local RECIPE_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
local BOOK_SUBCLASS = 0 -- generic books, not profession recipes

local recipeCache = {} -- [itemID] = recipeID or false
local requirementCache = {} -- [itemID] = { prof, level } or false
local handled = setmetatable({}, { __mode = "k" })

ns.OnDataChanged(function() wipe(recipeCache) end)

function RecipeItems.IsRecipeItem(itemID)
    local _, _, _, _, _, classID, subclassID = ns.ItemInstant(itemID)
    return classID == RECIPE_CLASS and subclassID ~= BOOK_SUBCLASS
end

-- "Pattern: Red Linen Robe" -> "Red Linen Robe"
local function StripPrefix(name)
    return name and (name:match("^[^:]+:%s*(.+)$") or name)
end

-- Recipe taught by a recipe item, or nil if it isn't one / we haven't seen that recipe.
function RecipeItems.Lookup(itemID)
    if not ns.IsReady() or not itemID or not RecipeItems.IsRecipeItem(itemID) then return nil end
    local cached = recipeCache[itemID]
    if cached ~= nil then return cached or nil end
    local recipes = ns.db.recipes
    local rid

    if C_Item and C_Item.GetItemSpell then
        local _, spellID = C_Item.GetItemSpell(itemID)
        if spellID and recipes[spellID] then rid = spellID end
    end

    local nameOf = C_Item and C_Item.GetItemNameByID or GetItemInfo
    local itemName = nameOf(itemID)
    if not itemName then return nil end -- not loaded yet; try again next time
    local taught = StripPrefix(itemName)

    if not rid then rid = ns.Data.RecipeByName(taught) end
    if not rid then
        -- recipe names can differ from the item they make; match the product's name instead
        for id, r in pairs(recipes) do
            if r.out and nameOf(r.out) == taught then rid = id; break end
        end
    end

    recipeCache[itemID] = rid or false
    return rid
end

---------------------------------------------------------------------------
-- Skill requirement ("Requires Tailoring (75)") read from the item's tooltip
---------------------------------------------------------------------------
local function FormatToPattern(fmt)
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%d%$s", "(.+)"):gsub("%%%d%$d", "(%%d+)") -- positional forms (%1$s) used by some locales
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end
local REQUIRES = FormatToPattern(ITEM_MIN_SKILL or "Requires %s (%d)")

function RecipeItems.Requirement(itemID)
    local cached = requirementCache[itemID]
    if cached ~= nil then return cached or nil end
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or type(data) ~= "table" or not data.lines then return nil end
    for _, line in ipairs(data.lines) do
        local prof, level = (line.leftText or ""):match(REQUIRES)
        if prof and tonumber(level) then
            requirementCache[itemID] = { prof = prof, level = tonumber(level) }
            return requirementCache[itemID]
        end
    end
    if #data.lines > 1 then requirementCache[itemID] = false end -- loaded, just no requirement line
    return nil
end

-- Your current rank per profession, by name and by skill line.
function RecipeItems.ProfessionRanks()
    local ranks = {}
    if not (GetProfessions and GetProfessionInfo) then return ranks end
    local list = { GetProfessions() }
    for i = 1, 6 do
        local index = list[i]
        if index then
            local name, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
            if name then ranks[name] = rank end
            if skillLine then ranks[skillLine] = rank end
        end
    end
    return ranks
end

-- "known", "other" (not your profession), "high" (skill too low, with need), or "learnable".
function RecipeItems.LearnStatus(itemID, rid, ranks)
    if ns.IsKnown(rid) then return "known" end
    ranks = ranks or RecipeItems.ProfessionRanks()
    local req = RecipeItems.Requirement(itemID)
    if req then
        local rank = ranks[req.prof]
        if not rank then return "other" end
        if rank < req.level then return "high", { prof = req.prof, level = req.level, rank = rank } end
        return "learnable"
    end
    local r = ns.db.recipes[rid]
    if r and r.prof and next(ns.char.profs) and not ns.char.profs[r.prof] then return "other" end
    return "learnable"
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function OnItemTooltip(tt, itemID)
    if not ns.IsReady() or not itemID then return end
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
    if handled[tt] == itemID then return end
    if not RecipeItems.IsRecipeItem(itemID) then return end
    handled[tt] = itemID

    local rid = RecipeItems.Lookup(itemID)
    if not rid then
        tt:AddLine(" ")
        tt:AddLine("|cffffd100ProfitCraft|r")
        tt:AddLine("I haven't seen this recipe yet. Open its profession window once and hover again.",
            0.6, 0.6, 0.6, true)
        tt:Show()
        return
    end

    local r = ns.db.recipes[rid]
    local status, need = RecipeItems.LearnStatus(itemID, rid)
    local title = "|cffffd100ProfitCraft|r   teaches " .. (r.out and ns.ItemLabel(r.out) or (r.name or "?"))
    local rank = ns.AuctionHouse and ns.AuctionHouse.BrowseRank(itemID)
    local style = rank and ns.Display.RANKS[rank]
    tt:AddLine(" ")
    tt:AddLine(title)
    if style then tt:AddLine("|c" .. style.hex .. style.label .. " recipe you can learn here|r") end
    ns.Display.AddRecipeLines(tt, rid, {
        header = false,
        patternItem = itemID,
        patternStatus = (status == "known" or status == "other") and status or nil,
        patternNeed = need,
    })
    tt:Show()
end

local function Clear(tt) handled[tt] = nil end

ns.On("PLAYER_LOGIN", function()
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt then tt:HookScript("OnTooltipCleared", Clear) end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            OnItemTooltip(tt, data and data.id)
        end)
    else
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tt then
                tt:HookScript("OnTooltipSetItem", function(self)
                    local _, link = self:GetItem()
                    OnItemTooltip(self, ns.ItemIDFromLink(link))
                end)
            end
        end
    end
end)
