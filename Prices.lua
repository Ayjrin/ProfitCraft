-- ProfitCraft: one place to ask "what does this cost / sell for / how fast does it sell".
--
-- Trust order for the price of one item on the auction house:
--   1. a live search ProfitCraft (or any addon, or the AH window) ran this session, under 15 minutes old
--   2. Auctionator's last scan
--   3. TradeSkillMaster's minimum buyout for your auction house (from the TSM desktop app)
-- TSM also gives the region's sale rate and daily sales, which nothing else here has.
-- Other addons are only read through their published APIs, inside pcall.
local ADDON, ns = ...

local Prices = {}
ns.Prices = Prices

Prices.LIVE_TTL = 15 * 60 -- seconds a live search stays the best price

local function TSM()
    return type(TSM_API) == "table" and type(TSM_API.GetCustomPriceValue) == "function" and TSM_API or nil
end

function Prices.HasTSM() return TSM() ~= nil end

-- A TSM price source (or custom price string) for a plain item, or nil.
function Prices.TSM(source, itemID)
    local api = TSM()
    if not api or not itemID then return nil end
    local ok, value = pcall(api.GetCustomPriceValue, source, "i:" .. itemID)
    if ok and type(value) == "number" and value > 0 then return value end
end

-- Lowest price from a fresh live search (OrderBook), or nil.
function Prices.Live(itemID)
    if not ns.OrderBook then return nil end
    local book = ns.OrderBook.Get(itemID, Prices.LIVE_TTL)
    if book then return book.min end
    return ns.OrderBook.BrowseMin(itemID, Prices.LIVE_TTL)
end

-- Price of one on the AH and where it came from ("live", "auctionator", "tsm").
function Prices.Get(itemID)
    if not itemID then return nil end
    local live = Prices.Live(itemID)
    if live then return live, "live" end
    local atr = ns.AuctionatorPrice(itemID)
    if atr then return atr, "auctionator" end
    local tsm = Prices.TSM("DBMinBuyout", itemID)
    if tsm then return tsm, "tsm" end
end

-- What you'd realistically sell one for: the live volume wall (see OrderBook.SellPrice), else the price above.
function Prices.SellPrice(itemID)
    local sell = ns.OrderBook and ns.OrderBook.SellPrice(itemID, Prices.LIVE_TTL)
    if sell then return sell, "wall" end
    return Prices.Get(itemID)
end

-- TSM's market value for your auction house (a 14-day trend), or nil.
function Prices.Market(itemID) return Prices.TSM("DBMarket", itemID) end

-- Region sale rate (share of listings that sell, 0..1) and sales per day. TSM rounds price strings to whole
-- numbers, so ask for x1000 and divide.
function Prices.SaleRate(itemID)
    local v = Prices.TSM("DBRegionSaleRate * 1000", itemID)
    return v and v / 1000 or nil
end

function Prices.SoldPerDay(itemID)
    local v = Prices.TSM("DBRegionSoldPerDay * 1000", itemID)
    return v and v / 1000 or nil
end

-- Seconds since the price we'd use was seen (nil = unknown).
function Prices.Age(itemID)
    local book = ns.OrderBook and ns.OrderBook.Get(itemID, Prices.LIVE_TTL)
    if book then return ns.Now() - book.at end
    local browsed = ns.OrderBook and ns.OrderBook.BrowseAt(itemID, Prices.LIVE_TTL)
    if browsed then return ns.Now() - browsed end
    local days = ns.AHAge(itemID)
    if days then return days * 86400 end
end

-- Vendor sell price of one (what a merchant pays you), or nil.
function Prices.VendorSell(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo or not itemID then return nil end
    local sell = select(11, getInfo(itemID))
    if type(sell) == "number" and sell > 0 then return sell end
end
