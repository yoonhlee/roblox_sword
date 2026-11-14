--!strict
--[[
	World — 로비와 경주 코스를 코드로 지을 때 쓰는 위치·크기 (전부 [기술] 값).

	밸런스 수치가 아니다. 미술 에셋이 없어서 블록으로만 짓는다(통합 기획서 10-3절).
	나중에 Studio 에서 직접 꾸민 로비로 바꾸면 이 파일의 LOBBY 부분은 필요 없어진다.

	좌표: 로비 바닥 윗면이 y = 0. 경주 코스는 로비 앞(+Z)쪽에서 시작해 +Z 방향으로 달린다.
	Roblox 타입(Vector3 등)을 쓰지 않고 숫자만 둔다(다른 Config 처럼 Studio 밖에서도 읽을 수 있게).
]]

local World = {}

World.LOBBY = {
	sizeX = 120,
	sizeZ = 120,
	floorThickness = 2,
	wallHeight = 24, -- 보이지 않는 벽 (밖으로 떨어지지 않게)
	spawnX = 0,
	spawnZ = -20,
	spawnSize = 14,
	spawnScatter = 5, -- 로비로 돌려보낼 때 이 범위 안에 흩어 놓는다
}

--[[
	트레드밀 발판. 수입(몇 초에 몇 골드)은 EconomyConfig.TREADMILL_TIERS 에 있다.
	tierId 가 같은 발판은 같은 수입을 준다. 한 발판에 여러 명이 올라가도 된다.
]]
World.TREADMILL_PADS = {
	{ tierId = "tier1", x = -44, z = -36 },
	{ tierId = "tier1", x = -44, z = -12 },
	{ tierId = "tier1", x = -44, z = 12 },
	{ tierId = "tier1", x = -44, z = 36 },
}
World.TREADMILL_PAD = {
	sizeX = 12,
	sizeZ = 18,
	height = 0.6, -- 발판 두께 (바닥 위로 올라온 높이)
	reach = 12, -- 발판 위로 이 높이까지 "올라가 있다"로 본다 (점프 포함)
}

World.COURSE = {
	startZ = 300, -- 출발선의 Z (로비는 Z = ±60 안쪽이다)
	slotSpacing = 90, -- 동시에 열리는 경주끼리 옆으로 떨어진 거리
	floorThickness = 2,
	segmentLength = 200, -- 바닥을 이 길이로 끊어서 만든다
	wallHeight = 18,
	wallThickness = 2,
	backExtra = 30, -- 추격자 출발 위치보다 뒤로 더 까는 바닥
	markerEvery = 100, -- 이 간격마다 바닥에 거리 표시 줄
	blockHeight = 9,
	blockDepth = 4,
	hurdleHeight = 3, -- 걸어서는 못 넘고 점프(기본 약 7칸)로 넘는 높이
	hurdleDepth = 1.5,
	gateHeight = 11,
	gateDepth = 3,
	chaserHeight = 40,
	chaserDepth = 6,
	spawnHeight = 3, -- 캐릭터를 놓을 때 바닥에서 띄우는 높이
}

-- 캐릭터끼리 부딪치지 않게 하는 충돌 그룹 이름
World.CHARACTER_COLLISION_GROUP = "ForgeCharacters"

-- Workspace 아래 폴더 이름 (클라이언트도 이 이름으로 찾는다)
World.LOBBY_FOLDER = "Lobby"
World.TREADMILL_FOLDER = "Treadmills"
World.RACES_FOLDER = "Races"
World.RACE_FOLDER_PREFIX = "Race_"
World.CHASER_NAME = "Chaser"
World.TREADMILL_TIER_ATTRIBUTE = "TreadmillTier"

return World
