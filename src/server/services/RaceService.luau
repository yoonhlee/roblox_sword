--!strict
--[[
	RaceService — 추격 생존 경주 (통합 기획서 4절).

	한 판의 흐름:
	  1) 로비에서 "매칭"을 누르면 대기열에 들어간다.
	  2) 대기열이 20명이 되면 바로, 아니면 첫 사람이 누른 뒤 7초에 대기열을 닫고
	     전원을 출발선에 세운다. 3초 카운트다운 뒤 출발 (누른 뒤 10초 안에 출발).
	  3) 모두가 공유하는 추격자 하나가 30칸 뒤에서 출발해 지수적으로 빨라진다.
	  4) 추격자에게 따라잡히면 탈락. 그 순간 보상을 확정해 지급한다.
	  5) 탈락한 사람은 관전하거나 "로비로" 를 눌러 나간다. 모두 탈락하면 판이 끝난다.

	서버 권위 (통합 기획서 4-5절):
	  - 클라이언트가 보내는 값은 "매칭", "대기 취소", "로비로" 요청뿐이다. 거리·속도·순위는 받지 않는다.
	  - 거리는 서버가 매 프레임 캐릭터 위치를 보고 계산한다. 그 위치는 플레이어 기기가 만드는 값이라
	    조작할 수 있으므로, "허용 최대 속도 × 지난 시간"까지만 인정한다(Pure/RaceLogic.effectivePosition).
	    그보다 앞에 있다고 주장해도 한계 위치에 있는 것으로 보고 추격자가 그 위치를 지나면 탈락시킨다.
	  - 이동 속도, 최대 거리, 보상은 "출발선에 섰을 때의 착용 검 레벨"로 정한다.
	    경주 중에 검을 바꾸거나 강화해도 그 판에는 영향이 없다.

	코스는 판마다 새로 짓는다(장애물 위치가 매번 다르다). 여러 판이 동시에 열릴 수 있어서
	판마다 옆으로 떨어진 자리(slot)를 하나씩 쓴다.

	아직 값이 없어서 자리만 만든 것:
	  [미정 D6]  1~3위 보너스 → rankBonusFor
	  [미정 D16] 특수 능력·도감 기념 업그레이드 → allowedSpeedFor (허용 속도에 반영할 자리)
	  [미정 D17] 신규 유저 보호 → 방해 능력이 생길 때 함께 만든다
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ConfigFolder = Shared:WaitForChild("Config")
local RaceConfig = require(ConfigFolder:WaitForChild("RaceConfig"))
local EnhanceTable = require(ConfigFolder:WaitForChild("EnhanceTable"))
local World = require(ConfigFolder:WaitForChild("World"))

local Pure = Shared:WaitForChild("Pure")
local RaceLogic = require(Pure:WaitForChild("RaceLogic"))
local EnhanceLogic = require(Pure:WaitForChild("EnhanceLogic"))
local SwordLogic = require(Pure:WaitForChild("SwordLogic"))

local services = script.Parent
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local AnalyticsService = require(services:WaitForChild("AnalyticsService"))
local LiveOpsService = require(services:WaitForChild("LiveOpsService"))
local WorldService = require(services:WaitForChild("WorldService"))
local RateLimiter = require(services:WaitForChild("RateLimiter"))
local CourseBuilder = require(services:WaitForChild("CourseBuilder"))

local RaceService = {}
RaceService.Name = "RaceService"

type Racer = {
	player: Player,
	userId: number,
	name: string,
	level: number, -- 출발선에 섰을 때의 착용 검 레벨
	speed: number, -- 그 레벨의 이동 속도 v(L)
	maxDistance: number, -- 그 레벨의 최대 거리 Dmax(L)
	lane: number, -- 출발선에서 설 자리 (트랙 중심 기준 좌우)
	best: number, -- 서버가 인정한 가장 먼 위치 (출발선 기준)
	alive: boolean,
	present: boolean, -- 아직 이 판에 붙어 있는지 (로비로 나가거나 접속을 끊으면 false)
	rank: number, -- 탈락했을 때 정해진다 (끝까지 남은 사람이 1위)
	distance: number, -- 보상에 쓴 거리
	reward: number, -- 지급한 골드
}

type Race = {
	id: number,
	slot: number,
	state: "lineup" | "running" | "finished",
	course: CourseBuilder.Built,
	racers: { Racer },
	aliveCount: number,
	placed: boolean, -- 캐릭터를 출발선으로 옮겼는지
	placeAt: number, -- 출발선으로 옮기는 시각 (os.clock)
	goAt: number, -- 출발 신호 시각
	startedAt: number,
	closeAt: number, -- 결과 표시가 끝나고 정리하는 시각
}

local CURVE: RaceLogic.Curve = {
	minTime = RaceConfig.MIN_TIME_SECONDS,
	maxTime = RaceConfig.MAX_TIME_SECONDS,
	maxLevel = EnhanceTable.MAX_LEVEL,
	accel = RaceConfig.CHASER_ACCEL,
	headStart = RaceConfig.HEAD_START,
	baseSpeed = RaceConfig.BASE_SPEED,
}

--[[
	코스를 지은 뒤 캐릭터를 출발선으로 옮기기까지 두는 틈(초).
	코스 파트가 플레이어 기기에 도착하기 전에 캐릭터부터 옮겨지면 바닥이 없는 곳에 떨어질 수 있다.
	LINEUP_SECONDS 안에 포함된다.
]]
local PLACE_DELAY_SECONDS = 0.5

local rng = Random.new()

-- 플레이어당 초당 4회 (매칭 버튼 연타 방지)
local limiter = RateLimiter.new({ maxRequests = 4, windowSeconds = 1 })

local queue: { Player } = {}
local queueOpenedAt = 0 -- 지금 대기열의 첫 사람이 들어온 시각

local races: { [number]: Race } = {}
local raceOf: { [Player]: Race } = {}
local usedSlots: { [number]: boolean } = {}
local nextRaceId = 1

local updateRemote: RemoteEvent? = nil

-- 쇳물 관문 바닥 원으로 대기열에 들어온 사람 (원 밖으로 나가면 빠진다)
local joinedByRing: { [Player]: boolean } = {}
local RING_CHECK_SECONDS = 0.2
local lastRingCheck = 0

local function fail(reason: string): Types.Failure
	return { ok = false, reason = reason }
end

local function send(player: Player, payload: Types.RaceUpdate)
	if updateRemote and player.Parent == Players then
		updateRemote:FireClient(player, payload)
	end
end

-- 그 판에 아직 붙어 있는 사람 모두에게 보낸다(관전 중인 사람 포함).
local function broadcast(race: Race, payload: Types.RaceUpdate)
	for _, racer in race.racers do
		if racer.present then
			send(racer.player, payload)
		end
	end
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function setWalkSpeed(player: Player, speed: number)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

local function findRacer(race: Race, player: Player): Racer?
	for _, racer in race.racers do
		if racer.player == player then
			return racer
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- 수치
--------------------------------------------------------------------------------

-- 보상 = 그 레벨의 강화 비용(검 1개 기준, 할증 없음) × 배율 × 달린 비율
local function rewardFor(level: number, distance: number, maxDistance: number): number
	local odds = EnhanceTable.Odds[level]
	local multiplier =
		RaceLogic.rewardMultiplier(level, if odds then odds.success else 0, RaceConfig.Multiplier)
	local cost =
		EnhanceLogic.cost(level, 1, EnhanceTable.COST_BASE, EnhanceTable.SWORD_COUNT_EXPONENT)

	return RaceLogic.reward(cost, multiplier, distance, maxDistance)
end

--[[
	서버가 인정하는 최대 이동 속도.
	[미정 D16] 도감 기념 업그레이드와 특수 능력이 속도를 올리게 되면 여기에 반영한다.
	(반영하지 않으면 정상적으로 빨라진 사람의 거리를 서버가 깎게 된다.)
]]
local function allowedSpeedFor(racer: Racer): number
	return racer.speed
end

--[[
	[미정 D6] 1~3위 보너스. 크기와 지급 최소 인원이 정해지면 여기서 계산한다.
	순위(racer.rank)와 참가 인원(#race.racers)은 탈락하는 순간 이미 정해져 있다.
]]
local function rankBonusFor(_race: Race, _racer: Racer): number
	return 0
end

--------------------------------------------------------------------------------
-- 대기열
--------------------------------------------------------------------------------

-- 관문 전광판·고리 연출용 상태 (대기 인원, 출발 예정 시각)
local function publishGate(secondsLeft: number?)
	local gate = WorldService.getGate()
	if gate == nil then
		return
	end
	gate:SetAttribute(World.ATTR.queueCount, #queue)
	gate:SetAttribute(
		World.ATTR.departAt,
		if #queue > 0 and secondsLeft then Workspace:GetServerTimeNow() + secondsLeft else 0
	)
end

local function notifyQueue()
	local waited = os.clock() - queueOpenedAt
	local secondsLeft = RaceLogic.secondsUntilStart(waited, RaceConfig.MATCH_WINDOW_SECONDS)
	publishGate(secondsLeft)

	for _, player in queue do
		send(player, {
			kind = "queue",
			queued = true,
			count = #queue,
			secondsLeft = secondsLeft,
		})
	end
end

local function removeFromQueue(player: Player): boolean
	local index = table.find(queue, player)
	if index == nil then
		return false
	end
	table.remove(queue, index)
	joinedByRing[player] = nil
	return true
end

--------------------------------------------------------------------------------
-- 로비로 돌려보내기
--------------------------------------------------------------------------------

local function sendToLobby(player: Player)
	-- 관문 앞으로 돌아온다 (바로 다시 참가하기 쉽게)
	WorldService.teleportToReturnPoint(player)
	setWalkSpeed(player, RaceConfig.BASE_SPEED)
	send(player, { kind = "lobby" })
end

--------------------------------------------------------------------------------
-- 탈락과 보상
--------------------------------------------------------------------------------

--[[
	탈락 처리. 이 순간 보상을 확정해 지급한다(바로 로비로 나가도 잃지 않는다).
	yield 하지 않는다.

	unloadingData: 접속을 끊는 중에 불린 경우 DataService 가 넘겨준 데이터.
	그때는 getActiveData 가 이미 nil 이라 이 데이터에 직접 지급한다(곧바로 저장된다).
]]
local function eliminate(race: Race, racer: Racer, unloadingData: Types.PlayerData?)
	if not racer.alive then
		return
	end

	racer.alive = false
	race.aliveCount -= 1
	racer.rank = race.aliveCount + 1
	racer.distance = RaceLogic.creditedDistance(racer.best, RaceConfig.DEAD_ZONE)

	local player = racer.player
	local bonus = rankBonusFor(race, racer)
	local amount = rewardFor(racer.level, racer.distance, racer.maxDistance) + bonus

	local data = unloadingData or DataService.getActiveData(player)
	if data ~= nil then
		racer.reward = EconomyService.addGold(player, data, amount, "race_reward")
		if unloadingData == nil then
			DataService.replicate(player)
		end
	end

	setWalkSpeed(player, 0)

	AnalyticsService.logFunnel(player, "race_eliminated", {
		level = racer.level,
		distance = racer.distance,
		rank = racer.rank,
		reward = racer.reward,
	})

	send(player, {
		kind = "result",
		raceId = race.id,
		rank = racer.rank,
		racerCount = #race.racers,
		level = racer.level,
		distance = math.floor(racer.distance),
		maxDistance = racer.maxDistance,
		reward = racer.reward,
		bonus = bonus,
	})

	broadcast(race, {
		kind = "eliminated",
		raceId = race.id,
		userId = racer.userId,
		rank = racer.rank,
		distance = math.floor(racer.distance),
	})
end

--------------------------------------------------------------------------------
-- 판 시작 · 진행 · 끝
--------------------------------------------------------------------------------

local function takeSlot(): number
	local slot = 0
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	return slot
end

-- 대기열에 있던 사람들로 한 판을 연다.
local function startRace(batch: { Player })
	local racers: { Racer } = {}

	for _, player in batch do
		local data = DataService.getActiveData(player)
		local sword = if data then SwordLogic.equipped(data.swords, data.equippedId) else nil
		local humanoid = humanoidOf(player)

		local canRace = player.Parent == Players
			and sword ~= nil
			and humanoid ~= nil
			and humanoid.Health > 0
			and rootOf(player) ~= nil
			and raceOf[player] == nil

		if not canRace or sword == nil then
			-- 기다리는 사이에 나갔거나 캐릭터가 없다. 대기열에서 빠졌다고 알려 준다.
			send(player, { kind = "queue", queued = false })
			continue
		end

		local level = sword.level
		table.insert(racers, {
			player = player,
			userId = player.UserId,
			name = player.DisplayName,
			level = level,
			speed = RaceLogic.runSpeed(level, CURVE),
			maxDistance = RaceLogic.maxDistance(level, CURVE),
			lane = 0,
			best = 0,
			alive = true,
			present = true,
			rank = 0,
			distance = 0,
			reward = 0,
		})
	end

	if #racers == 0 then
		return
	end

	-- 출발 자리를 섞는다.
	for index = #racers, 2, -1 do
		local other = rng:NextInteger(1, index)
		racers[index], racers[other] = racers[other], racers[index]
	end

	-- 코스 길이는 이 판에서 가장 멀리 갈 수 있는 사람 기준.
	local topDistance = 0
	for _, racer in racers do
		topDistance = math.max(topDistance, racer.maxDistance)
	end

	local courseConfig = RaceConfig.Course
	local length = RaceLogic.courseLength(topDistance, courseConfig)
	local obstacles = RaceLogic.generateObstacles(length, courseConfig, function(): number
		return rng:NextNumber()
	end)

	local slot = takeSlot()
	local id = nextRaceId
	nextRaceId += 1

	local origin = Vector3.new(slot * World.COURSE.slotSpacing, 0, World.COURSE.startZ)

	local ok, result = pcall(
		CourseBuilder.build,
		WorldService.getRacesFolder(),
		id,
		origin,
		length,
		RaceConfig.HEAD_START,
		courseConfig.trackWidth,
		obstacles
	)

	if not ok then
		usedSlots[slot] = nil
		error(`코스를 짓지 못했습니다: {result}`, 0)
	end

	local now = os.clock()
	local race: Race = {
		id = id,
		slot = slot,
		state = "lineup",
		course = result :: CourseBuilder.Built,
		racers = racers,
		aliveCount = #racers,
		placed = false,
		placeAt = now + PLACE_DELAY_SECONDS,
		goAt = now + RaceConfig.LINEUP_SECONDS,
		startedAt = 0,
		closeAt = 0,
	}
	races[id] = race

	local offsets =
		RaceLogic.lineupOffsets(#racers, courseConfig.lineupWidth, courseConfig.lineupMaxSpacing)
	local entrants: { Types.RaceEntrant } = {}

	for index, racer in racers do
		raceOf[racer.player] = race
		racer.lane = offsets[index]

		-- 출발 신호 전에는 움직이지 못한다. (출발선으로는 잠시 뒤 stepRace 가 옮긴다)
		setWalkSpeed(racer.player, 0)

		table.insert(entrants, {
			userId = racer.userId,
			name = racer.name,
			level = racer.level,
		})
	end

	for _, racer in racers do
		send(racer.player, {
			kind = "lineup",
			raceId = id,
			countdown = RaceConfig.LINEUP_SECONDS,
			originX = origin.X,
			originZ = origin.Z,
			level = racer.level,
			speed = racer.speed,
			maxDistance = racer.maxDistance,
			entrants = entrants,
		})
		AnalyticsService.logFunnel(racer.player, "race_start", {
			level = racer.level,
			racers = #racers,
		})
	end
end

-- 모두 탈락했다. 최종 순위를 알리고 잠시 뒤 정리한다.
local function finishRace(race: Race, now: number)
	race.state = "finished"
	race.closeAt = now + RaceConfig.RESULT_SECONDS

	local ranking: { Types.RaceRankingRow } = {}
	for _, racer in race.racers do
		table.insert(ranking, {
			rank = racer.rank,
			userId = racer.userId,
			name = racer.name,
			level = racer.level,
			distance = math.floor(racer.distance),
		})
	end
	table.sort(ranking, function(a, b)
		return a.rank < b.rank
	end)

	broadcast(race, {
		kind = "finished",
		raceId = race.id,
		ranking = ranking,
		returnIn = RaceConfig.RESULT_SECONDS,
	})
end

-- 판을 치운다. 아직 남아 있는 사람은 로비로 돌려보내고 코스를 지운다.
local function closeRace(race: Race)
	races[race.id] = nil
	usedSlots[race.slot] = nil

	for _, racer in race.racers do
		local player = racer.player
		if raceOf[player] == race then
			raceOf[player] = nil
		end

		if racer.present then
			racer.present = false
			if player.Parent == Players then
				sendToLobby(player)
			end
		end
	end

	CourseBuilder.destroy(race.course)
end

-- 캐릭터를 출발선의 자기 자리로 옮긴다.
local function placeOnLine(race: Race, racer: Racer)
	local character = racer.player.Character
	if character then
		character:PivotTo(CourseBuilder.lineupCFrame(race.course, racer.lane))
	end
end

local function stepRace(race: Race, now: number)
	if race.state == "lineup" then
		if not race.placed and now >= race.placeAt then
			race.placed = true
			for _, racer in race.racers do
				if racer.alive then
					placeOnLine(race, racer)
				end
			end
		end

		if now < race.goAt then
			return
		end

		race.state = "running"
		race.startedAt = now

		local floorY = race.course.origin.Y
		for _, racer in race.racers do
			if not racer.alive then
				continue
			end

			-- 드물게 바닥보다 먼저 옮겨져 아래로 떨어진 사람은 출발선에 다시 세운다.
			local root = rootOf(racer.player)
			if root and root.Position.Y < floorY - 5 then
				placeOnLine(race, racer)
			end

			setWalkSpeed(racer.player, racer.speed)
		end

		broadcast(race, { kind = "start", raceId = race.id })
		return
	end

	if race.state == "finished" then
		if now >= race.closeAt then
			closeRace(race)
		end
		return
	end

	-- 달리는 중
	local elapsed = now - race.startedAt
	local front = RaceLogic.chaserFront(elapsed, CURVE)
	CourseBuilder.moveChaser(race.course, front)

	local originZ = race.course.origin.Z
	local caught: { Racer } = {}

	for _, racer in race.racers do
		if not racer.alive then
			continue
		end

		local player = racer.player
		local root = rootOf(player)
		local humanoid = humanoidOf(player)

		if player.Parent ~= Players or root == nil or humanoid == nil or humanoid.Health <= 0 then
			-- 접속이 끊겼거나 캐릭터가 죽었다. 지금까지 인정된 거리로 탈락 처리한다.
			table.insert(caught, racer)
			continue
		end

		local position = RaceLogic.effectivePosition(
			root.Position.Z - originZ,
			elapsed,
			allowedSpeedFor(racer),
			RaceConfig.SPEED_TOLERANCE,
			RaceConfig.DISTANCE_SLACK
		)

		if position > racer.best then
			racer.best = position
		end

		if front >= position then
			table.insert(caught, racer)
		end
	end

	if #caught > 0 then
		-- 같은 순간에 여럿이 잡히면 덜 간 사람부터 탈락시킨다(더 간 사람의 순위가 높다).
		table.sort(caught, function(a, b)
			if a.best ~= b.best then
				return a.best < b.best
			end
			return a.userId < b.userId
		end)

		for _, racer in caught do
			eliminate(race, racer, nil)
		end
	end

	if race.aliveCount <= 0 then
		finishRace(race, now)
	end
end

-- 관문 바닥 원 확인 (아래 "리모트" 부분에서 정의한다. step 이 먼저 나오므로 이름만 미리 둔다)
local checkRing: () -> ()

local function step()
	local now = os.clock()

	if now - lastRingCheck >= RING_CHECK_SECONDS then
		lastRingCheck = now
		local ok, err = pcall(checkRing)
		if not ok then
			warn(`[RaceService] 관문 원 확인 오류: {err}`)
		end
	end

	if
		RaceLogic.shouldDepart(
			#queue,
			now - queueOpenedAt,
			RaceConfig.MATCH_WINDOW_SECONDS,
			RaceConfig.LINEUP_SECONDS,
			RaceConfig.MATCH_FULL_COUNT
		)
	then
		local batch = queue
		queue = {}
		joinedByRing = {}
		publishGate(nil)
		local gate = WorldService.getGate()
		if gate then
			gate:SetAttribute(World.ATTR.launchAt, Workspace:GetServerTimeNow())
		end

		local ok, err = xpcall(startRace, debug.traceback, batch)
		if not ok then
			warn(`[RaceService] 판을 열지 못했습니다:\n{err}`)
			for _, player in batch do
				if raceOf[player] == nil then
					send(player, { kind = "queue", queued = false })
				end
			end
		end
	end

	for _, race in races do
		local ok, err = xpcall(stepRace, debug.traceback, race, now)
		if not ok then
			-- 같은 오류가 매 프레임 반복되지 않도록 그 판을 닫고 사람들을 로비로 돌려보낸다.
			warn(`[RaceService] 판 {race.id} 진행 중 오류, 판을 닫습니다:\n{err}`)
			local closed, closeErr = pcall(closeRace, race)
			if not closed then
				warn(`[RaceService] 판 {race.id} 정리 실패: {closeErr}`)
				races[race.id] = nil
			end
		end
	end
end

--------------------------------------------------------------------------------
-- 리모트
--------------------------------------------------------------------------------

-- 대기열에 넣는다 (버튼과 관문 바닥 원이 같이 쓴다). 레이트 리밋은 부르는 쪽이 한다.
local function joinQueue(player: Player): Types.SimpleResponse
	if LiveOpsService.isMaintenance() then
		return fail("maintenance")
	end

	local data = DataService.getActiveData(player)
	if data == nil or SwordLogic.equipped(data.swords, data.equippedId) == nil then
		return fail("not_ready")
	end

	if raceOf[player] ~= nil then
		return fail("in_race")
	end

	local humanoid = humanoidOf(player)
	if humanoid == nil or humanoid.Health <= 0 then
		return fail("not_ready")
	end

	if table.find(queue, player) == nil then
		if #queue == 0 then
			queueOpenedAt = os.clock()
		end
		table.insert(queue, player)
		AnalyticsService.logFunnel(player, "race_queue")
	end

	notifyQueue()
	return { ok = true }
end

local function handleJoin(player: Player): Types.SimpleResponse
	if not limiter:consume(player.UserId) then
		return fail("too_fast")
	end
	return joinQueue(player)
end

--[[
	쇳물 관문 바닥 원: 올라서면 대기열에 들어가고, 원으로 들어온 사람이 원 밖으로 나가면 빠진다.
	위치는 서버가 본 캐릭터 위치로 판단한다. 버튼으로 들어온 사람은 원 밖에 있어도 그대로 둔다.
]]
function checkRing()
	local gateSpec = World.GATE
	if WorldService.getGate() == nil then
		return
	end

	for _, player in Players:GetPlayers() do
		if raceOf[player] ~= nil then
			continue
		end
		local root = rootOf(player)
		local inside = false
		if root then
			local position = root.Position
			local dx, dz = position.X - gateSpec.ringX, position.Z - gateSpec.ringZ
			inside = dx * dx + dz * dz <= gateSpec.ringRadius * gateSpec.ringRadius
				and position.Y >= 0
				and position.Y <= gateSpec.ringReach
		end

		local queued = table.find(queue, player) ~= nil
		if inside and not queued then
			local response = joinQueue(player)
			if response.ok then
				joinedByRing[player] = true
			end
		elseif not inside and queued and joinedByRing[player] then
			removeFromQueue(player)
			notifyQueue()
			send(player, { kind = "queue", queued = false })
		end
	end
end

local function handleLeaveQueue(player: Player): Types.SimpleResponse
	if not limiter:consume(player.UserId) then
		return fail("too_fast")
	end

	if removeFromQueue(player) then
		notifyQueue()
	end
	send(player, { kind = "queue", queued = false })

	return { ok = true }
end

--[[
	"로비로". 탈락한 뒤 관전을 끝내고 나갈 때 쓴다.
	아직 달리는 중(탈락 전)에는 쓸 수 없다. 경주 중이 아닐 때 누르면 그냥 로비 스폰으로 옮겨 준다.
]]
local function handleReturnToLobby(player: Player): Types.SimpleResponse
	if not limiter:consume(player.UserId) then
		return fail("too_fast")
	end

	local race = raceOf[player]
	if race ~= nil then
		local racer = findRacer(race, player)
		if racer ~= nil then
			if racer.alive then
				return fail("in_race")
			end
			racer.present = false
		end
		raceOf[player] = nil
	end

	sendToLobby(player)
	return { ok = true }
end

-- 처리 중 오류가 나도 클라이언트에는 { ok = false } 를 돌려준다.
local function guarded(handler: (player: Player) -> Types.SimpleResponse)
	return function(player: Player): Types.SimpleResponse
		local ok, response = xpcall(handler, debug.traceback, player)
		if not ok then
			warn(`[RaceService] 요청 처리 중 오류 ({player.UserId}):\n{response}`)
			return fail("unknown")
		end
		return response
	end
end

--------------------------------------------------------------------------------

function RaceService.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)

	updateRemote = remotesFolder:WaitForChild(Remotes.Events.RaceUpdate) :: RemoteEvent

	local joinRemote = remotesFolder:WaitForChild(Remotes.Functions.JoinRace) :: RemoteFunction
	joinRemote.OnServerInvoke = guarded(handleJoin)

	local leaveRemote =
		remotesFolder:WaitForChild(Remotes.Functions.LeaveRaceQueue) :: RemoteFunction
	leaveRemote.OnServerInvoke = guarded(handleLeaveQueue)

	local lobbyRemote =
		remotesFolder:WaitForChild(Remotes.Functions.ReturnToLobby) :: RemoteFunction
	lobbyRemote.OnServerInvoke = guarded(handleReturnToLobby)
end

function RaceService.Start()
	--[[
		접속을 끊는 순간. DataService 가 저장 직전에 데이터를 넘겨준다.
		달리던 중이었다면 지금까지의 거리로 보상을 확정해 그 데이터에 넣는다.
	]]
	DataService.onUnloading(function(player, data)
		if removeFromQueue(player) then
			notifyQueue()
		end

		local race = raceOf[player]
		if race == nil then
			return
		end

		local racer = findRacer(race, player)
		if racer ~= nil then
			if racer.alive then
				eliminate(race, racer, data)
			end
			racer.present = false
		end
		raceOf[player] = nil
	end)

	Players.PlayerRemoving:Connect(function(player)
		limiter:clear(player.UserId)

		-- 프로필이 열리기 전에 나간 경우 등 위 경로를 타지 않았을 때의 뒷정리.
		task.defer(function()
			if removeFromQueue(player) then
				notifyQueue()
			end

			local race = raceOf[player]
			if race == nil then
				return
			end

			local racer = findRacer(race, player)
			if racer ~= nil then
				if racer.alive then
					eliminate(race, racer, nil)
				end
				racer.present = false
			end
			raceOf[player] = nil
		end)
	end)

	RunService.Heartbeat:Connect(step)
end

-- 지금 경주에 붙어 있는지 (달리는 중이거나 관전 중)
function RaceService.isInRace(player: Player): boolean
	return raceOf[player] ~= nil
end

return RaceService
