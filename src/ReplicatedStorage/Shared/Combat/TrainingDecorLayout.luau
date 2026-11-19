--!strict
-- P1b minimum visual pass: pure (Roblox-API-free) layout for the training
-- ground decorations. TrainingSceneDecor.luau turns these numbers into
-- Instances. Nothing here changes gameplay: every decoration is created
-- non-colliding, non-touching and non-queryable, in its own container, so
-- the six owned children of TrainingGroundScene stay exactly as they are.
--
-- Positions are derived from TrainingSceneConfig and TrainingAttacker so a
-- later layout or range change moves the decorations with it.

local TrainingSceneConfig
local TrainingAttacker
if script then
	TrainingSceneConfig = require(script.Parent.TrainingSceneConfig)
	TrainingAttacker = require(script.Parent.TrainingAttacker)
else
	TrainingSceneConfig = require("./TrainingSceneConfig")
	TrainingAttacker = require("./TrainingAttacker")
end

export type Vec3 = { X: number, Y: number, Z: number }
export type Sign = { Id: string, Title: string, Body: string, Position: Vec3, Tone: string }
export type Gate = { Id: string, Center: Vec3, HalfWidth: number, Height: number, Tone: string }
export type Ring = { Id: string, Center: Vec3, Radius: number, Segments: number, Tone: string }

local TrainingDecorLayout = {}

TrainingDecorLayout.ContainerName = "TrainingGroundDecor"

-- Passive dummy positions on the ground, mirrored from TrainingDummyService's
-- DUMMIES table (X/Z only; that table stores the stand height in Y).
TrainingDecorLayout.PassiveDummies = {
	{ X = 12, Y = 0, Z = -16 },
	{ X = -12, Y = 0, Z = -16 },
	{ X = 0, Y = 0, Z = -30 },
} :: { Vec3 }

TrainingDecorLayout.LanternSpacing = 20
TrainingDecorLayout.LanternSideGap = 2
TrainingDecorLayout.GateHeight = 12
-- Area signs float well above head and name-tag height so they never cover
-- the character or a dummy's own name when the camera is close.
TrainingDecorLayout.SignHeight = 16
TrainingDecorLayout.PassivePadRadius = 4

local function walkwayBounds(points: any): (number, number, number)
	local size = TrainingSceneConfig.Walkway.Size
	local minX = points.WalkwayCenter.X - size.X / 2
	local maxX = points.WalkwayCenter.X + size.X / 2
	return minX, maxX, size.Z / 2
end

-- Lantern posts in pairs on both sides of the walkway. They stand outside
-- the walkway footprint and stop before the platform edge.
function TrainingDecorLayout.lanterns(): { Vec3 }
	local points = TrainingSceneConfig.resolve()
	local minX, _, halfZ = walkwayBounds(points)
	local platformEdgeX = points.Origin.X - TrainingSceneConfig.Platform.Size.X / 2
	local sideZ = halfZ + TrainingDecorLayout.LanternSideGap
	local result: { Vec3 } = {}
	local x = minX + TrainingDecorLayout.LanternSpacing
	while x < platformEdgeX do
		table.insert(result, { X = x, Y = points.Origin.Y, Z = points.WalkwayCenter.Z + sideZ })
		table.insert(result, { X = x, Y = points.Origin.Y, Z = points.WalkwayCenter.Z - sideZ })
		x += TrainingDecorLayout.LanternSpacing
	end
	return result
end

-- Arches over the entrance and exit pads. The pillars stand clear of the
-- pad's touch volume so they never sit inside it.
function TrainingDecorLayout.gates(): { Gate }
	local points = TrainingSceneConfig.resolve()
	local halfWidth = TrainingSceneConfig.RoleMarker.Size.Z / 2 + 2
	return {
		{ Id = "Entrance", Center = points.Entrance, HalfWidth = halfWidth, Height = TrainingDecorLayout.GateHeight, Tone = "Enter" },
		{ Id = "Exit", Center = points.Exit, HalfWidth = halfWidth, Height = TrainingDecorLayout.GateHeight, Tone = "Exit" },
	}
end

-- Ground rings. The block-practice ring uses the attacker's real practice
-- range, so standing inside the ring is what makes the dummy swing.
function TrainingDecorLayout.rings(): { Ring }
	local points = TrainingSceneConfig.resolve()
	local result: { Ring } = {
		{
			Id = "BlockPractice",
			Center = points.DummyMarker,
			Radius = TrainingAttacker.DEVELOPMENT_PRACTICE_RANGE,
			Segments = 32,
			Tone = "Danger",
		},
	}
	for index, position in TrainingDecorLayout.PassiveDummies do
		table.insert(result, {
			Id = `Passive{index}`,
			Center = position,
			Radius = TrainingDecorLayout.PassivePadRadius,
			Segments = 16,
			Tone = "Calm",
		})
	end
	return result
end

local function centroid(list: { Vec3 }): Vec3
	local x, z = 0, 0
	for _, p in list do
		x += p.X
		z += p.Z
	end
	return { X = x / #list, Y = 0, Z = z / #list }
end

-- Floating signs. Text states only what the game already does: the pads
-- start and end training, the three spawn-side dummies never attack, and
-- the scene dummy swings at a training player inside the ring.
function TrainingDecorLayout.signs(): { Sign }
	local points = TrainingSceneConfig.resolve()
	local minX, _, halfZ = walkwayBounds(points)
	local signY = TrainingDecorLayout.SignHeight
	local gateY = TrainingDecorLayout.GateHeight + 3
	local passive = centroid(TrainingDecorLayout.PassiveDummies)
	return {
		{
			Id = "Guide",
			Title = "訓練場 ▶",
			Body = "沿著石板路直走",
			Position = { X = minX + 22, Y = 8, Z = points.WalkwayCenter.Z + halfZ + 4 },
			Tone = "Neutral",
		},
		{
			Id = "Entrance",
			Title = "訓練場入口",
			Body = "走上綠色區域開始訓練",
			Position = { X = points.Entrance.X, Y = gateY, Z = points.Entrance.Z },
			Tone = "Enter",
		},
		{
			Id = "Exit",
			Title = "出口",
			Body = "走上紅色區域結束訓練",
			Position = { X = points.Exit.X, Y = gateY, Z = points.Exit.Z },
			Tone = "Exit",
		},
		{
			Id = "Passive",
			Title = "練習木人",
			Body = "不會還手，左鍵攻擊",
			Position = { X = passive.X, Y = signY, Z = passive.Z },
			Tone = "Calm",
		},
		{
			Id = "BlockPractice",
			Title = "格擋練習",
			Body = "訓練中站進紅圈會被攻擊，按住 F 格擋",
			Position = { X = points.DummyMarker.X, Y = signY, Z = points.DummyMarker.Z },
			Tone = "Danger",
		},
	}
end

return TrainingDecorLayout
