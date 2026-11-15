--!strict
--[[
	CourseBuilder — 경주 코스 "쇳물 수로" 한 판을 블록으로 짓는 유틸 (통합 기획서 4-1·8-2절).

	생명주기(Init/Start)가 없어서 부트스트랩 순서 목록에 넣지 않는다. RaceService 만 쓴다.

	무엇을 어디에 놓을지(장애물 종류·위치)는 Pure/RaceLogic.generateObstacles 가 정하고,
	여기서는 그 목록을 받아 파트로 만들기만 한다.
	  바닥 = 검은 돌, 양쪽 가장자리 = 갈라진 틈처럼 빛나는 쇳물 줄, 벽 = 낮은 돌벽 + 보이지 않는 벽
	  100칸마다 바닥 문양 띠와 숫자판, 500칸마다 화로 아치
	  장애물: 식은 쇳덩이(옆으로 피함) · 쇳물 홈(뛰어넘음) · 거푸집 벽(틈으로 지나감)
	  출발선: 흰 선, 쇠창살(보기만, 부딪히지 않음), 화로 3개 (카운트다운에 맞춰 기기가 켠다)
	  추격자 = 쇳물 해일: 네온 벽 + 불 + 불티 + 강한 빛. 출렁이는 꼭대기 같은 장식은 기기가 붙인다.

	좌표: origin 이 출발선 가운데의 바닥 윗면이다. 코스는 +Z 방향으로 뻗는다.
	추격자는 서버가 매 프레임 옮기는 큰 벽이다. 닿아서 잡는 게 아니라 서버가 위치를 비교해 잡는다
	(그래서 추격자 파트는 부딪히지 않는다).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local World = require(ConfigFolder:WaitForChild("World"))
local Palette = require(ConfigFolder:WaitForChild("Palette"))
local RaceLogic = require(Shared:WaitForChild("Pure"):WaitForChild("RaceLogic"))

local CourseBuilder = {}

export type Built = {
	folder: Folder,
	chaser: Part,
	origin: Vector3,
	length: number,
	trackWidth: number,
}

local W = Palette.WORLD
local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local FLOOR_A = { 38, 34, 42 }
local FLOOR_B = { 32, 29, 36 }

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: { number },
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.Size = size
	part.Position = position
	part.Color = rgb(color)
	part.Material = material or Enum.Material.Slate
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function glow(part: Part, transparency: number?): Part
	part.Material = Enum.Material.Neon
	part.CanCollide = false
	part.CastShadow = false
	part.Transparency = transparency or 0
	return part
end

-- 바닥 · 쇳물 줄 · 돌벽 · 보이지 않는 벽을 zFrom ~ zTo 구간에 놓는다.
local function buildSegment(
	parent: Instance,
	origin: Vector3,
	trackWidth: number,
	zFrom: number,
	zTo: number,
	index: number
)
	local course = World.COURSE
	local length = zTo - zFrom
	local centerZ = origin.Z + (zFrom + zTo) / 2

	makePart(
		parent,
		`Floor{index}`,
		Vector3.new(trackWidth, course.floorThickness, length),
		Vector3.new(origin.X, origin.Y - course.floorThickness / 2, centerZ),
		if index % 2 == 0 then FLOOR_A else FLOOR_B
	)

	for side = -1, 1, 2 do
		local edgeX = origin.X + side * (trackWidth / 2 - 0.4)
		glow(
			makePart(
				parent,
				`Crack{index}`,
				Vector3.new(0.5, 0.06, length),
				Vector3.new(edgeX, origin.Y + 0.03, centerZ),
				W.molten
			),
			0.15
		)

		local wallX = origin.X + side * (trackWidth / 2 + course.wallThickness / 2)
		makePart(
			parent,
			`Wall{index}`,
			Vector3.new(course.wallThickness, course.solidWallHeight, length),
			Vector3.new(wallX, origin.Y + course.solidWallHeight / 2, centerZ),
			W.stone
		)
		local barrier = makePart(
			parent,
			`Barrier{index}`,
			Vector3.new(course.wallThickness, course.wallHeight - course.solidWallHeight, length),
			Vector3.new(
				wallX,
				origin.Y + course.solidWallHeight + (course.wallHeight - course.solidWallHeight) / 2,
				centerZ
			),
			W.stone
		)
		barrier.Transparency = 1
		barrier.CastShadow = false
	end
end

-- 100칸마다: 바닥 문양 띠 + 왼쪽 벽 위 숫자판
local function buildMarker(parent: Instance, origin: Vector3, trackWidth: number, z: number)
	glow(
		makePart(
			parent,
			`Marker{z}`,
			Vector3.new(trackWidth - 1, 0.08, 0.8),
			Vector3.new(origin.X, origin.Y + 0.04, origin.Z + z),
			W.ember
		),
		0.35
	)

	local plate = makePart(
		parent,
		`MarkerPlate{z}`,
		Vector3.new(0.4, 2.4, 4.4),
		Vector3.new(
			origin.X - trackWidth / 2 - 0.2,
			origin.Y + World.COURSE.solidWallHeight + 1.4,
			origin.Z + z
		),
		W.wood,
		Enum.Material.WoodPlanks
	)
	plate.CanCollide = false

	-- 숫자만 쓰므로 언어와 상관없이 서버가 붙인다 (오른쪽 면 = 트랙 쪽)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = rgb(W.gold)
	label.Text = tostring(z)
	label.Parent = gui
end

-- 500칸마다: 돌기둥 두 개 + 윗돌 + 화로 두 개
local function buildArch(parent: Instance, origin: Vector3, trackWidth: number, z: number)
	local height = 14
	for side = -1, 1, 2 do
		local x = origin.X + side * (trackWidth / 2 - 1.5)
		makePart(
			parent,
			"ArchPillar",
			Vector3.new(3, height, 3),
			Vector3.new(x, origin.Y + height / 2, origin.Z + z),
			W.stone
		)
		local bowl = makePart(
			parent,
			"ArchBrazier",
			Vector3.new(2, 1, 2),
			Vector3.new(x, origin.Y + height + 0.5, origin.Z + z),
			W.iron,
			Enum.Material.Metal
		)
		local flame = Instance.new("Fire")
		flame.Color = rgb(W.molten)
		flame.SecondaryColor = rgb(W.moltenHot)
		flame.Size = 4
		flame.Parent = bowl
	end
	makePart(
		parent,
		"ArchLintel",
		Vector3.new(trackWidth, 2.5, 3),
		Vector3.new(origin.X, origin.Y + height - 1.25, origin.Z + z),
		W.stone
	)
end

-- 출발선: 흰 선 · 쇠창살 · 화로 3개
local function buildStart(parent: Instance, origin: Vector3, trackWidth: number)
	local course = World.COURSE
	glow(
		makePart(
			parent,
			"StartLine",
			Vector3.new(trackWidth, 0.1, 1.6),
			Vector3.new(origin.X, origin.Y + 0.05, origin.Z),
			{ 240, 236, 230 }
		),
		0
	)

	-- 쇠창살 (출발 신호 전에는 어차피 움직일 수 없으므로 보기만 한다)
	for index = 1, course.startBars do
		local x = origin.X - trackWidth / 2 + (index - 0.5) * trackWidth / course.startBars
		local bar = makePart(
			parent,
			"StartBar",
			Vector3.new(0.5, 8, 0.5),
			Vector3.new(x, origin.Y + 4, origin.Z + 1.5),
			W.iron,
			Enum.Material.Metal
		)
		bar.CanCollide = false
	end

	-- 출발 아치 + 화로 3개 (3·2·1 에 하나씩 켜진다)
	buildArch(parent, origin, trackWidth, -3)
	for index = 1, 3 do
		local x = origin.X + (index - 2) * 6
		local bowl = makePart(
			parent,
			`StartBrazier{index}`,
			Vector3.new(2, 1, 2),
			Vector3.new(x, origin.Y + 14.5, origin.Z - 3),
			W.iron,
			Enum.Material.Metal
		)
		local flame = Instance.new("Fire")
		flame.Name = "CountFire"
		flame.Color = rgb(W.molten)
		flame.SecondaryColor = rgb(W.moltenHot)
		flame.Size = 4
		flame.Enabled = false
		flame.Parent = bowl
	end
end

local function buildObstacle(
	parent: Instance,
	origin: Vector3,
	trackWidth: number,
	obstacle: RaceLogic.Obstacle,
	index: number
)
	local course = World.COURSE
	local z = origin.Z + obstacle.z

	if obstacle.kind == "block" then
		-- 식은 쇳덩이 + 윗면 모서리 열기 줄
		makePart(
			parent,
			`Block{index}`,
			Vector3.new(obstacle.width, course.blockHeight, course.blockDepth),
			Vector3.new(origin.X + obstacle.x, origin.Y + course.blockHeight / 2, z),
			W.iron,
			Enum.Material.Metal
		)
		glow(
			makePart(
				parent,
				`BlockSeam{index}`,
				Vector3.new(obstacle.width + 0.1, 0.25, 0.3),
				Vector3.new(
					origin.X + obstacle.x,
					origin.Y + course.blockHeight - 0.2,
					z - course.blockDepth / 2
				),
				W.moltenHot
			),
			0.1
		)
	elseif obstacle.kind == "hurdle" then
		-- 쇳물 홈: 낮은 쇠 막대 + 밑에서 새어 나오는 주황 빛 ("뜨거우니 넘어라")
		makePart(
			parent,
			`Hurdle{index}`,
			Vector3.new(obstacle.width, course.hurdleHeight, course.hurdleDepth),
			Vector3.new(origin.X + obstacle.x, origin.Y + course.hurdleHeight / 2, z),
			W.iron,
			Enum.Material.Metal
		)
		glow(
			makePart(
				parent,
				`HurdleGlow{index}`,
				Vector3.new(obstacle.width, 0.08, course.hurdleDepth + 2),
				Vector3.new(origin.X + obstacle.x, origin.Y + 0.05, z),
				W.molten
			),
			0.25
		)
	else
		-- 거푸집 벽: 틈 양쪽을 막고, 틈 가장자리에 등불 (멀리서도 틈이 보이게)
		local half = trackWidth / 2
		local gapLeft = obstacle.x - obstacle.width / 2
		local gapRight = obstacle.x + obstacle.width / 2

		local leftWidth = gapLeft + half
		if leftWidth > 0.5 then
			makePart(
				parent,
				`Gate{index}L`,
				Vector3.new(leftWidth, course.gateHeight, course.gateDepth),
				Vector3.new(origin.X + (-half + gapLeft) / 2, origin.Y + course.gateHeight / 2, z),
				W.stone
			)
		end
		local rightWidth = half - gapRight
		if rightWidth > 0.5 then
			makePart(
				parent,
				`Gate{index}R`,
				Vector3.new(rightWidth, course.gateHeight, course.gateDepth),
				Vector3.new(origin.X + (gapRight + half) / 2, origin.Y + course.gateHeight / 2, z),
				W.stone
			)
		end
		for _, edge in { gapLeft, gapRight } do
			glow(
				makePart(
					parent,
					`Lantern{index}`,
					Vector3.new(0.8, 1.2, 0.8),
					Vector3.new(
						origin.X + edge,
						origin.Y + course.gateHeight - 1.5,
						z - course.gateDepth / 2 - 0.5
					),
					W.gold
				),
				0
			)
		end
	end
end

--[[
	코스 한 판을 짓는다.
	headStart: 출발할 때 추격자가 출발선보다 뒤에 있는 거리 (그 뒤쪽까지 바닥을 깐다).
]]
function CourseBuilder.build(
	parent: Instance,
	raceId: number,
	origin: Vector3,
	length: number,
	headStart: number,
	trackWidth: number,
	obstacles: { RaceLogic.Obstacle }
): Built
	local course = World.COURSE

	local folder = Instance.new("Folder")
	folder.Name = `{World.RACE_FOLDER_PREFIX}{raceId}`

	-- 출발선 뒤쪽 (추격자가 달려오는 구간)
	local backZ = -(headStart + course.backExtra)
	buildSegment(folder, origin, trackWidth, backZ, 0, 0)

	local index = 1
	local z = 0
	while z < length do
		local nextZ = math.min(length, z + course.segmentLength)
		buildSegment(folder, origin, trackWidth, z, nextZ, index)
		z = nextZ
		index += 1
	end

	-- 앞뒤 끝을 막는 벽
	local outerWidth = trackWidth + course.wallThickness * 2
	for _, endZ in { backZ - course.wallThickness / 2, length + course.wallThickness / 2 } do
		makePart(
			folder,
			"EndWall",
			Vector3.new(outerWidth, course.wallHeight, course.wallThickness),
			Vector3.new(origin.X, origin.Y + course.wallHeight / 2, origin.Z + endZ),
			W.stone
		)
	end

	buildStart(folder, origin, trackWidth)

	local marker = course.markerEvery
	while marker < length do
		buildMarker(folder, origin, trackWidth, marker)
		if marker % course.archEvery == 0 then
			buildArch(folder, origin, trackWidth, marker + 3)
		end
		marker += course.markerEvery
	end

	for obstacleIndex, obstacle in obstacles do
		buildObstacle(folder, origin, trackWidth, obstacle, obstacleIndex)
	end

	-- 쇳물 해일
	local chaser = makePart(
		folder,
		World.CHASER_NAME,
		Vector3.new(outerWidth, course.chaserHeight, course.chaserDepth),
		Vector3.new(origin.X, origin.Y + course.chaserHeight / 2, origin.Z),
		W.molten,
		Enum.Material.Neon
	)
	chaser.CanCollide = false
	chaser.CastShadow = false
	chaser.Transparency = 0.15

	local flame = Instance.new("Fire")
	flame.Color = rgb(W.molten)
	flame.SecondaryColor = rgb(W.moltenHot)
	flame.Size = 25
	flame.Heat = 20
	flame.Parent = chaser

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Color = ColorSequence.new(rgb(W.moltenHot))
	embers.LightEmission = 1
	embers.Rate = 40
	embers.Lifetime = NumberRange.new(1, 2)
	embers.Speed = NumberRange.new(6, 14)
	embers.SpreadAngle = Vector2.new(40, 40)
	embers.Acceleration = Vector3.new(0, 6, 0)
	embers.Size = NumberSequence.new(0.5, 0)
	embers.EmissionDirection = Enum.NormalId.Front
	embers.Parent = chaser

	local chaserLight = Instance.new("PointLight")
	chaserLight.Color = rgb(W.molten)
	chaserLight.Range = 60
	chaserLight.Brightness = 3
	chaserLight.Parent = chaser

	local built: Built = {
		folder = folder,
		chaser = chaser,
		origin = origin,
		length = length,
		trackWidth = trackWidth,
	}

	CourseBuilder.moveChaser(built, -headStart)

	folder.Parent = parent
	return built
end

-- 추격자 앞면을 출발선 기준 front 칸 위치로 옮긴다. (앞면 = +Z 쪽 면, 파트의 Back 면)
function CourseBuilder.moveChaser(built: Built, front: number)
	local course = World.COURSE
	local origin = built.origin

	built.chaser.CFrame = CFrame.new(
		origin.X,
		origin.Y + course.chaserHeight / 2,
		origin.Z + front - course.chaserDepth / 2
	) * CFrame.Angles(0, math.pi, 0) -- Front 면(불티 나오는 쪽)이 +Z 를 보게
end

-- 출발선 위, 트랙 중심에서 offsetX 만큼 옆에 서서 코스 앞쪽(+Z)을 보는 자리
function CourseBuilder.lineupCFrame(built: Built, offsetX: number): CFrame
	local origin = built.origin
	local position = Vector3.new(origin.X + offsetX, origin.Y + World.COURSE.spawnHeight, origin.Z)
	return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

function CourseBuilder.destroy(built: Built)
	built.folder:Destroy()
end

return CourseBuilder
