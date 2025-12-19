-- LazyLock Core
-- Frame is initialized in LazyLock_Data.lua

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
	"CHAT_MSG_SPELL_SELF_BUFF",
	"CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS",
	"CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
	"VARIABLES_LOADED"
}

function LazyLock:Initialize()
	if LazyLockDB == nil then
		LazyLockDB = {}
	end
    -- ... (existing checks) ...
	if LazyLockDB.checkConsumables == nil then
		LazyLockDB.checkConsumables = true
	end
    
    -- Initialize Runtime Tables
    LazyLock.RecentHeals = {} 
    LazyLock.MovingAverages = {}
    
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
    if LazyLockDB.LTCounter == nil then
        LazyLockDB.LTCounter = 0
    end
	if LazyLockDB.impAutoAttack == nil then
		LazyLockDB.impAutoAttack = false
	end
	if LazyLockDB.debugPrint == nil then
		LazyLockDB.debugPrint = true
	end
	
	if LazyLock.Settings == nil then
		LazyLock.Settings = {}
	end
	
	-- Need to ensure Default is loaded (from Data module)
	if LazyLock.Default then
		for k,v in pairs(LazyLock.Default) do
			if LazyLock.Settings[k] == nil then
				LazyLock.Settings[k] = v
			end
		end
	end
	-- Print Status Report
	local drainStatus = LazyLockDB.drainSoulMode and "|cff00ff00ON|r" or "|cffff0000OFF|r"
	local logStatus = LazyLockDB.logging and "|cff00ff00ON|r" or "|cffff0000OFF|r"
	local impStatus = LazyLockDB.impAutoAttack and "|cff00ff00ON|r" or "|cffff0000OFF|r"
	local printStatus = LazyLockDB.debugPrint and "|cff00ff00ON|r" or "|cffff0000OFF|r"
	
	LazyLock:Print("LazyLock loaded. Type /ll help for commands.")
	LazyLock:Print("Status: Drain Soul Mode ["..drainStatus.."] | Imp Auto-Attack ["..impStatus.."] | Logging ["..logStatus.."] | Print ["..printStatus.."]")

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
    LazyLock:ScanSpellCosts()
	LazyLock:Print("LazyLock: Variables Loaded.")
end

function LazyLock:Print(msg)
	if not msg then return end
	if LazyLockDB and LazyLockDB.Log and LazyLockDB.logging then
		table.insert(LazyLockDB.Log, date("%c")..": "..tostring(msg))
	end
	if LazyLockDB and LazyLockDB.debugPrint then
		DEFAULT_CHAT_FRAME:AddMessage(msg)
	end
end

function LazyLock:CheckState()
	local status = "Active"
	if not LazyLockDB then status = "Error: No DB" end
	if not LazyLock.Settings then status = "Error: No Settings" end
	return status
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

LazyLock:SetScript("OnEvent", function()
	if event == "VARIABLES_LOADED" then
		LazyLock:Initialize()
	elseif event == "PLAYER_TARGET_CHANGED" then
		LazyLock:Print("|cffff0000[LL Debug]|r Target Changed")
		LazyLock.Settings["IsCasting"] = false 

		
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
		LazyLock:Print("|cff00ff00[Action]|r Casting: "..arg1)
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
		LazyLock:ParseCombatMessage(arg1) -- Parse Damage
		if string.find(arg1,"afflicted") then
			for curse,_ in pairs(LazyLock.Settings) do
				if string.find(arg1,curse) then
					--LazyLock.Settings[curse] = GetTime()
				end
			end
		end
	elseif event == "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE" then
        -- Maybe we want to parse this too? Unlikely for Warlock DPS.
	elseif event == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" then
		LazyLock:ParseCombatMessage(arg1) -- Parse PvP DoTs
	elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" or event == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" then
		LazyLock:ParseCombatMessage(arg1)
        LazyLock:ParseSelfDamage(arg1)
        
    elseif event == "CHAT_MSG_SPELL_SELF_BUFF" 
        or event == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" 
        or event == "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF" then
        
        LazyLock:ParseHealing(arg1)


	elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
		-- Format: "X dies."
		local targetName = LazyLock.TargetTracker.name
		if targetName and targetName ~= "" and string.find(arg1, targetName) then
            -- Fix: Verify it is OUR target that died (prevent same-name false positives)
            if UnitExists("target") and UnitName("target") == targetName and not UnitIsDead("target") then
                -- We are targeting a Mob with this name, but it is NOT dead. 
                -- This death message must belong to another mob nearby. Ignore it.
                return
            end

			local dmg = LazyLock.TargetTracker.damageDone
			if dmg > 0 then
				-- Removed confusing 'My Damage' print. Now relying on Report() for accurate breakdown.
				
				-- Learn Strategy (Record Duration)
				local duration = GetTime() - LazyLock.TargetTracker.startTime
				LazyLock:UpdateMobStats(targetName, duration, UnitHealthMax("target"))
				
				LazyLock:Report(true, LazyLockDB.reportToSay)
			end
		end
	end
end)
LazyLock:Print("|cff00ff00[LL Debug] SetScript with OLD STYLE wrapper!|r")

local _, pClass = UnitClass("player")
if pClass == "WARLOCK" then

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
			LazyLock:CheckConsumables()
			
		elseif cmd == "curse" then
			LazyLock:CurseSlashHandler(args)
			
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
			LazyLock:Print("LazyLock Logging: "..(LazyLockDB.logging and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		
		elseif cmd == "print" then
			if args == "on" then LazyLockDB.debugPrint = true
			elseif args == "off" then LazyLockDB.debugPrint = false
			else LazyLockDB.debugPrint = not LazyLockDB.debugPrint end
			LazyLock:Print("LazyLock Debug Print: "..(LazyLockDB.debugPrint and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		
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

		elseif cmd == "imp" then
			if args == "on" then LazyLockDB.impAutoAttack = true
			elseif args == "off" then LazyLockDB.impAutoAttack = false
			else LazyLockDB.impAutoAttack = not LazyLockDB.impAutoAttack end
			LazyLock:Print("LazyLock Imp Auto-Attack: "..(LazyLockDB.impAutoAttack and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		
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
			LazyLock:Print("|cff71d5ffLazyLock Usage:|r")
			LazyLock:Print("/ll check - Run consumable check manually")
			LazyLock:Print("/ll curse [name] - Set default curse")
			LazyLock:Print("/ll drain [on/off] - Toggle Drain Soul mode (shard farming)")
			LazyLock:Print("/ll imp [on/off] - Toggle Imp Auto-Attack")
			LazyLock:Print("/ll say [on/off] - Toggle report to Say channel")
			
			LazyLock:Print("|cff71d5ffLazyLock Debug:|r")
			LazyLock:Print("/ll clear - Clear all debug logs")
			LazyLock:Print("/ll export - Show gathered stats")
			LazyLock:Print("/ll log [on/off] - Toggle persistent logging")
			LazyLock:Print("/ll print [on/off] - Toggle chat output")
			LazyLock:Print("/ll puke - Show last fight report (Chat)")
			LazyLock:Print("/ll test [on/off] - Toggle ALL logging (Debug + CombatLog) for testing")
		elseif cmd == "save" then
			ReloadUI()		
		else
			LazyLock:Cast()
		end
	end
else
	LazyLock:Print("|cffff0000LazyLock Disabled: Class is not Warlock ("..tostring(pClass)..")|r")
end