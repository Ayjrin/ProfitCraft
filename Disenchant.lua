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

-- Every mat disenchanting can give (what the Plays tab scans).
Disenchant.MAT_IDS = { STRANGE, SOUL, VISION, DREAM, ILLUSION, LESSER_MAGIC, GREATER_MAGIC, LESSER_ASTRAL, GREATER_ASTRAL,
    LESSER_MYSTIC, GREATER_MYSTIC, LESSER_NETHER, GREATER_NETHER, LESSER_ETERNAL, GREATER_ETERNAL, SMALL_GLIMMERING,
    LARGE_GLIMMERING, SMALL_GLOWING, LARGE_GLOWING, SMALL_RADIANT, LARGE_RADIANT, SMALL_BRILLIANT, LARGE_BRILLIANT, NEXUS }
local SHARDS = { [SMALL_GLIMMERING] = true, [LARGE_GLIMMERING] = true, [SMALL_GLOWING] = true, [LARGE_GLOWING] = true,
    [SMALL_RADIANT] = true, [LARGE_RADIANT] = true, [SMALL_BRILLIANT] = true, [LARGE_BRILLIANT] = true, [NEXUS] = true }
function Disenchant.IsShard(itemID) return SHARDS[itemID] == true end

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
    for i, row in ipairs(tbl) do
        if itemLevel <= row[1] then return row, i end
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

local function Mat(spec, chance, price)
    if not spec or chance <= 0 then return nil end
    local item, min, max = spec[1], spec[2], spec[3]
    return { item = item, min = min, max = max, chance = chance, avg = chance * (min + max) / 2,
        unit = (price or ns.AHPrice)(item) }
end

-- Reads an item's class, quality and item level (nil while the game is still loading it).
function Disenchant.ItemSpec(itemID)
    if not itemID then return nil end
    local _, _, _, _, _, classID = ns.ItemInstant(itemID)
    if classID ~= ARMOR and classID ~= WEAPON then return nil end
    local quality, itemLevel = ItemInfo(itemID)
    if not quality then return nil end
    return classID, quality, itemLevel
end

function Disenchant.CanDisenchant(classID, quality, itemLevel)
    if classID ~= ARMOR and classID ~= WEAPON then return false end
    if not quality or not MIN_LEVEL[quality] or not itemLevel then return false end
    return itemLevel >= MIN_LEVEL[quality] and itemLevel <= MAX_LEVEL
end

-- The table bracket an item falls in: a key for the measurements, and its item level range.
function Disenchant.Bracket(classID, quality, itemLevel)
    if not Disenchant.CanDisenchant(classID, quality, itemLevel) then return nil end
    local tbl = quality == UNCOMMON_Q and UNCOMMON or quality == RARE_Q and RARE or EPIC
    local row, i = Band(tbl, itemLevel)
    local low = i > 1 and tbl[i - 1][1] + 1 or MIN_LEVEL[quality]
    local high = row[1] == math.huge and MAX_LEVEL or row[1]
    local key = ("%d:%d:%d-%d"):format(quality, quality == UNCOMMON_Q and classID or 0, low, high)
    return key, low, high
end

local QUALITY_NAME = { [UNCOMMON_Q] = "Green", [RARE_Q] = "Blue", [EPIC_Q] = "Purple" }
function Disenchant.BracketLabel(classID, quality, itemLevel)
    local key, low, high = Disenchant.Bracket(classID, quality, itemLevel)
    if not key then return nil end
    local what = quality == UNCOMMON_Q and (classID == WEAPON and " weapons" or " armor") or " gear"
    return ("%s%s, item level %d-%d"):format(QUALITY_NAME[quality], what, low, high)
end

-- What an item of this class/quality/level disenchants into, per the tables (Classic rates; see the top).
-- price(itemID) values each mat (default: its AH price). Returns mats, or nil + "unknown" for Forever's new
-- blue bracket. Measurements from your own disenchants fill that bracket in once there are enough (Telemetry.lua).
function Disenchant.TableMats(classID, quality, itemLevel, price)
    local mats = {}
    if quality == UNCOMMON_Q then
        local row = Band(UNCOMMON, itemLevel)
        local dust, essence, shard = row[5][1], row[5][2], row[5][3]
        if classID == WEAPON then dust, essence = essence, dust end
        mats[#mats + 1] = Mat(row[2], dust, price)
        mats[#mats + 1] = Mat(row[3], essence, price)
        mats[#mats + 1] = Mat(row[4], shard, price)
        table.sort(mats, function(a, b) return a.chance > b.chance end)
    else
        local row = Band(quality == RARE_Q and RARE or EPIC, itemLevel)
        if not row[2] then return nil, "unknown" end
        mats[1] = Mat(row[2], 1, price)
    end
    return mats
end

-- Mats measured from your own disenchants of this bracket, averaged, when there are enough of them.
local function MeasuredMats(classID, quality, itemLevel, price)
    local stats = ns.Telemetry and ns.Telemetry.Measured(Disenchant.Bracket(classID, quality, itemLevel), false)
    if not stats then return nil end
    local mats = {}
    for item, m in pairs(stats.mats) do
        mats[#mats + 1] = { item = item, min = m.min, max = m.max, chance = m.hits / stats.n, avg = m.total / stats.n,
            unit = (price or ns.AHPrice)(item) }
    end
    table.sort(mats, function(a, b) return a.chance > b.chance end)
    return mats, stats.n
end

-- Expected disenchant result for one `itemID`, or nil if it can't be disenchanted (or isn't loaded yet).
-- A new table every call:
--   mats     { item, min, max, chance, avg (expected count), unit (AH price, nil = no price) }
--   each     expected AH value of the mats from one item, before the AH cut (nil when a mat has no price)
--   unknown  true for a bracket whose mats nobody knows yet (mats empty, each nil)
--   measured number of your own disenchants the mats come from (for a bracket the tables don't cover)
function Disenchant.Evaluate(itemID)
    local classID, quality, itemLevel = Disenchant.ItemSpec(itemID)
    if not Disenchant.CanDisenchant(classID, quality, itemLevel) then return nil end

    local mats, measured = Disenchant.TableMats(classID, quality, itemLevel)
    if not mats then
        mats, measured = MeasuredMats(classID, quality, itemLevel)
        if not mats then return { mats = {}, unknown = true, quality = quality, itemLevel = itemLevel } end
    end

    local each = 0
    for _, m in ipairs(mats) do
        if not m.unit then each = nil; break end
        each = each + m.avg * m.unit
    end
    return { mats = mats, each = each, quality = quality, itemLevel = itemLevel, measured = measured }
end

---------------------------------------------------------------------------
-- For buying gear to disenchant: the spread of outcomes, not just the average
---------------------------------------------------------------------------
-- What a mat is worth to sell: the live wall price, and for essences the better of the two forms
-- (3 lesser and 1 greater convert into each other from the bags).
function Disenchant.MatValue(itemID)
    if ns.Essences then
        local best = ns.Essences.BestValue(itemID)
        if best then return best end
    end
    return (ns.Prices.SellPrice(itemID))
end

-- E[q] and E[q^2] of a whole number drawn evenly from min..max.
local function Moments(min, max)
    local mean = (min + max) / 2
    local n = max - min + 1
    return mean, (n * n - 1) / 12 + mean * mean
end

-- Per item of this class/quality/level, valued at what the mats sell for:
--   ev       expected mats value before the AH cut
--   sd       its standard deviation (how much one item's result swings)
--   mats     as in Evaluate, unit = sell value
--   source   "table" or "measured" (n = how many of your disenchants)
--   missing  true when a mat has no price (ev nil)
-- opts.salvager: count the Arcane Salvager bonus on dust and essences (Telemetry.SalvagerMultiplier).
function Disenchant.Stats(classID, quality, itemLevel, opts)
    if not Disenchant.CanDisenchant(classID, quality, itemLevel) then return nil end
    opts = opts or {}
    local mult = 1
    if opts.salvager then mult = ns.Telemetry and ns.Telemetry.SalvagerMultiplier() or 1 end
    local key = Disenchant.Bracket(classID, quality, itemLevel)

    -- your own measurements, when there are enough, replace the table (they are what this server gives)
    local measured = ns.Telemetry and ns.Telemetry.Measured(key, opts.salvager and mult > 1)
    if measured then
        local mean, sq, missing = 0, 0, false
        for _, sample in ipairs(measured.samples) do
            local v = 0
            for item, qty in pairs(sample) do
                local unit = Disenchant.MatValue(item)
                if not unit then missing = true else v = v + qty * unit end
            end
            mean, sq = mean + v, sq + v * v
        end
        local n = #measured.samples
        if not missing and n > 0 then
            mean, sq = mean / n, sq / n
            return { ev = mean, sd = math.sqrt(math.max(0, sq - mean * mean)), source = "measured", n = n, mats = {} }
        end
    end

    local mats, unknown = Disenchant.TableMats(classID, quality, itemLevel, Disenchant.MatValue)
    if not mats then return { unknown = true } end
    local ev, sq = 0, 0
    for _, m in ipairs(mats) do
        if not m.unit then return { missing = true, mats = mats } end
        local k = Disenchant.IsShard(m.item) and 1 or mult
        local e1, e2 = Moments(m.min, m.max)
        ev = ev + m.chance * e1 * k * m.unit
        sq = sq + m.chance * e2 * k * k * m.unit * m.unit
    end
    return { ev = ev, sd = math.sqrt(math.max(0, sq - ev * ev)), source = "table", mats = mats, multiplier = mult }
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
