--!strict
-- Server-side projectile simulation math. Pure module using the `vector`
-- library (vector values are Vector3 in Roblox), so it runs in unit tests.
--
-- The server owns every projectile: the client only sends an aim direction,
-- the server spawns the projectile at the attacker's real position and steps
-- it each frame, testing the swept segment against combatant hit spheres.

local Types = require("./Types")

type ProjectileSpec = Types.ProjectileSpec

export type State = {
	Position: vector,
	Velocity: vector,
	Travelled: number,
	Spec: ProjectileSpec,
	OwnerId: string,
	HitIds: { [string]: boolean },
	PierceLeft: number,
	Done: boolean,
}

local Projectile = {}

-- `direction` does not need to be normalized; a zero or non-finite direction is rejected.
function Projectile.new(origin: vector, direction: vector, spec: ProjectileSpec, ownerId: string): State?
	local length = vector.magnitude(direction)
	if length ~= length or length < 1e-6 or length == math.huge then
		return nil
	end
	return {
		Position = origin,
		Velocity = direction / length * spec.Speed,
		Travelled = 0,
		Spec = spec,
		OwnerId = ownerId,
		HitIds = {},
		PierceLeft = spec.Pierce or 0,
		Done = false,
	}
end

-- Advances by dt. Returns the swept segment (from, to) for collision tests.
function Projectile.step(p: State, dt: number): (vector, vector)
	local from = p.Position
	local gravity = p.Spec.Gravity or 0
	if gravity ~= 0 then
		p.Velocity -= vector.create(0, gravity * dt, 0)
	end
	local to = from + p.Velocity * dt
	local segment = vector.magnitude(to - from)
	if p.Travelled + segment >= p.Spec.MaxRange then
		-- clip the final segment to the remaining range
		local remaining = p.Spec.MaxRange - p.Travelled
		if segment > 0 then
			to = from + (to - from) * (remaining / segment)
		end
		p.Travelled = p.Spec.MaxRange
		p.Done = true
	else
		p.Travelled += segment
	end
	p.Position = to
	return from, to
end

-- Does segment a->b pass within `radius` of `center`? Returns the fraction
-- along the segment (0..1) of the closest approach, used to order hits.
function Projectile.sweepSphere(a: vector, b: vector, center: vector, radius: number): (boolean, number)
	local ab = b - a
	local lengthSq = vector.dot(ab, ab)
	local t = 0
	if lengthSq > 0 then
		t = math.clamp(vector.dot(center - a, ab) / lengthSq, 0, 1)
	end
	local closest = a + ab * t
	local offset = center - closest
	return vector.dot(offset, offset) <= radius * radius, t
end

-- Records a hit. Returns true if the projectile should keep flying (pierce).
function Projectile.registerHit(p: State, targetId: string): boolean
	p.HitIds[targetId] = true
	if p.PierceLeft > 0 then
		p.PierceLeft -= 1
		return true
	end
	p.Done = true
	return false
end

return table.freeze(Projectile)
