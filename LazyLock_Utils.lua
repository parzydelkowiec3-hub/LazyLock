

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
			else
				-- Fix: If unit has debuff but no time info (1.12), assume it is active
				return 10 
			end
		end
		i = i + 1
	end
	return 0
end

function LazyLock:GetGroupType()
	if GetNumRaidMembers() > 0 then return "raid" end
	if GetNumPartyMembers() > 0 then return "party" end
	return "solo"
end

function LazyLock:GetBuffName(unit, index)
	LazyLockTooltip:ClearLines()
	LazyLockTooltip:SetUnitBuff(unit, index)
	local buffName = LazyLockTooltipTextLeft1:GetText()
	return buffName
end

function LazyLock:KnowsSpell(spellName)
	local i = 1
	while true do
		local spell, rank = GetSpellName(i, BOOKTYPE_SPELL)
		if not spell then break end
		if spell == spellName then return true end
		i = i + 1
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
    
    -- Spell not found in book. Return TRUE (Unavailable) to stop spam attempts.
    return true 
end

-- Parse healing events to populate RecentHeals
function LazyLock:ParseHealing(msg)
    if not msg then return end
    
    local amount = 0
    -- Pattern 1: Direct Heals "X heals you for Y."
    local _, _, direct = string.find(msg, "heals you for (%d+)")
    if direct then amount = tonumber(direct) end

    -- Pattern 2: HoTs "You gain X health from Y."
    if amount == 0 then
        local _, _, hot = string.find(msg, "gain (%d+) health")
        if hot then amount = tonumber(hot) end
    end
    
    if amount > 0 then
        if not LazyLock.RecentHeals then LazyLock.RecentHeals = {} end
        table.insert(LazyLock.RecentHeals, { time = GetTime(), amount = amount })
        -- LazyLock:Print("|cff00ff00[LL Debug]|r Healing Detected: +"..amount)
    end
end

-- Generic Moving Average Updater
function LazyLock:UpdateMovingAverage(key, value, windowSize)
    if not LazyLock.MovingAverages then LazyLock.MovingAverages = {} end
    if not LazyLock.MovingAverages[key] then 
        LazyLock.MovingAverages[key] = { history = {}, avg = 0 } 
    end
    
    local ma = LazyLock.MovingAverages[key]
    table.insert(ma.history, value)
    
    -- Prune
    local historySize = table.getn(ma.history)
    if historySize > windowSize then
        table.remove(ma.history, 1)
        historySize = historySize - 1
    end
    
    -- Recalculate Average
    local sum = 0
    for _, v in ipairs(ma.history) do
        sum = sum + v
    end
    ma.avg = sum / historySize
    
    -- LazyLock:Print("|cff71d5ff[MA Update]|r "..key..": "..value.." (Avg: "..string.format("%.1f", ma.avg)..")")
end

-- Parse Self Damage for Life Tap
function LazyLock:ParseSelfDamage(msg)
    if not msg then return end
    
    -- "Your Life Tap hits you for 240."
    local _, _, dmg = string.find(msg, "Your Life Tap hits you for (%d+)")
    if dmg then
        LazyLock:UpdateMovingAverage("LifeTapCost", tonumber(dmg), 30)
        return
    end
    
    -- "You suffer 240 damage from your Life Tap."
    local _, _, dmg2 = string.find(msg, "suffer (%d+) damage from your Life Tap")
    if dmg2 then
        LazyLock:UpdateMovingAverage("LifeTapCost", tonumber(dmg2), 30)
    end
end

-- Helper to get Life Tap health cost AND mana gain from tooltip
function LazyLock:GetLifeTapValues()
    if not LazyLockDB.LTCounter then LazyLockDB.LTCounter = 0 end
    LazyLockDB.LTCounter = LazyLockDB.LTCounter + 1

    local curHealthAvg, curManaAvg = 0, 0
    if LazyLock.MovingAverages then
        if LazyLock.MovingAverages["LifeTapCost"] then curHealthAvg = LazyLock.MovingAverages["LifeTapCost"].avg end
        if LazyLock.MovingAverages["LifeTapMana"] then curManaAvg = LazyLock.MovingAverages["LifeTapMana"].avg end
    end

    -- Update from Tooltip every 30 calls OR if we have no data yet
    -- This keeps the average "alive" with theoretical values if combat data is sparse
    if (math.mod(LazyLockDB.LTCounter, 30) == 0) or (curHealthAvg == 0) then
        local i = 1
        while true do
            local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
            if not spellName then break end
            
            if spellName == "Life Tap" then
                LazyLockTooltip:ClearLines()
                LazyLockTooltip:SetSpell(i, BOOKTYPE_SPELL)
                -- Iterate lines to find "Converts X health into Y mana"
                for j=2, LazyLockTooltip:NumLines() do
                    local line = getglobal("LazyLockTooltipTextLeft"..j)
                    if line then
                        local text = line:GetText()
                        if text then
                            local _, _, cost, mana = string.find(text, "Converts (%d+) health into (%d+) mana")
                            if cost and mana then 
                                -- Feed tooltip data into Moving Average
                                LazyLock:UpdateMovingAverage("LifeTapCost", tonumber(cost), 30)
                                LazyLock:UpdateMovingAverage("LifeTapMana", tonumber(mana), 30)
                                
                                -- Refresh local ref
                                if LazyLock.MovingAverages["LifeTapCost"] then curHealthAvg = LazyLock.MovingAverages["LifeTapCost"].avg end
                                if LazyLock.MovingAverages["LifeTapMana"] then curManaAvg = LazyLock.MovingAverages["LifeTapMana"].avg end
                                
                                return curHealthAvg, curManaAvg 
                            end
                        end
                    end
                end
                break -- Found
            end
            i = i + 1
        end
    end
    
    local retHealth = (curHealthAvg > 0) and curHealthAvg or 9999
    local retMana = (curManaAvg > 0) and curManaAvg or 0
    return retHealth, retMana
end

function LazyLock:GetLifeTapCost()
    local hp, _ = LazyLock:GetLifeTapValues()
    return hp
end

function LazyLock:ScanSpellCosts()
    if not LazyLock.SpellCosts then LazyLock.SpellCosts = {} end
    local i = 1
    while true do
        local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        
        -- Check if it's a spell we care about
        local track = false
        if spellName == "Shadow Bolt" or spellName == "Immolate" or spellName == "Corruption" 
        or spellName == "Siphon Life" or spellName == "Curse of Agony" then
            track = true
        end
        
        if track then
             -- We want the highest rank cost usually. 
             -- Since we scan the whole book, we'll just overwrite, assuming higher ranks appear later or we just want *a* cost.
             -- Actually, scanning tooltips for "X Mana"
             LazyLockTooltip:ClearLines()
             LazyLockTooltip:SetSpell(i, BOOKTYPE_SPELL)
             local text = LazyLockTooltipTextLeft2:GetText()
             if text then
                 local _, _, cost = string.find(text, "(%d+) Mana")
                 if cost then
                     LazyLock.SpellCosts[spellName] = tonumber(cost)
                 end
             end
        end
        i = i + 1
    end
end

function LazyLock:IsPlayerReceivingHealing(threshold)
    if not LazyLock.RecentHeals then return false end
    
    local now = GetTime()
    local totalHealing = 0
    if not threshold then threshold = LazyLock:GetLifeTapCost() end
    local timeWindow = 3.0
    
    -- Prune and Sum
    local i = 1
    while i <= table.getn(LazyLock.RecentHeals) do
        if now - LazyLock.RecentHeals[i].time > timeWindow then
            table.remove(LazyLock.RecentHeals, i)
        else
            totalHealing = totalHealing + LazyLock.RecentHeals[i].amount
            i = i + 1
        end
    end
    
    if totalHealing >= threshold then
        LazyLock:Print("|cff00ff00[LL Debug]|r Recent Healing: "..totalHealing)
        return true
    end
    
    return false
end
