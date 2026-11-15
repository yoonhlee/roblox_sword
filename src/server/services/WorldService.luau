--!strict
--[[
	WorldService — 불씨 광장(로비)을 블록으로 짓는다 (통합 기획서 8-2절, 디자인 시안 "불씨 광장과 쇳물 수로").

	해 질 녘 대장간 마을. 지은 뒤 움직이는 장식(망치질, 벨트, 풀무, 관문 고리, 불빛 흔들림)은
	각 플레이어 기기(WorldFxController)가 돌리고, 서버는 짓기와 "상태 속성"만 맡는다(서버 부담을 줄이기 위해).
	글자(표지판, 전광판, 명예의 벽, 진열대 명패)도 언어가 플레이어마다 달라서 기기가 붙인다.

	지은 것:
	  바닥·낮은 돌담·보이지 않는 벽 / 스폰 원판 / 돌길과 표지판 / 횃불 8개
	  모루 영감의 대장간(기단·기둥·지붕·뒷벽·화덕·굴뚝·모루·연장·물통) + 모루 영감 블록 인형 + "강화하기" 근접 버튼
	  쇳물 관문(기둥·윗돌·문양·전광판·뒤 쇳물 폭포) + 바닥 원(고리 12칸)
	  풀무 러닝머신 4대(받침·벨트·줄무늬·난간·손잡이·계기판·풀무) + 화덕까지 이어진 쇠 관
	  명예의 벽 / 서버 최고 검 진열대(검은 SwordDisplayService 가 넣는다) / 담 밖 산
	  해 질 녘 빛(시각·대기·번짐·색 보정·햇살)

	- Workspace 에 이미 "Lobby" 폴더가 있으면(개발자가 Studio 에서 직접 꾸민 경우) 새로 짓지 않고
	  그 안의 Treadmills 폴더에서 발판을 찾아 쓴다.
	- 캐릭터끼리는 서로 부딪치지 않게 한다 (공식 문서 workspace/collisions 의 방식).
	- 부트스트랩 맨 앞에서 Init 된다. 캐릭터가 나타나기 전에 바닥이 있어야 하기 때문이다.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local ConfigFolder = Shared:WaitForChild("Config")
local World = require(ConfigFolder:WaitForChild("World"))
local EconomyConfig = require(ConfigFolder:WaitForChild("EconomyConfig"))
local Palette = require(ConfigFolder:WaitForChild("Palette"))

local TreadmillLogic = require(Shared:WaitForChild("Pure"):WaitForChild("TreadmillLogic"))

local WorldService = {}
WorldService.Name = "WorldService"

export type TreadmillPad = {
	part: BasePart,
	tier: EconomyConfig.TreadmillTier,
	bounds: TreadmillLogic.Pad,
}

local W = Palette.WORLD
local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local rng = Random.new()

local pads: { TreadmillPad } = {}
local racesFolder: Folder? = nil
local lobbyFolder: Instance? = nil
local gateModel: Model? = nil
local showcaseBase: BasePart? = nil
local collisionGroupReady = false
local worldEvent: RemoteEvent? = nil

--------------------------------------------------------------------------------
-- 블록 하나 놓기
--------------------------------------------------------------------------------

type PartProps = {
	name: string?,
	size: Vector3,
	cframe: CFrame,
	color: { number },
	material: Enum.Material?,
	shape: Enum.PartType?,
	collide: boolean?,
	transparency: number?,
	shadow: boolean?,
}

local function block(parent: Instance, props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = props.name or "Part"
	part.Anchored = true
	part.CanTouch = false
	part.Size = props.size
	part.CFrame = props.cframe
	part.Color = rgb(props.color)
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Shape = props.shape or Enum.PartType.Block
	part.CanCollide = props.collide ~= false
	part.Transparency = props.transparency or 0
	part.CastShadow = props.shadow ~= false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function light(
	parent: Instance,
	name: string,
	color: { number },
	range: number,
	brightness: number,
	shadows: boolean?
)
	local pointLight = Instance.new("PointLight")
	pointLight.Name = name
	pointLight.Color = rgb(color)
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Shadows = shadows == true
	pointLight.Parent = parent
	return pointLight
end

local function fire(parent: Instance, size: number, heat: number, name: string?)
	local flame = Instance.new("Fire")
	flame.Name = name or "Fire"
	flame.Color = rgb(W.molten)
	flame.SecondaryColor = rgb(W.moltenHot)
	flame.Size = size
	flame.Heat = heat
	flame.Parent = parent
	return flame
end

-- 불티 (기본 상태는 꺼짐, 연출이 :Emit 으로 쏜다)
local function sparks(parent: Instance, name: string, color: { number }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Color = ColorSequence.new(rgb(color))
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.3, 0.7)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(50, 50)
	emitter.Size = NumberSequence.new(0.18, 0)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Parent = parent
	return emitter
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
-- 해 질 녘 빛
--------------------------------------------------------------------------------

local function setupLighting()
	Lighting.ClockTime = 17.6
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(70, 52, 62)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 96, 96)

	-- Studio 에서 직접 넣은 효과가 있으면 존중한다
	if Lighting:FindFirstChildOfClass("Atmosphere") == nil then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.35
		atmosphere.Offset = 0.2
		atmosphere.Color = Color3.fromRGB(255, 170, 120)
		atmosphere.Decay = Color3.fromRGB(90, 60, 80)
		atmosphere.Glare = 0.4
		atmosphere.Haze = 1.6
		atmosphere.Parent = Lighting
	end
	if Lighting:FindFirstChildOfClass("BloomEffect") == nil then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.6
		bloom.Size = 24
		bloom.Threshold = 1.6
		bloom.Parent = Lighting
	end
	if Lighting:FindFirstChildOfClass("ColorCorrectionEffect") == nil then
		local correction = Instance.new("ColorCorrectionEffect")
		correction.Saturation = 0.1
		correction.TintColor = Color3.fromRGB(255, 240, 225)
		correction.Parent = Lighting
	end
	if Lighting:FindFirstChildOfClass("SunRaysEffect") == nil then
		local rays = Instance.new("SunRaysEffect")
		rays.Intensity = 0.05
		rays.Parent = Lighting
	end
end

--------------------------------------------------------------------------------
-- 광장 바탕
--------------------------------------------------------------------------------

local function buildGround(parent: Instance)
	local lobby = World.LOBBY
	local halfX, halfZ = lobby.sizeX / 2, lobby.sizeZ / 2

	block(parent, {
		name = "Floor",
		size = Vector3.new(lobby.sizeX, lobby.floorThickness, lobby.sizeZ),
		cframe = at(0, -lobby.floorThickness / 2, 0),
		color = W.stoneDark,
		material = Enum.Material.Slate,
	})

	-- 낮은 돌담 + 그 위 보이지 않는 벽
	local t = 2
	local walls = {
		{ Vector3.new(lobby.sizeX + 2 * t, 0, t), Vector3.new(0, 0, halfZ + t / 2) },
		{ Vector3.new(lobby.sizeX + 2 * t, 0, t), Vector3.new(0, 0, -halfZ - t / 2) },
		{ Vector3.new(t, 0, lobby.sizeZ), Vector3.new(halfX + t / 2, 0, 0) },
		{ Vector3.new(t, 0, lobby.sizeZ), Vector3.new(-halfX - t / 2, 0, 0) },
	}
	for index, wall in walls do
		local size, pos = wall[1], wall[2]
		block(parent, {
			name = `StoneWall{index}`,
			size = Vector3.new(size.X, lobby.stoneWallHeight, size.Z),
			cframe = at(pos.X, lobby.stoneWallHeight / 2, pos.Z),
			color = W.stone,
			material = Enum.Material.Slate,
		})
		block(parent, {
			name = `Barrier{index}`,
			size = Vector3.new(size.X, lobby.wallHeight, size.Z),
			cframe = at(pos.X, lobby.stoneWallHeight + lobby.wallHeight / 2, pos.Z),
			color = W.stone,
			transparency = 1,
			shadow = false,
		})
	end

	-- 돌길 (밟아도 걸리지 않게 얇고 부딪힘 없음)
	for index, path in World.PATHS do
		local dx, dz = path.x2 - path.x1, path.z2 - path.z1
		local length = math.sqrt(dx * dx + dz * dz)
		local mid = Vector3.new((path.x1 + path.x2) / 2, 0.06, (path.z1 + path.z2) / 2)
		block(parent, {
			name = `Path{index}`,
			size = Vector3.new(path.width, 0.12, length + path.width),
			cframe = CFrame.lookAt(mid, mid + Vector3.new(dx, 0, dz)),
			color = W.cobble,
			material = Enum.Material.Cobblestone,
			collide = false,
			shadow = false,
		})
	end
end

local function buildSpawn(parent: Instance)
	local lobby = World.LOBBY
	local x, z = lobby.spawnX, lobby.spawnZ

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 0.4, 12)
	spawn.CFrame =
		CFrame.lookAt(Vector3.new(x, 0.2, z), Vector3.new(World.FORGE.x, 0.2, World.FORGE.z))
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0 -- 스폰 직후 보호막 없음
	spawn.Parent = parent

	-- 둥근 돌 원판 + 불꽃 테두리 + 모루 무늬
	local flat = CFrame.Angles(0, 0, math.rad(90))
	block(parent, {
		name = "SpawnDisc",
		size = Vector3.new(0.3, lobby.spawnSize, lobby.spawnSize),
		cframe = at(x, 0.15, z) * flat,
		color = W.stone,
		material = Enum.Material.Slate,
		shape = Enum.PartType.Cylinder,
		collide = false,
	})
	block(parent, {
		name = "SpawnRing",
		size = Vector3.new(0.2, lobby.spawnSize + 1, lobby.spawnSize + 1),
		cframe = at(x, 0.1, z) * flat,
		color = W.ember,
		material = Enum.Material.Neon,
		shape = Enum.PartType.Cylinder,
		collide = false,
		transparency = 0.35,
		shadow = false,
	})
	-- 모루 무늬 (윗판 · 허리 · 받침)
	for _, piece in { { 6, 1.2, 1.4 }, { 1.6, 1.2, -0.2 }, { 4, 1.2, -1.6 } } do
		block(parent, {
			name = "SpawnMark",
			size = Vector3.new(piece[1], 0.05, piece[2]),
			cframe = at(x, 0.32, z + piece[3]),
			color = W.ember,
			material = Enum.Material.Neon,
			collide = false,
			transparency = 0.2,
			shadow = false,
		})
	end
end

local function buildTorch(parent: Instance, x: number, z: number, index: number)
	local baseY = World.LOBBY.stoneWallHeight
	block(parent, {
		name = `TorchPost{index}`,
		size = Vector3.new(0.6, 4, 0.6),
		cframe = at(x, baseY + 2, z),
		color = W.wood,
		material = Enum.Material.Wood,
	})
	local bowl = block(parent, {
		name = `TorchBowl{index}`,
		size = Vector3.new(0.8, 1.6, 1.6),
		cframe = at(x, baseY + 4.3, z) * CFrame.Angles(0, 0, math.rad(90)),
		color = W.iron,
		material = Enum.Material.Metal,
		shape = Enum.PartType.Cylinder,
	})
	fire(bowl, 3, 6)
	light(bowl, "TorchLight", W.ember, 14, 1.3)
end

local function buildSigns(parent: Instance)
	for index, sign in World.SIGNS do
		local rotation = CFrame.Angles(0, math.rad(sign.facing), 0)
		block(parent, {
			name = `SignPost{index}`,
			size = Vector3.new(0.5, 4, 0.5),
			cframe = at(sign.x, 2, sign.z) * rotation,
			color = W.wood,
			material = Enum.Material.Wood,
		})
		local board = block(parent, {
			name = `Sign{index}`,
			size = Vector3.new(7, 2.2, 0.4),
			cframe = at(sign.x, 4.6, sign.z) * rotation,
			color = W.wood,
			material = Enum.Material.WoodPlanks,
		})
		board:SetAttribute(World.ATTR.signKey, sign.key)
	end
end

local function buildMountains(parent: Instance)
	for index, mountain in World.MOUNTAINS do
		-- 쐐기 두 개를 등지게 붙여 산마루 모양
		for side = 0, 1 do
			block(parent, {
				name = `Mountain{index}`,
				size = Vector3.new(mountain.width / 2, mountain.height, mountain.width * 0.6),
				cframe = at(
					mountain.x + (side - 0.5) * mountain.width / 2,
					mountain.height / 2 - 4,
					mountain.z
				) * CFrame.Angles(0, math.rad(if side == 0 then 90 else -90), 0),
				color = W.mountain,
				material = Enum.Material.Slate,
				shape = Enum.PartType.Wedge,
				collide = false,
				shadow = false,
			})
		end
	end
end

--------------------------------------------------------------------------------
-- 모루 영감의 대장간
--------------------------------------------------------------------------------

local function buildNpc(parent: Instance)
	local spec = World.FORGE.npc
	local anvil = World.FORGE.anvil
	local base = 1 -- 대장간 기단 윗면
	-- 모루 쪽(+X)을 바라본다
	local facing = CFrame.lookAt(Vector3.new(spec.x, 0, spec.z), Vector3.new(anvil.x, 0, anvil.z))
	local function local_(x: number, y: number, z: number): CFrame
		return CFrame.new(spec.x, base, spec.z) * (facing - facing.Position) * CFrame.new(x, y, z)
	end

	local npc = Instance.new("Model")
	npc.Name = "AnvilElder"

	block(npc, {
		name = "LegL",
		size = Vector3.new(0.9, 2, 0.9),
		cframe = local_(-0.5, 1, 0),
		color = W.iron,
	})
	block(npc, {
		name = "LegR",
		size = Vector3.new(0.9, 2, 0.9),
		cframe = local_(0.5, 1, 0),
		color = W.iron,
	})
	block(npc, {
		name = "Torso",
		size = Vector3.new(2.2, 2.2, 1.2),
		cframe = local_(0, 3.1, 0),
		color = W.apron,
	})
	block(npc, {
		name = "Apron",
		size = Vector3.new(1.8, 2.8, 0.2),
		cframe = local_(0, 2.6, -0.7),
		color = W.leather,
		material = Enum.Material.Fabric,
	})
	local head = block(npc, {
		name = "Head",
		size = Vector3.new(1.4, 1.4, 1.4),
		cframe = local_(0, 4.9, 0),
		color = W.skin,
	})
	block(npc, {
		name = "Beard",
		size = Vector3.new(1.4, 1.2, 0.5),
		cframe = local_(0, 4.25, -0.75) * CFrame.Angles(math.rad(180), 0, 0),
		color = W.beard,
		material = Enum.Material.Fabric,
		shape = Enum.PartType.Wedge,
	})
	block(npc, {
		name = "BrowL",
		size = Vector3.new(0.5, 0.18, 0.2),
		cframe = local_(-0.35, 5.25, -0.72),
		color = W.beard,
	})
	block(npc, {
		name = "BrowR",
		size = Vector3.new(0.5, 0.18, 0.2),
		cframe = local_(0.35, 5.25, -0.72),
		color = W.beard,
	})
	block(npc, {
		name = "Cap",
		size = Vector3.new(1.5, 0.4, 1.5),
		cframe = local_(0, 5.75, 0),
		color = W.apron,
		material = Enum.Material.Fabric,
	})
	block(npc, {
		name = "ArmL",
		size = Vector3.new(0.7, 2, 0.7),
		cframe = local_(-1.45, 3.1, 0),
		color = W.skin,
	})

	-- 망치 든 오른팔: 어깨를 축으로 돈다 (기기가 돌린다)
	local arm = Instance.new("Model")
	arm.Name = "HammerArm"
	local shoulder = local_(1.45, 4.1, 0)
	block(arm, {
		name = "Arm",
		size = Vector3.new(0.7, 2, 0.7),
		cframe = shoulder * CFrame.new(0, -1, 0),
		color = W.skin,
	})
	block(arm, {
		name = "Haft",
		size = Vector3.new(0.25, 2.2, 0.25),
		cframe = shoulder * CFrame.new(0, -2, -0.9) * CFrame.Angles(math.rad(90), 0, 0),
		color = W.wood,
		material = Enum.Material.Wood,
	})
	block(arm, {
		name = "HammerHead",
		size = Vector3.new(0.6, 0.6, 1.1),
		cframe = shoulder * CFrame.new(0, -2, -2),
		color = W.iron,
		material = Enum.Material.Metal,
	})
	arm.WorldPivot = shoulder
	arm.Parent = npc

	npc.PrimaryPart = head
	npc.Parent = parent
end

local function buildForge(parent: Instance)
	local spec = World.FORGE
	local forge = folder(parent, "Forge")
	local cx, cz = spec.x, spec.z
	local hx, hz = spec.sizeX / 2, spec.sizeZ / 2

	block(forge, {
		name = "Base",
		size = Vector3.new(spec.sizeX, 1, spec.sizeZ),
		cframe = at(cx, 0.5, cz),
		color = W.stone,
		material = Enum.Material.Slate,
	})

	for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		block(forge, {
			name = "Post",
			size = Vector3.new(1.6, spec.postHeight, 1.6),
			cframe = at(
				cx + corner[1] * (hx - 1),
				1 + spec.postHeight / 2,
				cz + corner[2] * (hz - 1)
			),
			color = W.wood,
			material = Enum.Material.Wood,
		})
	end

	-- 뒷벽(북쪽)과 양옆 반쯤 막힌 벽
	block(forge, {
		name = "BackWall",
		size = Vector3.new(spec.sizeX - 2, spec.postHeight, 1),
		cframe = at(cx, 1 + spec.postHeight / 2, cz + hz - 1),
		color = W.brick,
		material = Enum.Material.Brick,
	})
	for side = -1, 1, 2 do
		block(forge, {
			name = "SideWall",
			size = Vector3.new(1, spec.postHeight * 0.45, spec.sizeZ - 2),
			cframe = at(cx + side * (hx - 1), 1 + spec.postHeight * 0.225, cz),
			color = W.brick,
			material = Enum.Material.Brick,
		})
	end

	-- 지붕: 앞쪽으로 기운 판 + 마룻대
	block(forge, {
		name = "Roof",
		size = Vector3.new(spec.sizeX + 4, 1, spec.sizeZ + 4),
		cframe = at(cx, 1 + spec.postHeight + 1.2, cz) * CFrame.Angles(math.rad(-10), 0, 0),
		color = W.roof,
		material = Enum.Material.Slate,
	})
	block(forge, {
		name = "RoofBeam",
		size = Vector3.new(spec.sizeX + 5, 1.2, 1.2),
		cframe = at(cx, 1 + spec.postHeight + 2.4, cz + hz + 1.2),
		color = W.wood,
		material = Enum.Material.Wood,
	})

	-- 화덕
	local furnace = spec.furnace
	block(forge, {
		name = "Furnace",
		size = Vector3.new(furnace.sizeX, furnace.sizeY, furnace.sizeZ),
		cframe = at(furnace.x, 1 + furnace.sizeY / 2, furnace.z),
		color = W.brick,
		material = Enum.Material.Brick,
	})
	local mouth = block(forge, {
		name = "FurnaceMouth",
		size = Vector3.new(3.6, 2.4, 0.3),
		cframe = at(furnace.x, 1 + 2.2, furnace.z - furnace.sizeZ / 2 - 0.1),
		color = W.moltenHot,
		material = Enum.Material.Neon,
		collide = false,
	})
	light(mouth, "FurnaceLight", W.ember, 18, 2.2, true)
	local flameHolder = block(forge, {
		name = "FurnaceFlame",
		size = Vector3.new(2, 1, 2),
		cframe = at(furnace.x, 1 + 2.4, furnace.z - 1),
		color = W.molten,
		transparency = 1,
		collide = false,
		shadow = false,
	})
	fire(flameHolder, 4, 8, "FurnaceFire")

	-- 굴뚝
	local chimney = spec.chimney
	local chimneyBottom = 1 + furnace.sizeY
	local chimneyHeight = chimney.height - chimneyBottom
	block(forge, {
		name = "Chimney",
		size = Vector3.new(chimney.size, chimneyHeight, chimney.size),
		cframe = at(chimney.x, chimneyBottom + chimneyHeight / 2, chimney.z),
		color = W.brick,
		material = Enum.Material.Brick,
	})
	local top = block(forge, {
		name = "ChimneyTop",
		size = Vector3.new(chimney.size, 0.5, chimney.size),
		cframe = at(chimney.x, chimney.height + 0.25, chimney.z),
		color = W.iron,
		material = Enum.Material.Metal,
	})
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(150, 140, 145)
	smoke.Opacity = 0.18
	smoke.RiseVelocity = 4
	smoke.Size = 3
	smoke.Parent = top

	-- 모루 (받침 · 허리 · 윗판 · 뿔)
	local anvil = spec.anvil
	block(forge, {
		name = "AnvilBase",
		size = Vector3.new(3, 1.2, 2),
		cframe = at(anvil.x, 1.6, anvil.z),
		color = W.iron,
		material = Enum.Material.Metal,
	})
	block(forge, {
		name = "AnvilWaist",
		size = Vector3.new(1.4, 1.4, 1),
		cframe = at(anvil.x, 2.9, anvil.z),
		color = W.iron,
		material = Enum.Material.Metal,
	})
	local anvilTop = block(forge, {
		name = "AnvilTop",
		size = Vector3.new(4.4, 1.2, 1.8),
		cframe = at(anvil.x, 4.2, anvil.z),
		color = W.iron,
		material = Enum.Material.Metal,
	})
	block(forge, {
		name = "AnvilHorn",
		size = Vector3.new(1.8, 1.2, 1.6),
		cframe = at(anvil.x + 3, 4.2, anvil.z) * CFrame.Angles(0, math.rad(-90), 0),
		color = W.iron,
		material = Enum.Material.Metal,
		shape = Enum.PartType.Wedge,
	})
	sparks(anvilTop, "Sparks", W.gold)
	light(anvilTop, "AnvilGlow", W.gold, 10, 0)

	-- "강화하기" 근접 버튼. 글자는 기기가 플레이어 언어로 바꾼다.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ForgePrompt"
	prompt.ActionText = ""
	prompt.ObjectText = ""
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = spec.promptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = anvilTop
	prompt.Triggered:Connect(function(player: Player)
		if worldEvent then
			worldEvent:FireClient(player, { kind = "openForge" })
		end
	end)

	-- 연장 걸이와 물통
	for index, x in { -8, -5, -2 } do
		block(forge, {
			name = `ToolHaft{index}`,
			size = Vector3.new(0.3, 2.6, 0.3),
			cframe = at(cx + x, 7, cz + hz - 1.7),
			color = W.wood,
			material = Enum.Material.Wood,
		})
		block(forge, {
			name = `ToolHead{index}`,
			size = Vector3.new(1.1, 0.6, 0.6),
			cframe = at(cx + x, 8.2, cz + hz - 1.7),
			color = W.iron,
			material = Enum.Material.Metal,
		})
	end
	block(forge, {
		name = "QuenchTub",
		size = Vector3.new(2, 3, 3),
		cframe = at(cx - 11, 2, cz + 4) * CFrame.Angles(0, 0, math.rad(90)),
		color = W.wood,
		material = Enum.Material.WoodPlanks,
		shape = Enum.PartType.Cylinder,
	})
	block(forge, {
		name = "QuenchWater",
		size = Vector3.new(0.1, 2.6, 2.6),
		cframe = at(cx - 11, 3, cz + 4) * CFrame.Angles(0, 0, math.rad(90)),
		color = W.glass,
		material = Enum.Material.Glass,
		shape = Enum.PartType.Cylinder,
		transparency = 0.4,
		collide = false,
	})

	buildNpc(forge)
end

--------------------------------------------------------------------------------
-- 쇳물 관문
--------------------------------------------------------------------------------

local function buildGate(parent: Instance)
	local spec = World.GATE
	local gate = Instance.new("Model")
	gate.Name = "Gate"

	local half = spec.width / 2 - spec.pillarSize / 2
	for side = -1, 1, 2 do
		local x = spec.x + side * half
		block(gate, {
			name = "Pillar",
			size = Vector3.new(spec.pillarSize, spec.pillarHeight, spec.pillarSize),
			cframe = at(x, spec.pillarHeight / 2, spec.z),
			color = W.stone,
			material = Enum.Material.Slate,
		})
		for _, y in { 5, 12 } do
			block(gate, {
				name = "Band",
				size = Vector3.new(spec.pillarSize + 0.4, 0.6, spec.pillarSize + 0.4),
				cframe = at(x, y, spec.z),
				color = W.iron,
				material = Enum.Material.Metal,
			})
		end
		local rune = block(gate, {
			name = "Rune",
			size = Vector3.new(0.3, 12, 0.6),
			cframe = at(x - side * (spec.pillarSize / 2 + 0.1), 9, spec.z),
			color = W.molten,
			material = Enum.Material.Neon,
			collide = false,
			transparency = 0.5,
			shadow = false,
		})
		light(rune, "RuneLight", W.molten, 10, 0.8)
	end

	block(gate, {
		name = "Lintel",
		size = Vector3.new(spec.width, 4, spec.pillarSize),
		cframe = at(spec.x, spec.pillarHeight + 2, spec.z),
		color = W.stone,
		material = Enum.Material.Slate,
	})
	block(gate, {
		name = "Board",
		size = Vector3.new(14, 4, 0.4),
		cframe = at(spec.x, spec.pillarHeight + 6.5, spec.z - 0.6),
		color = W.wood,
		material = Enum.Material.WoodPlanks,
	})

	-- 관문 뒤로 흘러내리는 쇳물 (네온 줄 3개, 밝기는 기기가 엇갈려 바꾼다)
	block(gate, {
		name = "FallWall",
		size = Vector3.new(spec.width - 4, 16, 1),
		cframe = at(spec.x, 8, spec.z + 3),
		color = W.stoneDark,
		material = Enum.Material.Slate,
	})
	for index, x in { -6, 0, 6 } do
		local fall = block(gate, {
			name = `MoltenFall{index}`,
			size = Vector3.new(1.4, 16, 0.2),
			cframe = at(spec.x + x, 8, spec.z + 2.4),
			color = W.molten,
			material = Enum.Material.Neon,
			collide = false,
			shadow = false,
		})
		if index == 2 then
			local embers = sparks(fall, "Embers", W.moltenHot)
			embers.Rate = 6
			embers.Speed = NumberRange.new(1, 3)
			embers.Acceleration = Vector3.new(0, 4, 0)
		end
	end

	-- 바닥 원: 돌 원판 + 고리 12칸
	local flat = CFrame.Angles(0, 0, math.rad(90))
	block(gate, {
		name = "RingDisc",
		size = Vector3.new(0.25, spec.ringRadius * 2, spec.ringRadius * 2),
		cframe = at(spec.ringX, 0.12, spec.ringZ) * flat,
		color = W.stone,
		material = Enum.Material.Slate,
		shape = Enum.PartType.Cylinder,
		collide = false,
	})
	for index = 1, spec.ringSegments do
		local angle = (index - 0.5) / spec.ringSegments * math.pi * 2
		local px = spec.ringX + math.sin(angle) * spec.ringRadius
		local pz = spec.ringZ + math.cos(angle) * spec.ringRadius
		local arc = 2 * math.pi * spec.ringRadius / spec.ringSegments
		local segment = block(gate, {
			name = "RingSegment",
			size = Vector3.new(arc * 0.82, 0.25, 0.7),
			cframe = CFrame.lookAt(
				Vector3.new(px, 0.2, pz),
				Vector3.new(spec.ringX, 0.2, spec.ringZ)
			),
			color = W.molten,
			material = Enum.Material.Neon,
			collide = false,
			transparency = 0.5,
			shadow = false,
		})
		segment:SetAttribute("Index", index)
	end

	gate:SetAttribute(World.ATTR.queueCount, 0)
	gate:SetAttribute(World.ATTR.departAt, 0)
	gate:SetAttribute(World.ATTR.launchAt, 0)
	gate.Parent = parent
	gateModel = gate
end

--------------------------------------------------------------------------------
-- 풀무 러닝머신
--------------------------------------------------------------------------------

local function cylinderBetween(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	diameter: number
)
	local length = (b - a).Magnitude
	if length < 0.01 then
		return
	end
	local mid = (a + b) / 2
	-- 원기둥의 축은 X 다: 두 점을 잇는 방향을 X 로 맞춘다
	local look = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)
	block(parent, {
		name = name,
		size = Vector3.new(length, diameter, diameter),
		cframe = look,
		color = W.iron,
		material = Enum.Material.Metal,
		shape = Enum.PartType.Cylinder,
		collide = false,
	})
end

local function buildTreadmills(parent: Instance)
	local treadmills = folder(parent, World.TREADMILL_FOLDER)
	local padSpec = World.TREADMILL_PAD
	local counts: { [string]: number } = {}

	for padIndex, spec in World.TREADMILL_PADS do
		counts[spec.tierId] = (counts[spec.tierId] or 0) + 1

		local model = Instance.new("Model")
		model.Name = `Treadmill_{spec.tierId}_{counts[spec.tierId]}`
		model:SetAttribute("PadIndex", padIndex)

		local h = padSpec.height
		local pad = block(model, {
			name = "Pad",
			size = Vector3.new(padSpec.sizeX, h, padSpec.sizeZ),
			cframe = at(spec.x, h / 2, spec.z),
			color = W.iron,
			material = Enum.Material.Metal,
		})
		pad:SetAttribute(World.TREADMILL_TIER_ATTRIBUTE, spec.tierId)
		pad:SetAttribute(World.ATTR.occupied, false)
		pad:SetAttribute(World.ATTR.paidAt, 0)

		local beltLength = padSpec.sizeZ - 2
		block(model, {
			name = "Belt",
			size = Vector3.new(padSpec.sizeX - 2, 0.12, beltLength),
			cframe = at(spec.x, h + 0.06, spec.z),
			color = { 20, 18, 22 },
			material = Enum.Material.Slate,
			collide = false,
		})
		for index = 1, padSpec.stripes do
			local stripe = block(model, {
				name = "BeltStripe",
				size = Vector3.new(padSpec.sizeX - 2.2, 0.14, 0.45),
				cframe = at(
					spec.x,
					h + 0.08,
					spec.z - beltLength / 2 + (index - 0.5) * beltLength / padSpec.stripes
				),
				color = { 72, 74, 82 },
				material = Enum.Material.Metal,
				collide = false,
				shadow = false,
			})
			stripe:SetAttribute("Index", index)
		end

		-- 난간 · 손잡이 · 계기판 (앞쪽 = 북쪽)
		for side = -1, 1, 2 do
			block(model, {
				name = "Rail",
				size = Vector3.new(0.5, 0.5, beltLength),
				cframe = at(spec.x + side * (padSpec.sizeX / 2 - 0.4), h + 2.6, spec.z),
				color = W.wood,
				material = Enum.Material.Wood,
			})
			block(model, {
				name = "RailPost",
				size = Vector3.new(0.4, 2.6, 0.4),
				cframe = at(
					spec.x + side * (padSpec.sizeX / 2 - 0.4),
					h + 1.3,
					spec.z + beltLength / 2 - 0.3
				),
				color = W.wood,
				material = Enum.Material.Wood,
			})
		end
		block(model, {
			name = "Handle",
			size = Vector3.new(padSpec.sizeX - 0.4, 0.35, 0.35),
			cframe = at(spec.x, h + 3.9, spec.z + beltLength / 2),
			color = W.iron,
			material = Enum.Material.Metal,
			shape = Enum.PartType.Cylinder,
		})
		block(model, {
			name = "Console",
			size = Vector3.new(3, 1.4, 1.2),
			cframe = at(spec.x, h + 4.2, spec.z + beltLength / 2 + 0.6)
				* CFrame.Angles(math.rad(-25), 0, 0),
			color = W.stoneDark,
			material = Enum.Material.Metal,
		})
		local lamp = block(model, {
			name = "Lamp",
			size = Vector3.new(0.6, 0.6, 0.6),
			cframe = at(spec.x, h + 4.8, spec.z + beltLength / 2 + 0.4),
			color = W.gold,
			material = Enum.Material.Neon,
			shape = Enum.PartType.Ball,
			collide = false,
			transparency = 0.6,
		})
		lamp:SetAttribute("Base", 0.6)
		sparks(lamp, "Coins", W.gold)

		-- 풀무 (아코디언 3단) — 발판 동쪽
		local bx = spec.x + padSpec.bellowsOffsetX
		block(model, {
			name = "BellowsBase",
			size = Vector3.new(2.6, 0.6, 3.6),
			cframe = at(bx, 0.3, spec.z),
			color = W.wood,
			material = Enum.Material.Wood,
		})
		for layer = 1, 3 do
			local part = block(model, {
				name = "BellowsLayer",
				size = Vector3.new(2.4 - layer * 0.1, 0.7, 3.2 - layer * 0.15),
				cframe = at(bx, 0.6 + 0.35 + (layer - 1) * 0.7, spec.z),
				color = if layer % 2 == 0 then { 150, 106, 76 } else W.leather,
				material = Enum.Material.Fabric,
			})
			part:SetAttribute("Layer", layer)
		end

		-- 풀무에서 큰 관까지 짧은 관
		local path = World.pipePath(padIndex)
		local y = World.PIPE.height
		if #path >= 2 then
			cylinderBetween(
				model,
				"Pipe",
				Vector3.new(path[1][1], y, path[1][2]),
				Vector3.new(path[2][1], y, path[2][2]),
				World.PIPE.diameter
			)
		end

		model.PrimaryPart = pad
		model.Parent = treadmills
	end

	-- 큰 관 (남북) + 화덕으로 가는 관 (동쪽)
	local zs: { number } = {}
	for _, spec in World.TREADMILL_PADS do
		table.insert(zs, spec.z)
	end
	table.insert(zs, World.PIPE.feedZ)
	local minZ, maxZ = math.min(table.unpack(zs)), math.max(table.unpack(zs))
	local y = World.PIPE.height
	cylinderBetween(
		parent,
		"MainPipe",
		Vector3.new(World.PIPE.mainX, y, minZ),
		Vector3.new(World.PIPE.mainX, y, maxZ),
		World.PIPE.diameter * 1.4
	)
	cylinderBetween(
		parent,
		"FeedPipe",
		Vector3.new(World.PIPE.mainX, y, World.PIPE.feedZ),
		Vector3.new(World.FORGE.x - World.FORGE.sizeX / 2, y, World.PIPE.feedZ),
		World.PIPE.diameter * 1.4
	)
end

--------------------------------------------------------------------------------
-- 명예의 벽 · 진열대
--------------------------------------------------------------------------------

local function buildHonorWall(parent: Instance)
	local spec = World.RANKING_WALL
	local honor = folder(parent, "Honor")

	block(honor, {
		name = "HonorStone",
		size = Vector3.new(2, spec.height, spec.width),
		cframe = at(spec.x, spec.height / 2, spec.z),
		color = W.stone,
		material = Enum.Material.Slate,
	})
	-- 액자 (위·아래·양옆)
	local frameX = spec.x - 1.1
	for _, piece in
		{
			{ spec.width + 0.8, spec.height - 0.6 },
			{ spec.width + 0.8, 0.6 },
		}
	do
		block(honor, {
			name = "HonorFrame",
			size = Vector3.new(0.4, 0.5, piece[1]),
			cframe = at(frameX, piece[2], spec.z),
			color = W.wood,
			material = Enum.Material.Wood,
		})
	end
	for side = -1, 1, 2 do
		block(honor, {
			name = "HonorFrame",
			size = Vector3.new(0.4, spec.height - 0.6, 0.5),
			cframe = at(frameX, spec.height / 2, spec.z + side * (spec.width / 2 + 0.15)),
			color = W.wood,
			material = Enum.Material.Wood,
		})
	end
	block(honor, {
		name = "HonorBoard",
		size = Vector3.new(0.2, spec.height - 1.6, spec.width - 0.6),
		cframe = at(frameX - 0.05, spec.height / 2, spec.z),
		color = W.stoneDark,
		material = Enum.Material.SmoothPlastic,
	})
	-- 양옆 횃불
	for index, side in { -1, 1 } do
		local z = spec.z + side * (spec.width / 2 + 2)
		block(honor, {
			name = "HonorTorchPost",
			size = Vector3.new(0.6, 6, 0.6),
			cframe = at(spec.x - 1.5, 3, z),
			color = W.wood,
			material = Enum.Material.Wood,
		})
		local bowl = block(honor, {
			name = `HonorTorch{index}`,
			size = Vector3.new(0.8, 1.6, 1.6),
			cframe = at(spec.x - 1.5, 6.3, z) * CFrame.Angles(0, 0, math.rad(90)),
			color = W.iron,
			material = Enum.Material.Metal,
			shape = Enum.PartType.Cylinder,
		})
		fire(bowl, 3, 6)
		light(bowl, "TorchLight", W.ember, 12, 1.1)
	end
end

local function buildShowcase(parent: Instance)
	local spec = World.SHOWCASE
	local showcase = folder(parent, "Showcase")

	local base = block(showcase, {
		name = "ShowcaseBase",
		size = Vector3.new(4, 3, 4),
		cframe = at(spec.x, 1.5, spec.z),
		color = W.stone,
		material = Enum.Material.Slate,
	})
	block(showcase, {
		name = "ShowcaseGlass",
		size = Vector3.new(3.4, 5.6, 3.4),
		cframe = at(spec.x, 3 + 2.8, spec.z),
		color = W.glass,
		material = Enum.Material.Glass,
		transparency = 0.75,
	})
	block(showcase, {
		name = "ShowcaseCap",
		size = Vector3.new(3.8, 0.4, 3.8),
		cframe = at(spec.x, 3 + 5.8, spec.z),
		color = W.iron,
		material = Enum.Material.Metal,
	})
	block(showcase, {
		name = "ShowcasePlaque",
		size = Vector3.new(0.2, 1.2, 3.4),
		cframe = at(spec.x - 2.1, 1.8, spec.z),
		color = W.gold,
		material = Enum.Material.Metal,
	})
	light(base, "ShowcaseLight", W.gold, 10, 0.8)
	base:SetAttribute(World.ATTR.ownerName, "")
	base:SetAttribute(World.ATTR.swordId, "")
	base:SetAttribute(World.ATTR.swordLevel, 0)
	showcaseBase = base
end

--------------------------------------------------------------------------------

local function buildLobby(): Folder
	local lobby = Instance.new("Folder")
	lobby.Name = World.LOBBY_FOLDER

	buildGround(lobby)
	buildSpawn(lobby)
	for index, torch in World.TORCHES do
		buildTorch(lobby, torch.x, torch.z, index)
	end
	buildSigns(lobby)
	buildMountains(lobby)
	buildForge(lobby)
	buildGate(lobby)
	buildTreadmills(lobby)
	buildHonorWall(lobby)
	buildShowcase(lobby)

	lobby:SetAttribute(World.ATTR.treadmillUsers, 0)
	lobby.Parent = Workspace
	return lobby
end

-- 로비 폴더에서 러닝머신 발판을 찾는다 (직접 지은 로비든 Studio 에서 꾸민 로비든 같다).
-- 발판은 TreadmillTier 속성이 있는 파트다. 모델 안에 "Pad" 로 있어도 되고 폴더 바로 아래 있어도 된다.
local function collectPads(lobby: Instance)
	pads = {}

	local treadmills = lobby:FindFirstChild(World.TREADMILL_FOLDER)
	if treadmills == nil then
		warn(
			"[WorldService] 로비에 Treadmills 폴더가 없습니다. 러닝머신이 동작하지 않습니다."
		)
		return
	end

	for _, child in treadmills:GetChildren() do
		local part: Instance? = child
		if child:IsA("Model") then
			part = child:FindFirstChild("Pad")
		end
		if part == nil or not part:IsA("BasePart") then
			continue
		end

		local tierId = part:GetAttribute(World.TREADMILL_TIER_ATTRIBUTE)
		local tier = if type(tierId) == "string" then EconomyConfig.treadmillTier(tierId) else nil
		if tier == nil then
			warn(
				`[WorldService] 러닝머신 발판 {child.Name} 의 단계를 알 수 없습니다`
			)
			continue
		end

		table.insert(pads, {
			part = part,
			tier = tier,
			bounds = {
				x = part.Position.X,
				z = part.Position.Z,
				sizeX = part.Size.X,
				sizeZ = part.Size.Z,
				topY = part.Position.Y + part.Size.Y / 2,
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

function WorldService.getLobby(): Instance?
	return lobbyFolder
end

-- 쇳물 관문 모델 (Studio 에서 꾸민 로비에 없으면 nil)
function WorldService.getGate(): Model?
	return gateModel
end

-- 서버 최고 검 진열대의 받침 (없으면 nil)
function WorldService.getShowcaseBase(): BasePart?
	return showcaseBase
end

-- 경주 코스를 담는 폴더 (Workspace/Races)
function WorldService.getRacesFolder(): Folder
	local f = racesFolder
	if f == nil then
		f = Instance.new("Folder")
		f.Name = World.RACES_FOLDER
		f.Parent = Workspace
		racesFolder = f
	end
	return f
end

local function teleport(
	player: Player,
	x: number,
	z: number,
	scatter: number,
	lookAt: Vector3?
): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local position = Vector3.new(
		x + rng:NextNumber(-scatter, scatter),
		1 + World.COURSE.spawnHeight,
		z + rng:NextNumber(-scatter, scatter)
	)
	local target = lookAt or Vector3.new(World.FORGE.x, position.Y, World.FORGE.z)
	character:PivotTo(CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z)))
	return true
end

-- 캐릭터를 로비 스폰 근처로 옮긴다. 캐릭터가 없으면 false.
function WorldService.teleportToLobby(player: Player): boolean
	local lobby = World.LOBBY
	return teleport(player, lobby.spawnX, lobby.spawnZ, lobby.spawnScatter, nil)
end

-- 경주에서 돌아올 때: 관문 앞 (바로 다시 참가하기 쉽게)
function WorldService.teleportToReturnPoint(player: Player): boolean
	local point = World.RETURN_POINT
	return teleport(
		player,
		point.x,
		point.z,
		point.scatter,
		Vector3.new(World.GATE.ringX, 0, World.GATE.ringZ)
	)
end

function WorldService.Init()
	setupCollisionGroup()
	setupLighting()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	worldEvent = remotesFolder:WaitForChild(Remotes.Events.WorldEvent) :: RemoteEvent

	local existing = Workspace:FindFirstChild(World.LOBBY_FOLDER)
	local lobby = if existing then existing else buildLobby()
	lobbyFolder = lobby
	if existing then
		local gate = existing:FindFirstChild("Gate")
		gateModel = if gate and gate:IsA("Model") then gate else nil
	end
	collectPads(lobby)

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
