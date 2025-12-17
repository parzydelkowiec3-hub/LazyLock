if not LazyLock then LazyLock = {} end

LazyLock.LastConsumableCheck = 0

function LazyLock:CheckConsumables()
	-- Manual check only now
	LazyLock:Print("|cff71d5ffLazyLock:|r Checking Consumables...")


	-- Gather current buffs
	local currentBuffs = {}
	local i = 1
	while UnitBuff("player", i) do
		local buffName = LazyLock:GetBuffName("player", i)
		if buffName then
			currentBuffs[buffName] = true
		end
		i = i + 1
	end
	
	local required = LazyLock.Consumables


	for _, req in pairs(required) do
		local found = false
		if type(req.name) == "table" then
			for _, n in pairs(req.name) do
				if currentBuffs[n] then found = true break end
			end
		else
			if currentBuffs[req.name] then found = true end
		end
		
		if not found then
			LazyLock:Print("|cffff0000LazyLock:|r Missing |cff71d5ff["..req.display.."]|r")
		end
	end
	
	local hasMainHandEnchant, _, _, _, _, _ = GetWeaponEnchantInfo()
	if not hasMainHandEnchant then
		LazyLock:Print("|cffff0000LazyLock:|r Missing |cff71d5ff[Weapon Oil/Enchant]|r")
	end
end

function LazyLock:UseCooldowns()
	-- Trinkets (13 and 14)
	if not LazyLock.Settings["IsCasting"] then
		local start, duration, enable = GetInventoryItemCooldown("player", 13)
		if start == 0 and duration == 0 then
			UseInventoryItem(13)
		end
		local start, duration, enable = GetInventoryItemCooldown("player", 14)
		if start == 0 and duration == 0 then
			UseInventoryItem(14)
		end
		
		-- Racials
		local _, race = UnitRace("player")
		if race == "Orc" and not LazyLock:GetSpellCooldown("Blood Fury") then
			CastSpellByName("Blood Fury")
		elseif race == "Troll" and not LazyLock:GetSpellCooldown("Berserking") then
			CastSpellByName("Berserking")
		end
	end
end


function LazyLock:ExecuteStrategy(strategy)
    if not strategy then return false end
    
    -- If strategy is a string name (e.g. "BURST"), lookup the definition
    if type(strategy) == "string" then
        strategy = LazyLock.StrategyDefinitions[strategy]
    end
    
    if not strategy or type(strategy) ~= "table" then return false end

    for _, actionName in ipairs(strategy) do
        if LazyLock:TryAction(actionName) then
            return true
        end
    end
    return false
end

function LazyLock:Cast()
	-- Early exit checks - don't run algorithm if we can't cast
	
	-- 1. Check if player is dead
	if UnitIsDead("player") then return end
	
	-- 2. Check if player has a valid target
	if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then
		return
	end
	
	-- 3. Check if already casting (most important - prevents all spam)
	-- This includes both casting and channeling via SPELLCAST events
	if LazyLock.Settings["IsCasting"] then return end
	
	-- 4. Check if on taxi/flight path
	if UnitOnTaxi("player") then return end
	
	LazyLock:UseCooldowns()
	if LazyLock.Settings["CastCounter"] == nil then LazyLock.Settings["CastCounter"] = 0 end
	LazyLock.Settings["CastCounter"] = LazyLock.Settings["CastCounter"] + 1


	if not LazyLock:GetSpellCooldown("Death Coil") and not LazyLock.Settings["IsCasting"] then
		CastSpellByName("Death Coil")
        -- Death Coil is instant, but triggers GCD. Return true? 
        -- Actually, global GCD will block next cast anyway, but for safety:
		return
	end
	
	local tName = UnitName("target") or "Unknown"
	local strat = LazyLock:GetCombatStrategy(tName, LazyLock:GetGroupType())
	local ttd = LazyLock:GetTTD()

	-- Life Tap Logic
	-- Only tap if we are actively receiving healing (HoT) and need mana
    local currentMana = UnitMana("player")
    local maxMana = UnitManaMax("player")
    local manaPct = currentMana / maxMana * 100
	local hpPct = UnitHealth("player") / UnitHealthMax("player") * 100
	
    local ltHpCost, ltManaGain = LazyLock:GetLifeTapValues()
    local deficit = maxMana - currentMana
    
    -- Smart Check:
    -- 1. Must account for the FULL mana gain (don't waste hp on tapping for 10 mana).
    -- 2. Must "need" the mana (Deficit > ltManaGain).
    -- 3. Healing safety check (IsPlayerReceivingHealing).
    -- 4. HP Safety (>35%).
    
	if LazyLock:IsPlayerReceivingHealing(ltHpCost) 
	and (deficit >= ltManaGain) 
	and (hpPct > 35) then 
		LazyLock:PerformCast("Life Tap", "Healed & Mana Needed")
		return true
	end

    local casted = LazyLock:ExecuteStrategy(strat)
    if not casted then
    	-- Fallback if strategy is missing or empty?
    	LazyLock:ExecuteStrategy("NORMAL")
    end
	
    -- Fallback Shadow Bolt removed to prevent spam

end

-- Helper function to check if we should use Drain Soul for shard farming
function LazyLock:ShouldUseDrainSoul()
	if not LazyLockDB.drainSoulMode then return false end
	
	local hp = UnitHealth("target")
	local maxHp = UnitHealthMax("target")
	if not hp or not maxHp or maxHp == 0 then return false end
	
	local hpPercent = (hp / maxHp) * 100
	local drainSoulThreshold = 25  -- Use Drain Soul below 25% HP
	
	return hpPercent < drainSoulThreshold
end

-- Generic Helper to perform the cast and logging
function LazyLock:PerformCast(spell, reason)
	if LazyLock.Settings["IsCasting"] then return false end
	if LazyLock:GetSpellCooldown(spell) then return false end
	
	local msg = "|cffff0000[LL Debug]|r Casting "..spell
	if reason then msg = msg.." ("..reason..")" end
	LazyLock:Print(msg)
	
	CastSpellByName(spell)
	LazyLock.Settings[spell] = GetTime()
	return true
end

-- Generic Logic Handlers
-- Generic Logic Handlers
local function HandleDoT(actionObj, actionName)
    local spellName = actionName
	local checkName = actionName
	local refreshTime = 0
	
	-- Resolve dynamic properties if they exist
	if actionObj.resolveName then
		spellName, checkName = actionObj.resolveName()
	end
	
	if actionObj.refreshTime then
		refreshTime = actionObj.refreshTime
	end

	-- Unified Check: Recast if time remaining <= threshold 
	local remaining = LazyLock:GetDebuffTimeRemaining("target", checkName)
	
	if remaining <= refreshTime 
	and (GetTime() - (LazyLock.Settings[spellName] or 0) > 2) then
		local reason = nil
		if remaining > 0 then reason = "Renew: "..string.format("%.1f", remaining).."s" end
		return LazyLock:PerformCast(spellName, reason)
	end
	
	return false
end

local function HandleDirect(actionObj, actionName)
	-- Direct handlers now assume condition() checked "worth"
	local result = LazyLock:PerformCast(actionName)
	if result and actionName == "Searing Pain" then
		LazyLock:Print("|cffff0000[LL Debug]|r Fallback: Casting Searing Pain")
	end
	return result
end

-- Helper for common TTD check
local function IsWorth(spell, minTTD)
	-- Immunity Check
	local tName = UnitName("target")
	if tName and LazyLockDB.MobStats[tName] and LazyLockDB.MobStats[tName].immuneSpells and LazyLockDB.MobStats[tName].immuneSpells[spell] then
		return false
	end
	
	local ttd = LazyLock:GetTTD()
	if ttd > minTTD then return true end
	
	LazyLock:Print("|cffff0000[LL Debug]|r Skipping "..spell..": TTD "..string.format("%.1f", ttd).."s < Req "..minTTD.."s")
	return false
end


-- Action Definitions
local ActionHandlers = {
	["Drain Soul"] = {
		handler = function()
			return LazyLock:PerformCast("Drain Soul", "Shard")
		end,
		condition = function()
			return LazyLock:ShouldUseDrainSoul()
		end
	},
	
	["Curse"] = {
		handler = HandleDoT,
		resolveName = function()
			local spellName = LazyLockDB.defaultCurse or "Curse of Agony"
			local checkName = spellName
			if LazyLock.CurseData[spellName] and LazyLock.CurseData[spellName].check then
				checkName = LazyLock.CurseData[spellName].check
			end
			return spellName, checkName
		end,
		refreshTime = 3,
		condition = function() 
			local spell = LazyLockDB.defaultCurse or "Curse of Agony"
			return IsWorth(spell, 8) 
		end
	},
	
	["Immolate"] = { 
		handler = HandleDoT, 
		condition = function() return IsWorth("Immolate", 5) end 
	},
	
	["Corruption"] = { 
		handler = HandleDoT, 
		condition = function() return IsWorth("Corruption", 5) end 
	},
	
	["Siphon Life"] = { 
		handler = HandleDoT, 
		condition = function() 
			return LazyLock:KnowsSpell("Siphon Life") and IsWorth("Siphon Life", 6)
		end 
	},
	
	["Shadowburn"] = {
		handler = function()
			return LazyLock:PerformCast("Shadowburn")
		end,
		condition = function()
			if LazyLock:GetItemCount(6265) == 0 then return false end
			
			local ttd = LazyLock:GetTTD()
			local hp = UnitHealth("target")
			local maxHp = UnitHealthMax("target")
			if not maxHp or maxHp == 0 then maxHp = 100 end
			local hpPct = (hp / maxHp) * 100
			
			local playerHp = UnitHealth("player")
			local playerMax = UnitHealthMax("player")
			local playerPct = (playerHp / playerMax) * 100

			-- 1. PANIC MODE (Survival)
			-- If we are dying (< 30% HP), burn it to end the fight ASAP
			if playerPct < 30 then return true end

			-- 2. ABUNDANCE (Shard overflowing)
			if LazyLock:GetItemCount(6265) > 15 then 
				return (ttd < 15) or (hpPct < 25)
			end

			-- 3. EXECUTE (Kill Confirm)
			-- Relaxed threshold: 20% HP or dying in < 10s
			if ttd < 10 then return true end 
			if hpPct < 20 then return true end
			
			return false
		end
	},
	
	["Shadow Bolt"] = { 
		handler = HandleDirect, 
		condition = function() return IsWorth("Shadow Bolt", 0) end 
	},
	
	["Searing Pain"] = { 
		handler = HandleDirect, 
		condition = function() return IsWorth("Searing Pain", 0) end 
	},

	["Shoot"] = {
		handler = function()
			CastSpellByName("Shoot")
			LazyLock:Print("|cffff0000[LL Debug]|r Fallback: Wand")
			return true
		end,
		condition = function()
			return LazyLock.WandSlot 
			   and not IsAutoRepeatAction(LazyLock.WandSlot)
			   and not LazyLock.Settings["IsCasting"]
		end
	}
}

function LazyLock:TryAction(action)
	if LazyLock.Settings["IsCasting"] then return false end
	
	local actionObj = ActionHandlers[action]
	if actionObj then
		if actionObj.condition and not actionObj.condition() then
			return false
		end
		
		if actionObj.handler then
			return actionObj.handler(actionObj, action)
		end
	end
	return false
end
