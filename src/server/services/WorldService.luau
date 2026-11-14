--!strict
--[[
	WorldService — 로비 공간을 코드로 짓는다 (통합 기획서 4-4·6절, 10-3절).

	미술 에셋이 없어서 블록으로만 짓는다: 바닥, 보이지 않는 벽, 스폰 지점, 모루 장식, 트레드밀 발판.
	경주 코스는 판마다 RaceService 가 CourseBuilder 로 따로 짓고, 여기서는 코스를 담을 폴더만 만든다.

	- Workspace 에 이미 "Lobby" 폴더가 있으면(개발자가 Studio 에서 직접 꾸민 경우) 새로 짓지 않고
	  그 안의 Treadmills 폴더에서 발판을 찾아 쓴다. 발판 파트에는 TreadmillTier 속성(단계 id)이 있어야 한다.
	- 캐릭터끼리는 서로 부딪치지 않게 한다. 트레드밀에서 남을 밀어내거나 출발선에서 서로 끼는 일을 막는다.
	  (공식 문서 workspace/collisions 의 "Disable character collisions" 방식)
	- 발판 위 글자는 서버가 붙이지 않는다. 언어가 플레이어마다 달라서 클라이언트(LobbyController)가 붙인다.

	부트스트랩 맨 앞에서 Init 된다. 플레이어의 캐릭터가 나타나기 전에 바닥이 있어야 하기 때문이다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ConfigFolder = Shared:WaitForChild("Config")
local World = require(ConfigFolder:WaitForChild("World"))
local EconomyConfig = require(ConfigFolder:WaitForChild("EconomyConfig"))

local TreadmillLogic = require(Shared:WaitForChild("Pure"):WaitForChild("TreadmillLogic"))

local WorldService = {}
WorldService.Name = "WorldService"

export type TreadmillPad = {
	part: BasePart,
	tier: EconomyConfig.TreadmillTier,
	bounds: TreadmillLogic.Pad,
}

local COLOR_FLOOR = Color3.fromRGB(58, 52, 62)
local COLOR_SPAWN = Color3.fromRGB(226, 142, 58)
local COLOR_ANVIL = Color3.fromRGB(38, 36, 42)
local COLOR_PAD = Color3.fromRGB(72, 168, 132)

local rng = Random.new()

local pads: { TreadmillPad } = {}
local racesFolder: Folder? = nil
local collisionGroupReady = false

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
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

--------------------------------------------------------------------------------
-- 캐릭터끼리 부딪치지 않게
--------------------------------------------------------------------------------

local function setupCollisionGroup()
	local group = World.CHARACTER_COLLISION_GROUP

	local ok, err = pcall(function()
		if not Workspace:IsCollisionGroupRegistered(group) then
			Workspace:RegisterCollisionGroup(group)
		end
		Workspace:CollisionGroupSetCollidable(group, group, false)
	end)

	if ok then
		collisionGroupReady = true
	else
		-- 게임 진행에는 지장이 없다. 캐릭터끼리 부딪칠 뿐이다.
		warn(`[WorldService] 충돌 그룹을 만들지 못했습니다: {err}`)
	end
end

local function onCharacterDescendantAdded(descendant: Instance)
	if collisionGroupReady and descendant:IsA("BasePart") then
		descendant.CollisionGroup = World.CHARACTER_COLLISION_GROUP
	end
end

local function onCharacterAdded(character: Model)
	for _, descendant in character:GetDescendants() do
		onCharacterDescendantAdded(descendant)
	end
	character.DescendantAdded:Connect(onCharacterDescendantAdded)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)

	local character = player.Character
	if character then
		onCharacterAdded(character)
	end
end

--------------------------------------------------------------------------------
-- 로비 짓기
--------------------------------------------------------------------------------

local function buildWalls(parent: Instance)
	local lobby = World.LOBBY
	local halfX = lobby.sizeX / 2
	local halfZ = lobby.sizeZ / 2
	local height = lobby.wallHeight
	local thickness = 2

	local specs = {
		{
			name = "WallNorth",
			size = Vector3.new(lobby.sizeX, height, thickness),
			position = Vector3.new(0, height / 2, halfZ + thickness / 2),
		},
		{
			name = "WallSouth",
			size = Vector3.new(lobby.sizeX, height, thickness),
			position = Vector3.new(0, height / 2, -halfZ - thickness / 2),
		},
		{
			name = "WallEast",
			size = Vector3.new(thickness, height, lobby.sizeZ),
			position = Vector3.new(halfX + thickness / 2, height / 2, 0),
		},
		{
			name = "WallWest",
			size = Vector3.new(thickness, height, lobby.sizeZ),
			position = Vector3.new(-halfX - thickness / 2, height / 2, 0),
		},
	}

	for _, spec in specs do
		local wall = makePart(parent, spec.name, spec.size, spec.position, COLOR_FLOOR)
		wall.Transparency = 1
		wall.CastShadow = false
	end
end

local function buildSpawn(parent: Instance)
	local lobby = World.LOBBY

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(lobby.spawnSize, 1, lobby.spawnSize)
	spawn.Position = Vector3.new(lobby.spawnX, 0.5, lobby.spawnZ)
	spawn.Color = COLOR_SPAWN
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0 -- 스폰 직후 보호막 없음
	spawn.Parent = parent
end

-- 대장간 분위기를 내는 모루 모양 장식 (기능 없음)
local function buildAnvil(parent: Instance)
	local x, z = 0, 24

	makePart(parent, "AnvilBase", Vector3.new(6, 1.5, 4), Vector3.new(x, 0.75, z), COLOR_ANVIL)
	makePart(parent, "AnvilNeck", Vector3.new(3, 2, 2.5), Vector3.new(x, 2.5, z), COLOR_ANVIL)
	local top =
		makePart(parent, "AnvilTop", Vector3.new(9, 2, 4), Vector3.new(x, 4.5, z), COLOR_ANVIL)
	top.Material = Enum.Material.Metal
end

local function buildTreadmills(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = World.TREADMILL_FOLDER

	local padSize = World.TREADMILL_PAD
	local counts: { [string]: number } = {}

	for _, spec in World.TREADMILL_PADS do
		counts[spec.tierId] = (counts[spec.tierId] or 0) + 1

		local part = makePart(
			folder,
			`Treadmill_{spec.tierId}_{counts[spec.tierId]}`,
			Vector3.new(padSize.sizeX, padSize.height, padSize.sizeZ),
			Vector3.new(spec.x, padSize.height / 2, spec.z),
			COLOR_PAD
		)
		part.Material = Enum.Material.Neon
		part:SetAttribute(World.TREADMILL_TIER_ATTRIBUTE, spec.tierId)
	end

	folder.Parent = parent
end

local function buildLobby(): Folder
	local lobby = World.LOBBY

	local folder = Instance.new("Folder")
	folder.Name = World.LOBBY_FOLDER

	makePart(
		folder,
		"Floor",
		Vector3.new(lobby.sizeX, lobby.floorThickness, lobby.sizeZ),
		Vector3.new(0, -lobby.floorThickness / 2, 0),
		COLOR_FLOOR
	)

	buildWalls(folder)
	buildSpawn(folder)
	buildAnvil(folder)
	buildTreadmills(folder)

	folder.Parent = Workspace
	return folder
end

-- 로비 폴더에서 트레드밀 발판을 찾아 목록으로 만든다(직접 지은 로비든 Studio 에서 꾸민 로비든 같다).
local function collectPads(lobbyFolder: Instance)
	pads = {}

	local folder = lobbyFolder:FindFirstChild(World.TREADMILL_FOLDER)
	if folder == nil then
		warn(
			"[WorldService] 로비에 Treadmills 폴더가 없습니다. 트레드밀이 동작하지 않습니다."
		)
		return
	end

	for _, child in folder:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end

		local tierId = child:GetAttribute(World.TREADMILL_TIER_ATTRIBUTE)
		local tier = if type(tierId) == "string" then EconomyConfig.treadmillTier(tierId) else nil
		if tier == nil then
			warn(
				`[WorldService] 트레드밀 발판 {child.Name} 의 단계를 알 수 없습니다`
			)
			continue
		end

		table.insert(pads, {
			part = child,
			tier = tier,
			bounds = {
				x = child.Position.X,
				z = child.Position.Z,
				sizeX = child.Size.X,
				sizeZ = child.Size.Z,
				topY = child.Position.Y + child.Size.Y / 2,
				reach = World.TREADMILL_PAD.reach,
			},
		})
	end
end

--------------------------------------------------------------------------------
-- 공개 함수
--------------------------------------------------------------------------------

function WorldService.getTreadmillPads(): { TreadmillPad }
	return pads
end

-- 경주 코스를 담는 폴더 (Workspace/Races)
function WorldService.getRacesFolder(): Folder
	local folder = racesFolder
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = World.RACES_FOLDER
		folder.Parent = Workspace
		racesFolder = folder
	end
	return folder
end

-- 캐릭터를 로비 스폰 근처로 옮긴다. 캐릭터가 없으면 false.
function WorldService.teleportToLobby(player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end

	local lobby = World.LOBBY
	local scatter = lobby.spawnScatter

	local position = Vector3.new(
		lobby.spawnX + rng:NextNumber(-scatter, scatter),
		1 + World.COURSE.spawnHeight,
		lobby.spawnZ + rng:NextNumber(-scatter, scatter)
	)

	character:PivotTo(CFrame.new(position))
	return true
end

function WorldService.Init()
	setupCollisionGroup()

	local existing = Workspace:FindFirstChild(World.LOBBY_FOLDER)
	local lobbyFolder = if existing then existing else buildLobby()
	collectPads(lobbyFolder)

	WorldService.getRacesFolder()

	print(`[WorldService] 로비 준비 완료 (트레드밀 발판 {#pads}개)`)
end

function WorldService.Start()
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
end

return WorldService
