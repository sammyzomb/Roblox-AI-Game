--!strict
-- Presentation-only reading of a server CombatEvent Hit.
--
-- The server already decided Damage, Blocked and Absorbed. This module only
-- checks those fields and builds the short label a floating text can show.
-- It does not apply damage, read CombatRequest, or create BillboardGui,
-- TweenService, or any other Instance. A nil return means "show nothing".

local DamageFloat = {}

-- Bound how many labels a client keeps at once, and how long each one lasts.
-- These are presentation limits, not combat rules.
DamageFloat.MAX_SIMULTANEOUS = 8
DamageFloat.LIFETIME_SECONDS = 0.8

export type Tone = "Damage" | "FullBlock" | "PartialBlock" | "Absorb" | "PartialAbsorb"

export type Rgb = { number }

export type HitDisplay = {
	Damage: number,
	Blocked: number?,
	Absorbed: number?,
	Text: string,
	Tone: Tone,
}

local COLOR_DAMAGE: Rgb = { 255, 72, 64 }
local COLOR_FULL_BLOCK: Rgb = { 214, 220, 230 }
local COLOR_PARTIAL_BLOCK: Rgb = { 255, 176, 48 }
local COLOR_ABSORB: Rgb = { 96, 196, 255 }
local COLOR_PARTIAL_ABSORB: Rgb = { 150, 220, 255 }

local function finiteNumber(value: unknown): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

-- absent -> ok, nil. present and usable -> ok, amount. present and bad -> not ok.
local function optionalAmount(value: unknown): (boolean, number?)
	if value == nil then
		return true, nil
	end
	local amount = finiteNumber(value)
	if amount == nil or amount < 0 then
		return false, nil
	end
	return true, amount
end

local function formatAmount(value: number): string
	if value == math.floor(value) then
		return string.format("%.0f", value)
	end
	return tostring(value)
end

local function classify(damage: number, blocked: number?, absorbed: number?): HitDisplay
	local showBlock = blocked ~= nil and blocked > 0
	local showAbsorb = absorbed ~= nil and absorbed > 0
	local label = ""
	if showBlock and showAbsorb then
		label = " Block Absorb"
	elseif showBlock then
		label = " Block"
	elseif showAbsorb then
		label = " Absorb"
	end

	local tone: Tone = "Damage"
	if showBlock and damage == 0 then
		tone = "FullBlock"
	elseif showBlock then
		tone = "PartialBlock"
	elseif showAbsorb and damage == 0 then
		tone = "Absorb"
	elseif showAbsorb then
		tone = "PartialAbsorb"
	end

	local display: HitDisplay = {
		Damage = damage,
		Blocked = blocked,
		Absorbed = absorbed,
		Text = formatAmount(damage) .. label,
		Tone = tone,
	}
	return display
end

function DamageFloat.normalizeHit(event: unknown): HitDisplay?
	if type(event) ~= "table" then
		return nil
	end
	local record = event :: { [string]: unknown }
	if record.Kind ~= "Hit" then
		return nil
	end
	local damage = finiteNumber(record.Damage)
	if damage == nil or damage < 0 then
		return nil
	end
	local blockedOk, blocked = optionalAmount(record.Blocked)
	if not blockedOk then
		return nil
	end
	local absorbedOk, absorbed = optionalAmount(record.Absorbed)
	if not absorbedOk then
		return nil
	end

	return classify(damage, blocked, absorbed)
end

function DamageFloat.toneRgb(tone: string): Rgb?
	if tone == "Damage" then
		return COLOR_DAMAGE
	elseif tone == "FullBlock" then
		return COLOR_FULL_BLOCK
	elseif tone == "PartialBlock" then
		return COLOR_PARTIAL_BLOCK
	elseif tone == "Absorb" then
		return COLOR_ABSORB
	elseif tone == "PartialAbsorb" then
		return COLOR_PARTIAL_ABSORB
	end
	return nil
end

-- How many already-shown labels to drop before showing one more.
-- nil means the count itself is unusable and the caller should show nothing.
function DamageFloat.slotsToRetire(activeCount: number): number?
	if type(activeCount) ~= "number" then
		return nil
	end
	if activeCount ~= math.floor(activeCount) or activeCount < 0 or activeCount == math.huge then
		return nil
	end
	local overflow = activeCount + 1 - DamageFloat.MAX_SIMULTANEOUS
	if overflow <= 0 then
		return 0
	end
	return overflow
end

return DamageFloat
