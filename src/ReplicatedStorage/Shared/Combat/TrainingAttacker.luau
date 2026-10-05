--!strict
-- Development-only cadence and target choice for the one scene dummy that
-- practices blocking. This module does not create instances, move anyone,
-- grant rewards, or change damage. The numbers below are not approved
-- balance and are not the training sword's own Range or Recovery.
--
-- DEVELOPMENT_PRACTICE_RANGE is horizontal XZ studs from the attacker root.
-- 10 is inside the existing melee reach used by CombatService (sword range
-- 7, plus the existing melee tolerance and hit radius), so a selected
-- player can actually be hit by the current Primary swing.
--
-- DEVELOPMENT_BYSTANDER_CLEARANCE is also horizontal XZ studs. 12 is a
-- safety buffer, not release balance. The current training_sword Primary
-- can connect when the 3D distance between roots is at most 11 studs
-- (Range 7 + MeleeRangeTolerance 2 + hit radius 2). Horizontal distance is
-- never larger than that 3D distance, so anyone who could be hit is inside
-- this clearance. The only allowed swing is when exactly one registered,
-- alive player with a finite root is inside it, and that same player is
-- training and inside DEVELOPMENT_PRACTICE_RANGE. A second such player
-- suppresses the swing. Suppression is not an attempt and does not advance
-- the cadence.
--
-- Public API:
--   TrainingAttacker.DEVELOPMENT_INTERVAL_SECONDS
--   TrainingAttacker.DEVELOPMENT_PRACTICE_RANGE
--   TrainingAttacker.DEVELOPMENT_BYSTANDER_CLEARANCE
--   TrainingAttacker.initial(now) -> State
--   TrainingAttacker.adopt(state, attackerId, now) -> State
--       Binds one attacker. The same id keeps its cadence. A different id
--       replaces it and the previous id is no longer active.
--   TrainingAttacker.retire(state, attackerId) -> State
--       Clears that id only. Retiring an id that is not current is a no-op.
--   TrainingAttacker.isDue(state, attackerId, now) -> boolean
--   TrainingAttacker.step(state, probe) -> (Decision, State)
--       At most one Attack per interval. The returned state is already
--       advanced when the decision is Attack, including when the caller
--       later finds that the combat core rejected the swing. Wait, Skip,
--       and Inactive do not move the next due time. A replaced attacker
--       cannot spend or receive the current attacker's turn.

export type Vec3 = { X: number, Y: number, Z: number }

export type Candidate = {
	Id: unknown,
	TieKey: string,
	Training: boolean,
	Registered: boolean,
	Alive: boolean,
	Root: Vec3?,
}

export type State = {
	AttackerId: unknown,
	NextDue: number,
}

export type Action = "Attack" | "Wait" | "Skip" | "Inactive"

export type Decision = {
	Action: Action,
	TargetId: unknown?,
	Aim: Vec3?,
}

export type Probe = {
	Now: number,
	AttackerId: unknown,
	AttackerAlive: boolean,
	Origin: Vec3?,
	Candidates: { Candidate },
}

local TrainingAttacker = {
	-- Seconds between practice swings. Not an approved attack speed.
	DEVELOPMENT_INTERVAL_SECONDS = 2.5,
	-- Horizontal studs. Not an approved weapon range.
	DEVELOPMENT_PRACTICE_RANGE = 10,
	-- Horizontal studs. Safety buffer over the 11-stud melee bound, not balance.
	DEVELOPMENT_BYSTANDER_CLEARANCE = 12,
}

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function finiteOrigin(origin: Vec3?): Vec3?
	if origin == nil or not finite(origin.X) or not finite(origin.Y) or not finite(origin.Z) then
		return nil
	end
	return origin
end

function TrainingAttacker.initial(now: number): State
	return {
		AttackerId = nil,
		NextDue = if finite(now) then now else 0,
	}
end

function TrainingAttacker.adopt(state: State, attackerId: unknown, now: number): State
	if state.AttackerId == attackerId then
		return state
	end
	return {
		AttackerId = attackerId,
		NextDue = if finite(now) then now else 0,
	}
end

function TrainingAttacker.retire(state: State, attackerId: unknown): State
	if state.AttackerId ~= attackerId then
		return state
	end
	return {
		AttackerId = nil,
		NextDue = state.NextDue,
	}
end

function TrainingAttacker.isDue(state: State, attackerId: unknown, now: number): boolean
	return state.AttackerId == attackerId and finite(now) and now >= state.NextDue
end

local function horizontalDistanceSquared(origin: Vec3, root: Vec3): number?
	if not finite(root.X) or not finite(root.Y) or not finite(root.Z) then
		return nil
	end
	local dx = root.X - origin.X
	local dz = root.Z - origin.Z
	return dx * dx + dz * dz
end

type Ranked = {
	Distance: number,
	TieKey: string,
	Index: number,
	Id: unknown,
	Aim: Vec3,
}

local function insideClearance(origin: Vec3, candidate: Candidate, clearanceSquared: number): boolean
	if candidate.Registered ~= true or candidate.Alive ~= true then
		return false
	end
	local root = candidate.Root
	if root == nil then
		return false
	end
	local distance = horizontalDistanceSquared(origin, root)
	return distance ~= nil and distance <= clearanceSquared
end

-- Registered, alive players with a finite root. Training is not required:
-- a bystander in the clearance is enough to withhold the swing.
local function clearanceOccupantCount(origin: Vec3, candidates: { Candidate }, clearanceSquared: number): number
	local count = 0
	for _, candidate in candidates do
		if insideClearance(origin, candidate, clearanceSquared) then
			count += 1
		end
	end
	return count
end

local function selectTarget(origin: Vec3, candidates: { Candidate }, rangeSquared: number): Ranked?
	local ranked: { Ranked } = {}
	for index, candidate in candidates do
		local eligible = candidate.Training == true
			and candidate.Registered == true
			and candidate.Alive == true
			and type(candidate.TieKey) == "string"
		if eligible then
			local root = candidate.Root
			local distance = if root then horizontalDistanceSquared(origin, root) else nil
			if root and distance and distance <= rangeSquared then
				table.insert(ranked, {
					Distance = distance,
					TieKey = candidate.TieKey,
					Index = index,
					Id = candidate.Id,
					Aim = { X = root.X, Y = root.Y, Z = root.Z },
				})
			end
		end
	end
	table.sort(ranked, function(a, b)
		if a.Distance ~= b.Distance then
			return a.Distance < b.Distance
		end
		if a.TieKey ~= b.TieKey then
			return a.TieKey < b.TieKey
		end
		return a.Index < b.Index
	end)
	return ranked[1]
end

local function decide(action: Action, target: Ranked?): Decision
	if action ~= "Attack" or target == nil then
		return { Action = action }
	end
	return {
		Action = "Attack",
		TargetId = target.Id,
		Aim = target.Aim,
	}
end

function TrainingAttacker.step(state: State, probe: Probe): (Decision, State)
	if state.AttackerId ~= probe.AttackerId then
		return decide("Inactive"), state
	end
	local origin = finiteOrigin(probe.Origin)
	if probe.AttackerAlive ~= true or origin == nil or not finite(probe.Now) then
		return decide("Skip"), state
	end
	if probe.Now < state.NextDue then
		return decide("Wait"), state
	end
	local candidates = probe.Candidates
	if type(candidates) ~= "table" then
		return decide("Skip"), state
	end
	local clearance = TrainingAttacker.DEVELOPMENT_BYSTANDER_CLEARANCE
	if clearanceOccupantCount(origin, candidates, clearance * clearance) ~= 1 then
		-- Zero occupants is an ordinary miss. Two or more is crowding.
		-- Neither one is an attack attempt, so NextDue stays put.
		return decide("Skip"), state
	end
	local range = TrainingAttacker.DEVELOPMENT_PRACTICE_RANGE
	local target = selectTarget(origin, candidates, range * range)
	if target == nil then
		return decide("Skip"), state
	end
	return decide("Attack", target), {
		AttackerId = state.AttackerId,
		NextDue = probe.Now + TrainingAttacker.DEVELOPMENT_INTERVAL_SECONDS,
	}
end

return TrainingAttacker
