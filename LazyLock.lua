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
	["Curse of the Elements"] = { duration = 300, aliases = {"elements", "coe"}, check = "Curse of Agony" },
	["Curse of Shadow"] = { duration = 300, aliases = {"shadow", "shadows", "cos"}, check = "Curse of Agony" },
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
		LazyLockDB.logging = true
	end
	if LazyLockDB.Log == nil then
		LazyLockDB.Log = {}
	end
	
	if LazyLock.Settings == nil then
		LazyLock.Settings = {}
		for k,v in pairs(LazyLock.Default) do
			LazyLock.Settings[k] = v
		end
	end
	LazyLock:Print("LazyLock: Variables Loaded.")
end

LazyLock.TargetTracker = {
	name = nil,
	startTime = 0,
	damageDone = 0,
	strategy = "NORMAL",
	spells = {}
}

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

function LazyLock:RecordDamage(spell, amount)
	if not LazyLockDB.SpellStats then
		LazyLockDB.SpellStats = {}
	end
	if not LazyLockDB.SpellStats[spell] then
		LazyLockDB.SpellStats[spell] = { count = 0, total = 0, avg = 0 }
	end
	
	local s = LazyLockDB.SpellStats[spell]
	s.count = s.count + 1
	s.total = s.total + amount
	s.avg = s.total / s.count
end

function LazyLock:UpdateTargetTracker(spell, damage)
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
	local t = LazyLock.TargetTracker
	if not t.name or t.damageDone == 0 then
		if toChat then DEFAULT_CHAT_FRAME:AddMessage("LazyLock: No recent combat data.") end
		return
	end
	
	local strat = t.strategy or "Unknown"
	local state = LazyLock:CheckState()
	local msg = "LazyLock ["..state.."]: Killed "..t.name.." ("..strat.."). Total: "..t.damageDone.."."
	
	local breakdown = ""
	for spell, dmg in pairs(t.spells) do
		breakdown = breakdown.." ["..spell..": "..dmg.."]"
	end
	
	local output = msg..breakdown
	
	if toChat then
		LazyLock:Print("|cff00ff00"..output.."|r")
	end
	
	if toSay then
		SendChatMessage(output, "SAY")
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

	if strat ~= "BURST" and (UnitMana("player") / UnitManaMax("player") * 100 < 5) and (UnitHealth("player") / UnitHealthMax("player") * 100 > 50) then
		if not LazyLock.Settings["IsCasting"] then
			CastSpellByName("Life Tap")
			return
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

function LazyLock:CastBurst()
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
	if not LazyLock:HasDebuff("target", "Immolate")
	and not LazyLock:GetSpellCooldown("Immolate") and not LazyLock.Settings["IsCasting"] and LazyLock:IsWorthCasting("Immolate") 
	and (GetTime() - (LazyLock.Settings["Immolate"] or 0) > 2) then
		CastSpellByName("Immolate")
		LazyLock.Settings["Immolate"] = GetTime() 
		return true
	end
	
	if not LazyLock:HasDebuff("target", "Corruption") 
	and not LazyLock:GetSpellCooldown("Corruption") and not LazyLock.Settings["IsCasting"] and LazyLock:IsWorthCasting("Corruption") 
	and (GetTime() - (LazyLock.Settings["Corruption"] or 0) > 2) then
		CastSpellByName("Corruption")
		LazyLock.Settings["Corruption"] = GetTime()
		return true
	end
	
	if LazyLock:GetItemCount(6265) > 0 and not LazyLock:GetSpellCooldown("Shadowburn") and not LazyLock.Settings["IsCasting"] and LazyLock:IsWorthCasting("Shadowburn") then
		CastSpellByName("Shadowburn")
		return true
	end
	
	if not LazyLock.Settings["IsCasting"] then
		CastSpellByName("Shadow Bolt")
		LazyLock:Print("|cffff0000[LL Debug]|r Casting Shadow Bolt")
		return true
	end
    return false
end

function LazyLock:CastLong()
	local curseName = LazyLockDB.defaultCurse or "Curse of Agony"
	local checkName = curseName
	if LazyLock.CurseData[curseName] and LazyLock.CurseData[curseName].check then
		checkName = LazyLock.CurseData[curseName].check
	end

	
	if not LazyLock:HasDebuff("target", "Curse of Shadow") 
	and not LazyLock:GetSpellCooldown("Curse of Shadow") 
	and not LazyLock.Settings["IsCasting"] 
	and LazyLock:IsWorthCasting("Curse of Shadow") 
	and (GetTime() - (LazyLock.Settings["Curse of Shadow"] or 0) > 2) then
		LazyLock:Print("|cffff0000[LL Debug]|r Casting Curse of Shadow")
		CastSpellByName("Curse of Shadow")
		LazyLock.Settings["Curse of Shadow"] = GetTime()
		return true
	end

	if not LazyLock:HasDebuff("target", "Curse of Agony") 
	and not LazyLock:GetSpellCooldown("Curse of Agony") 
	and not LazyLock.Settings["IsCasting"] 
	and LazyLock:IsWorthCasting("Curse of Agony") 
	and (GetTime() - (LazyLock.Settings["Curse of Agony"] or 0) > 2) then
		LazyLock:Print("|cffff0000[LL Debug]|r Casting Curse of Agony")
		CastSpellByName("Curse of Agony")
		LazyLock.Settings["Curse of Agony"] = GetTime()
		return true
	end
	
	if not LazyLock:HasDebuff("target", "Siphon Life") 
	and not LazyLock:GetSpellCooldown("Siphon Life") 
	and not LazyLock.Settings["IsCasting"] 
	and LazyLock:IsWorthCasting("Siphon Life") 
	and (GetTime() - (LazyLock.Settings["Siphon Life"] or 0) > 2) then
		CastSpellByName("Siphon Life")
		LazyLock.Settings["Siphon Life"] = GetTime()
		return true
	end
	
	if not LazyLock:HasDebuff("target", "Corruption") 
	and not LazyLock:GetSpellCooldown("Corruption") 
	and not LazyLock.Settings["IsCasting"] 
	and LazyLock:IsWorthCasting("Corruption") 
	and (GetTime() - (LazyLock.Settings["Corruption"] or 0) > 2) then
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
	
	if LazyLock:HasDebuff("target", LazyLockDB.defaultCurse)
	and LazyLock:HasDebuff("target", "Curse of Agony")
	and LazyLock:HasDebuff("target", "Siphon Life")
	and LazyLock:HasDebuff("target", "Corruption")
	and LazyLock:HasDebuff("target", "Immolate")
	and LazyLock:GetItemCount(6265) > 0 and not LazyLock:GetSpellCooldown("Shadowburn") and not LazyLock.Settings["IsCasting"] and LazyLock:IsWorthCasting("Shadowburn") then
		 CastSpellByName("Shadowburn")
		 return true
	end
	
	if LazyLock:HasDebuff("target", LazyLockDB.defaultCurse)
	and LazyLock:HasDebuff("target", "Curse of Agony")
	and LazyLock:HasDebuff("target", "Siphon Life")
	and LazyLock:HasDebuff("target", "Corruption")
	and LazyLock:HasDebuff("target", "Immolate")
	and not LazyLock.Settings["IsCasting"] then
		CastSpellByName("Shadow Bolt")
		return true
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
	

	
	if LazyLock.CurseData[spell] then
	    if ttd > (24 * thresholdMod) then return true end
	    LazyLock:Print("|cffff0000[LL Debug]|r Skipping "..spell..": TTD "..string.format("%.1f", ttd).."s < Req "..string.format("%.1f", 24 * thresholdMod).."s")
		return false
	end

	LazyLock:Print("|cffff0000[LL Debug]|r Checking "..spell..". TTD: "..ttd..". Rich: "..tostring(isRich))
	
	if spell == "Immolate" then
	    if ttd > (15 * thresholdMod) then return true end
        LazyLock:Print("|cffff0000[LL Debug]|r Skipping "..spell..": TTD "..string.format("%.1f", ttd).."s < Req "..string.format("%.1f", 15 * thresholdMod).."s")
		return false
	elseif spell == "Siphon Life" then
	    if ttd > (30 * thresholdMod) then return true end
	    LazyLock:Print("|cffff0000[LL Debug]|r Skipping "..spell..": TTD "..string.format("%.1f", ttd).."s < Req "..string.format("%.1f", 30 * thresholdMod).."s")
		return false
	elseif spell == "Corruption" then
	    if ttd > (18 * thresholdMod) then return true end
	    LazyLock:Print("|cffff0000[LL Debug]|r Skipping "..spell..": TTD "..string.format("%.1f", ttd).."s < Req "..string.format("%.1f", 18 * thresholdMod).."s")
		return false
	elseif spell == "Shadowburn" then
		if LazyLock:GetItemCount(6265) >= 20 then return true end

		local hp = UnitHealth("target") / UnitHealthMax("target") * 100
		local lethal = false
		
		if LazyLockDB.SpellStats["Shadowburn"] and LazyLockDB.SpellStats["Shadowburn"].avg > 0 then
			if UnitHealth("target") <= LazyLockDB.SpellStats["Shadowburn"].avg then
				lethal = true
			end
		end
		
		return (ttd < 15) or (hp < 25) or lethal
	end
	
	return true
end

function LazyLock:ProcessDamageMatch(spell, damage)
    if not spell or not damage then return end
    -- Remove distinct period if present
    spell = string.gsub(spell, "%.$", "")
    local d = tonumber(damage)
    self:RecordDamage(spell, d)
    self:UpdateTargetTracker(spell, d)
end

function LazyLock:ParseCombatMessage(msg)
    for spell, damage in string.gfind(msg, "Your (.+) hits .+ for (%d+)") do
        LazyLock:ProcessDamageMatch(spell, damage)
    end
    for spell, damage in string.gfind(msg, "Your (.+) crits .+ for (%d+)") do
        LazyLock:ProcessDamageMatch(spell, damage)
    end
    for spell, damage in string.gfind(msg, "Your (.+) ticks for (%d+)") do
        LazyLock:ProcessDamageMatch(spell, damage)
    end
    -- Added support for "Target suffers X damage from your Spell"
    for _, damage, spell in string.gfind(msg, "(.+) suffers (%d+) .+ from your (.+)") do
        LazyLock:ProcessDamageMatch(spell, damage)
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
			end
			
			-- Learn Strategy (Record Duration)
			local duration = GetTime() - LazyLock.TargetTracker.startTime
			LazyLock:UpdateMobStats(targetName, duration, UnitHealthMax("target"))
			
			LazyLock:Report(true, LazyLockDB.reportToSay)
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
	
	elseif cmd == "help" then
		LazyLock:Print("|cff71d5ffLazyLock Commands:|r")
		LazyLock:Print("/ll check [on/off] - Toggle consumable check")
		LazyLock:Print("/ll curse [name] - Set default curse")
		LazyLock:Print("/ll export - Show gathered stats")
		LazyLock:Print("/ll log [on/off] - Toggle persistent logging")
		LazyLock:Print("/ll puke - Show last fight report (Chat)")
		LazyLock:Print("/ll say [on/off] - Toggle report to Say channel")
	elseif cmd == "save" then
		ReloadUI()		
	else
		LazyLock:Cast()
	end
end