-- ProfitCraft: what a crafted item is worth disenchanted, for Enchanters.
--
-- Which items can be disenchanted: the game's own ItemDisenchantLoot table for WoW Forever (live build
-- 1.60.1.70959, read from wago.tools): armor and weapons, green or blue from item level 5, purple from 40,
-- up to 99. Its skill column is 0 on every row: in Forever any Enchanter can disenchant anything.
-- What they give (server-side, not in the client): the Classic tables, which Wowhead's WoW Forever loot
-- counts match for greens. Blue items under item level 21 are new in Forever and nobody has published
-- what they give yet, so they're shown as unknown and not valued.
-- Each mat is valued at its AH price, so "worth" means what the mats would sell for. Nothing here is
-- used unless you have Enchanting.
local _, ns = ...

local Disenchant = {}
ns.Disenchant = Disenchant

local ENCHANTING = 333

-- Mats
local STRANGE, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204
local LESSER_MAGIC, GREATER_MAGIC = 10938, 10939
local LESSER_ASTRAL, GREATER_ASTRAL = 10998, 11082
local LESSER_MYSTIC, GREATER_MYSTIC = 11134, 11135
local LESSER_NETHER, GREATER_NETHER = 11174, 11175
local LESSER_ETERNAL, GREATER_ETERNAL = 16202, 16203
local SMALL_GLIMMERING, LARGE_GLIMMERING = 10978, 11084
local SMALL_GLOWING, LARGE_GLOWING = 11138, 11139
local SMALL_RADIANT, LARGE_RADIANT = 11177, 11178
local SMALL_BRILLIANT, LARGE_BRILLIANT = 14343, 14344
local NEXUS = 20725

local MIN_LEVEL = { [2] = 5, [3] = 5, [4] = 40 } -- lowest item level that can be disenchanted, by quality
local MAX_LEVEL = 99

-- Uncommon (green): { highest item level, dust, essence, shard, armor chances { dust, essence, shard } }.
-- Each mat is { itemID, min, max }. Weapons swap the dust and essence chances (mostly essences).
local UNCOMMON = {
    { 15, { STRANGE, 1, 2 }, { LESSER_MAGIC, 1, 2 }, nil, { 0.80, 0.20, 0 } },
    { 20, { STRANGE, 2, 3 }, { GREATER_MAGIC, 1, 2 }, { SMALL_GLIMMERING, 1, 1 }, { 0.75, 0.20, 0.05 } },
    { 25, { STRANGE, 4, 6 }, { LESSER_ASTRAL, 1, 2 }, { SMALL_GLIMMERING, 1, 1 }, { 0.75, 0.15, 0.10 } },
    { 30, { SOUL, 1, 2 }, { GREATER_ASTRAL, 1, 2 }, { LARGE_GLIMMERING, 1, 1 }, { 0.75, 0.20, 0.05 } },
    { 35, { SOUL, 2, 5 }, { LESSER_MYSTIC, 1, 2 }, { SMALL_GLOWING, 1, 1 }, { 0.75, 0.20, 0.05 } },
    { 40, { VISION, 1, 2 }, { GREATER_MYSTIC, 1, 2 }, { LARGE_GLOWING, 1, 1 }, { 0.75, 0.20, 0.05 } },
    { 45, { VISION, 2, 5 }, { LESSER_NETHER, 1, 2 }, { SMALL_RADIANT, 1, 1 }, { 0.75, 0.20, 0.05 } },
    { 50, { DREAM, 1, 2 }, { GREATER_NETHER, 1, 2 }, { LARGE_RADIANT, 1, 1 }, { 0.75, 0.20, 0.05 } },
    { 55, { DREAM, 2, 5 }, { LESSER_ETERNAL, 1, 2 }, { SMALL_BRILLIANT, 1, 1 }, { 0.75, 0.20, 0.05 } },
    { 60, { ILLUSION, 1, 2 }, { GREATER_ETERNAL, 1, 2 }, { LARGE_BRILLIANT, 1, 1 }, { 0.75, 0.20, 0.05 } },
    { math.huge, { ILLUSION, 2, 5 }, { GREATER_ETERNAL, 2, 3 }, { LARGE_BRILLIANT, 1, 1 }, { 0.75, 0.20, 0.05 } },
}

-- Rare (blue) and epic (purple): { highest item level, { itemID, min, max } }, always that one mat.
-- nil mat = Forever's new bracket, not known yet.
local RARE = {
    { 20, nil },
    { 25, { SMALL_GLIMMERING, 1, 1 } },
    { 30, { LARGE_GLIMMERING, 1, 1 } },
    { 35, { SMALL_GLOWING, 1, 1 } },
    { 40, { LARGE_GLOWING, 1, 1 } },
    { 45, { SMALL_RADIANT, 1, 1 } },
    { 50, { LARGE_RADIANT, 1, 1 } },
    { 55, { SMALL_BRILLIANT, 1, 1 } },
    { math.huge, { LARGE_BRILLIANT, 1, 1 } },
}
local EPIC = {
    { 45, { SMALL_RADIANT, 2, 4 } },
    { 50, { LARGE_RADIANT, 2, 4 } },
    { 55, { SMALL_BRILLIANT, 2, 4 } },
    { 60, { NEXUS, 1, 1 } },
    { math.huge, { NEXUS, 1, 2 } },
}

local UNCOMMON_Q, RARE_Q, EPIC_Q = 2, 3, 4
local WEAPON, ARMOR = 2, 4 -- item class IDs

local function Band(tbl, itemLevel)
    for _, row in ipairs(tbl) do
        if itemLevel <= row[1] then return row end
    end
end

---------------------------------------------------------------------------
-- Your Enchanting skill (nil without Enchanting, which turns everything here off). Any skill will do.
---------------------------------------------------------------------------
function Disenchant.PlayerSkill()
    if GetProfessions and GetProfessionInfo then
        local list, sawAny = { GetProfessions() }, false
        for i = 1, 6 do
            local index = list[i]
            if index then
                sawAny = true
                local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
                if skillLine == ENCHANTING then return rank or 0 end
            end
        end
        if sawAny then return nil end -- the game answered and there's no Enchanting
    end
    -- the game didn't say: fall back to what the Enchanting window last showed
    local saved = ns.char and ns.char.profs[ENCHANTING]
    return saved and (saved.rank or 0) or nil
end

---------------------------------------------------------------------------
-- What one item disenchants into
---------------------------------------------------------------------------
local waiting = {} -- items whose level/quality the game is still loading

local function ItemInfo(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return nil end
    local name, _, quality, itemLevel = getInfo(itemID)
    if name and quality and itemLevel then return quality, itemLevel end
    waiting[itemID] = true
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
end

local function Mat(spec, chance)
    if not spec or chance <= 0 then return nil end
    local item, min, max = spec[1], spec[2], spec[3]
    return { item = item, min = min, max = max, chance = chance, avg = chance * (min + max) / 2, unit = ns.AHPrice(item) }
end

-- Expected disenchant result for one `itemID`, or nil if it can't be disenchanted (or isn't loaded yet).
-- A new table every call:
--   mats     { item, min, max, chance, avg (expected count), unit (AH price, nil = no price) }
--   each     expected AH value of the mats from one item, before the AH cut (nil when a mat has no price)
--   unknown  true for a bracket whose mats nobody knows yet (mats empty, each nil)
function Disenchant.Evaluate(itemID)
    if not itemID then return nil end
    local _, _, _, _, _, classID = ns.ItemInstant(itemID)
    if classID ~= ARMOR and classID ~= WEAPON then return nil end
    local quality, itemLevel = ItemInfo(itemID)
    if not quality or not MIN_LEVEL[quality] then return nil end
    if itemLevel < MIN_LEVEL[quality] or itemLevel > MAX_LEVEL then return nil end

    local mats = {}
    if quality == UNCOMMON_Q then
        local row = Band(UNCOMMON, itemLevel)
        local dust, essence, shard = row[5][1], row[5][2], row[5][3]
        if classID == WEAPON then dust, essence = essence, dust end
        mats[#mats + 1] = Mat(row[2], dust)
        mats[#mats + 1] = Mat(row[3], essence)
        mats[#mats + 1] = Mat(row[4], shard)
        table.sort(mats, function(a, b) return a.chance > b.chance end)
    else
        local row = Band(quality == RARE_Q and RARE or EPIC, itemLevel)
        if not row[2] then return { mats = mats, unknown = true, quality = quality, itemLevel = itemLevel } end
        mats[1] = Mat(row[2], 1)
    end

    local each = 0
    for _, m in ipairs(mats) do
        if not m.unit then each = nil; break end
        each = each + m.avg * m.unit
    end
    return { mats = mats, each = each, quality = quality, itemLevel = itemLevel }
end

---------------------------------------------------------------------------
-- Events: re-evaluate when item info arrives or you learn or drop Enchanting
---------------------------------------------------------------------------
ns.On("GET_ITEM_INFO_RECEIVED", function(_, itemID)
    if itemID and waiting[itemID] then
        waiting[itemID] = nil
        ns.Debounce("disenchant-items", 0.5, function() ns.Engine:Invalidate() end)
    end
end)

-- Learning or dropping Enchanting turns disenchant values on or off (the skill level doesn't matter).
local hadEnchanting
ns.On("SKILL_LINES_CHANGED", function()
    ns.Debounce("disenchant-skill", 1, function()
        if not ns.IsReady() then return end
        local has = Disenchant.PlayerSkill() ~= nil
        if has ~= hadEnchanting then
            hadEnchanting = has
            ns.Engine:Invalidate()
        end
    end)
end)
