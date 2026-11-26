-- ProfitCraft: the Work button, for everything away from the AH window. One press = one action:
--   * Mailbox open: take one auction house mail (purchases, sales money, expired auctions); keeps a bag slot free.
--   * Split or combine one essence (a play's conversions).
--   * Disenchant one item ProfitCraft bought for it (never soulbound gear, never equipment-set items, and only
--     unbound greens you didn't buy if you turn that on). Items bought for an Arcane Salvager run wait until the
--     Salvager's buff is on you: the button turns red and does nothing without it.
--   * Craft the play's recipe (the game's own "craft N", with the profession window open).
-- Casting and using items are protected actions, so the button is a SecureActionButton: on each press ProfitCraft
-- only fills in which item or spell the press is for (the same way TSM's Destroy button does), and the game does
-- the rest. While a disenchant is casting or its loot is pending, presses do nothing. Nothing changes in combat.
local _, ns = ...

local Work = {}
ns.Work = Work

local button, keyButton, status
local mailOpen = false
local forced = false
local pendingConvert -- { from, before, at }
local pendingMail    -- { at } until the inbox updates
local pendingCraft   -- { recipeID, left, at } while the casts of one press run
local lastPress = -math.huge
local PRESS_GAP = 0.3 -- presses closer together than this are treated as one

local function Name(id) return ns.ItemName(id) end
local function BagCount(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, false) or 0 end
    return ns.ItemCount(id)
end

---------------------------------------------------------------------------
-- What the next press does
---------------------------------------------------------------------------
local AH_SUBJECTS
local function IsAuctionMail(i)
    local _, _, _, subject, money, cod, _, itemCount, _, _, _, canReply, isGM = GetInboxHeaderInfo(i)
    if (cod or 0) > 0 or isGM then return false end
    if not ((money or 0) > 0 or (itemCount or 0) > 0) then return false end
    if GetInboxInvoiceInfo and GetInboxInvoiceInfo(i) then return true, itemCount or 0 end
    if canReply then return false end
    if not AH_SUBJECTS then
        AH_SUBJECTS = {}
        for _, key in ipairs({ "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT", "AUCTION_OUTBID_MAIL_SUBJECT",
            "AUCTION_WON_MAIL_SUBJECT", "AUCTION_SOLD_MAIL_SUBJECT" }) do
            local fmt = _G[key]
            if type(fmt) == "string" then AH_SUBJECTS[#AH_SUBJECTS + 1] = "^" .. fmt:gsub("%%s", ".+"):gsub("%%d", "%%d+") end
        end
    end
    for _, pattern in ipairs(AH_SUBJECTS) do
        if subject and subject:find(pattern) then return true, itemCount or 0 end
    end
    return false
end

-- Only when ProfitCraft is waiting on something: queued disenchants, conversions or a craft, or a purchase
-- made with it in the last 3 hours. Otherwise the mailbox is left to you.
local function Expecting()
    local c = ns.char
    if next(c.deQueue) or next(c.convert) or (c.craft and c.craft.count and c.craft.count > 0) then return true end
    local since = ns.Now() - 3 * 3600
    for i = #ns.db.ledger, 1, -1 do
        local e = ns.db.ledger[i]
        if e.t < since then break end
        if e.kind == "buy" then return true end
    end
    return false
end

local function MailStep(free)
    if not (mailOpen and GetInboxNumItems and GetInboxHeaderInfo) then return nil end
    if not forced and not Expecting() then return nil end
    local count, index, items = 0, nil, 0
    for i = 1, GetInboxNumItems() do
        local ok, n = IsAuctionMail(i)
        if ok then
            count = count + 1
            if not index then index, items = i, n end
        end
    end
    if not index then return nil end
    if items > 0 and free - items < 1 then
        return { kind = "locked", label = "Bags full: disenchant or post before taking more mail" }
    end
    return { kind = "mail", index = index, label = ("Take auction mail (%d left)"):format(count) }
end

local function ConvertStep(free)
    for from, n in pairs(ns.char.convert) do
        if n > 0 then
            local pair, role = ns.Essences.Pair(from)
            local need = role == "lesser" and 3 or 1
            if pair and BagCount(from) >= need then
                if role == "greater" and free < 1 then
                    return { kind = "locked", label = "Bags full: a split needs a free slot" }
                end
                local verb = role == "greater" and "Split" or "Combine"
                return { kind = "convert", item = from, label = ("%s %s (%d left)"):format(verb, Name(from), n) }
            end
        end
    end
end

local function InEquipmentSet(itemID)
    if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs) then return false end
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        for _, id in pairs(C_EquipmentSet.GetItemIDs(setID) or {}) do
            if id == itemID then return true end
        end
    end
    return false
end

-- The next item to disenchant: bag, slot, itemID, needsSalvager.
function Work.NextDisenchant()
    if not ns.Profile.EnchantingSkill() then return nil end
    if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not info.isLocked and not info.isBound then
                local bought = (ns.char.deQueue[id] or 0) > 0
                local anyGreen = ns.settings.deAny and info.quality == 2
                if (bought or anyGreen) and ns.Disenchant.Evaluate(id) and not InEquipmentSet(id) then
                    return bag, slot, id, bought and ns.char.salvager[id] or false
                end
            end
        end
    end
end

local function DisenchantStep(free)
    local bag, slot, id, needsSalvager = Work.NextDisenchant()
    if not bag then return nil end
    if needsSalvager and ns.Profile.SalvagerBuff() ~= true then
        return { kind = "locked", warn = true, label = "Salvager buff missing: stand next to your Arcane Salvager" }
    end
    if free < 1 then return { kind = "locked", label = "Bags full: post or sell something first" } end
    local left = 0
    for itemID, n in pairs(ns.char.deQueue) do if BagCount(itemID) > 0 then left = left + math.min(n, BagCount(itemID)) end end
    return { kind = "disenchant", bag = bag, slot = slot, itemID = id,
        label = ("Disenchant %s%s"):format(Name(id), left > 1 and (" (%d left)"):format(left) or "") }
end

local function CraftStep()
    local craft = ns.char.craft
    if not (craft and craft.count and craft.count > 0) then return nil end
    local r = ns.db.recipes[craft.recipeID]
    local name = r and r.name or ("recipe " .. craft.recipeID)
    local open = ProfessionsFrame and ProfessionsFrame:IsShown()
    local craftable = open and C_TradeSkillUI.GetCraftableCount and C_TradeSkillUI.GetCraftableCount(craft.recipeID) or 0
    if craftable and craftable > 0 then
        local n = math.min(craft.count, craftable)
        return { kind = "craft", recipeID = craft.recipeID, count = n, label = ("Craft %d %s"):format(n, name) }
    end
    if not open then return { kind = "locked", label = ("Open your profession window to craft %s"):format(name) } end
    return nil -- window open but no reagents yet: nothing to show
end

-- The next action: { kind = "mail"/"convert"/"disenchant"/"craft"/"locked"/"wait", label, ... } or nil.
function Work.NextStep()
    if ns.Profile.InCombat() then return { kind = "locked", label = "In combat" } end
    if ns.Telemetry.Busy() then return { kind = "wait", label = "Disenchanting..." } end
    if pendingConvert and GetTime() - pendingConvert.at < 2 then return { kind = "wait", label = "Converting..." } end
    if pendingMail and GetTime() - pendingMail.at < 3 then return { kind = "wait", label = "Taking mail..." } end
    if pendingCraft and GetTime() - pendingCraft.at < 8 then return { kind = "wait", label = "Crafting..." } end
    pendingMail, pendingCraft = nil, nil
    local free = ns.Profile.FreeSlots()
    local mail = MailStep(free)
    if mail and mail.kind == "mail" then return mail end
    return ConvertStep(free) or DisenchantStep(free) or mail or CraftStep()
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------
local function Paint()
    if not button then return end
    local step = Work.NextStep()
    local text = step and step.label or "Nothing to do"
    button:SetText(text)
    local fs = button:GetFontString()
    if fs then
        if step and step.warn then fs:SetTextColor(1, 0.3, 0.3)
        elseif step and (step.kind == "locked" or step.kind == "wait") then fs:SetTextColor(0.7, 0.7, 0.7)
        else fs:SetTextColor(1, 0.82, 0) end
    end
    status:SetText(ns.settings.dryRun and "|cffff9933Dry run is on: buying and posting are rehearsals.|r" or "")
    if not ns.Profile.InCombat() then
        local show = forced or (step ~= nil and not (step.kind == "locked" and step.label == "In combat"))
        button:SetShown(show)
    end
end

function Work.Refresh() ns.Debounce("work-paint", 0.1, function() ns.Safe("work button", Paint) end) end

local function PreClick(self, mouse)
    if ns.Profile.InCombat() then return end -- attributes can't change in combat; the press does nothing
    self:SetAttribute("type1", nil)
    self:SetAttribute("macrotext1", nil)
    if mouse ~= "LeftButton" then return end
    if GetTime() - lastPress < PRESS_GAP then return end
    local step = Work.NextStep()
    if not step then return end
    lastPress = GetTime()
    if step.kind == "mail" then
        pendingMail = { at = GetTime() }
        AutoLootMailItem(step.index)
    elseif step.kind == "convert" then
        pendingConvert = { from = step.item, before = BagCount(step.item), at = GetTime() }
        self:SetAttribute("type1", "macro")
        self:SetAttribute("macrotext1", "/use item:" .. step.item)
    elseif step.kind == "disenchant" then
        local spell = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ns.Profile.DISENCHANT_SPELL)
        if not spell then return end
        ns.Telemetry.Expect(step.bag, step.slot, step.itemID)
        self:SetAttribute("type1", "macro")
        self:SetAttribute("macrotext1", ("/cast %s\n/use %d %d"):format(spell, step.bag, step.slot))
    elseif step.kind == "craft" then
        pendingCraft = { recipeID = step.recipeID, left = step.count, at = GetTime() }
        C_TradeSkillUI.CraftRecipe(step.recipeID, step.count, {})
    end
end

-- The press is done: clear what it did, so a later press (e.g. in combat, when this can't be changed) can never
-- repeat it on whatever is in that bag slot by then.
local function PostClick(self)
    if not ns.Profile.InCombat() then
        self:SetAttribute("type1", nil)
        self:SetAttribute("macrotext1", nil)
    end
    Work.Refresh()
end

-- Each finished craft cast: count it, and queue the product for what it was made for.
local function CraftDone(spellID)
    local p, craft = pendingCraft, ns.char.craft
    if not (p and spellID == p.recipeID) then return end
    p.left, p.at = p.left - 1, GetTime()
    if p.left <= 0 then pendingCraft = nil end
    if not craft then return end
    craft.count = craft.count - 1
    local r = ns.db.recipes[p.recipeID]
    if r and r.out then
        if craft.disenchant then ns.char.deQueue[r.out] = (ns.char.deQueue[r.out] or 0) + 1
        else ns.char.toSell[r.out] = true end
    end
    if craft.count <= 0 then ns.char.craft = nil end
end

-- Scroll-down over the button presses its key twin (below), only while the cursor is on the button.
local function SetWheel(self, on)
    if ns.Profile.InCombat() then return end
    if on and ns.settings.wheel then
        SetOverrideBindingClick(self, true, "MOUSEWHEELDOWN", "ProfitCraftWorkKey", "LeftButton")
    else
        ClearOverrideBindings(self)
    end
end
Work.SetWheel = SetWheel

local function Build()
    button = CreateFrame("Button", "ProfitCraftWorkButton", UIParent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    button:SetSize(320, 30)
    local pos = ns.char.workPos
    if pos then button:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    else button:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180) end
    button:SetAttribute("useOnKeyDown", false) -- act on release only: one press = one action, from mouse, key or wheel
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("PreClick", PreClick)
    button:SetScript("PostClick", PostClick)
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not ns.Profile.InCombat() then self:StartMoving() end
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ns.char.workPos = { point, x, y }
    end)
    button:SetScript("OnEnter", function(self)
        SetWheel(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("ProfitCraft: Work", 1, 0.82, 0)
        GameTooltip:AddLine("Each press does one thing: take a mail, convert an essence, disenchant an item or craft.", 1, 1, 1, true)
        if ns.settings.wheel then GameTooltip:AddLine("Scroll down here to press it (zoom works everywhere else).", 0.7, 0.7, 0.7, true) end
        GameTooltip:AddLine("Shift-drag to move. /craftprofit work hides it.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        SetWheel(self, false)
        GameTooltip:Hide()
    end)
    button:SetScript("OnHide", function(self) SetWheel(self, false) end)
    status = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    status:SetPoint("TOP", button, "BOTTOM", 0, -2)
    button:Hide()
    Work.button = button

    -- The key twin: key bindings and scroll-down press this hidden button, which acts on key-down only (keys and
    -- the wheel always send a down; their release isn't registered). The visible button acts on mouse release.
    -- Either way one physical press is one action.
    keyButton = CreateFrame("Button", "ProfitCraftWorkKey", UIParent, "SecureActionButtonTemplate")
    keyButton:SetAttribute("useOnKeyDown", true)
    keyButton:RegisterForClicks("LeftButtonDown")
    keyButton:SetScript("PreClick", PreClick)
    keyButton:SetScript("PostClick", PostClick)
    keyButton:Hide()
    Work.keyButton = keyButton
end

function Work.Toggle()
    forced = not forced
    Work.Refresh()
    return forced
end

ns.On("PLAYER_LOGIN", function() if not button and ns.IsReady() then Build(); Work.Refresh() end end)
ns.On("MAIL_SHOW", function() mailOpen = true; Work.Refresh() end)
ns.On("MAIL_CLOSED", function() mailOpen = false; Work.Refresh() end)
ns.On("MAIL_INBOX_UPDATE", function() pendingMail = nil; Work.Refresh() end)
ns.On("UNIT_AURA", function(_, unit) if unit == "player" then Work.Refresh() end end)
ns.On("PLAYER_REGEN_ENABLED", function()
    -- if the cursor left the button during combat, the wheel binding couldn't be cleared then: do it now
    if button and not (button.IsMouseOver and button:IsMouseOver()) then ClearOverrideBindings(button) end
    Work.Refresh()
end)
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID) if unit == "player" then CraftDone(spellID) end end)
local function CraftStopped(_, unit, _, spellID)
    if unit == "player" and pendingCraft and spellID == pendingCraft.recipeID then pendingCraft = nil; Work.Refresh() end
end
ns.On("UNIT_SPELLCAST_FAILED", CraftStopped)
ns.On("UNIT_SPELLCAST_INTERRUPTED", CraftStopped)
ns.On("MAIL_SUCCESS", function() pendingMail = nil; Work.Refresh() end)
ns.On("MAIL_FAILED", function() pendingMail = nil; Work.Refresh() end)
ns.On("LOOT_CLOSED", Work.Refresh)
ns.On("UNIT_SPELLCAST_STOP", function(_, unit) if unit == "player" then Work.Refresh() end end)
ns.On("TRADE_SKILL_SHOW", Work.Refresh)
ns.On("TRADE_SKILL_CLOSE", Work.Refresh)
ns.On("BAG_UPDATE_DELAYED", function()
    if pendingConvert and BagCount(pendingConvert.from) < pendingConvert.before then
        local from = pendingConvert.from
        ns.char.convert[from] = math.max(0, (ns.char.convert[from] or 0) - 1)
        if ns.char.convert[from] == 0 then ns.char.convert[from] = nil end
        pendingConvert = nil
    end
    Work.Refresh()
end)
