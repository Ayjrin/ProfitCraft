-- ProfitCraft: "what to train first" glows + tooltips at profession trainers.
local _, ns = ...

local Trainer = { hooked = false }
ns.Trainer = Trainer

local rowHooked = setmetatable({}, { __mode = "k" })
local services, rankByRecipe = {}, {}
local dirty = true

local function IsProfessionTrainer()
    return IsTradeskillTrainer and IsTradeskillTrainer() or false
end

local function ServiceIndex(row)
    if row.GetElementData then
        local ok, data = pcall(row.GetElementData, row)
        if ok and type(data) == "table" then
            local index = data.skillIndex or data.index or data.serviceIndex
            if type(index) == "number" then return index end
        end
    end
    local id = row.GetID and row:GetID()
    if id and id > 0 then return id end
end

-- Works out which recipe a trainer service teaches.
local function ResolveRecipe(index, name)
    local itemID = GetTrainerServiceItemLink and ns.ItemIDFromLink(GetTrainerServiceItemLink(index))
    local spellID
    if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
        local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
        if ok and type(data) == "table" and type(data.id) == "number" then
            local kinds = Enum and Enum.TooltipDataType
            if kinds and data.type == kinds.Item then
                itemID = itemID or data.id
            elseif not kinds or data.type == kinds.Spell then
                spellID = data.id
            end
        end
    end

    local recipes = ns.db.recipes
    local function fits(rid) return recipes[rid] and (not itemID or recipes[rid].out == itemID) end

    if spellID and fits(spellID) then return spellID, itemID end
    if itemID then
        local list = ns.Data.RecipesByOutput(itemID)
        if list then
            for _, rid in ipairs(list) do
                if recipes[rid].name == name then return rid, itemID end
            end
            return list[1], itemID
        end
    end
    if name then
        local rid = ns.Data.RecipeByName(name)
        if rid and fits(rid) then return rid, itemID end
    end
    -- Not seen in the profession window yet: read it straight from the game.
    if spellID then
        local def = ns.Data.ReadSchematic(spellID)
        if def and def.out and (not itemID or def.out == itemID) then
            def.name = def.name or name
            recipes[spellID] = def
            ns.Data.MarkIndexDirty()
            return spellID, itemID
        end
    end
    return nil, itemID
end

local relaxed = false -- glows came from the low-skill fallback (see Engine:GlowRanks)

local function Recompute()
    dirty = false
    relaxed = false
    wipe(services)
    wipe(rankByRecipe)
    if not ns.IsReady() or not IsProfessionTrainer() or not GetNumTrainerServices then return end

    local candidates, learnedSomething = {}, false
    for i = 1, GetNumTrainerServices() do
        local name, _, kind = GetTrainerServiceInfo(i)
        if kind and kind ~= "header" then
            local rid, itemID = ResolveRecipe(i, name)
            services[i] = { rid = rid, kind = kind, name = name, item = itemID, cost = GetTrainerServiceCost(i) }
            if rid and kind == "used" and ns.Data.MarkKnown(rid) then learnedSomething = true end
            if rid and kind == "available" then candidates[#candidates + 1] = rid end
        end
    end
    if learnedSomething then
        ns.Engine:Invalidate() -- also re-runs Recompute via DataChanged
        dirty = true
    end

    local ranks, _, isRelaxed = ns.Engine:GlowRanks(candidates)
    for rid, rank in pairs(ranks) do rankByRecipe[rid] = rank end
    relaxed = isRelaxed
end

local function ShowTooltip(row)
    if not IsProfessionTrainer() then return end
    local index = ServiceIndex(row)
    local s = index and services[index]
    if not s then return end
    if s.rid then
        local rank = s.kind == "available" and rankByRecipe[s.rid] or nil
        ns.Display.ShowForRow(row, s.name, s.rid, {
            rank = rank,
            relaxed = rank and relaxed,
            trainCost = s.kind ~= "used" and s.cost or nil,
        })
    elseif s.item then
        local tt = GameTooltip
        if not tt:IsOwned(row) then
            tt:SetOwner(row, "ANCHOR_RIGHT")
            tt:AddLine(s.name, 1, 1, 1)
        end
        tt:AddLine(" ")
        tt:AddLine("|cffffd100ProfitCraft|r")
        tt:AddLine("Open this profession's window once so I can read this recipe's reagents.", 0.6, 0.6, 0.6, true)
        tt:Show()
    end
end

local function OnEnter(row) ns.Safe("trainer tooltip", ShowTooltip, row) end

local function OnLeave(row)
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function PaintRow(row)
    if not rowHooked[row] then
        rowHooked[row] = true
        row:HookScript("OnEnter", OnEnter)
        row:HookScript("OnLeave", OnLeave)
    end
    local index = ServiceIndex(row)
    local s = index and services[index]
    local rank = s and s.rid and s.kind == "available" and rankByRecipe[s.rid] or nil
    ns.Display.SetGlow(row, rank)
end

function Trainer.Paint()
    local box = ClassTrainerFrame and ClassTrainerFrame.ScrollBox
    if not box or not box:IsVisible() then return end
    -- a failed ranking still leaves every row hooked for tooltips
    if dirty then ns.Safe("trainer glows", Recompute) end
    box:ForEachFrame(PaintRow)
end

local function MarkDirty()
    dirty = true
    Trainer.Paint()
end

function Trainer.TryHook()
    if Trainer.hooked then return end
    local box = ClassTrainerFrame and ClassTrainerFrame.ScrollBox
    if not box or type(box.Update) ~= "function" then return end
    Trainer.hooked = true
    hooksecurefunc(box, "Update", Trainer.Paint)
    if type(ClassTrainerFrame_Update) == "function" then hooksecurefunc("ClassTrainerFrame_Update", MarkDirty) end
    ClassTrainerFrame:HookScript("OnShow", MarkDirty)
    MarkDirty()
end

ns.OnDataChanged(MarkDirty)
ns.On("ADDON_LOADED", Trainer.TryHook)
ns.On("TRAINER_SHOW", function()
    dirty = true
    C_Timer.After(0, function()
        Trainer.TryHook()
        Trainer.Paint()
    end)
end)
ns.On("TRAINER_UPDATE", function() C_Timer.After(0, MarkDirty) end)
