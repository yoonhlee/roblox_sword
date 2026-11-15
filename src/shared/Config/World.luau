--!strict
--[[
	World — 불씨 광장(로비)과 쇳물 수로(코스)를 블록으로 지을 때 쓰는 위치·크기 (통합 기획서 8-2절).

	밸런스 수치가 아니라 [기술]·[추천치] 값이다. 미술 에셋 없이 기본 블록·재질·효과로 짓는다.
	좌표: 로비 바닥 윗면이 y = 0, 원점이 광장 가운데. 북쪽(+Z)이 코스 방향.
	코스는 로비 북쪽 멀리(+Z)에서 시작해 +Z 로 달린다.
	Roblox 타입(Vector3 등)을 쓰지 않고 숫자만 둔다(Studio 밖 테스트에서도 읽을 수 있게).
	색은 Config/Palette 의 WORLD 에 있다.
]]

local World = {}

World.LOBBY = {
	sizeX = 120,
	sizeZ = 120,
	floorThickness = 2,
	wallHeight = 24, -- 보이지 않는 벽 높이 (밖으로 떨어지지 않게)
	stoneWallHeight = 2.5, -- 보이는 낮은 돌담
	spawnX = 0,
	spawnZ = -30,
	spawnSize = 22, -- 스폰 원판 지름
	spawnScatter = 5,
}

-- 경주에서 돌아오는 자리: 관문 앞 (스폰이 아니라 다시 참가하기 쉬운 곳)
World.RETURN_POINT = { x = 12, z = 28, scatter = 4 }

-- 모루 영감의 대장간 (앞이 트인 건물, 남쪽을 향함)
World.FORGE = {
	x = 0,
	z = 8,
	sizeX = 32,
	sizeZ = 20,
	postHeight = 13,
	furnace = { x = 9, z = 14, sizeX = 8, sizeY = 6, sizeZ = 6 },
	chimney = { x = 9, z = 15, size = 3, height = 22 },
	anvil = { x = -1, z = 2 },
	npc = { x = -6, z = 3 },
	promptDistance = 10, -- 모루에서 이 거리 안이면 "강화하기" 버튼
}

-- 쇳물 관문 (경주 참가)
World.GATE = {
	x = 0,
	z = 54, -- 기둥이 서는 줄
	width = 22, -- 기둥 사이 바깥 폭
	pillarSize = 4,
	pillarHeight = 18,
	ringX = 0,
	ringZ = 42, -- 바닥 원 가운데
	ringRadius = 8,
	ringSegments = 12,
	ringReach = 10, -- 원 위로 이 높이 안이면 "올라섰다"
}

--[[
	풀무 러닝머신 발판. 수입(몇 초에 몇 골드)은 EconomyConfig.TREADMILL_TIERS 에 있다.
	tierId 가 같은 발판은 같은 수입을 준다. 한 발판에 여러 명이 올라가도 된다.
	[미정 D18] 2단계 이상은 이 줄 북쪽에 자리만 비워 둔다.
]]
World.TREADMILL_PADS = {
	{ tierId = "tier1", x = -51, z = -36 },
	{ tierId = "tier1", x = -51, z = -14 },
	{ tierId = "tier1", x = -51, z = 8 },
	{ tierId = "tier1", x = -51, z = 30 },
}
World.TREADMILL_PAD = {
	sizeX = 10,
	sizeZ = 16,
	height = 1.2, -- 받침 높이 (바닥 위로 올라온 높이)
	reach = 12, -- 발판 윗면에서 이 높이까지 "올라가 있다"로 본다 (점프 포함)
	bellowsOffsetX = 8, -- 풀무는 발판 동쪽에
	stripes = 8, -- 벨트 줄무늬 수
}

World.RANKING_WALL = { x = 56, z = 0, width = 20, height = 12 } -- 동쪽 담, 서쪽을 바라봄
World.SHOWCASE = { x = 41, z = -39 }

-- 담 위 횃불 (모서리 4 + 남북 담 4)
World.TORCHES = {
	{ x = -58, z = -58 },
	{ x = 58, z = -58 },
	{ x = -58, z = 58 },
	{ x = 58, z = 58 },
	{ x = -20, z = -58 },
	{ x = 20, z = -58 },
	{ x = -28, z = 58 },
	{ x = 28, z = 58 },
}

-- 돌길 (가운데 선 x1,z1 → x2,z2, 폭)
World.PATHS = {
	{ x1 = 0, z1 = -30, x2 = 0, z2 = 36, width = 6 }, -- 스폰 → 관문
	{ x1 = 0, z1 = -14, x2 = -44, z2 = -14, width = 5 }, -- → 러닝머신
	{ x1 = 0, z1 = -14, x2 = 50, z2 = -14, width = 5 }, -- → 명예의 벽
	{ x1 = 30, z1 = -14, x2 = 41, z2 = -33, width = 4 }, -- → 진열대
}

-- 길 끝 표지판 (글자는 각자 언어로 클라이언트가 붙인다)
-- facing: 표지판 앞면이 바라보는 방향(도). 0 = 남쪽(스폰 쪽), -90 = 동쪽, 90 = 서쪽
World.SIGNS = {
	{ x = 6, z = 30, key = "world.sign.gate", facing = 0 },
	{ x = -38, z = -9, key = "world.sign.treadmill", facing = -90 },
	{ x = 44, z = -9, key = "world.sign.honor", facing = 90 },
}

-- 풀무에서 대장간 화덕까지 이어지는 쇠 관이 지나는 줄
World.PIPE = {
	mainX = -30, -- 러닝머신 줄 옆을 남북으로 지나는 관
	feedZ = 14, -- 이 줄에서 동쪽으로 꺾어 대장간 서쪽 벽까지
	height = 0.4,
	diameter = 0.6,
}

--[[
	padIndex 번째 러닝머신의 풀무에서 화덕까지 관이 지나는 점들 (x, z). 불씨 구슬이 이 길을 따라 굴러간다.
	서버(관 짓기)와 클라이언트(불씨 연출)가 같은 함수를 쓴다.
]]
function World.pipePath(padIndex: number): { { number } }
	local pad = World.TREADMILL_PADS[padIndex]
	if pad == nil then
		return {}
	end
	local startX = pad.x + World.TREADMILL_PAD.bellowsOffsetX
	local forgeWest = World.FORGE.x - World.FORGE.sizeX / 2
	return {
		{ startX, pad.z },
		{ World.PIPE.mainX, pad.z },
		{ World.PIPE.mainX, World.PIPE.feedZ },
		{ forgeWest, World.PIPE.feedZ },
	}
end

-- 담 밖 산 실루엣 (부딪히지 않는다)
World.MOUNTAINS = {
	{ x = -170, z = 210, width = 160, height = 90 },
	{ x = 40, z = 260, width = 220, height = 120 },
	{ x = 230, z = 180, width = 160, height = 80 },
	{ x = -240, z = -60, width = 180, height = 70 },
	{ x = 240, z = -90, width = 170, height = 75 },
}

World.COURSE = {
	startZ = 300, -- 출발선의 Z (로비는 Z = ±60 안쪽이다)
	slotSpacing = 90, -- 동시에 열리는 경주끼리 옆으로 떨어진 거리
	floorThickness = 2,
	segmentLength = 200, -- 바닥을 이 길이로 끊어서 만든다
	wallHeight = 18, -- 보이지 않는 벽 포함 높이
	solidWallHeight = 6, -- 보이는 돌벽 높이
	wallThickness = 2,
	backExtra = 30, -- 추격자 출발 위치보다 뒤로 더 까는 바닥
	markerEvery = 100, -- 이 간격마다 거리 문양 띠와 숫자판
	archEvery = 500, -- 이 간격마다 화로 아치
	blockHeight = 9,
	blockDepth = 4,
	hurdleHeight = 3, -- 걸어서는 못 넘고 점프(기본 약 7칸)로 넘는 높이
	hurdleDepth = 1.5,
	gateHeight = 11,
	gateDepth = 3,
	chaserHeight = 40,
	chaserDepth = 6,
	spawnHeight = 3, -- 캐릭터를 놓을 때 바닥에서 띄우는 높이
	startBars = 9, -- 출발선 쇠창살 수
}

-- 캐릭터끼리 부딪치지 않게 하는 충돌 그룹 이름
World.CHARACTER_COLLISION_GROUP = "ForgeCharacters"

-- Workspace 아래 이름 (클라이언트도 이 이름으로 찾는다)
World.LOBBY_FOLDER = "Lobby"
World.TREADMILL_FOLDER = "Treadmills"
World.RACES_FOLDER = "Races"
World.RACE_FOLDER_PREFIX = "Race_"
World.CHASER_NAME = "Chaser"
World.TREADMILL_TIER_ATTRIBUTE = "TreadmillTier"

-- 서버가 세계 물체에 다는 속성 이름 (클라이언트가 이것을 보고 연출한다)
World.ATTR = {
	treadmillUsers = "TreadmillUsers", -- Lobby 폴더: 러닝머신 위 인원
	occupied = "Occupied", -- 발판: 누가 올라서 있는지
	paidAt = "PaidAt", -- 발판: 마지막 지급 시각 (서버 시간)
	queueCount = "QueueCount", -- 관문: 대기 인원
	departAt = "DepartAt", -- 관문: 출발 예정 시각 (서버 시간, 대기 없으면 0)
	launchAt = "LaunchAt", -- 관문: 마지막 출발 시각
	signKey = "SignKey", -- 표지판: Locale 키
	ownerName = "OwnerName", -- 진열대
	swordId = "SwordId",
	swordLevel = "SwordLevel",
}

return World
