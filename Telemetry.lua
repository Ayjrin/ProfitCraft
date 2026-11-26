-- ProfitCraft: what your disenchants actually give.
--
-- Every disenchant done with ProfitCraft's Disenchant button is recorded: the item's bracket, whether the
-- Arcane Salvager's "Boosted Disenchanting" aura was on, and the mats that came out. Buffed and unbuffed results
-- are kept apart so the Salvager's bonus never skews the normal rates. From them:
--   * Measured(): once a bracket has enough results, they replace the published tables (that's what this
--     server gives, including Forever's new blue bracket nobody has published),
--   * SalvagerMultiplier(): how much more dust and essence the Salvager really gives, once measured.
-- Stored account-wide in ProfitCraftDB.telemetry (drop rates are the same for every character).
local _, ns = ...

local Telemetry = {}
ns.Telemetry = Telemetry

Telemetry.MIN_SAMPLES = 40    -- results in a bracket before they replace the table
Telemetry.MIN_SALVAGER = 50   -- buffed results before the Salvager bonus counts as measured
Telemetry.MAX_SAMPLES = 500   -- newest results kept per bracket

local DISENCHANT = 13262
local expect          -- the item the Disenchant button just targeted
local casting = false
local parsed = {}     -- [key .. buffed] = cached Measured() result
local session = { count = 0, actual = 0, expected = 0 }

local function DB()
    local t = ns.db.telemetry
    t.brackets = t.brackets or {}
    return t
end

local function Encode(sample)
    local parts = {}
    for item, qty in pairs(sample) do parts[#parts + 1] = item .. ":" .. qty end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function Decode(text)
    local sample = {}
    for item, qty in text:gmatch("(%d+):(%d+)") do sample[tonumber(item)] = tonumber(qty) end
    return sample
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
-- Called by the Disenchant button right before it casts on bag/slot.
function Telemetry.Expect(bag, slot, itemID)
    local classID, quality, itemLevel = ns.Disenchant.ItemSpec(itemID)
    local key = classID and ns.Disenchant.Bracket(classID, quality, itemLevel)
    local buffed = ns.Profile.SalvagerBuff() == true
    local stats = key and ns.Disenchant.Stats(classID, quality, itemLevel, { salvager = buffed })
    expect = { bag = bag, slot = slot, itemID = itemID, key = key, buffed = buffed, at = GetTime(),
        ev = stats and stats.ev or nil }
end

-- True while a disenchant is casting or its loot hasn't arrived (the button waits).
function Telemetry.Busy()
    if casting then return true end
    return expect ~= nil and expect.castAt ~= nil and GetTime() - expect.castAt < 4
end

function Telemetry.Record(key, buffed, sample)
    if not key or not next(sample) then return end
    local brackets = DB().brackets
    local b = brackets[key] or {}
    brackets[key] = b
    local field = buffed and "buffed" or "base"
    local list = b[field] or {}
    b[field] = list
    list[#list + 1] = Encode(sample)
    while #list > Telemetry.MAX_SAMPLES do table.remove(list, 1) end
    parsed[key .. tostring(true)], parsed[key .. tostring(false)] = nil, nil
end

local function ReadLoot()
    local sample = {}
    for i = 1, (GetNumLootItems and GetNumLootItems()) or 0 do
        local link = GetLootSlotLink and GetLootSlotLink(i)
        local itemID = ns.ItemIDFromLink(link)
        local _, _, quantity = GetLootSlotInfo(i)
        if itemID and quantity and quantity > 0 then sample[itemID] = (sample[itemID] or 0) + quantity end
    end
    return sample
end

local function OnLoot()
    local e = expect
    if not (e and e.castAt and GetTime() - e.castAt < 5) then return end
    expect = nil
    local sample = ReadLoot()
    if not next(sample) then return end
    Telemetry.Record(e.key, e.buffed, sample)

    -- this item is done: take it off the disenchant list, and put its mats up for sale
    local queue = ns.char.deQueue
    local bought = queue[e.itemID] and queue[e.itemID] > 0
    if bought then
        queue[e.itemID] = queue[e.itemID] - 1
        if queue[e.itemID] <= 0 then queue[e.itemID], ns.char.salvager[e.itemID] = nil, nil end
        for item in pairs(sample) do ns.char.toSell[item] = true end
    end

    local value = 0
    for item, qty in pairs(sample) do value = value + qty * (ns.Disenchant.MatValue(item) or 0) end
    session.count = session.count + 1
    session.actual = session.actual + value
    session.expected = session.expected + (e.ev or value)
    if ns.Ledger then ns.Ledger.Disenchant(e.itemID, value, e.ev) end
end

local function IsMyDisenchant(unit, spellID) return unit == "player" and spellID == DISENCHANT end

ns.On("UNIT_SPELLCAST_START", function(_, unit, _, spellID)
    if IsMyDisenchant(unit, spellID) then casting = true end
end)
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
    if not IsMyDisenchant(unit, spellID) then return end
    casting = false
    if expect then expect.castAt = GetTime() end
end)
local function Failed(_, unit, _, spellID)
    if not IsMyDisenchant(unit, spellID) then return end
    casting = false
    expect = nil
end
ns.On("UNIT_SPELLCAST_FAILED", Failed)
ns.On("UNIT_SPELLCAST_FAILED_QUIET", Failed)
ns.On("UNIT_SPELLCAST_INTERRUPTED", Failed)
ns.On("LOOT_READY", OnLoot)
ns.On("LOOT_OPENED", OnLoot)

---------------------------------------------------------------------------
-- Reading it back
---------------------------------------------------------------------------
function Telemetry.Count(key, buffed)
    local b = key and DB().brackets[key]
    local list = b and b[buffed and "buffed" or "base"]
    return list and #list or 0
end

-- Your results for a bracket once there are at least `min` (default MIN_SAMPLES), else nil:
--   { n, samples = { {[itemID] = qty} }, mats = { [itemID] = { hits, total, min, max } } }
function Telemetry.Measured(key, buffed, min)
    if not key then return nil end
    if Telemetry.Count(key, buffed) < (min or Telemetry.MIN_SAMPLES) then return nil end
    local cacheKey = key .. tostring(buffed and true or false)
    local cached = parsed[cacheKey]
    if cached and cached.n == Telemetry.Count(key, buffed) then return cached end
    local result = { n = 0, samples = {}, mats = {} }
    for _, text in ipairs(DB().brackets[key][buffed and "buffed" or "base"]) do
        local sample = Decode(text)
        result.samples[#result.samples + 1] = sample
        for item, qty in pairs(sample) do
            local m = result.mats[item] or { hits = 0, total = 0, min = qty, max = qty }
            result.mats[item] = m
            m.hits, m.total = m.hits + 1, m.total + qty
            m.min, m.max = math.min(m.min, qty), math.max(m.max, qty)
        end
    end
    result.n = #result.samples
    parsed[cacheKey] = result
    return result
end

-- Expected dust + essence count per disenchant in a bracket without the Salvager.
local function BaseCount(key)
    local base = Telemetry.Measured(key, false, 20)
    local sum = 0
    if base then
        for item, m in pairs(base.mats) do
            if not ns.Disenchant.IsShard(item) then sum = sum + m.total end
        end
        return sum / base.n
    end
    local quality, classID, low = key:match("^(%d+):(%d+):(%d+)")
    quality, classID, low = tonumber(quality), tonumber(classID), tonumber(low)
    local mats = ns.Disenchant.TableMats(classID == 0 and 4 or classID, quality, low, function() return 1 end)
    for _, m in ipairs(mats or {}) do
        if not ns.Disenchant.IsShard(m.item) then sum = sum + m.avg end
    end
    return sum
end

-- How many times the normal dust and essences a disenchant gives next to an Arcane Salvager:
--   measured from your buffed disenchants once there are MIN_SALVAGER of them, else your "Salvager bonus"
--   setting (0% by default: no bonus is counted until it's measured). Returns multiplier, buffed count, source.
function Telemetry.SalvagerMultiplier()
    local got, expected, n = 0, 0, 0
    for key, b in pairs(DB().brackets) do
        if b.buffed and #b.buffed > 0 then
            local base = BaseCount(key)
            if base > 0 then
                for _, text in ipairs(b.buffed) do
                    for item, qty in pairs(Decode(text)) do
                        if not ns.Disenchant.IsShard(item) then got = got + qty end
                    end
                    expected, n = expected + base, n + 1
                end
            end
        end
    end
    if n >= Telemetry.MIN_SALVAGER and expected > 0 then return got / expected, n, "measured" end
    local bonus = (ns.settings and ns.settings.salvagerBonus) or 0
    if bonus > 0 then return 1 + bonus / 100, n, "setting" end
    return 1, n, "none"
end

-- This session's disenchants: how many, what the mats are worth now, and what was expected.
function Telemetry.Session() return session end

-- Per bracket: how many results, without and with the Salvager (for /craftprofit de).
function Telemetry.Summary()
    local list = {}
    for key, b in pairs(DB().brackets) do
        list[#list + 1] = { key = key, base = b.base and #b.base or 0, buffed = b.buffed and #b.buffed or 0 }
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end
