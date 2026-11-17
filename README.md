# Tagaria SoundFX

A WoW Forever addon that plays **your own sounds** (.mp3 / .wav) when combat
events happen: you killed a player, you died, a proc triggered, you got
crowd controlled, and more.

Each event has its own **list of sounds** — when an event fires, one is picked
**at random** (a single sound in the list always plays that one).

Built and tested against the current WoW Forever client (interface `16001`,
modern engine). The same download also works on Midnight retail and the
Classic family clients (Era, TBC Anniversary, MoP Classic, Titan Reforged),
where available detection is even better thanks to the combat log.

---

## Installation

1. Download or clone this repository and put its contents into your game's
   addon folder — the folder name must match the `.toc` file name:
   * WoW Forever: `World of Warcraft\_forever_\Interface\AddOns\TagariaSoundFX`
   * (That folder must end up containing `TagariaSoundFX.toc`, `Core.lua`,
     `Options.lua` and the `sounds` subfolder. Renaming the addon is fine:
     just rename the folder and the `.toc` file the same way.)
2. Drop your sound files (`.mp3` or `.wav`; `.ogg` also works on modern
   clients) into the `sounds` folder inside the addon.
3. Start the game, make sure the addon is enabled in the add-on list, then
   type:

   ```
   /tsfx
   ```

4. Pick an event, type the file name (e.g. `kill1.mp3`) and press **Add**.
   The sound plays immediately so you can verify it works. Press **Test**
   any time to hear a random sound from that event's list.

> WoW addons cannot list the contents of a folder, so every sound file has to
> be named once in the addon's options. This is a Blizzard limitation, not a
> bug. Full file paths (with `\` in them) are also accepted, so you can point
> an event at built-in game sounds such as
> `Sound\Creature\Illidan\BLACK_Temple01.wav` if you want to.

---

## Events

| Event | Plays when | Default |
|---|---|---|
| Killing Blow on a Player | you (or your pet) land the killing blow on an enemy player | on |
| Killing Blow on a Mob | you (or your pet) kill something that is not a player | off |
| You Died | you die | on |
| You Died to a Player (PvP Death) | you die to an enemy player, or within the PvP death window (default 15s) of being damaged by one | on |
| Proc / Buff Trigger | one of your tracked buffs (see below) is applied to you | on |
| Critical Hit on a Player | you critically hit an enemy player without killing them | off |
| Interrupt or Silence | you successfully interrupt a target's cast, or land a silence on your target | on |
| You Got Crowd Controlled | you are feared, rooted, stunned, polymorphed, slept, sapped, charmed or mind controlled | on |
| Double / Triple / Quad / Multi Kill | 2 / 3 / 4 / 5+ player kills inside the streak window (default 8s) | off |
| Entering / Leaving Combat | you enter or leave combat | off |

Notes:

* If a PvP death is detected, the PvP death sound replaces the plain "You
  Died" sound (never both).
* Streak sounds play in addition to the kill sound.
* Honorable kills are what the game credits to you (green-level or higher
  enemies, world PvP / battlegrounds). Kills of gray enemies give no credit,
  so on the WoW Forever client they are only detected when the client lets
  the addon see who the victim was.

### Procs

A "proc" is any buff appearing on you whose **spell name** (e.g. `Crusader`,
`Berserking`) or **spell ID** is on the Proc list. Open `/tsfx`, select the
**Proc / Buff Trigger** event, add your proc spells, and give the event one
or more sounds.

### Interrupts and silences

* **Interrupts** are detected directly: the modern client reports *who*
  interrupted a cast (`UNIT_SPELLCAST_INTERRUPTED` with the interrupter's
  GUID), and Classic clients report every interrupt through the combat log.
  Any interrupt spell works — no configuration needed.
* **Silences** are recognized by spell: a built-in list covers Kick, Pummel,
  Shield Bash, Counterspell, Earth Shock, Spell Lock and Silence (all ranks,
  by name and ID), and you can add more in the options under the
  **Interrupt or Silence** event. On WoW Forever a silence is detected when
  you land it on your **target**; on Classic clients it works on anyone.

### Crowd control

Plays when a crowd control effect lands on you: fears, roots, stuns,
polymorphs, sleep, sap, charm / mind control, daze and paralysis. It is
matched by the effect's type (the client's CC "mechanic": feared, rooted,
stunned, polymorph, ...) and by its name, so it works on any client that
exposes aura data — on WoW Forever and on Classic-family clients. Silence
and snares are **not** crowd control (you can still act or move).

### PvP deaths

* On Classic-family clients every hit you take from an enemy player is
  remembered: if you die within the **PvP death window** (15 seconds by
  default, adjustable in the options), the PvP death sound plays instead of
  the normal death sound.
* On WoW Forever the addon uses the game's death recap (the same list of
  killing blows the death recap UI shows) plus active-battleground checks —
  any death inside a battleground or arena counts as a PvP death. When the
  client hides the recap's sources, the plain death sound plays.

---

## How detection works (important for WoW Forever)

WoW Forever runs Blizzard's modern client engine, which **does not give
addons a combat log** and restricts combat data ("secret values"). The addon
therefore uses the supported replacement signals:

* **Killing blows** — Blizzard's `PARTY_KILL` event (attacker + victim) plus
  the game's own honorable-kill credit (`PLAYER_PVP_KILLS_CHANGED` /
  session kill counter). Works in open world and battlegrounds.
* **Your death** — `PLAYER_DEAD`. Always works.
* **Procs** — your own aura data (`UNIT_AURA`), read through
  secret-value-safe guards.
* **Crowd control** — your own aura data (`UNIT_AURA`) again, matched by the
  CC mechanic of the effect that lands on you (fear, root, stun, polymorph,
  mind control, ...) with a name fallback.
* **Crit hits** — the client does not expose your *outgoing* crits. The
  optional, experimental **"Watch my target's combat text"** option tells the
  game to watch your **target** for floating combat text; when your target
  takes a critical hit (usually from you), the crit event can fire. Side
  effect: your own floating combat text then shows your target's damage taken
  instead, so leave it off if you use the built-in floating combat text.
* On **Classic family clients** (which still have a combat log), kills and
  crit hits are detected directly from the combat log — fully and without the
  experiment above.

Enable **debug mode** (`/tsfx debug`) to see every signal the addon receives;
restricted values are shown as `<secret>`.

---

## Options

Open with `/tsfx`, Esc → Options → AddOns → Tagaria SoundFX, or the addon
compartment button near the minimap (right-click it to toggle the addon on/off).

* **Enabled** — master switch: turning it on enables every event, turning
  it off disables every event.
* **Only my killing blows** — in a group, stay silent for kills a group
  member finished off (when the client can tell who it was). If the client
  can't tell, the kill still counts.
* **Sound channel** — *Master volume* (plays even with Sound Effects muted)
  or *Sound Effects volume*.
* **Kill streak window** — seconds in which consecutive player kills count
  as Double/Triple/Quad/Multi kills.
* **PvP death window** — seconds in which enemy player damage before dying
  still counts as a death to a player (15 by default).
* Per event: enable/disable, sound list with **Test** / **X** (remove),
  **Add** by file name, and a per-event detectability status line.

Settings are stored per character in `WTF\Account\...\SavedVariables\TagariaSoundFXDB.lua`.

## Slash commands

| Command | Action |
|---|---|
| `/tsfx` | open the options panel |
| `/tsfx on` / `off` / `toggle` | enable / disable / toggle the addon |
| `/tsfx status` | list all events, sound counts and client capabilities |
| `/tsfx test <event>` | play a random sound for an event (e.g. `/tsfx test kill`) |
| `/tsfx watchtarget on\|off` | toggle experimental crit detection |
| `/tsfx debug` | toggle debug output for troubleshooting |

`/tagaria` works as an alias.

---

## Troubleshooting

* **A sound doesn't play.** Use the **Test** button next to it. Check the
  spelling and the extension, and make sure the file really is in the
  addon's `sounds` folder. Files with spaces are fine.
* **No sound when you kill a player.** With *Only my killing blows* on and a
  group/raid present, kills finished by others stay silent. In battlegrounds
  the addon relies on kill credit that the game awards for honorable kills.
  Run `/tsfx debug` while fighting to see what the client reports.
* **Crit sounds never play.** On WoW Forever they need the experimental
  *Watch my target's combat text* option (see above), and you must have your
  victim targeted. On Classic clients they work out of the box.
* **Everything is silent.** Check the master **Enabled** checkbox, the
  per-event checkbox, and that the file names were added to the event.

## Credits

The modern-client detection approach (PARTY_KILL + honorable kill credit,
secret-value guards) follows the patterns proven by open-source addons such
as [HonorSnap](https://github.com/vityachis/HonorSnap), which keeps this
addon within the rules Blizzard set for WoW Forever and Midnight.
