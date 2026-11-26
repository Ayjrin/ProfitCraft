-- ProfitCraft: searches the auction house, politely.
--
-- One search at a time, at least a second apart (60 a minute; the game allows 100 a minute for search queries)
-- and only when the game says its query throttle is ready. Searches are read-only and never buy anything.
-- ProfitCraft never runs a full-AH scan (ReplicateItems); it reads Auctionator's for the rest.
local _, ns = ...

local Scanner = {}
ns.Scanner = Scanner

Scanner.MIN_GAP = 1.0          -- seconds between queries
Scanner.TIMEOUT = 8            -- seconds before giving up on an answer
Scanner.MAX_BROWSE_PAGES = 8   -- "more results" pages per browse query

local queue, current = {}, nil
local lastSent = -math.huge
local open = false
local done, total = 0, 0
local listeners = {}

local function AH() return C_AuctionHouse end

local function Sorts()
    local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
    return { { sortOrder = order, reverseSort = false } }
end

function Scanner.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed()
    for _, fn in ipairs(listeners) do ns.Safe("scanner listener", fn) end
end

function Scanner.IsOpen() return open end
function Scanner.Busy() return current ~= nil or #queue > 0 end
function Scanner.Progress() return done, total end

local function JobKey(job)
    if job.kind == "browse" then return "browse:" .. (job.name or "") end
    if job.itemKey then return "key:" .. ns.OrderBook.KeyString(job.itemKey) end
    return "item:" .. job.itemID
end

local function Finish(job, ok)
    if current == job then current = nil end
    done = done + 1
    for _, cb in ipairs(job.callbacks) do ns.Safe("search callback", cb, ok) end
    Changed()
end

local function Enqueue(job, front)
    local key = JobKey(job)
    if current and JobKey(current) == key then
        for _, cb in ipairs(job.callbacks) do table.insert(current.callbacks, cb) end
        return
    end
    for _, queued in ipairs(queue) do
        if JobKey(queued) == key then
            for _, cb in ipairs(job.callbacks) do table.insert(queued.callbacks, cb) end
            return
        end
    end
    if front then table.insert(queue, 1, job) else queue[#queue + 1] = job end
    total = total + 1
    Changed()
end

-- Search one item (itemID) or one exact item key (gear with a level/suffix). cb(ok) when the answer arrives.
function Scanner.Search(item, cb, front)
    local job = { kind = "search", callbacks = { cb } }
    if type(item) == "table" then job.itemKey, job.itemID = item, item.itemID else job.itemID = item end
    Enqueue(job, front)
end

-- Browse query (see C_AuctionHouse.SendBrowseQuery); results go to OrderBook.ReadBrowse.
function Scanner.Browse(name, query, cb)
    Enqueue({ kind = "browse", name = name, query = query, pages = 0, callbacks = { cb } })
end

function Scanner.Cancel()
    local pending = queue
    queue = {}
    for _, job in ipairs(pending) do Finish(job, false) end
    if current then Finish(current, false) end
    done, total = 0, 0
    Changed()
end

-- Green and blue armor and weapons, cheapest first (what disenchant and vendor plays look at).
function Scanner.GearQuery()
    local F = Enum and Enum.AuctionHouseFilter or {}
    return {
        searchString = "",
        sorts = Sorts(),
        filters = { F.UncommonQuality or 8, F.RareQuality or 9 },
        itemClassFilters = { { classID = 4 }, { classID = 2 } },
    }
end

-- Everything the Plays tab needs: enchanting mats and essences, your best crafts' products and reagents,
-- what you're selling, and (for Enchanters) the green/blue gear listings.
function Scanner.ScanMarket()
    local items, seen = {}, {}
    local function Add(id) if id and not seen[id] then seen[id] = true; items[#items + 1] = id end end
    for _, id in ipairs(ns.Disenchant.MAT_IDS) do Add(id) end
    for id in pairs(ns.char.toSell) do Add(id) end
    local ids = {}
    for rid in pairs(ns.KnownSet()) do ids[#ids + 1] = rid end
    local ranked = ns.Engine:Rank(ids)
    for i = 1, math.min(10, #ranked) do
        Add(ranked[i].out)
        for _, part in ipairs(ranked[i].plan.parts) do if part.source ~= "vendor" then Add(part.item) end end
    end
    for _, id in ipairs(items) do Scanner.Search(id) end
    Scanner.Browse("gear", Scanner.GearQuery())
    return #items + 1
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
-- The last query the game was sent, by anyone (PlaceBid wants the item's own search to be the latest).
local last = {}
function Scanner.LastQuery() return last end
local function Track(kind, itemKey)
    last = { kind = kind, itemID = itemKey and itemKey.itemID, key = itemKey and ns.OrderBook.KeyString(itemKey), at = GetTime() }
end

local hooked = false
local function HookQueries()
    local api = AH()
    if hooked or not api or type(api.SendSearchQuery) ~= "function" then return end
    hooked = true
    local function Hook(name, kind)
        if type(api[name]) == "function" then
            hooksecurefunc(api, name, function(itemKey) Track(kind, type(itemKey) == "table" and itemKey.itemID and itemKey or nil) end)
        end
    end
    Hook("SendSearchQuery", "search")
    Hook("SendSellSearchQuery", "sell")
    Hook("SendBrowseQuery", "browse")
    Hook("RequestMoreBrowseResults", "browse")
    Hook("SearchForFavorites", "other")
    Hook("SearchForItemKeys", "other")
end

local function Send(job)
    local api = AH()
    if job.kind == "browse" then
        if job.pages == 0 then api.SendBrowseQuery(job.query) else api.RequestMoreBrowseResults() end
        if not hooked then Track("browse") end
    else
        local key = job.itemKey or api.MakeItemKey(job.itemID)
        api.SendSearchQuery(key, Sorts(), true)
        if not hooked then Track("search", key) end
    end
end

function Scanner.Pump()
    if not open then return end
    local now = GetTime()
    if current then
        if now - current.sentAt > Scanner.TIMEOUT then Finish(current, false) else return end
    end
    if #queue == 0 then return end
    if now - lastSent < Scanner.MIN_GAP then return end
    local api = AH()
    if not api then return end
    if api.IsThrottledMessageSystemReady and not api.IsThrottledMessageSystemReady() then return end
    local job = table.remove(queue, 1)
    current, job.sentAt, lastSent = job, now, now
    local ok, err = pcall(Send, job)
    if not ok then
        ns.ReportError("auction house search", err)
        Finish(job, false)
    end
end

local pump = CreateFrame("Frame")
pump:Hide()
pump:SetScript("OnUpdate", function() Scanner.Pump() end)

---------------------------------------------------------------------------
-- Answers
---------------------------------------------------------------------------
local function AnswerSearch(itemID, itemKey)
    local job = current
    if not job or job.kind ~= "search" or job.itemID ~= itemID then return end
    if job.itemKey and itemKey and ns.OrderBook.KeyString(job.itemKey) ~= ns.OrderBook.KeyString(itemKey) then return end
    Finish(job, true)
end

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, itemID) AnswerSearch(itemID) end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, itemKey) if itemKey then AnswerSearch(itemKey.itemID, itemKey) end end)

local function AnswerBrowse()
    local job = current
    if not job or job.kind ~= "browse" then return end
    local api = AH()
    ns.OrderBook.ReadBrowse(api.GetBrowseResults and api.GetBrowseResults() or {})
    job.pages = job.pages + 1
    if api.HasFullBrowseResults and not api.HasFullBrowseResults() and job.pages < Scanner.MAX_BROWSE_PAGES then
        current = nil
        table.insert(queue, 1, job) -- ask for the next page when the throttle allows
        Changed()
    else
        Finish(job, true)
    end
end
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", AnswerBrowse)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", AnswerBrowse)
ns.On("AUCTION_HOUSE_BROWSE_FAILURE", function() if current and current.kind == "browse" then Finish(current, false) end end)

-- The game dropped our query: put it back and wait a little longer than usual.
ns.On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    if current then
        table.insert(queue, 1, current)
        current = nil
        lastSent = GetTime() + Scanner.MIN_GAP
    end
end)

ns.On("AUCTION_HOUSE_SHOW", function()
    HookQueries()
    open = true
    pump:Show()
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
    open = false
    pump:Hide()
    Scanner.Cancel()
end)
