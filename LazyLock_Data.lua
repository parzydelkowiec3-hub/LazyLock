-- Initialize Core Frame here to ensure it exists for all modules
LazyLock = CreateFrame("Frame", "LazyLockFrame", UIParent)
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
LazyLock.Consumables = {
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

LazyLock.TTDThresholds = {
	BURST = 10,
	LONG = 30
}

LazyLock.StrategyDefinitions = {
	BURST = { 
		"Drain Soul", 
		"Shadowburn", 
		"Searing Pain" 
	},
	NORMAL = { 
		"Drain Soul", 
		"Shadowburn", 
		"Curse", 
		"Immolate", 
		"Siphon Life", 
		"Corruption", 
		"Shadow Bolt", 
		"Searing Pain", 
		"Shoot" 
	},
	LONG = { 
		"Drain Soul", 
		"Curse", 
		"Immolate", 
		"Siphon Life", 
		"Corruption", 
		"Shadow Bolt", 
		"Searing Pain", 
		"Shoot" 
	}
}

LazyLock.HealingBuffs = {
	"Renew",
	"Rejuvenation",
	"Regrowth"
}

