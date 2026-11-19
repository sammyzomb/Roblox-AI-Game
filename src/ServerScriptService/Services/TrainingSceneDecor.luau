--!strict
-- P1b minimum visual pass: decorations for the placeholder training ground
-- so a new player can see the route, the entrance and exit, the passive
-- targets and the block-practice area. Presentation only.
--
-- Everything is built into its own Workspace folder (TrainingDecorLayout
-- .ContainerName), never into TrainingGroundScene, whose six owned children
-- and tags stay under TrainingSceneBootstrap. Every decoration part is
-- anchored with CanCollide, CanTouch and CanQuery off, so walking, pad
-- touches, melee arcs and projectile sweeps behave as before.
--
-- The folder holds no state: an owned folder from a previous boot is
-- destroyed and rebuilt. A same-named object without the owning attribute
-- is left untouched and decoration is skipped.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TrainingDecorLayout = require(ReplicatedStorage.Shared.Combat.TrainingDecorLayout)

local TrainingSceneDecor = {
	Priority = 16, -- right after TrainingSceneBootstrap (15)
}

local OWNED_ATTRIBUTE = "TrainingDecorOwned"

local TONES: { [string]: Color3 } = {
	Enter = Color3.fromRGB(88, 200, 120),
	Exit = Color3.fromRGB(226, 110, 86),
	Danger = Color3.fromRGB(226, 82, 70),
	Calm = Color3.fromRGB(214, 180, 110),
	Neutral = Color3.fromRGB(246, 196, 72),
}
local WOOD = Color3.fromRGB(110, 78, 52)
local PANEL = Color3.fromRGB(20, 22, 28)
local TEXT = Color3.fromRGB(244, 246, 250)

local function tone(name: string): Color3
	return TONES[name] or TONES.Neutral
end

local function decorPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Locked = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Parent = parent
	return part
end

local function signFont(weight: Enum.FontWeight): Font
	local ok, font = pcall(Font.new, "rbxasset://fonts/families/SourceHanSans.json", weight, Enum.FontStyle.Normal)
	if ok then
		return font
	end
	return Font.fromEnum(Enum.Font.GothamBold)
end

local function buildLantern(parent: Instance, position: TrainingDecorLayout.Vec3, index: number)
	local base = Vector3.new(position.X, position.Y, position.Z)
	decorPart(parent, `LanternPost{index}`, Vector3.new(0.6, 7, 0.6), CFrame.new(base + Vector3.new(0, 3.5, 0)), WOOD, Enum.Material.Wood)
	local lamp = decorPart(
		parent,
		`LanternLamp{index}`,
		Vector3.new(1.4, 1.4, 1.4),
		CFrame.new(base + Vector3.new(0, 7.6, 0)),
		Color3.fromRGB(255, 214, 140),
		Enum.Material.Neon
	)
	lamp.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 214, 140)
	light.Range = 18
	light.Brightness = 1.2
	light.Parent = lamp
end

local function buildGate(parent: Instance, gate: TrainingDecorLayout.Gate)
	local center = Vector3.new(gate.Center.X, gate.Center.Y, gate.Center.Z)
	local color = tone(gate.Tone)
	for _, side in { -1, 1 } do
		decorPart(
			parent,
			`{gate.Id}GatePillar{if side < 0 then "A" else "B"}`,
			Vector3.new(1.4, gate.Height, 1.4),
			CFrame.new(center + Vector3.new(0, gate.Height / 2, side * gate.HalfWidth)),
			WOOD,
			Enum.Material.Wood
		)
	end
	decorPart(
		parent,
		`{gate.Id}GateBeam`,
		Vector3.new(1.8, 1.2, gate.HalfWidth * 2 + 3),
		CFrame.new(center + Vector3.new(0, gate.Height + 0.6, 0)),
		WOOD,
		Enum.Material.Wood
	)
	local banner = decorPart(
		parent,
		`{gate.Id}GateBanner`,
		Vector3.new(0.3, 0.5, gate.HalfWidth * 2),
		CFrame.new(center + Vector3.new(0, gate.Height - 0.4, 0)),
		color,
		Enum.Material.Neon
	)
	banner.CastShadow = false
end

-- A ring drawn as short flat segments, each tangent to the circle.
local function buildRing(parent: Instance, ring: TrainingDecorLayout.Ring)
	local center = Vector3.new(ring.Center.X, ring.Center.Y + 0.06, ring.Center.Z)
	local chord = 2 * ring.Radius * math.sin(math.pi / ring.Segments)
	for i = 1, ring.Segments do
		local angle = (i - 1) / ring.Segments * 2 * math.pi
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * ring.Radius
		local segment = decorPart(
			parent,
			`{ring.Id}Ring{i}`,
			Vector3.new(0.5, 0.12, chord + 0.1),
			CFrame.new(center + offset) * CFrame.Angles(0, -angle, 0),
			tone(ring.Tone),
			Enum.Material.Neon
		)
		segment.CastShadow = false
		segment.Transparency = 0.15
	end
end

local function buildSign(parent: Instance, sign: TrainingDecorLayout.Sign)
	local anchor = decorPart(
		parent,
		`{sign.Id}SignAnchor`,
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(sign.Position.X, sign.Position.Y, sign.Position.Z),
		PANEL,
		Enum.Material.SmoothPlastic
	)
	anchor.Transparency = 1
	anchor.CastShadow = false

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Sign"
	billboard.Size = UDim2.fromScale(16, 4.6)
	billboard.MaxDistance = 220
	billboard.LightInfluence = 0
	billboard.Adornee = anchor

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.2
	panel.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.18, 0)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = tone(sign.Tone)
	stroke.Thickness = 3
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.92, 0.5)
	title.Position = UDim2.fromScale(0.04, 0.06)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.FontFace = signFont(Enum.FontWeight.Bold)
	title.TextColor3 = tone(sign.Tone)
	title.Text = sign.Title
	title.Parent = panel

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.Size = UDim2.fromScale(0.92, 0.32)
	body.Position = UDim2.fromScale(0.04, 0.6)
	body.BackgroundTransparency = 1
	body.TextScaled = true
	body.FontFace = signFont(Enum.FontWeight.Medium)
	body.TextColor3 = TEXT
	body.Text = sign.Body
	body.Parent = panel

	billboard.Parent = anchor
end

local function buildGuidePost(parent: Instance, sign: TrainingDecorLayout.Sign)
	decorPart(
		parent,
		"GuidePost",
		Vector3.new(0.7, sign.Position.Y - 2, 0.7),
		CFrame.new(sign.Position.X, (sign.Position.Y - 2) / 2, sign.Position.Z),
		WOOD,
		Enum.Material.Wood
	)
end

-- Late-afternoon light and a light haze. Only the properties below are
-- touched; an Atmosphere a builder already placed is left alone.
local function applyLighting()
	Lighting.ClockTime = 16.2
	Lighting.Brightness = 2.4
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 122, 116)
	if Lighting:FindFirstChildOfClass("Atmosphere") == nil then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "TrainingAtmosphere"
		atmosphere.Density = 0.28
		atmosphere.Offset = 0.2
		atmosphere.Color = Color3.fromRGB(214, 200, 180)
		atmosphere.Decay = Color3.fromRGB(150, 120, 100)
		atmosphere.Glare = 0.2
		atmosphere.Haze = 1.4
		atmosphere:SetAttribute(OWNED_ATTRIBUTE, true)
		atmosphere.Parent = Lighting
	end
end

function TrainingSceneDecor:Init(_registry) end

local function build()
	local existing = Workspace:FindFirstChild(TrainingDecorLayout.ContainerName)
	if existing ~= nil then
		if existing:GetAttribute(OWNED_ATTRIBUTE) ~= true then
			warn(
				`[Combat] Training decor found an existing "{TrainingDecorLayout.ContainerName}" it does not own; `
					.. "leaving it untouched and skipping decorations."
			)
			return
		end
		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = TrainingDecorLayout.ContainerName
	container:SetAttribute(OWNED_ATTRIBUTE, true)

	for index, position in TrainingDecorLayout.lanterns() do
		buildLantern(container, position, index)
	end
	for _, gate in TrainingDecorLayout.gates() do
		buildGate(container, gate)
	end
	for _, ring in TrainingDecorLayout.rings() do
		buildRing(container, ring)
	end
	for _, sign in TrainingDecorLayout.signs() do
		buildSign(container, sign)
		if sign.Id == "Guide" then
			buildGuidePost(container, sign)
		end
	end

	container.Parent = Workspace
	applyLighting()
	print(`[Combat] Training decor built "{TrainingDecorLayout.ContainerName}"`)
end

-- Decorations are optional. A failure here must not stop the services that
-- boot after this one (TrainingGroundService), so it is reported and dropped.
function TrainingSceneDecor:Start()
	local ok, err = pcall(build)
	if not ok then
		warn(`[Combat] Training decor skipped: {err}`)
	end
end

return TrainingSceneDecor
