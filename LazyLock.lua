local LazyLock = CreateFrame("Frame",nil,UIParent);
CreateFrame( "GameTooltip", "LazyLockTooltip", nil, "GameTooltipTemplate")
LazyLockTooltip:SetOwner( WorldFrame, "ANCHOR_NONE" )

LazyLock.Default = {
	["Curse of Agony"] = 0,
	["Corruption"] = 0,
	["Siphon Life"] = 0,
	["Immolate"] = 0,
	["IsCasting"] = false,
	["Curse of the Elements"] = 0,
	["Curse of Shadow"] = 0,
	["Curse of Tongues"] = 0,
	["Curse of Recklessness"] = 0,
	["Curse of Weakness"] = 0,
	["Curse of Doom"] = 0,
	["CastCounter"] = 0,
}

LazyLock.CurseData = {
	["Curse of Agony"] = { duration = 24, aliases = {"agony", "coa"}, check = "Curse of Agony" },
	["Curse of the Elements"] = { duration = 300, aliases = {"elements", "coe"}, check = "Curse of the Elements" },
	["Curse of Shadow"] = { duration = 300, aliases = {"shadow", "shadows", "cos"}, check = "Curse of Shadow" },
	["Curse of Tongues"] = { duration = 30, aliases = {"tongues", "cot"}, check = "Curse of Tongues" },
	["Curse of Recklessness"] = { duration = 120, aliases = {"recklessness", "cor"}, check = "Curse of Recklessness" },
	["Curse of Weakness"] = { duration = 120, aliases = {"weakness", "cow"}, check = "Curse of Weakness" },
	["Curse of Doom"] = { duration = 60, aliases = {"doom", "cod"}, check = "Curse of Doom" },
}

local eventsToRegister = {
	"ADDON_LOADED",
	"PLAYER_TARGET_CHANGED",
	"SPELLCAST_START",
	"SPELLCAST_STOP",
	"SPELLCAST_FAILED",
	"SPELLCAST_INTERRUPTED",
	"SPELLCAST_DELAYED",
	"SPELLCAST_CHANNEL_START",
	"SPELLCAST_CHANNEL_STOP",
	"SPELLCAST_CHANNEL_UPDATE",
	"CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
	"CHAT_MSG_SPELL_SELF_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
	"CHAT_MSG_COMBAT_HOSTILE_DEATH",
	"VARIABLES_LOADED"
}

function LazyLock:Initialize()
	if LazyLockDB == nil then
		LazyLockDB = {}
	end
	if LazyLockDB.checkConsumables == nil then
		LazyLockDB.checkConsumables = true
	end
	if LazyLockDB.defaultCurse == nil then
		LazyLockDB.defaultCurse = "Curse of Shadow"
	end
	if LazyLockDB.SpellStats == nil then
		LazyLockDB.SpellStats = {}
	end
	if LazyLockDB.MobStats == nil then
		LazyLockDB.MobStats = {}
	end
	if LazyLockDB.reportToSay == nil then
		LazyLockDB.reportToSay = false
	end
	if LazyLockDB.logging == nil then
		LazyLockDB.logging = false
	end
	if LazyLockDB.Log == nil then
		LazyLockDB.Log = {}
	end
	if LazyLockDB.drainSoulMode == nil then
		LazyLockDB.drainSoulMode = false
	end
	
	if LazyLock.Settings == nil then
		LazyLock.Settings = {}
		for k,v in pairs(LazyLock.Default) do
			LazyLock.Settings[k] = v
		end
	end
	-- Print Status Report
	local drainStatus = LazyLockDB.drainSoulMode and "|cff00ff00ON|r" or "|cffff0000OFF|r"
	local logStatus = LazyLockDB.logging and "|cff00ff00ON|r" or "|cffff0000OFF|r"
	
	LazyLock:Print("LazyLock loaded. Type /ll help for commands.")
	LazyLock:Print("Status: Drain Soul Mode ["..drainStatus.."] | Logging ["..logStatus.."]")

	-- Find Wand Slot (for IsAutoRepeatAction)
	LazyLock.WandSlot = nil
	for i = 1, 120 do
		if IsAttackAction(i) then
			-- Generic attack is usually slot 1, we want Shoot
			-- Check texture
			local texture = GetActionTexture(i)
			if texture and string.find(texture, "Ability_ShootWand") then
				LazyLock.WandSlot = i
				break
			end
		end
	end

	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	LazyLock:Print("LazyLock: Variables Loaded.")
end

LazyLock.TargetTracker = { name = nil, startTime = 0, damageDone = 0, hpHistory = {}, spells = {} }
LazyLock.LastTargetTracker = { name = nil, startTime = 0, damageDone = 0, spells = {} }
LazyLock.LastConsumableCheck = 0

function LazyLock:Print(msg)
	if not msg then return end
	if LazyLockDB and LazyLockDB.Log and LazyLockDB.logging then
		table.insert(LazyLockDB.Log, date("%c")..": "..tostring(msg))
	end
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end


function LazyLock:GetPotentialMana()
    local current = UnitMana("player")
    local max = UnitManaMax("player")
    local deficit = max - current
    
    -- Life Tap Potential (Health > 50%)
    local hp = UnitHealth("player")
    local hpMax = UnitHealthMax("player")
    local tapPotential = 0
    
    if (hp / hpMax) > 0.5 then
        -- Rough estimate: 1 Tap ~ 400-500 mana depending on gear/talents
        -- Let's conserve and say we can safely tap twice if > 50% HP
        tapPotential = 800
    end
    
    -- Check for Mana Potions (Simple ID check for Major/Superior)
    -- Major: 13444, Superior: 13443, Combat: 22832
    local potionPotential = 0
    if LazyLock:GetItemCount(13444) > 0 or LazyLock:GetItemCount(13443) > 0 or LazyLock:GetItemCount(22832) > 0 then
         if ShowCooldown and GetContainerItemCooldown then
             -- We'd check CD here ideally, but for now let's assume if we HAVE it, we count it as "reserve"
             potionPotential = 1500
         else
             potionPotential = 1500
         end
    end
    
    -- Healthstones/Whipper Root (Act as mana via Life Tap)
    -- Major HS: 19012
    if LazyLock:GetItemCount(19012) > 0 then
        -- 1 HS = ~1200 HP = ~1200 Mana via Taps
        tapPotential = tapPotential + 1000
    end
    
    return current + tapPotential + potionPotential
end

function LazyLock:GetItemCount(itemID)
	local total = 0

	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			if link then
				-- VANILLA WAY (Lua 5.0)
				local _, _, id = string.find(link, "item:(%d+)")
				id = tonumber(id)

				if id == itemID then
					local _, count = GetContainerItemInfo(bag, slot)
					total = total + (count or 1)
				end
			end
		end
	end

	return total
end

function LazyLock:UpdateMobStats(name, duration, maxHP)
	local gType = LazyLock:GetGroupType()
	
	if not LazyLockDB.MobStats[name] then
		LazyLockDB.MobStats[name] = { maxHP = maxHP, solo = nil, party = nil, raid = nil }
	end
	
	if LazyLockDB.MobStats[name].count or (LazyLockDB.MobStats[name][gType] and not LazyLockDB.MobStats[name][gType].history) then 
		LazyLockDB.MobStats[name] = { maxHP = maxHP } 
	end
	
	if not LazyLockDB.MobStats[name][gType] then
		LazyLockDB.MobStats[name][gType] = { count = 0, avgTTD = duration, history = {} }
	end
	
	local m = LazyLockDB.MobStats[name][gType]
	m.count = m.count + 1
	
	if not m.history then m.history = {} end
	table.insert(m.history, duration)
	if table.getn(m.history) > 50 then
		table.remove(m.history, 1) 
	end
	
	m.avgTTD = (m.avgTTD * 0.7) + (duration * 0.3)
	
	-- Update maxHP and calculate strategy
	LazyLockDB.MobStats[name].maxHP = maxHP
	
	-- Calculate and save strategy
	local strategy = LazyLock:GetCombatStrategy(name, gType)
	LazyLockDB.MobStats[name].strategy = strategy
	LazyLockDB.MobStats[name][gType].strategy = strategy
	
	LazyLock:Print("|cffff0000[LL Debug]|r Saved MobStats for "..name..": TTD="..string.format("%.1f", duration).."s, Strategy="..strategy)
end

function LazyLock:AnalyzeHistory(name, gType)
	LazyLock:Print("|cffff0000[LL Debug]|r Analyzing history for "..name.." in "..gType)
	local m = nil
	if LazyLockDB.MobStats and LazyLockDB.MobStats[name] then
		m = LazyLockDB.MobStats[name][gType]
	end
	m = m or { count = 0, avsgTTD = duration, history = {} }
	if not m or not m.history or table.getn(m.history) == 0 then return nil end
	
	local sorted = {}
	for _, v in pairs(m.history) do table.insert(sorted, v) end
	table.sort(sorted)
	
	local count = table.getn(sorted)
	local index = math.floor(count * 0.2)
	if index < 1 then index = 1 end
	
	return sorted[index]
end

function LazyLock:HasDebuff(unit, name)
	local i = 1
	while UnitDebuff(unit, i) do
		LazyLockTooltip:ClearLines()
		LazyLockTooltip:SetUnitDebuff(unit, i)
		local debuffName = LazyLockTooltipTextLeft1:GetText()
		if debuffName then
			if string.find(string.lower(debuffName), string.lower(name)) then
				LazyLock:Print("|cffff0000[LL Debug]|r Found debuff "..name.." on "..unit)
				return true
			end
		end
		i = i + 1
	end
	LazyLock:Print("|cffff0000[LL Debug]|r No debuff "..name.." on "..unit)
	return false
end

function LazyLock:GetDebuffTimeRemaining(unit, name)
	local i = 1
	while UnitDebuff(unit, i) do
		LazyLockTooltip:ClearLines()
		LazyLockTooltip:SetUnitDebuff(unit, i)
		local debuffName = LazyLockTooltipTextLeft1:GetText()
		if debuffName and string.find(string.lower(debuffName), string.lower(name)) then
			-- Get time remaining (texture, stacks, debuffType, duration, timeLeft)
			local _, _, _, _, timeLeft = UnitDebuff(unit, i)
			if timeLeft and timeLeft > 0 then
				local remaining = timeLeft - GetTime()
				return remaining > 0 and remaining or 0
			end
			return 0
		end
		i = i + 1
	end
	return 0
end

function LazyLock:GetCombatStrategy(name, gType)
	local safeTTD = LazyLock:AnalyzeHistory(name, gType)
	if not safeTTD then return "NORMAL" end 
	
	if safeTTD < 10 then return "BURST" end
	if safeTTD > 30 then return "LONG" end
	return "NORMAL"
end

function LazyLock:GetGroupType()
	if GetNumRaidMembers() > 0 then return "raid" end
	if GetNumPartyMembers() > 0 then return "party" end
	return "solo"
end

function LazyLock:RecordDamage(mob, spell, damage)
	-- Update Global Damage Tracker in MobStats
	if not mob then mob = UnitName("target") end
	if not mob then return end
	
	if not LazyLockDB.MobStats[mob] then
		LazyLockDB.MobStats[mob] = { maxHP = 0 }
	end
	
	local ms = LazyLockDB.MobStats[mob]
	if not ms.session then ms.session = { damage = 0, spells = {}, startTime = GetTime() } end
	
	ms.session.damage = ms.session.damage + damage
	if not ms.session.spells[spell] then ms.session.spells[spell] = 0 end
	ms.session.spells[spell] = ms.session.spells[spell] + damage
	
	-- Update SpellStats (Global)
	if not LazyLockDB.SpellStats then
		LazyLockDB.SpellStats = {}
	end
	if not LazyLockDB.SpellStats[spell] then
		LazyLockDB.SpellStats[spell] = { count = 0, total = 0, avg = 0 }
	end
	
	local s = LazyLockDB.SpellStats[spell]
	s.count = s.count + 1
	s.total = s.total + damage
	s.avg = s.total / s.count
end

function LazyLock:UpdateTargetTracker(spell, damage)
	-- Keep TargetTracker for TTD/HP logic, but use RecordDamage for accounting
	LazyLock.TargetTracker.damageDone = LazyLock.TargetTracker.damageDone + damage
	if not LazyLock.TargetTracker.spells[spell] then LazyLock.TargetTracker.spells[spell] = 0 end
	LazyLock.TargetTracker.spells[spell] = LazyLock.TargetTracker.spells[spell] + damage
end



function LazyLock:GetBuffName(unit, index)
	LazyLockTooltip:ClearLines()
	LazyLockTooltip:SetUnitBuff(unit, index)
	local buffName = LazyLockTooltipTextLeft1:GetText()
	return buffName
end

function LazyLock:ExportStats()
	LazyLock:Print("LazyLock Stats Export (Spell, Count, Total, Avg):")
	for k, v in pairs(LazyLockDB.SpellStats) do
		LazyLock:Print(k..", "..v.count..", "..v.total..", "..string.format("%.1f", v.avg))
	end
	LazyLock:Print("LazyLock Mob Strategy (Name [Type], AvgTTD, Strategy):")
	for k, v in pairs(LazyLockDB.MobStats) do
		if v.solo then 
			local strat = LazyLock:GetCombatStrategy(k, "solo")
			LazyLock:Print(k.." [solo], "..string.format("%.1f", v.solo.avgTTD)..", "..strat) 
		end
		if v.party then 
			local strat = LazyLock:GetCombatStrategy(k, "party")
			LazyLock:Print(k.." [party], "..string.format("%.1f", v.party.avgTTD)..", "..strat) 
		end
		if v.raid then 
			local strat = LazyLock:GetCombatStrategy(k, "raid")
			LazyLock:Print(k.." [raid], "..string.format("%.1f", v.raid.avgTTD)..", "..strat) 
		end
	end
end

function LazyLock:CheckState()
	local status = "Active"
	if not LazyLockDB then status = "Error: No DB" end
	if not LazyLock.Settings then status = "Error: No Settings" end
	return status
end

function LazyLock:Report(toChat, toSay)
	-- Try current target first, fall back to last target
	local t = LazyLock.TargetTracker
	local usingBackup = false
	
	if not t.name or t.damageDone == 0 then
		t = LazyLock.LastTargetTracker
		usingBackup = true
	end
	
	-- Verify we haven't reported this fallback already
	if usingBackup and LazyLock.LastTargetTracker.reported then return end
	
	if not t.name or t.damageDone == 0 then
		if toChat and not usingBackup then DEFAULT_CHAT_FRAME:AddMessage("LazyLock: No recent combat data.") end
		return
	end
	
	-- Try to get accurate data from MobStats.session
	local totalDmg = t.damageDone
	local spellBreakdown = t.spells
	
	if LazyLockDB.MobStats[t.name] and LazyLockDB.MobStats[t.name].session then
		totalDmg = LazyLockDB.MobStats[t.name].session.damage
		spellBreakdown = LazyLockDB.MobStats[t.name].session.spells
	end
	
	local strat = t.strategy or "Unknown"
	local state = LazyLock:CheckState()
	local msg = "LazyLock ["..state.."]: Killed "..t.name.." ("..strat.."). Total: "..totalDmg.."."
	
	local breakdown = ""
	for spell, dmg in pairs(spellBreakdown) do
		breakdown = breakdown.." ["..spell..": "..dmg.."]"
	end
	
	-- Clear Session Data
	if LazyLockDB.MobStats[t.name] then
		LazyLockDB.MobStats[t.name].session = nil
	end
	
	local output = msg..breakdown
	
	if toChat then
		LazyLock:Print("|cff00ff00"..output.."|r")
	end
	
	if toSay then
		SendChatMessage(output, "SAY")
	end
	
	-- Mark as reported to prevent spam
	if usingBackup then 
		LazyLock.LastTargetTracker.reported = true 
	end
end

function LazyLock:CheckConsumables()
	-- Only check if enabled
	if not LazyLockDB.checkConsumables then return end
	
	-- Anti-spam throttle (3 seconds)
	if LazyLock.LastConsumableCheck and (GetTime() - LazyLock.LastConsumableCheck) < 3 then return end
	LazyLock.LastConsumableCheck = GetTime()

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
	
	local required = {
		{ name = "Elixir of Shadow Power", display = "Elixir of Shadow Power" },
		{ name = "Greater Arcane Elixir", display = "Greater Arcane Elixir" },
		{ name = "Dreamshard Elixir", display = "Dreamshard Elixir" }, 
		{ name = "Juju Guile", display = "Juju Guile" },
		{ name = {"Infallible Mind", "Arcane Brilliance", "Arcane Intellect"}, display = "Intellect Buff" }, 
		{ name = {"Power Word: Fortitude", "Prayer of Fortitude"}, display = "Fortitude" },
		{ name = {"Mark of the Wild", "Gift of the Wild"}, display = "MotW" },
		{ name = {"Blessing of Kings", "Greater Blessing of Kings"}, display = "Kings" },
		{ name = {"Blessing of Salvation", "Greater Blessing of Salvation"}, display = "Salvation" },
	}

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

function LazyLock:CurseSlashHandler(msg)
	msg = string.lower(msg)
	local found = false
	for realName, data in pairs(LazyLock.CurseData) do
		if string.lower(realName) == msg then
			LazyLockDB.defaultCurse = realName
			found = true
			break
		else
			for _, alias in pairs(data.aliases) do
				if alias == msg then
					LazyLockDB.defaultCurse = realName
					found = true
					break
				end
			end
		end
		if found then break end
	end
	
	if found then
		LazyLock:Print("LazyLock: Default curse set to |cff71d5ff["..LazyLockDB.defaultCurse.."]|r")
	else
		LazyLock:Print("LazyLock: Unknown curse. Available: agony, elements, shadow, tongues, recklessness, weakness, doom.")
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
	local manaPct = UnitMana("player") / UnitManaMax("player") * 100
	local hpPct = UnitHealth("player") / UnitHealthMax("player") * 100
	
	-- 1. Emergency Life Tap (Any strategy)
	-- If we have less than 20% mana and are not critical on HP (>35%), we MUST tap to continue fighting
	if (manaPct < 20) and (hpPct > 35) then 
		if not LazyLock.Settings["IsCasting"] then
			LazyLock:Print("|cffff0000[LL Debug]|r Emergency Life Tap (Low Mana)")
			CastSpellByName("Life Tap")
			return true
		end
	end

	-- 2. Sustain Life Tap (NORMAL/LONG only)
	-- Tap earlier (<60% mana) if we are very healthy (>80% HP) to avoid running dry later
	if strat ~= "BURST" and (manaPct < 60) and (hpPct > 80) then
		 if not LazyLock.Settings["IsCasting"] then
			-- LazyLock:Print("|cffff0000[LL Debug]|r Sustain Life Tap (Healthy)") -- Optional debug
			CastSpellByName("Life Tap")
			return true
		end
	end

    local casted = false
	if strat == "BURST" then
		casted = self:CastBurst()
	elseif strat == "NORMAL" then
		casted = self:CastNormal()
	elseif strat == "LONG" then
	    casted = self:CastLong()
	else
        -- Fallback to LONG or NORMAL if unknown
        casted = self:CastNormal()
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

function LazyLock:CastBurst()
	-- Drain Soul for shard collection (only if mode enabled)
	if LazyLock:ShouldUseDrainSoul() 
	and not LazyLock:GetSpellCooldown("Drain Soul") 
	and not LazyLock.Settings["IsCasting"] then
		LazyLock:Print("|cffff0000[LL Debug]|r Casting Drain Soul for shard")
		CastSpellByName("Drain Soul")
		return true
	end
	
	if LazyLock:GetItemCount(6265) > 0 and not LazyLock:GetSpellCooldown("Shadowburn") and not LazyLock.Settings["IsCasting"] then
		CastSpellByName("Shadowburn")
		return true
	end
	
	if not LazyLock.Settings["IsCasting"] and not LazyLock:GetSpellCooldown("Searing Pain") then
		CastSpellByName("Searing Pain")
		return true
	end
    return false
end

function LazyLock:CastNormal()
	LazyLock:Print("|cffff0000[LL Debug]|r Entering CastNormal")
	-- Drain Soul for shard collection (only if mode enabled)
	if LazyLock:ShouldUseDrainSoul() 
	and not LazyLock:GetSpellCooldown("Drain Soul") 
	and not LazyLock.Settings["IsCasting"] then
		LazyLock:Print("|cffff0000[LL Debug]|r Casting Drain Soul for shard")
		CastSpellByName("Drain Soul")
		return true
	end
	
	-- Curse Logic (Added to Normal Mode)
	local curseName = LazyLockDB.defaultCurse or "Curse of Agony"
	local checkName = curseName
	if LazyLock.CurseData[curseName] and LazyLock.CurseData[curseName].check then
		checkName = LazyLock.CurseData[curseName].check
	end
	
	-- Dynamic Curse (defaultCurse) - Renew if < 3s remaining
	local remaining = LazyLock:GetDebuffTimeRemaining("target", checkName)
	local cdVal = LazyLock:GetSpellCooldown(curseName)
	local isCastingVal = LazyLock.Settings["IsCasting"]
	local isWorthVal = LazyLock:IsWorthCasting(curseName)
	local timerVal = (GetTime() - (LazyLock.Settings[curseName] or 0)) 
	
	-- DEBUG LOGGING FOR CURSE (NORMAL)
	LazyLock:Print("|cffff0000[LL Debug]|r Eval Curse (Normal): "..curseName.." Check: "..checkName.." Rem: "..string.format("%.1f", remaining).." CD: "..tostring(cdVal).." Casting: "..tostring(isCastingVal).." Worth: "..tostring(isWorthVal).." Timer: "..string.format("%.1f", timerVal))

	if remaining < 3 
	and not cdVal 
	and not isCastingVal 
	and isWorthVal 
	and (timerVal > 2) then
		LazyLock:Print("|cffff0000[LL Debug]|r Renewing "..curseName.." (remaining: "..string.format("%.1f", remaining).."s)")
		CastSpellByName(curseName)
		LazyLock.Settings[curseName] = GetTime()
		return true
	end
	
	-- Immolate Check with logging
	local hasImmolate = LazyLock:HasDebuff("target", "Immolate")
	LazyLock:Print("|cffff0000[LL Debug]|r " .. (hasImmolate and "Found" or "No") .. " debuff Immolate on target")
	
	if not hasImmolate
	and not LazyLock:GetSpellCooldown("Immolate") and not LazyLock.Settings["IsCasting"] and LazyLock:IsWorthCasting("Immolate") 
	and (GetTime() - (LazyLock.Settings["Immolate"] or 0) > 2) then
		CastSpellByName("Immolate")
		LazyLock.Settings["Immolate"] = GetTime() 
		return true
	end
	
	-- Corruption Check with detailed logging
	local hasCorruption = LazyLock:HasDebuff("target", "Corruption")
	LazyLock:Print("|cffff0000[LL Debug]|r " .. (hasCorruption and "Found" or "No") .. " debuff Corruption on target")
	
	if hasCorruption then
		-- Skip - already has debuff
	elseif LazyLock:GetSpellCooldown("Corruption") then
		LazyLock:Print("|cffff0000[LL Debug]|r Skipping Corruption: on cooldown")
	elseif LazyLock.Settings["IsCasting"] then
		LazyLock:Print("|cffff0000[LL Debug]|r Skipping Corruption: already casting")
	elseif (GetTime() - (LazyLock.Settings["Corruption"] or 0) <= 2) then
		LazyLock:Print("|cffff0000[LL Debug]|r Skipping Corruption: cast timer not expired")
	elseif LazyLock:IsWorthCasting("Corruption") then
		-- All conditions met, cast it
		LazyLock:Print("|cffff0000[LL Debug]|r Casting Corruption (NORMAL mode)")
		CastSpellByName("Corruption")
		LazyLock.Settings["Corruption"] = GetTime()
		return true
	end
	
	if LazyLock:GetItemCount(6265) > 0 and not LazyLock:GetSpellCooldown("Shadowburn") and not LazyLock.Settings["IsCasting"] and LazyLock:IsWorthCasting("Shadowburn") then
		CastSpellByName("Shadowburn")
		return true
	end
	
	-- Filler: Shadow Bolt (with Immunity Check)
	if LazyLock:IsWorthCasting("Shadow Bolt") then
		if not LazyLock.Settings["IsCasting"] then
			CastSpellByName("Shadow Bolt")
			LazyLock:Print("|cffff0000[LL Debug]|r Casting Shadow Bolt")
			return true
		end
	end
	
	-- Fallback 1: Searing Pain
	if LazyLock:IsWorthCasting("Searing Pain") and not LazyLock:GetSpellCooldown("Searing Pain") then
		if not LazyLock.Settings["IsCasting"] then
			CastSpellByName("Searing Pain")
			LazyLock:Print("|cffff0000[LL Debug]|r Fallback: Casting Searing Pain")
			return true
		end
	end

	-- Fallback 2: Wand (Shoot)
	if LazyLock.WandSlot and not IsAutoRepeatAction(LazyLock.WandSlot) then
		if not LazyLock.Settings["IsCasting"] then
			CastSpellByName("Shoot")
			LazyLock:Print("|cffff0000[LL Debug]|r Fallback: Wand")
			return true
		end
	end
	
    return false
end

function LazyLock:CastLong()
	LazyLock:Print("|cffff0000[LL Debug]|r Entering CastLong")
	-- Drain Soul for shard collection (only if mode enabled)
	if LazyLock:ShouldUseDrainSoul() 
	and not LazyLock:GetSpellCooldown("Drain Soul") 
	and not LazyLock.Settings["IsCasting"] then
		LazyLock:Print("|cffff0000[LL Debug]|r Casting Drain Soul for shard")
		CastSpellByName("Drain Soul")
		return true
	end
	
	local curseName = LazyLockDB.defaultCurse or "Curse of Agony"
	local checkName = curseName
	if LazyLock.CurseData[curseName] and LazyLock.CurseData[curseName].check then
		checkName = LazyLock.CurseData[curseName].check
	end

	
	-- Dynamic Curse (defaultCurse) - Renew if < 3s remaining
	local remaining = LazyLock:GetDebuffTimeRemaining("target", checkName)
	local cdVal = LazyLock:GetSpellCooldown(curseName)
	local isCastingVal = LazyLock.Settings["IsCasting"]
	local isWorthVal = LazyLock:IsWorthCasting(curseName)
	local timerVal = (GetTime() - (LazyLock.Settings[curseName] or 0)) 
	
	-- DEBUG LOGGING FOR CURSE
	LazyLock:Print("|cffff0000[LL Debug]|r Eval Curse: "..curseName.." Check: "..checkName.." Rem: "..string.format("%.1f", remaining).." CD: "..tostring(cdVal).." Casting: "..tostring(isCastingVal).." Worth: "..tostring(isWorthVal).." Timer: "..string.format("%.1f", timerVal))

	if remaining < 3 
	and not cdVal 
	and not isCastingVal 
	and isWorthVal 
	and (timerVal > 2) then
		LazyLock:Print("|cffff0000[LL Debug]|r Renewing "..curseName.." (remaining: "..string.format("%.1f", remaining).."s)")
		CastSpellByName(curseName)
		LazyLock.Settings[curseName] = GetTime()
		return true
	end

	-- Curse of Agony - Renew if < 3s remaining
	local coaRemaining = LazyLock:GetDebuffTimeRemaining("target", "Curse of Agony")
	if coaRemaining < 3 
	and not LazyLock:GetSpellCooldown("Curse of Agony") 
	and not LazyLock.Settings["IsCasting"] 
	and LazyLock:IsWorthCasting("Curse of Agony") 
	and (GetTime() - (LazyLock.Settings["Curse of Agony"] or 0) > 2) then
		LazyLock:Print("|cffff0000[LL Debug]|r Renewing Curse of Agony (remaining: "..string.format("%.1f", coaRemaining).."s)")
		CastSpellByName("Curse of Agony")
		LazyLock.Settings["Curse of Agony"] = GetTime()
		return true
	end
	
	local hasSiphon = LazyLock:HasDebuff("target", "Siphon Life")
	-- LazyLock:Print("|cffff0000[LL Debug]|r " .. (hasSiphon and "Found" or "No") .. " debuff Siphon Life on target") -- Uncomment if needed, usually spammy

	if not hasSiphon
	and not LazyLock:GetSpellCooldown("Siphon Life") 
	and not LazyLock.Settings["IsCasting"] 
	and LazyLock:IsWorthCasting("Siphon Life") 
	and (GetTime() - (LazyLock.Settings["Siphon Life"] or 0) > 2) then
		LazyLock:Print("|cffff0000[LL Debug]|r Casting Siphon Life")
		CastSpellByName("Siphon Life")
		LazyLock.Settings["Siphon Life"] = GetTime()
		return true
	end
	
	if not LazyLock:HasDebuff("target", "Corruption") 
	and not LazyLock:GetSpellCooldown("Corruption") 
	and not LazyLock.Settings["IsCasting"] 
	and LazyLock:IsWorthCasting("Corruption") 
	and (GetTime() - (LazyLock.Settings["Corruption"] or 0) > 2) then
		LazyLock:Print("|cffff0000[LL Debug]|r Casting Corruption")
		CastSpellByName("Corruption")
		LazyLock.Settings["Corruption"] = GetTime()
		return true
	end
	
	if not LazyLock:HasDebuff("target", "Immolate") 
	and not LazyLock:GetSpellCooldown("Immolate") 
	and not LazyLock.Settings["IsCasting"] 
	and LazyLock:IsWorthCasting("Immolate") 
	and (GetTime() - (LazyLock.Settings["Immolate"] or 0) > 2) then
		CastSpellByName("Immolate")
		LazyLock.Settings["Immolate"] = GetTime()
		return true
	end
	
	-- Shadowburn Execute (if all other dots are fine)
	-- We don't require ALL dots, just that we are not busy casting something else
	if LazyLock:GetItemCount(6265) > 0 and not LazyLock:GetSpellCooldown("Shadowburn") 
	and not LazyLock.Settings["IsCasting"] and LazyLock:IsWorthCasting("Shadowburn") then
		 CastSpellByName("Shadowburn")
		 return true
	end
	
	-- Filler: Shadow Bolt (with Immunity Check)
	if LazyLock:IsWorthCasting("Shadow Bolt") then
		if not LazyLock.Settings["IsCasting"] then
			CastSpellByName("Shadow Bolt")
			LazyLock:Print("|cffff0000[LL Debug]|r Casting Shadow Bolt (Filler)")
			return true
		end
	end
	
	-- Fallback 1: Searing Pain
	if LazyLock:IsWorthCasting("Searing Pain") and not LazyLock:GetSpellCooldown("Searing Pain") then
		if not LazyLock.Settings["IsCasting"] then
			CastSpellByName("Searing Pain")
			LazyLock:Print("|cffff0000[LL Debug]|r Fallback: Casting Searing Pain")
			return true
		end
	end

	-- Fallback 2: Wand (Shoot)
	if LazyLock.WandSlot and not IsAutoRepeatAction(LazyLock.WandSlot) then
		if not LazyLock.Settings["IsCasting"] then
			CastSpellByName("Shoot")
			LazyLock:Print("|cffff0000[LL Debug]|r Fallback: Wand")
			return true
		end
	end
	
    return false
end

function LazyLock:GetSpellCooldown(spellName)
    local spellID = 1
    local spell = GetSpellName(spellID, BOOKTYPE_SPELL)

    while spell do
        if spell == spellName then
            local start, duration = GetSpellCooldown(spellID, BOOKTYPE_SPELL)
            if duration and duration > 0 then
                return true
            else
                return false
            end
        end
        spellID = spellID + 1
        spell = GetSpellName(spellID, BOOKTYPE_SPELL)
    end
    return false
end	

function LazyLock:GetTTD()
	if not UnitExists("target") or UnitIsDead("target") then return 999 end
	
	local currentHP = UnitHealth("target")
	local maxHP = UnitHealthMax("target")
	if not maxHP or maxHP == 0 then maxHP = 100 end
	
	local now = GetTime()
	
	-- Track HP changes over time
	if not LazyLock.TargetTracker.lastHP then
		LazyLock.TargetTracker.lastHP = currentHP
		LazyLock.TargetTracker.lastUpdate = now
	end
	
	-- Update tracking every 1 second
	if now - LazyLock.TargetTracker.lastUpdate > 1 then
		LazyLock.TargetTracker.lastHP = currentHP
		LazyLock.TargetTracker.lastUpdate = now
		LazyLock:Print("|cffff0000[LL Debug]|r Updated lastHP to "..currentHP)
	end
	
	-- Calculate actual HP lost (not percentage!)
	local startHP = (LazyLock.TargetTracker.startHP / 100) * maxHP
	local hpLost = startHP - currentHP
	local timeElapsed = now - LazyLock.TargetTracker.startTime
	
	LazyLock:Print("|cffff0000[LL Debug]|r HP lost: "..tostring(hpLost).." Time elapsed: "..tostring(timeElapsed))
	
	-- Stabilization: If < 5s elapsed or no damage, return 999 (or predicted)
	if timeElapsed < 5 or hpLost <= 0 then 
		if LazyLock.TargetTracker.predictedTTD then
			LazyLock:Print("|cffff0000[LL Debug]|r Using predicted TTD: "..tostring(LazyLock.TargetTracker.predictedTTD))
			return LazyLock.TargetTracker.predictedTTD 
		end
		return 999 
	end
	
	-- Calculate DPS (HP per second, not percentage!)
	local dps = hpLost / timeElapsed
	if dps <= 0 then 
		if LazyLock.TargetTracker.predictedTTD then 
			LazyLock:Print("|cffff0000[LL Debug]|r Using predicted TTD: "..tostring(LazyLock.TargetTracker.predictedTTD))
			return LazyLock.TargetTracker.predictedTTD 
		end
		return 999 
	end
	
	-- Calculate TTD: current HP / DPS
	local timeToDie = currentHP / dps
	LazyLock:Print("|cffff0000[LL Debug]|r Calculated TTD: "..tostring(currentHP).." / "..tostring(dps).." = "..tostring(timeToDie).." seconds")
	
	return timeToDie
end

function LazyLock:IsWorthCasting(spell)
	-- Immunity Check (Persistent)
	local tName = UnitName("target")
	if tName and LazyLockDB.MobStats[tName] and LazyLockDB.MobStats[tName].immuneSpells and LazyLockDB.MobStats[tName].immuneSpells[spell] then
		LazyLock:Print("|cffff0000[LL Debug]|r Skipping "..spell.." (Target Immune - Persistent)")
		return false
	end

	local ttd = LazyLock:GetTTD()
	local histTTD = LazyLock:AnalyzeHistory(UnitName("target"), LazyLock:GetGroupType())
	
	if histTTD then 
		ttd = histTTD 
	end

    -- Resource Analysis
    local potentialMana = LazyLock:GetPotentialMana()
    local maxMana = UnitManaMax("player")
    local isRich = (potentialMana > (maxMana * 0.6)) -- considerate "Rich" if we can sustain >60% mana pool
    
    local thresholdMod = 1.0
    if isRich then
        thresholdMod = 0.7 -- Reduce TTD requirement by 30% if we are rich
    end
	

	
	-- Curses: Duration 24s, need at least 8s for worthwhile damage
	if LazyLock.CurseData[spell] then
	    if ttd > (8 * thresholdMod) then return true end
	    LazyLock:Print("|cffff0000[LL Debug]|r Skipping "..spell..": TTD "..string.format("%.1f", ttd).."s < Req "..string.format("%.1f", 8 * thresholdMod).."s")
		return false
	end

	LazyLock:Print("|cffff0000[LL Debug]|r Checking "..spell..". TTD: "..ttd..". Rich: "..tostring(isRich))
	
	-- Immolate: 15s duration, instant damage + ticks every 3s. Need 4s minimum (was 5s)
	if spell == "Immolate" then
	    if ttd > (4 * thresholdMod) then return true end
        LazyLock:Print("|cffff0000[LL Debug]|r Skipping "..spell..": TTD "..string.format("%.1f", ttd).."s < Req "..string.format("%.1f", 4 * thresholdMod).."s")
		return false
	-- Siphon Life: 30s duration, ticks every 3s. Need 6s minimum (was 9s)
	elseif spell == "Siphon Life" then
	    if ttd > (6 * thresholdMod) then return true end
	    LazyLock:Print("|cffff0000[LL Debug]|r Skipping "..spell..": TTD "..string.format("%.1f", ttd).."s < Req "..string.format("%.1f", 6 * thresholdMod).."s")
		return false
	-- Corruption: 18s duration, ticks every 3s. Need 5s minimum (was 6s)
	elseif spell == "Corruption" then
	    if ttd > (5 * thresholdMod) then return true end
	    LazyLock:Print("|cffff0000[LL Debug]|r Skipping "..spell..": TTD "..string.format("%.1f", ttd).."s < Req "..string.format("%.1f", 5 * thresholdMod).."s")
		return false
	elseif spell == "Shadowburn" then
		local shardCount = LazyLock:GetItemCount(6265)
		local hp = UnitHealth("target") / UnitHealthMax("target") * 100
		local lethal = false
		
		if LazyLockDB.SpellStats["Shadowburn"] and LazyLockDB.SpellStats["Shadowburn"].avg > 0 then
			if UnitHealth("target") <= LazyLockDB.SpellStats["Shadowburn"].avg then
				lethal = true
			end
		end

		-- Abundance: Burn freely
		if shardCount > 15 then 
			return (ttd < 15) or (hp < 25) or lethal
		end

		-- Conservation: Strict Execute Only
		-- Only use if we are finishing the mob off to save shards
		if shardCount <= 15 then
			if lethal then return true end
			if ttd < 5 then return true end -- Only if dying VERY soon
			if hp < 5 then return true end  -- True execute range
			
			return false
		end
		
		return false
	end
	
	return true
end

function LazyLock:ProcessDamageMatch(spell, damage, mob)
    if not spell or not damage then return end
    -- Remove distinct period if present
    spell = string.gsub(spell, "%.$", "")
    local d = tonumber(damage)
    self:RecordDamage(mob, spell, d) -- Use mob name if available
    
    -- Only update TargetTracker if it matches the current target (or no mob specified)
    if not mob or (UnitName("target") == mob) then
    	self:UpdateTargetTracker(spell, d)
    end
end

function LazyLock:ParseCombatMessage(msg)
	-- Check for immunity (Self - "Your X failed. Y is immune")
	for spell in string.gfind(msg, "Your (.+) failed%. .+ is immune%.") do
		local tName = LazyLock.TargetTracker.name
		if tName then
			if not LazyLockDB.MobStats[tName] then LazyLockDB.MobStats[tName] = {} end
			if not LazyLockDB.MobStats[tName].immuneSpells then LazyLockDB.MobStats[tName].immuneSpells = {} end
			
			LazyLockDB.MobStats[tName].immuneSpells[spell] = true
			LazyLock:Print("|cffff0000[LL Debug]|r Learned Persistent Immunity: "..spell.." for "..tName)
		end
	end

	-- Check for immunity (Passive/Others - "Name's X fails. Y is immune")
	for caster, spell, mob in string.gfind(msg, "(.+)'s (.+) fails%. (.+) is immune%.") do
		if LazyLockDB.MobStats[mob] or (UnitName("target") == mob) then
			if not LazyLockDB.MobStats[mob] then LazyLockDB.MobStats[mob] = {} end
			if not LazyLockDB.MobStats[mob].immuneSpells then LazyLockDB.MobStats[mob].immuneSpells = {} end
			
			if not LazyLockDB.MobStats[mob].immuneSpells[spell] then
				LazyLockDB.MobStats[mob].immuneSpells[spell] = true
				LazyLock:Print("|cffff0000[LL Debug]|r Learned Passive Immunity: "..spell.." for "..mob.." (from "..caster..")")
			end
		end
	end

    for spell, mob, damage in string.gfind(msg, "Your (.+) hits (.+) for (%d+)") do
        LazyLock:ProcessDamageMatch(spell, damage, mob)
    end
    for spell, mob, damage in string.gfind(msg, "Your (.+) crits (.+) for (%d+)") do
        LazyLock:ProcessDamageMatch(spell, damage, mob)
    end
    for spell, damage in string.gfind(msg, "Your (.+) ticks for (%d+)") do
    	-- Ticks usually don't have mob name in this client version string? 
    	-- Standard Vanilla: "Your Corruption ticks for 100." (Target implicit)
    	-- Or "Mob suffers 100 from your Corruption." (This is handled below)
        LazyLock:ProcessDamageMatch(spell, damage, UnitName("target"))
    end
    -- Added support for "Target suffers X damage from your Spell"
    for mob, damage, spell in string.gfind(msg, "(.+) suffers (%d+) .+ from your (.+)") do
        LazyLock:ProcessDamageMatch(spell, damage, mob)
    end
end

LazyLock:SetScript("OnEvent", function()
	if event == "VARIABLES_LOADED" then
		LazyLock:Initialize()
	elseif event == "PLAYER_TARGET_CHANGED" then
		LazyLock:Print("|cffff0000[LL Debug]|r Target Changed")
		LazyLock.Settings["IsCasting"] = false 
		LazyLock:CheckConsumables()
		
		if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
			local tName = UnitName("target") or "Unknown"
			local max_hp = UnitHealthMax("target")
			if not max_hp or max_hp == 0 then max_hp = 100 end
			
			-- Initialize stats if missing
			if not LazyLockDB.MobStats[tName] then
				LazyLockDB.MobStats[tName] = { maxHP = max_hp }
			end
			
			local gType = LazyLock:GetGroupType()
			local predTTD = LazyLock:AnalyzeHistory(tName, gType)
			
			local hp = UnitHealth("target")
			if not hp or hp == 0 then hp = 100 end

			-- Calc HP Percent for Tracker
			local hpPercent = (hp / max_hp) * 100

			LazyLock.TargetTracker = {
				name = tName,
				startTime = GetTime(),
				startHP = hpPercent,
				maxHP = max_hp,
				lastHP = hpPercent,
				lastUpdate = GetTime(),
				damageDone = 0,
				spells = {},
				predictedTTD = predTTD
			}
			
			local strat = LazyLock:GetCombatStrategy(tName, gType)
			LazyLock.TargetTracker.strategy = strat
		else
			-- Save current target data before reset
			if LazyLock.TargetTracker.name and LazyLock.TargetTracker.damageDone > 0 then
				LazyLock.LastTargetTracker = {
					name = LazyLock.TargetTracker.name,
					startTime = LazyLock.TargetTracker.startTime,
					damageDone = LazyLock.TargetTracker.damageDone,
					strategy = LazyLock.TargetTracker.strategy,
					reported = false,
					spells = {}
				}
				-- Copy spells table
				for spell, dmg in pairs(LazyLock.TargetTracker.spells) do
					LazyLock.LastTargetTracker.spells[spell] = dmg
				end
			end
			
			LazyLock.TargetTracker = { 
				name = nil,
				startTime = 0,
				damageDone = 0,
				strategy = "NORMAL",
				spells = {}
			}
		end
		
		-- Reset Cast Timers (Allow immediate recast on new target)
		LazyLock.Settings["Curse of Agony"] = 0
		LazyLock.Settings["Curse of the Elements"] = 0
		LazyLock.Settings["Curse of Shadow"] = 0
		LazyLock.Settings["Curse of Tongues"] = 0
		LazyLock.Settings["Curse of Recklessness"] = 0
		LazyLock.Settings["Curse of Weakness"] = 0
		LazyLock.Settings["Curse of Doom"] = 0
		LazyLock.Settings["Corruption"] = 0
		LazyLock.Settings["Siphon Life"] = 0
		LazyLock.Settings["Immolate"] = 0
		

		
	
	elseif event == "SPELLCAST_START" then
		LazyLock.Settings["IsCasting"] = true
	elseif event == "SPELLCAST_INTERRUPTED" then
		LazyLock.Settings["IsCasting"] = false
	elseif event == "SPELLCAST_FAILED" then
		LazyLock.Settings["IsCasting"] = false
	elseif event == "SPELLCAST_DELAYED" then
	
	elseif event == "SPELLCAST_STOP" or event == "SPELLCAST_CHANNEL_STOP" then
		LazyLock.Settings["IsCasting"] = false
	elseif event == "SPELLCAST_CHANNEL_START" then
		LazyLock.Settings["IsCasting"] = true
	elseif event == "SPELLCAST_CHANNEL_UPDATE" then
		if arg1 == 0 then LazyLock.Settings["IsCasting"] = false end
	elseif event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" then 		-- when dots land on mobs
		if string.find(arg1,"afflicted") then
			for curse,_ in pairs(LazyLock.Settings) do
				if string.find(arg1,curse) then
					--LazyLock.Settings[curse] = GetTime()
				end
			end
		end
	elseif event == "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE" then
	elseif event == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" then
	elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" or event == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" then
		LazyLock:ParseCombatMessage(arg1)

	elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
		-- Format: "X dies."
		local targetName = LazyLock.TargetTracker.name
		if targetName and targetName ~= "" and string.find(arg1, targetName) then
			local dmg = LazyLock.TargetTracker.damageDone
			if dmg > 0 then
				LazyLock:Print("|cff00ff00LazyLock:|r Killed ["..targetName.."]. My Damage: "..dmg)
				
				-- Learn Strategy (Record Duration)
				local duration = GetTime() - LazyLock.TargetTracker.startTime
				LazyLock:UpdateMobStats(targetName, duration, UnitHealthMax("target"))
				
				LazyLock:Report(true, LazyLockDB.reportToSay)
			end
		end
	end
end)
LazyLock:Print("|cff00ff00[LL Debug] SetScript with OLD STYLE wrapper!|r")

for _, event in pairs(eventsToRegister) do
	LazyLock:RegisterEvent(event)
	LazyLock:Print("|cffff0000[LL Debug] Registered Event: "..event.."|r")
end
LazyLock:Print("|cff00FF00[LL Debug] All events registered!|r")

LazyLock:Print("|cffff0000[LL Debug]|r RegisterSlashCommands called.")
SLASH_LAZYLOCK1 = "/lazylock"
SLASH_LAZYLOCK2 = "/ll"
SlashCmdList["LAZYLOCK"] = function(msg)
	LazyLock:Print("|cffff0000[LL Debug]|r Slash Handler called with: '"..(msg or "nil").."'") 
	LazyLock.Settings["IsCasting"] = false
	
	local _, _, cmd, args = string.find(msg, "%s?(%w+)%s?(.*)")
	if cmd then cmd = string.lower(cmd) end
	
	if cmd == "check" then
		if args == "on" then LazyLockDB.checkConsumables = true
		elseif args == "off" then LazyLockDB.checkConsumables = false
		elseif args == "toggle" then LazyLockDB.checkConsumables = not LazyLockDB.checkConsumables
		elseif args == "status" then 
		else
			LazyLockDB.checkConsumables = not LazyLockDB.checkConsumables
		end
		LazyLock:Print("LazyLock Consumables Check: "..(LazyLockDB.checkConsumables and "ON" or "OFF"))
		
	elseif cmd == "curse" then
		local curse = nil
		if args and args ~= "" then
			for fullName, data in pairs(LazyLock.CurseData) do
				for _, alias in pairs(data.aliases) do
					if string.lower(args) == string.lower(alias) then
						curse = fullName
						break
					end
				end
			end
		end
		
		if curse then
			LazyLockDB.defaultCurse = curse
			LazyLock:Print("LazyLock: Default Curse set to |cff71d5ff"..curse.."|r")
		else
			LazyLock:Print("LazyLock: Invalid curse alias. Usage: /ll curse [agony/elements/shadow/recklessness/tongues/weakness/doom]")
		end
		
	elseif cmd == "export" then
		LazyLock:ExportStats()
		
	elseif cmd == "puke" then
		LazyLock:Report(true, false)
		
	elseif cmd == "say" then
		if args == "on" then LazyLockDB.reportToSay = true
		elseif args == "off" then LazyLockDB.reportToSay = false
		else LazyLockDB.reportToSay = not LazyLockDB.reportToSay end
		LazyLock:Print("LazyLock Say Report: "..(LazyLockDB.reportToSay and "ON" or "OFF"))

	elseif cmd == "log" then
		if args == "on" then LazyLockDB.logging = true
		elseif args == "off" then LazyLockDB.logging = false
		else LazyLockDB.logging = not LazyLockDB.logging end
		LazyLock:Print("LazyLock Logging: "..(LazyLockDB.logging and "ON" or "OFF"))
	
	elseif cmd == "test" then
		local state
		if args == "on" then 
			LazyLockDB.logging = true
			LoggingCombat(true)
			state = "|cff00ff00ON|r"
		elseif args == "off" then 
			LazyLockDB.logging = false
			LoggingCombat(false)
			state = "|cffff0000OFF|r"
		else 
			LazyLockDB.logging = not LazyLockDB.logging
			if LazyLockDB.logging then LoggingCombat(true) else LoggingCombat(false) end
			state = LazyLockDB.logging and "|cff00ff00ON|r" or "|cffff0000OFF|r"
		end
		LazyLock:Print("LazyLock Testing Mode (Addon Log + Combat Log): "..state)

	elseif cmd == "drain" then
		if args == "on" then LazyLockDB.drainSoulMode = true
		elseif args == "off" then LazyLockDB.drainSoulMode = false
		else LazyLockDB.drainSoulMode = not LazyLockDB.drainSoulMode end
		LazyLock:Print("LazyLock Drain Soul Mode: "..(LazyLockDB.drainSoulMode and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
	
	elseif cmd == "clear" then
		if LazyLockDB.Log then
			local logCount = 0
			for _ in pairs(LazyLockDB.Log) do logCount = logCount + 1 end
			LazyLockDB.Log = {}
			LazyLock:Print("|cff71d5ffLazyLock:|r Cleared "..logCount.." log entries")
		else
			LazyLock:Print("|cff71d5ffLazyLock:|r No logs to clear")
		end
	
	elseif cmd == "help" then
		LazyLock:Print("|cff71d5ffLazyLock Commands:|r")
		LazyLock:Print("/ll check [on/off] - Toggle consumable check")
		LazyLock:Print("/ll clear - Clear all debug logs")
		LazyLock:Print("/ll curse [name] - Set default curse")
		LazyLock:Print("/ll drain [on/off] - Toggle Drain Soul mode (shard farming)")
		LazyLock:Print("/ll export - Show gathered stats")
		LazyLock:Print("/ll log [on/off] - Toggle persistent logging")
		LazyLock:Print("/ll puke - Show last fight report (Chat)")
		LazyLock:Print("/ll test [on/off] - Toggle ALL logging (Debug + CombatLog) for testing")
		LazyLock:Print("/ll say [on/off] - Toggle report to Say channel")
	elseif cmd == "save" then
		ReloadUI()		
	else
		LazyLock:Cast()
	end
end