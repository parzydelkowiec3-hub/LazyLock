local LazyLock = CreateFrame("Frame",nil,UIParent);
CreateFrame( "GameTooltip", "LazyLockTooltip", nil, "GameTooltipTemplate")
LazyLockTooltip:SetOwner( WorldFrame, "ANCHOR_NONE" )

LazyLock.Default = {
	["Curse of Agony"] = 0,
	["Corruption"] = 0,
	["Siphon Life"] = 0,
	["Immolate"] = 0,
	["IsCasting"] = false,
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
	"CHAT_MSG_COMBAT_HOSTILE_DEATH"
}

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

if LazyLock.Settings == nil then
	LazyLock.Settings = {}
	for k,v in pairs(LazyLock.Default) do
		LazyLock.Settings[k] = v
	end
end

LazyLock.TargetTracker = {
	name = nil,
	startTime = 0,
	damageDone = 0,
	strategy = "NORMAL",
	spells = {}
}

function LazyLock:Debug(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[LL Debug]|r "..tostring(msg))
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
	
	LazyLockDB.MobStats[name].maxHP = maxHP
end

function LazyLock:AnalyzeHistory(name, gType)
	LazyLock:Debug("Analyzing history for "..name.." in "..gType)
	local m = LazyLockDB.MobStats and LazyLockDB.MobStats[name][gType] or { count = 0, avgTTD = duration, history = {} }
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
				LazyLock:Debug("Found debuff "..name.." on "..unit)
				return true
			end
		end
		i = i + 1
	end
	LazyLock:Debug("No debuff "..name.." on "..unit)
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

function LazyLock:GetTTD()
	local t = LazyLock.TargetTracker
	if not t.name or t.startTime == 0 then return nil end
	
	local currentHP = UnitHealth("target")
	local maxHP = UnitHealthMax("target")
	
	
	if deltaHP <= 0 or duration < 2 then 
		return 100 
	end
	
	local dps = deltaHP / duration
	local ttd = currentHP / dps
	
	return ttd
end

function LazyLock:GetBuffName(unit, index)
	LazyLockTooltip:ClearLines()
	LazyLockTooltip:SetUnitBuff(unit, index)
	local buffName = LazyLockTooltipTextLeft1:GetText()
	return buffName
end

function LazyLock:ExportStats()
	DEFAULT_CHAT_FRAME:AddMessage("LazyLock Stats Export (Spell, Count, Total, Avg):")
	for k, v in pairs(LazyLockDB.SpellStats) do
		DEFAULT_CHAT_FRAME:AddMessage(k..", "..v.count..", "..v.total..", "..string.format("%.1f", v.avg))
	end
	DEFAULT_CHAT_FRAME:AddMessage("LazyLock Mob Strategy (Name [Type], AvgTTD, Strategy):")
	for k, v in pairs(LazyLockDB.MobStats) do
		if v.solo then 
			local strat = LazyLock:GetCombatStrategy(k, "solo")
			DEFAULT_CHAT_FRAME:AddMessage(k.." [solo], "..string.format("%.1f", v.solo.avgTTD)..", "..strat) 
		end
		if v.party then 
			local strat = LazyLock:GetCombatStrategy(k, "party")
			DEFAULT_CHAT_FRAME:AddMessage(k.." [party], "..string.format("%.1f", v.party.avgTTD)..", "..strat) 
		end
		if v.raid then 
			local strat = LazyLock:GetCombatStrategy(k, "raid")
			DEFAULT_CHAT_FRAME:AddMessage(k.." [raid], "..string.format("%.1f", v.raid.avgTTD)..", "..strat) 
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
		DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..output.."|r")
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
			DEFAULT_CHAT_FRAME:AddMessage("|cffff0000LazyLock:|r Missing |cff71d5ff["..req.display.."]|r")
		end
	end
	
	local hasMainHandEnchant, _, _, _, _, _ = GetWeaponEnchantInfo()
	if not hasMainHandEnchant then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff0000LazyLock:|r Missing |cff71d5ff[Weapon Oil/Enchant]|r")
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
		DEFAULT_CHAT_FRAME:AddMessage("LazyLock: Default curse set to |cff71d5ff["..LazyLockDB.defaultCurse.."]|r")
	else
		DEFAULT_CHAT_FRAME:AddMessage("LazyLock: Unknown curse. Available: agony, elements, shadow, tongues, recklessness, weakness, doom.")
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

	-- if strat == "BURST" then
	-- 	self:CastBurst()
	-- elseif strat == "NORMAL" then
	-- 	self:CastNormal()
	-- elseif strat == "LONG" then
	self:CastLong()
	-- end
	
	-- if not LazyLock.Settings["IsCasting"] then
	-- 	CastSpellByName("Shadow Bolt")
	-- end
end

function LazyLock:CastBurst()
	if LazyLock:GetItemCount(6265) > 0 and not LazyLock:GetSpellCooldown("Shadowburn") and not LazyLock.Settings["IsCasting"] then
		CastSpellByName("Shadowburn")
		return
	end
	
	if not LazyLock.Settings["IsCasting"] and not LazyLock:GetSpellCooldown("Searing Pain") then
		CastSpellByName("Searing Pain")
		return
	end
end

function LazyLock:CastNormal()
	if not LazyLock:HasDebuff("target", "Immolate")
	and not LazyLock:GetSpellCooldown("Immolate") and not LazyLock.Settings["IsCasting"] and LazyLock:IsWorthCasting("Immolate") then
		CastSpellByName("Immolate")
		LazyLock.Settings["Immolate"] = GetTime() 
		return
	end
	
	if not LazyLock:HasDebuff("target", "Corruption") 
	and not LazyLock:GetSpellCooldown("Corruption") and not LazyLock.Settings["IsCasting"] and LazyLock:IsWorthCasting("Corruption") then
		CastSpellByName("Corruption")
		LazyLock.Settings["Corruption"] = GetTime()
		return
	end
	
	if LazyLock:GetItemCount(6265) > 0 and not LazyLock:GetSpellCooldown("Shadowburn") and not LazyLock.Settings["IsCasting"] and LazyLock:IsWorthCasting("Shadowburn") then
		CastSpellByName("Shadowburn")
		return
	end
	
	if not LazyLock.Settings["IsCasting"] then
		CastSpellByName("Shadow Bolt")
		return
	end
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
	and LazyLock:IsWorthCasting("Curse of Shadow") then
		LazyLock:Debug("Casting Curse of Shadow")
		CastSpellByName("Curse of Shadow")
		LazyLock.Settings["Curse of Shadow"] = GetTime()
		return
	end

	if not LazyLock:HasDebuff("target", "Curse of Agony") 
	and not LazyLock:GetSpellCooldown("Curse of Agony") 
	and not LazyLock.Settings["IsCasting"] 
	and LazyLock:IsWorthCasting("Curse of Agony") then
		LazyLock:Debug("Casting Currse of Agony")
		CastSpellByName("Curse of Agony")
		LazyLock.Settings["Curse of Agony"] = GetTime()
		return
	end
	
	if not LazyLock:HasDebuff("target", "Siphon Life") 
	and not LazyLock:GetSpellCooldown("Siphon Life") 
	and not LazyLock.Settings["IsCasting"] 
	and LazyLock:IsWorthCasting("Siphon Life") then
		CastSpellByName("Siphon Life")
		LazyLock.Settings["Siphon Life"] = GetTime()
		return
	end
	
	if not LazyLock:HasDebuff("target", "Corruption") 
	and not LazyLock:GetSpellCooldown("Corruption") 
	and not LazyLock.Settings["IsCasting"] 
	and LazyLock:IsWorthCasting("Corruption") then
		CastSpellByName("Corruption")
		LazyLock.Settings["Corruption"] = GetTime()
		return
	end
	
	if not LazyLock:HasDebuff("target", "Immolate") 
	and not LazyLock:GetSpellCooldown("Immolate") 
	and not LazyLock.Settings["IsCasting"] 
	and LazyLock:IsWorthCasting("Immolate") then
		CastSpellByName("Immolate")
		LazyLock.Settings["Immolate"] = GetTime()
		return
	end
	
	if LazyLock:HasDebuff("target", LazyLockDB.defaultCurse)
	and LazyLock:HasDebuff("target", "Curse of Agony")
	and LazyLock:HasDebuff("target", "Siphon Life")
	and LazyLock:HasDebuff("target", "Corruption")
	and LazyLock:HasDebuff("target", "Immolate")
	and LazyLock:GetItemCount(6265) > 0 and not LazyLock:GetSpellCooldown("Shadowburn") and not LazyLock.Settings["IsCasting"] and LazyLock:IsWorthCasting("Shadowburn") then
		 CastSpellByName("Shadowburn")
		 return
	end
	
	if LazyLock:HasDebuff("target", LazyLockDB.defaultCurse)
	and LazyLock:HasDebuff("target", "Curse of Agony")
	and LazyLock:HasDebuff("target", "Siphon Life")
	and LazyLock:HasDebuff("target", "Corruption")
	and LazyLock:HasDebuff("target", "Immolate")
	and not LazyLock.Settings["IsCasting"] then
		CastSpellByName("Shadow Bolt")
		return
	end
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
	
	local currentHP = UnitHealth("target") / UnitHealthMax("target") * 100
	local now = GetTime()
	
	if now - LazyLock.TargetTracker.lastUpdate > 1 then
		LazyLock.TargetTracker.lastHP = currentHP
		LazyLock.TargetTracker.lastUpdate = now
		LazyLock:Debug("Updated lastHP to "..tostring(LazyLock.TargetTracker.lastHP))
	end
	
	local percentLost = LazyLock.TargetTracker.startHP - currentHP
	local timeElapsed = now - LazyLock.TargetTracker.startTime
	
	LazyLock:Debug("Percent lost: "..tostring(percentLost).." Time elapsed: "..tostring(timeElapsed))
	if timeElapsed < 2 or percentLost <= 0 then 
		if LazyLock.TargetTracker.predictedTTD then
			LazyLock:Debug("Using predicted TTD: "..tostring(LazyLock.TargetTracker.predictedTTD))
			return LazyLock.TargetTracker.predictedTTD 
		end
		return 999 
	end
	
	LazyLock:Debug("Calculated TTD: "..tostring(currentHP).." / "..tostring(timeElapsed))
	local dpsPercent = percentLost / timeElapsed
	if dpsPercent <= 0 then 
		if LazyLock.TargetTracker.predictedTTD then 
			LazyLock:Debug("Using predicted TTD: "..tostring(LazyLock.TargetTracker.predictedTTD))
			return LazyLock.TargetTracker.predictedTTD 
		end
		return 999 
	end
	
	LazyLock:Debug("Calculated TTD: "..tostring(currentHP).." / "..tostring(dpsPercent))
	local timeToDie = currentHP / dpsPercent
	DEFAULT_CHAT_FRAME:AddMessage("TTD: "..timeToDie)
	return timeToDie
end

function LazyLock:IsWorthCasting(spell)

	local ttd = LazyLock:GetTTD()
	
	local histTTD = LazyLock:AnalyzeHistory(UnitName("target"), LazyLock:GetGroupType())
	if histTTD then 
		ttd = histTTD 
	end

	if "a" == "a" then
		return true
	end
	
	if LazyLock.CurseData[spell] then
		return ttd > 24
	end

	LazyLock:Debug("Checking if "..spell.." is worth casting on "..UnitName("target").." with TTD of "..ttd)
	LazyLock:Debug("Worth casting: "..tostring(ttd > 15).." (TTD > 15)"..tostring(ttd > 18).." (TTD > 18)"..tostring(ttd > 24).." (TTD > 24)")
	if spell == "Immolate" then
		return ttd > 15
	elseif spell == "Siphon Life" then
		return ttd > 30
	elseif spell == "Corruption" then
		return ttd > 18
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

LazyLock:SetScript("OnEvent", function()
	if event == "PLAYER_ENTERING_WORLD" then
		LazyLock:Debug("Initializing LazyLock...")
		LazyLock:UnregisterEvent("PLAYER_ENTERING_WORLD")
		
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
		
		
		if LazyLock.Settings == nil then
			LazyLock.Settings = {}
			for k,v in pairs(LazyLock.Default) do
				LazyLock.Settings[k] = v
			end
		end
		
		
		LazyLock.TargetTracker = {
			name = nil,
			startTime = 0,
			damageDone = 0,
			strategy = "NORMAL",
			spells = {}
		}
		
		LazyLock:RegisterSlashCommands()
		DEFAULT_CHAT_FRAME:AddMessage("|cffFF00FF[LL INIT]|r RegisterSlashCommands done!")
		LazyLock:Debug("Initialization Complete.")
		
	elseif event == "PLAYER_TARGET_CHANGED" then
		LazyLock:Debug("Target Changed")
		LazyLock.Settings["IsCasting"] = false 
		LazyLock:CheckConsumables()
		local tName = UnitName("target") or "Unknown"
		local predTTD = nil
		local gType = LazyLock:GetGroupType()
		
		local predTTD = nil
		local gType = LazyLock:GetGroupType()
		
		if LazyLockDB.MobStats and LazyLockDB.MobStats[tName] and LazyLockDB.MobStats[tName][gType] then
			predTTD = LazyLock:AnalyzeHistory(tName, gType)
			if not predTTD then
				predTTD = LazyLockDB.MobStats[tName][gType].avgTTD
			end
		end
		
		local hp = UnitHealth("target")
		local max_hp = UnitHealthMax("target")
		LazyLock.TargetTracker = {
			name = tName,
			startTime = GetTime(),
			startHP = hp,
			maxHP = max_hp,
			lastHP = hp,
			lastUpdate = GetTime(),
			damageDone = 0,
			damageDone = 0,
			spells = {} 
		}
		
		
		if UnitCanAttack("player", "target") and not UnitIsDead("target") then
			local strat = LazyLock:GetCombatStrategy(tName, LazyLock:GetGroupType())
			LazyLock.TargetTracker.strategy = strat
		end
		
		LazyLock.Settings["Curse of Agony"] = 0
		LazyLock.Settings["Curse of the Elements"] = 0
		LazyLock.Settings["Curse of Shadow"] = 0
		LazyLock.Settings["Curse of Tongues"] = 0
		LazyLock.Settings["Curse of Recklessness"] = 0
		LazyLock.Settings["Curse of Weakness"] = 0
		LazyLock.Settings["Curse of Doom"] = 0
		LazyLock.Settings["Corruption"] = 0
		LazyLock.Settings["Siphon Life"] = 0
		
	
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
		for spellName, damage in string.gfind(arg1, "Your (.+) hits .+ for (%d+)") do
			LazyLock:RecordDamage(spellName, tonumber(damage))
			LazyLock:UpdateTargetTracker(spellName, tonumber(damage))
		end
		for spellName, damage in string.gfind(arg1, "Your (.+) crits .+ for (%d+)") do
			LazyLock:RecordDamage(spellName, tonumber(damage))
			LazyLock:UpdateTargetTracker(spellName, tonumber(damage))
		end
		for spellName, damage in string.gfind(arg1, "Your (.+) ticks for (%d+)") do
			LazyLock:RecordDamage(spellName, tonumber(damage))
			LazyLock:UpdateTargetTracker(spellName, tonumber(damage))
		end
	elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
		-- Format: "X dies."
		local targetName = LazyLock.TargetTracker.name
		if targetName and targetName ~= "" and string.find(arg1, targetName) then
			local dmg = LazyLock.TargetTracker.damageDone
			if dmg > 0 then
				DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00LazyLock:|r Killed ["..targetName.."]. My Damage: "..dmg)
			end
			
			-- Learn Strategy (Record Duration)
			local duration = GetTime() - LazyLock.TargetTracker.startTime
			LazyLock:UpdateMobStats(targetName, duration, UnitHealthMax("target"))
			
			LazyLock:Report(true, LazyLockDB.reportToSay)
		end
	end
end)
DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[LL Debug] SetScript with OLD STYLE wrapper!|r")

for _, event in pairs(eventsToRegister) do
	LazyLock:RegisterEvent(event)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[LL Debug] Registered Event: "..event.."|r")
end
DEFAULT_CHAT_FRAME:AddMessage("|cff00FF00[LL Debug] All events registered!|r")

LazyLock:Debug("RegisterSlashCommands called.")
SLASH_LAZYLOCK1 = "/lazylock"
SLASH_LAZYLOCK2 = "/ll"
SlashCmdList["LAZYLOCK"] = function(msg)
	LazyLock:Debug("Slash Handler called with: '"..(msg or "nil").."'") 
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
		DEFAULT_CHAT_FRAME:AddMessage("LazyLock Consumables Check: "..(LazyLockDB.checkConsumables and "ON" or "OFF"))
		
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
			DEFAULT_CHAT_FRAME:AddMessage("LazyLock: Default Curse set to |cff71d5ff"..curse.."|r")
		else
			DEFAULT_CHAT_FRAME:AddMessage("LazyLock: Invalid curse alias. Usage: /ll curse [agony/elements/shadow/recklessness/tongues/weakness/doom]")
		end
		
	elseif cmd == "export" then
		LazyLock:ExportStats()
		
	elseif cmd == "puke" then
		LazyLock:Report(true, false)
		
	elseif cmd == "say" then
		if args == "on" then LazyLockDB.reportToSay = true
		elseif args == "off" then LazyLockDB.reportToSay = false
		else LazyLockDB.reportToSay = not LazyLockDB.reportToSay end
		DEFAULT_CHAT_FRAME:AddMessage("LazyLock Say Report: "..(LazyLockDB.reportToSay and "ON" or "OFF"))
	
	elseif cmd == "help" then
		DEFAULT_CHAT_FRAME:AddMessage("|cff71d5ffLazyLock Commands:|r")
		DEFAULT_CHAT_FRAME:AddMessage("/ll check [on/off] - Toggle consumable check")
		DEFAULT_CHAT_FRAME:AddMessage("/ll curse [name] - Set default curse")
		DEFAULT_CHAT_FRAME:AddMessage("/ll export - Show gathered stats")
		DEFAULT_CHAT_FRAME:AddMessage("/ll puke - Show last fight report (Chat)")
		DEFAULT_CHAT_FRAME:AddMessage("/ll say [on/off] - Toggle report to Say channel")
		
	else
		LazyLock:Cast()
	end
end