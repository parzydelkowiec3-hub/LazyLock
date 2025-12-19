if not LazyLock then LazyLock = {} end

LazyLock.TargetTracker = { name = nil, startTime = 0, damageDone = 0, hpHistory = {}, spells = {} }
LazyLock.LastTargetTracker = { name = nil, startTime = 0, damageDone = 0, spells = {} }

function LazyLock:UpdateMobStats(name, duration, maxHP)
	local gType = LazyLock:GetGroupType()
	
    -- Fix: Prevent Pollution by checking if we fought the mob from the start
    if LazyLock.TargetTracker and LazyLock.TargetTracker.startHP and LazyLock.TargetTracker.startHP < 95 then
        LazyLock:Print("|cffff0000[LL Debug]|r Invalid TTD Data (StartHP "..string.format("%.1f", LazyLock.TargetTracker.startHP).."% < 95%). Skipped save.")
        return
    end
	
	if not LazyLockDB.MobStats[name] then
		LazyLockDB.MobStats[name] = { maxHP = maxHP, solo = nil, party = nil, raid = nil }
	end
	
	if LazyLockDB.MobStats[name].count or (LazyLockDB.MobStats[name][gType] and not LazyLockDB.MobStats[name][gType].history) then 
		LazyLockDB.MobStats[name] = { maxHP = maxHP } 
	end
	
	if not LazyLockDB.MobStats[name][gType] then
		LazyLockDB.MobStats[name][gType] = { count = 0, avgTTD = duration, history = {}, strategies = {} }
	end
    -- Ensure strategies table exists for legacy data
    if not LazyLockDB.MobStats[name][gType].strategies then
        LazyLockDB.MobStats[name][gType].strategies = {}
    end
	
	local m = LazyLockDB.MobStats[name][gType]
	m.count = m.count + 1
	
	if not m.history then m.history = {} end
	table.insert(m.history, duration)
	if table.getn(m.history) > 50 then
		table.remove(m.history, 1) 
	end
	
	m.avgTTD = (m.avgTTD * 0.7) + (duration * 0.3)
	
	-- Update maxHP
	LazyLockDB.MobStats[name].maxHP = maxHP
    
    -- Record Strategy Performance
    local sessionStrategy = LazyLockDB.MobStats[name].strategy or "NORMAL"
    local sessionDmg = 0
    if LazyLockDB.MobStats[name].session then
        sessionDmg = LazyLockDB.MobStats[name].session.damage
    end
    
    if sessionDmg > 0 and duration > 0 then
        local dps = sessionDmg / duration
        local sTable = LazyLockDB.MobStats[name][gType].strategies
        
        if not sTable[sessionStrategy] then
            sTable[sessionStrategy] = { count = 0, totalDPS = 0, avgDPS = 0 }
        end
        
        local s = sTable[sessionStrategy]
        s.count = s.count + 1
        s.totalDPS = s.totalDPS + dps
        s.avgDPS = s.totalDPS / s.count
        
        LazyLock:Print("|cffff0000[LL Debug]|r Stat Update: "..name.." ("..sessionStrategy..") DPS: "..string.format("%.1f", dps).." (Avg: "..string.format("%.1f", s.avgDPS)..")")
    end
	
	-- Calculate and save strategy for NEXT fight
	local strategy = LazyLock:GetCombatStrategy(name, gType)
	LazyLockDB.MobStats[name].strategy = strategy
	LazyLockDB.MobStats[name][gType].strategy = strategy
	
	LazyLock:Print("|cffff0000[LL Debug]|r Saved MobStats for "..name..": TTD="..string.format("%.1f", duration).."s, Next Strategy="..strategy)
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

function LazyLock:GetCombatStrategy(name, gType)
	local safeTTD = LazyLock:AnalyzeHistory(name, gType)
    
    -- 1. Check Historical Performance (Dynamic Switching)
    if LazyLockDB.MobStats[name] and LazyLockDB.MobStats[name][gType] and LazyLockDB.MobStats[name][gType].strategies then
        local sTable = LazyLockDB.MobStats[name][gType].strategies
        local bestStrat = nil
        local maxDPS = 0
        
        -- Compare known strategies
        for stratName, data in pairs(sTable) do
            if data.count >= 3 then -- Minimum samples to trust
                if data.avgDPS > maxDPS then
                    maxDPS = data.avgDPS
                    bestStrat = stratName
                end
            end
        end
        
        if bestStrat then 
            LazyLock:Print("|cffff0000[LL Debug]|r Dynamic Strategy: "..bestStrat.." (Avg DPS: "..string.format("%.1f", maxDPS)..")")
            return bestStrat 
        end
    end

    -- 2. Fallback to TTD Logic
	if not safeTTD then return "NORMAL" end 
	
	if safeTTD < LazyLock.TTDThresholds.BURST then return "BURST" end
	if safeTTD > LazyLock.TTDThresholds.LONG then return "LONG" end
	return "NORMAL"
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
	local source = "Tracker"
	
	if LazyLockDB.MobStats[t.name] and LazyLockDB.MobStats[t.name].session then
		totalDmg = LazyLockDB.MobStats[t.name].session.damage
		spellBreakdown = LazyLockDB.MobStats[t.name].session.spells
		source = "Session"
	end
	
	-- DEBUG REPORT
	local count = 0
	for k,v in pairs(spellBreakdown) do count = count + 1 end
	LazyLock:Print("|cffff0000[LL Debug]|r Report Gen: Source="..source.." Dmg="..totalDmg.." Spells="..count)
	
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

function LazyLock:GetTTD()
	if not UnitExists("target") or UnitIsDead("target") then return 999 end
	
	local currentHP = UnitHealth("target")
	local maxHP = UnitHealthMax("target")
	if not maxHP or maxHP == 0 then maxHP = 100 end
	
	-- Normalize to Percentage (0-100) to handle both MobHealth (Real/Real) and Default (100/100)
	local currentPct = (currentHP / maxHP) * 100
	
	local now = GetTime()
	
	-- World Boss Override REMOVED. Relying on Percentage Math + History.
	
	-- Initialize Tracker
	if not LazyLock.TargetTracker.lastHP then
		LazyLock.TargetTracker.lastHP = currentPct
		LazyLock.TargetTracker.startHP = currentPct -- Store STARTING PERCENTAGE
		LazyLock.TargetTracker.startTime = now
		LazyLock.TargetTracker.lastUpdate = now
	end
	
		-- Update simple debug tracker every 1s
	if now - LazyLock.TargetTracker.lastUpdate > 1 then
		LazyLock.TargetTracker.lastHP = currentPct
		LazyLock.TargetTracker.lastUpdate = now
	end
	
	local timeElapsed = now - LazyLock.TargetTracker.startTime
	local pctLost = LazyLock.TargetTracker.startHP - currentPct
	
	LazyLock:Print("|cffff0000[LL Debug]|r % Lost: "..string.format("%.1f", pctLost).."% Time: "..string.format("%.1f", timeElapsed).."s")
	
	-- Stabilization: If < 5s elapsed or no damage, return 999 (or predicted)
	if timeElapsed < 3 or pctLost <= 0 then 
		if LazyLock.TargetTracker.predictedTTD then
			return LazyLock.TargetTracker.predictedTTD 
		end
		return 999 
	end
	
	-- Calculate DPS in terms of PERCENT per SECOND
	local pctDPS = pctLost / timeElapsed
	if pctDPS <= 0.01 then -- Very slow damage
		return 999 
	end
	
	-- Calculate TTD: current Percent / PercentDPS
	local timeToDie = currentPct / pctDPS
	LazyLock:Print("|cffff0000[LL Debug]|r TTD: "..string.format("%.1f", currentPct).."% / "..string.format("%.2f", pctDPS).."%/s = "..string.format("%.1f", timeToDie).."s")
	
	return timeToDie
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
