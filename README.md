# LazyLock

# LazyLock

**Author:** Tuziak  
**Version:** 1.2  
**WoW Version:** 1.12.1 (Compatible with **Turtle WoW**)

LazyLock is an advanced automation addon for Warlocks that optimizes your DPS rotation based on **statistical analysis** and **historical data**.

## Features

### 🧠 Smart Decision Making
Instead of a blind rotation, LazyLock analyzes the target::
- **TTD Estimator:** Calculates how fast the target is dying (Real-time & Historical).
- **Historical Learning:** Remembers "Safe TTD" for every mob you kill.
- **Dynamic Strategies:**
    - **BURST (< 10s):** Shadowburn -> Searing Pain spam. (No DoTs).
    - **NORMAL (10-30s):** Immolate -> Corruption -> Shadowburn -> Shadow Bolt.
    - **LONG (> 30s):** Full DoTs (Curse/Siphon) -> Filler.

### ⚔️ DPS Maximization
- **Auto Cooldowns:** Automatically uses Trinkets and Racials (Blood Fury/Berserking).
- **Shadowburn Logic:**
  - **Execute:** Casts when target < 25% HP or < 15s TTD.
  - **Excess Shards:** If you have >= 20 Soul Shards, spam Shadowburn on cooldown.
  - **Lethal Check:** Learns your average Shadowburn damage and executes instantly if `Health < AvgDmg`.
- **Advanced Curse Logic:**
  - Unified handling for "Base Curse applies Agony" side-effects.
  - Supports all curses (Doom, Tongues, Elements, etc.).

### 🔮 Soul Shard Farming
- **Auto Drain Soul:** Configurable mode to automatically use Drain Soul when target < 25% HP.
- **Priority System:** Overrides other spells to ensure shard collection before mob death.
- **Toggleable:** Enable only when you need shards with `/ll drain`.

### 📊 Reporting & Analytics
- **Detailed Logs:** Tracks damage per spell for every combat.
- **Reporting:** View last fight stats with `/ll puke`.
- **Auto-Say:** Toggle announcing damage/strategy to `/say` channel.
- **Log Management:** Clear old logs to save space with `/ll clear`.

## Usage

**Main Macro:**
Bind this to your main attack key (e.g., MouseWheelUp/Down or a button):
```lua
/lazylock
```
or
```lua
/ll
```

**Commands:**
- `/ll help`- List all commands.
- `/ll puke` - Print detailed report of last fight to Chat.
- `/ll say [on/off]` - Toggle announcing report to Say channel (Default: Off).
- `/ll curse [agony/elements/shadow/recklessness/tongues/weakness/doom]` - Set your default curse.
- `/ll drain [on/off]` - Toggle Drain Soul mode for shard farming (Default: Off).
- `/ll test [on/off]` - Toggle ALL logging (Debug + CombatLog) for testing.
- `/ll log [on/off]` - Toggle persistent debug logging (Default: Off).
- `/ll clear` - Clear all saved debug logs.
- `/ll check [on/off/toggle]` - Enable/Disable consumable warnings.
- `/ll export` - Print collected Spell Stats and historical Mob Strategies database.

## Installation
1. Extract the folder to `Interface/AddOns/LazyLock`.
2. Ensure the folder is named `LazyLock`.
3. Launch WoW.
