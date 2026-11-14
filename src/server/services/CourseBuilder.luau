--!strict
--[[
	CourseBuilder — 경주 코스 한 판을 블록으로 짓는 유틸 (통합 기획서 4-1절 5번).

	생명주기(Init/Start)가 없어서 부트스트랩 순서 목록에 넣지 않는다. RaceService 만 쓴다.

	무엇을 어디에 놓을지(장애물 종류·위치)는 Pure/RaceLogic.generateObstacles 가 정하고,
	여기서는 그 목록을 받아 파트로 만들기만 한다. 크기·색은 Config/World 의 COURSE 값이다.

	좌표: origin 이 출발선 가운데의 바닥 윗면이다. 코스는 +Z 방향으로 뻗는다.
	추격자는 서버가 매 프레임 옮기는 큰 벽이다. 닿아서 잡는 게 아니라, 서버가 위치를 비교해 잡는다
	(그래서 추격자 파트는 충돌이 꺼져 있다).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared:WaitForChild("Config"):WaitForChild("World"))
local RaceLogic = require(Shared:WaitForChild("Pure"):WaitForChild("RaceLogic"))

local CourseBuilder = {}

export type Built = {
	folder: Folder,
	chaser: Part,
	origin: Vector3,
	length: number,
	trackWidth: number,
}

local COLOR_FLOOR_A = Color3.fromRGB(70, 66, 76)
local COLOR_FLOOR_B = Color3.fromRGB(58, 54, 64)
local COLOR_WALL = Color3.fromRGB(120, 150, 190)
local COLOR_START = Color3.fromRGB(240, 236, 230)
local COLOR_MARKER = Color3.fromRGB(226, 142, 58)
local COLOR_BLOCK = Color3.fromRGB(150, 84, 62)
local COLOR_HURDLE = Color3.fromRGB(230, 200, 80)
local COLOR_GATE = Color3.fromRGB(128, 96, 170)
local COLOR_CHASER = Color3.fromRGB(255, 60, 40)

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

-- 바닥과 양옆 벽을 zFrom ~ zTo 구간에 놓는다.
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
		if index % 2 == 0 then COLOR_FLOOR_A else COLOR_FLOOR_B
	)

	for side = -1, 1, 2 do
		local wall = makePart(
			parent,
			`Wall{index}{if side < 0 then "L" else "R"}`,
			Vector3.new(course.wallThickness, course.wallHeight, length),
			Vector3.new(
				origin.X + side * (trackWidth / 2 + course.wallThickness / 2),
				origin.Y + course.wallHeight / 2,
				centerZ
			),
			COLOR_WALL
		)
		wall.Transparency = 0.7
		wall.CastShadow = false
	end
end

-- 바닥에 붙은 얇은 줄 (출발선, 거리 표시). 밟아도 걸리지 않는다.
local function buildStripe(
	parent: Instance,
	origin: Vector3,
	trackWidth: number,
	z: number,
	name: string,
	color: Color3,
	depth: number
)
	local stripe = makePart(
		parent,
		name,
		Vector3.new(trackWidth, 0.2, depth),
		Vector3.new(origin.X, origin.Y + 0.1, origin.Z + z),
		color
	)
	stripe.CanCollide = false
	stripe.CastShadow = false
	stripe.Material = Enum.Material.Neon
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
		makePart(
			parent,
			`Block{index}`,
			Vector3.new(obstacle.width, course.blockHeight, course.blockDepth),
			Vector3.new(origin.X + obstacle.x, origin.Y + course.blockHeight / 2, z),
			COLOR_BLOCK
		)
	elseif obstacle.kind == "hurdle" then
		makePart(
			parent,
			`Hurdle{index}`,
			Vector3.new(obstacle.width, course.hurdleHeight, course.hurdleDepth),
			Vector3.new(origin.X + obstacle.x, origin.Y + course.hurdleHeight / 2, z),
			COLOR_HURDLE
		)
	else
		-- gate: 틈의 왼쪽과 오른쪽을 각각 벽으로 막는다.
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
				COLOR_GATE
			)
		end

		local rightWidth = half - gapRight
		if rightWidth > 0.5 then
			makePart(
				parent,
				`Gate{index}R`,
				Vector3.new(rightWidth, course.gateHeight, course.gateDepth),
				Vector3.new(origin.X + (gapRight + half) / 2, origin.Y + course.gateHeight / 2, z),
				COLOR_GATE
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

	-- 출발선 앞쪽
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
		local wall = makePart(
			folder,
			"EndWall",
			Vector3.new(outerWidth, course.wallHeight, course.wallThickness),
			Vector3.new(origin.X, origin.Y + course.wallHeight / 2, origin.Z + endZ),
			COLOR_WALL
		)
		wall.Transparency = 0.7
		wall.CastShadow = false
	end

	buildStripe(folder, origin, trackWidth, 0, "StartLine", COLOR_START, 2)

	local marker = course.markerEvery
	while marker < length do
		buildStripe(folder, origin, trackWidth, marker, `Marker{marker}`, COLOR_MARKER, 1)
		marker += course.markerEvery
	end

	for obstacleIndex, obstacle in obstacles do
		buildObstacle(folder, origin, trackWidth, obstacle, obstacleIndex)
	end

	local chaser = makePart(
		folder,
		World.CHASER_NAME,
		Vector3.new(outerWidth, course.chaserHeight, course.chaserDepth),
		Vector3.new(origin.X, origin.Y + course.chaserHeight / 2, origin.Z),
		COLOR_CHASER
	)
	chaser.CanCollide = false
	chaser.CastShadow = false
	chaser.Material = Enum.Material.Neon
	chaser.Transparency = 0.25

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

-- 추격자 앞면을 출발선 기준 front 칸 위치로 옮긴다.
function CourseBuilder.moveChaser(built: Built, front: number)
	local course = World.COURSE
	local origin = built.origin

	built.chaser.CFrame = CFrame.new(
		origin.X,
		origin.Y + course.chaserHeight / 2,
		origin.Z + front - course.chaserDepth / 2
	)
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
