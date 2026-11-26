-- ProfitCraft: what this character can do right now: gold to spend, bag space, Enchanting, Arcane Salvager.
local _, ns = ...

local Profile = {}
ns.Profile = Profile

-- Arcane Salvager, from WoW Forever's own tables (build 1.60.1.71139 on wago.tools):
--   item 279985 (Enchanting 140), places a Salvager for 15 minutes next to a Campfire, 1-hour shared camping cooldown;
--   standing near it gives aura 1283701 "Boosted Disenchanting" ("chance of bonus disenchanting output is
--   increased"; the client doesn't say by how much). Disenchant is spell 13262 (3-second cast).
Profile.SALVAGER_ITEM = 279985
Profile.SALVAGER_AURA = 1283701
Profile.SALVAGER_SKILL = 140
Profile.DISENCHANT_SPELL = 13262

local BACKPACK, LAST_BAG = 0, 4

function Profile.Money() return (GetMoney and GetMoney()) or 0 end

-- Gold kept back for deposits, repairs and postage.
function Profile.Reserve()
    local pct = (ns.settings and ns.settings.reservePct) or ns.DEFAULTS.reservePct
    return math.floor(Profile.Money() * pct / 100)
end

-- What ProfitCraft may still spend: your gold above the reserve, and no more than what's left of the session cap.
function Profile.Budget()
    local free = math.max(0, Profile.Money() - Profile.Reserve())
    local cap = (ns.settings and ns.settings.sessionCap) or 0
    if cap > 0 then
        local spent = ns.Ledger and ns.Ledger.SessionSpent() or 0
        free = math.min(free, math.max(0, cap - spent))
    end
    return free
end

-- Free slots in ordinary bags (profession bags can't hold what we buy).
function Profile.FreeSlots()
    if not (C_Container and C_Container.GetContainerNumFreeSlots) then return 0 end
    local free = 0
    for bag = BACKPACK, LAST_BAG do
        local n, family = C_Container.GetContainerNumFreeSlots(bag)
        if n and (family == nil or family == 0) then free = free + n end
    end
    return free
end

function Profile.EnchantingSkill()
    return ns.Disenchant and ns.Disenchant.PlayerSkill() or nil
end

function Profile.HasSalvager() return ns.ItemCount(Profile.SALVAGER_ITEM) > 0 end

-- Can this character run Arcane Salvager plays (Enchanting 140 and a Salvager in the bags)?
function Profile.CanSalvage()
    local skill = Profile.EnchantingSkill()
    return skill ~= nil and skill >= Profile.SALVAGER_SKILL and Profile.HasSalvager()
end

-- Seconds until the camping cooldown is ready (0 = ready, nil = unknown).
function Profile.SalvagerCooldown()
    if not (C_Container and C_Container.GetItemCooldown) then return nil end
    local start, duration = C_Container.GetItemCooldown(Profile.SALVAGER_ITEM)
    if not start or start == 0 or not duration then return 0 end
    return math.max(0, start + duration - GetTime())
end

-- true / false when the game says whether "Boosted Disenchanting" is on you; nil when it won't say
-- (aura data can be withheld from addons in combat).
function Profile.SalvagerBuff()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, Profile.SALVAGER_AURA)
    if not ok then return nil end
    if issecretvalue and issecretvalue(aura) then return nil end
    return aura ~= nil
end

function Profile.InCombat() return InCombatLockdown and InCombatLockdown() or false end
