-- ProfitCraft: what you bought, posted, disenchanted and sold, and how that compares with what was predicted.
--
--   buy     a purchase made with ProfitCraft's button (exact price, and the value predicted at the time)
--   post    an auction posted with ProfitCraft's button (the deposit paid)
--   de      a disenchant done with ProfitCraft's button (mats' value now vs. the expected value)
--   sale    an auction house "sold" mail taken from the mailbox (the money it held)
-- Kept in ProfitCraftDB.ledger (newest last, at most MAX entries).
local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger

Ledger.MAX = 3000
local sessionSpent = 0

local function Add(entry)
    local list = ns.db.ledger
    entry.t = ns.Now()
    list[#list + 1] = entry
    while #list > Ledger.MAX do table.remove(list, 1) end
    return entry
end

function Ledger.SessionSpent() return sessionSpent end

function Ledger.Buy(itemID, qty, cost, predicted, play)
    sessionSpent = sessionSpent + cost
    Add({ kind = "buy", item = itemID, qty = qty, money = cost, predicted = predicted, play = play })
end

function Ledger.Post(itemID, qty, deposit, unitPrice)
    Add({ kind = "post", item = itemID, qty = qty, money = deposit or 0, price = unitPrice })
end

function Ledger.Disenchant(itemID, value, expected)
    Add({ kind = "de", item = itemID, money = value, predicted = expected })
end

function Ledger.Sale(name, money)
    Add({ kind = "sale", name = name, money = money })
end

-- Totals for the last `days` days:
--   spent, predicted (what those buys were expected to be worth), sold, deposits, buys, sales,
--   deCount, deActual, deExpected
function Ledger.Summary(days)
    local since = ns.Now() - (days or 7) * 86400
    local s = { spent = 0, predicted = 0, sold = 0, deposits = 0, buys = 0, sales = 0, deCount = 0, deActual = 0, deExpected = 0 }
    for _, e in ipairs(ns.db.ledger) do
        if e.t >= since then
            if e.kind == "buy" then
                s.spent, s.buys = s.spent + e.money, s.buys + (e.qty or 1)
                s.predicted = s.predicted + (e.predicted or e.money)
            elseif e.kind == "post" then
                s.deposits = s.deposits + e.money
            elseif e.kind == "sale" then
                s.sold, s.sales = s.sold + e.money, s.sales + 1
            elseif e.kind == "de" then
                s.deCount = s.deCount + 1
                s.deActual = s.deActual + (e.money or 0)
                s.deExpected = s.deExpected + (e.predicted or e.money or 0)
            end
        end
    end
    return s
end

---------------------------------------------------------------------------
-- Sales: read the auction house invoice of a mail as its money is taken (by any addon or the mail window)
---------------------------------------------------------------------------
local recent = {} -- mails already counted (taking a mail can fire both hooks)

local function CountSale(index)
    if not (GetInboxInvoiceInfo and GetInboxHeaderInfo and index) then return end
    local invoiceType, itemName = GetInboxInvoiceInfo(index)
    if invoiceType ~= "seller" then return end
    local _, _, _, subject, money, cod = GetInboxHeaderInfo(index)
    if not money or money <= 0 or (cod and cod > 0) then return end
    local key = tostring(subject) .. "|" .. money
    if recent[key] and GetTime() - recent[key] < 10 then return end
    recent[key] = GetTime()
    Ledger.Sale(itemName or subject, money)
end

ns.On("PLAYER_LOGIN", function()
    if type(TakeInboxMoney) == "function" then hooksecurefunc("TakeInboxMoney", function(i) ns.Safe("ledger sale", CountSale, i) end) end
    if type(AutoLootMailItem) == "function" then hooksecurefunc("AutoLootMailItem", function(i) ns.Safe("ledger sale", CountSale, i) end) end
end)
