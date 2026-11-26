-- ProfitCraft: prices by weekday and time of day, learned from your own searches.
--
-- Each live search records the cheapest price into a bucket for its weekday and 3-hour window (your computer's
-- clock), at most once an hour per item. After a week of data the Plays tab can say whether now is a cheap or
-- dear moment for an item compared to its usual price, and when it usually sells highest.
-- Stored in ProfitCraftDB.clock; nothing leaves your computer.
local _, ns = ...

local Clock = {}
ns.Clock = Clock

Clock.MIN_DAYS = 7         -- distinct days of data before Phase() says anything
Clock.WINDOW_HOURS = 3
Clock.WEIGHT = 0.25        -- weight of a new reading in its bucket's running average
Clock.MAX_ITEMS = 300

local DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local lastHour = {} -- [itemID] = hour stamp of the last recording this session

local function Date(t) return date("*t", t or ns.Now()) end

function Clock.Bucket(t)
    local d = Date(t)
    return (d.wday - 1) * 8 + math.floor(d.hour / Clock.WINDOW_HOURS)
end

function Clock.BucketLabel(bucket)
    local day, window = math.floor(bucket / 8), bucket % 8
    local from = window * Clock.WINDOW_HOURS
    return ("%s %02d-%02d"):format(DAYS[day + 1], from, from + Clock.WINDOW_HOURS)
end

local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

function Clock.Record(itemID, price, t)
    if not (ns.db and itemID and price and price > 0) then return end
    t = t or ns.Now()
    local stamp = math.floor(t / 3600)
    if lastHour[itemID] == stamp then return end
    lastHour[itemID] = stamp
    local store = ns.db.clock
    local entry = store[itemID]
    if not entry then
        if Count(store) >= Clock.MAX_ITEMS then return end
        entry = { b = {}, days = {} }
        store[itemID] = entry
    end
    local bucket = Clock.Bucket(t)
    local b = entry.b[bucket]
    if b then b.m, b.n = b.m + Clock.WEIGHT * (price - b.m), b.n + 1
    else entry.b[bucket] = { m = price, n = 1 } end
    local d = Date(t)
    entry.days[("%04d%02d%02d"):format(d.year, d.month, d.day)] = true
    if Count(entry.days) > 60 then entry.days = { [("%04d%02d%02d"):format(d.year, d.month, d.day)] = true, old = true } end
end

-- How today's price compares with the item's usual one, once there's a week of data:
--   { tag = "low"/"high"/"normal", vsUsual = fraction (+0.18 = 18% above usual), sellAt, buyAt (bucket labels) }
function Clock.Phase(itemID, price)
    local entry = ns.db and ns.db.clock[itemID]
    if not entry or not price then return nil end
    local days = Count(entry.days)
    if entry.days.old then days = Clock.MIN_DAYS end
    if days < Clock.MIN_DAYS then return nil end
    local sum, n, best, worst = 0, 0, nil, nil
    for bucket, b in pairs(entry.b) do
        sum, n = sum + b.m, n + 1
        if not best or b.m > entry.b[best].m then best = bucket end
        if not worst or b.m < entry.b[worst].m then worst = bucket end
    end
    if n < 4 then return nil end
    local usual = sum / n
    local vs = price / usual - 1
    local tag = vs <= -0.10 and "low" or vs >= 0.10 and "high" or "normal"
    return { tag = tag, vsUsual = vs, usual = usual, sellAt = Clock.BucketLabel(best), buyAt = Clock.BucketLabel(worst) }
end

ns.OrderBook.OnUpdate(function(itemID)
    local book = ns.OrderBook.Get(itemID)
    if book and book.min then Clock.Record(itemID, book.min) end
end)
