--!strict
-- Pure level/xp math. No Roblox APIs, so it can be unit tested with the Luau CLI.

export type Settings = {
	BaseXp: number,
	Growth: number,
	MaxLevel: number,
}

local Progression = {}

-- Xp needed to advance from `level` to `level + 1`.
function Progression.xpToNextLevel(level: number, settings: Settings): number
	return math.floor(settings.BaseXp * settings.Growth ^ (level - 1))
end

-- Adds xp and resolves any level-ups.
-- Returns the new level, the leftover xp and how many levels were gained.
-- At MaxLevel xp stays at 0.
function Progression.addXp(level: number, xp: number, amount: number, settings: Settings): (number, number, number)
	assert(amount >= 0, "xp amount must be non-negative")

	local gained = 0
	xp += amount
	while level < settings.MaxLevel do
		local needed = Progression.xpToNextLevel(level, settings)
		if xp < needed then
			break
		end
		xp -= needed
		level += 1
		gained += 1
	end

	if level >= settings.MaxLevel then
		level = settings.MaxLevel
		xp = 0
	end

	return level, xp, gained
end

return Progression
