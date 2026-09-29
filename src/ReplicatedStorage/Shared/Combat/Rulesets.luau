--!strict
-- Rulesets let PvE and PvP share one combat core. A ruleset only changes
-- WHO can be targeted and HOW numbers are scaled; the combat flow is identical.
--
-- Extension point: add a ruleset (e.g. a "Duel" or a level-bracket arena) here.
-- Round logic (scores, timers, respawns) does NOT belong in a ruleset; it lives
-- in the mode/arena service that listens to CombatService signals.

local Types = require("./Types")

type Ruleset = Types.Ruleset
type Combatant = Types.Combatant

local RULESETS: { [string]: Ruleset } = {
	-- Open world / dungeons: players fight NPCs, never each other.
	PvE = {
		Id = "PvE",
		Targeting = {
			PlayerVsPlayer = false,
			PlayerVsNPC = true,
			NPCVsPlayer = true,
			NPCVsNPC = false,
			FriendlyFire = false,
		},
		DamageMultiplier = 1,
		ResistCap = 0.75,
	},

	-- Arenas: players fight players. Normalized so PvE gear and levels help,
	-- but cannot dominate: levels above the bracket cap stop scaling damage,
	-- armor and resists are capped, damage and healing are scaled down to
	-- lengthen time-to-kill and keep skill relevant.
	PvP = {
		Id = "PvP",
		Targeting = {
			PlayerVsPlayer = true,
			PlayerVsNPC = false,
			NPCVsPlayer = false,
			NPCVsNPC = false,
			FriendlyFire = false,
		},
		DamageMultiplier = 0.6,
		ArchetypeMultipliers = {},
		LevelCap = 30,
		ArmorCap = 40,
		ResistCap = 0.5,
		HealingMultiplier = 0.5,
	},
}

for _, ruleset in RULESETS do
	table.freeze(ruleset.Targeting)
	if ruleset.ArchetypeMultipliers then
		table.freeze(ruleset.ArchetypeMultipliers)
	end
	table.freeze(ruleset)
end
table.freeze(RULESETS)

local Rulesets = {}

function Rulesets.get(id: string): Ruleset
	local ruleset = RULESETS[id]
	assert(ruleset, `unknown ruleset "{id}"`)
	return ruleset
end

function Rulesets.exists(id: string): boolean
	return RULESETS[id] ~= nil
end

-- Can `attacker` damage `target` under `ruleset`? Returns false + reason if not.
function Rulesets.canTarget(ruleset: Ruleset, attacker: Combatant, target: Combatant): (boolean, string?)
	if attacker == target then
		return false, "Self"
	end
	if not target.Alive then
		return false, "TargetDead"
	end
	if attacker.Team ~= nil and attacker.Team == target.Team and not ruleset.Targeting.FriendlyFire then
		return false, "SameTeam"
	end
	local t = ruleset.Targeting
	local allowed
	if attacker.Kind == "Player" then
		allowed = if target.Kind == "Player" then t.PlayerVsPlayer else t.PlayerVsNPC
	else
		allowed = if target.Kind == "Player" then t.NPCVsPlayer else t.NPCVsNPC
	end
	if not allowed then
		return false, "TargetNotAllowed"
	end
	return true, nil
end

return table.freeze(Rulesets)
