-- ProfitCraft: learns recipes from the profession window and vendor prices from merchants.
local _, ns = ...

local Data = {}
ns.Data = Data

local T = C_TradeSkillUI

---------------------------------------------------------------------------
-- Recipe definitions
---------------------------------------------------------------------------
local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic

local function IsRequiredSlot(slot)
    if slot.required ~= nil then return slot.required end
    return BASIC == nil or slot.reagentType == BASIC
end

-- Reads a recipe's static definition. Works for unlearned recipes too.
function Data.ReadSchematic(rid)
    if not (T and T.GetRecipeSchematic) then return nil end
    local ok, s = pcall(T.GetRecipeSchematic, rid, false)
    if not ok or type(s) ~= "table" then return nil end
    local reagents = {}
    for _, slot in ipairs(s.reagentSlotSchematics or {}) do
        if IsRequiredSlot(slot) then
            local first = slot.reagents and slot.reagents[1]
            if first and first.itemID then
                reagents[#reagents + 1] = { item = first.itemID, qty = slot.quantityRequired or 1 }
            end
        end
    end
    local qmin = math.max(1, s.quantityMin or 1)
    return {
        name = s.name,
        icon = s.icon,
        out = s.outputItemID,
        qmin = qmin,
        qmax = math.max(qmin, s.quantityMax or qmin),
        reagents = reagents,
    }
end

function Data.Yield(r)
    return ((r.qmin or 1) + (r.qmax or r.qmin or 1)) / 2
end

-- Viewing someone else's profession (link, guild, NPC) must not change what *you* know.
function Data.IsForeign()
    if not T then return true end
    return (T.IsTradeSkillLinked and T.IsTradeSkillLinked())
        or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
        or (T.IsNPCCrafting and T.IsNPCCrafting())
        or false
end

function Data.CurrentProfession()
    local info = T and T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    if info and info.professionID and info.professionID ~= 0 then return info.professionID, info end
end

---------------------------------------------------------------------------
-- Lookup indexes
---------------------------------------------------------------------------
local byOutput, byName, indexDirty = {}, {}, true

function Data.MarkIndexDirty() indexDirty = true end

local function BuildIndex()
    if not indexDirty or not ns.db then return end
    byOutput, byName = {}, {}
    for rid, r in pairs(ns.db.recipes) do
        if r.out then
            local list = byOutput[r.out]
            if not list then list = {}; byOutput[r.out] = list end
            list[#list + 1] = rid
        end
        if r.name and not byName[r.name] then byName[r.name] = rid end
    end
    indexDirty = false
end

function Data.RecipesByOutput(itemID) BuildIndex(); return byOutput[itemID] end
function Data.RecipeByName(name) BuildIndex(); return name and byName[name] end

---------------------------------------------------------------------------
-- Scanning the open profession window
---------------------------------------------------------------------------
function Data.ScanOpenProfession()
    if not ns.IsReady() or not (T and T.GetAllRecipeIDs) then return end
    if T.IsTradeSkillReady and not T.IsTradeSkillReady() then
        ns.Debounce("scanretry", 1, Data.ScanOpenProfession)
        return
    end
    if T.IsDataSourceChanging and T.IsDataSourceChanging() then
        ns.Debounce("scanretry", 1, Data.ScanOpenProfession)
        return
    end
    local profID, prof = Data.CurrentProfession()
    if not profID then return end
    local ids = T.GetAllRecipeIDs()
    if not ids or #ids == 0 then return end

    local known = {}
    for _, rid in ipairs(ids) do
        local info = T.GetRecipeInfo(rid)
        if info and not info.isRecraft and not info.isSalvageRecipe and not info.isDummyRecipe then
            local def = Data.ReadSchematic(rid)
            if def then
                def.name = info.name or def.name
                def.icon = info.icon or def.icon
                def.prof = profID
                ns.db.recipes[rid] = def
                if info.learned then known[rid] = true end
            end
        end
    end

    if not Data.IsForeign() then
        ns.char.known[profID] = known
        ns.char.profs[profID] = { name = prof.professionName, rank = prof.skillLevel, max = prof.maxSkillLevel }
    end
    Data.MarkIndexDirty()
    ns.Engine:Invalidate()
end

function Data.ScheduleScan()
    ns.Debounce("scan", 0.3, Data.ScanOpenProfession)
end

function Data.MarkKnown(rid)
    local r = ns.db and ns.db.recipes[rid]
    if not r or not r.prof then return false end
    local set = ns.char.known[r.prof]
    if not set then set = {}; ns.char.known[r.prof] = set end
    if set[rid] then return false end
    set[rid] = true
    return true
end

-- Crafting professions you have that haven't been opened yet (so their recipes aren't usable as steps).
function Data.UnscannedProfessions()
    local missing = {}
    if not (GetProfessions and GetProfessionInfo and ns.char) then return missing end
    local list = { GetProfessions() }
    for i = 1, 6 do
        local index = list[i]
        if index then
            local name, _, _, _, _, _, skillLine = GetProfessionInfo(index)
            if skillLine and ns.CRAFTING_SKILL_LINES[skillLine] and not ns.char.profs[skillLine] then
                missing[#missing + 1] = name
            end
        end
    end
    return missing
end

ns.On("TRADE_SKILL_SHOW", Data.ScheduleScan)
ns.On("TRADE_SKILL_LIST_UPDATE", Data.ScheduleScan)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", Data.ScheduleScan)
ns.On("NEW_RECIPE_LEARNED", function(_, rid)
    if rid and Data.MarkKnown(rid) then ns.Engine:Invalidate() end
    Data.ScheduleScan()
end)

---------------------------------------------------------------------------
-- Vendor prices (thread, vials, flux...) captured whenever a merchant is open
---------------------------------------------------------------------------
local function MerchantItem(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if info then return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
    elseif GetMerchantItemInfo then
        local _, _, price, stack, available, _, _, extended = GetMerchantItemInfo(i)
        return price, stack, available, extended
    end
end

function Data.ScanMerchant()
    if not ns.IsReady() or not GetMerchantNumItems or not GetMerchantItemID then return end
    local changed = false
    for i = 1, GetMerchantNumItems() do
        local itemID = GetMerchantItemID(i)
        local price, stack, available, extended = MerchantItem(i)
        -- only unlimited stock bought with gold
        if itemID and price and price > 0 and not extended and (available == nil or available < 0) then
            local each = price / math.max(stack or 1, 1)
            if ns.db.vendor[itemID] ~= each then
                ns.db.vendor[itemID] = each
                changed = true
            end
        end
    end
    if changed then ns.Engine:Invalidate() end
end

ns.On("MERCHANT_SHOW", function() ns.Debounce("merchant", 0.5, Data.ScanMerchant) end)
ns.On("MERCHANT_UPDATE", function() ns.Debounce("merchant", 0.5, Data.ScanMerchant) end)

-- Auctionator records prices while the AH is open; re-evaluate once it closes.
ns.On("AUCTION_HOUSE_CLOSED", function() ns.Engine:Invalidate() end)
