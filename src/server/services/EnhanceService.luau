--!strict
--[[
	EnhanceService — 강화 요청 처리.

	흐름 (지시서 4절):
	  1) 레이트 리밋 + 동시 요청 락
	  2) 점검 모드 / 프로필 로드 상태 확인
	  3) 레벨 < MAX, 골드 >= 비용 확인
	  4) 골드 차감 → 결과 계산 → 레벨/통계/도감 갱신을 yield 없이 한 번에
	  5) 결과 반환
	  6) 경제/결과 로그

	난수는 서버에서 Random 객체 하나를 만들어 재사용한다.
	클라이언트가 보낸 값은 "방지권을 쓸지" 하나뿐이고, 그것도 boolean 인지 검사한다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ConfigFolder = Shared:WaitForChild("Config")
local EnhanceTable = require(ConfigFolder:WaitForChild("EnhanceTable"))
local Weapons = require(ConfigFolder:WaitForChild("Weapons"))

local EnhanceLogic = require(Shared:WaitForChild("Pure"):WaitForChild("EnhanceLogic"))

local services = script.Parent
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local AnalyticsService = require(services:WaitForChild("AnalyticsService"))
local LiveOpsService = require(services:WaitForChild("LiveOpsService"))
local RateLimiter = require(services:WaitForChild("RateLimiter"))

local EnhanceService = {}
EnhanceService.Name = "EnhanceService"

-- 서버 난수. 요청마다 새로 만들지 않는다.
local rng = Random.new()

-- 플레이어당 초당 3회, 동시 처리 1건
local limiter = RateLimiter.new({ maxRequests = 3, windowSeconds = 1 })

local feedRemote: RemoteEvent? = nil

local function fail(reason: string): Types.Failure
	return { ok = false, reason = reason }
end

-- 현재 적용 중인 이벤트까지 반영한 최종 확률
local function finalOddsFor(level: number): EnhanceLogic.Odds?
	local base = EnhanceTable.Odds[level]
	if base == nil then
		return nil
	end
	return EnhanceLogic.applyBuff(base, LiveOpsService.getSuccessBuff())
end

local function buildDisplayOdds(level: number): Types.DisplayOdds
	local odds = finalOddsFor(level)
	local event = LiveOpsService.getActiveEvent()

	if odds == nil then
		-- 최대 레벨: 더 이상 강화할 수 없다.
		return {
			level = level,
			success = 0,
			keep = 0,
			destroy = 0,
			cost = 0,
			eventName = if event then event.nameKey else nil,
		}
	end

	return {
		level = level,
		success = odds.success,
		keep = odds.keep,
		destroy = odds.destroy,
		cost = odds.cost,
		eventName = if event then event.nameKey else nil,
	}
end

-- 도감 기록. 보상 지급은 CodexService(Phase 6)가 맡고, 여기서는 달성 사실만 남긴다.
local function recordCodex(data: Types.PlayerData, level: number)
	for _, milestone in Weapons.CODEX_MILESTONES do
		if level >= milestone then
			data.codex[`{data.weapon.id}:{milestone}`] = true
		end
	end
end

local function broadcastIfNotable(player: Player, data: Types.PlayerData, level: number)
	if level < EnhanceTable.BROADCAST_MIN_LEVEL or feedRemote == nil then
		return
	end

	local weapon = Weapons.get(data.weapon.id)
	feedRemote:FireAllClients({
		kind = "broadcast",
		playerName = player.DisplayName,
		weaponKey = if weapon then weapon.nameKey else "",
		level = level,
	})
end

--[[
	실제 처리. 여기에는 yield 가 하나도 없다.
	(task.wait, WaitForChild, :Async 호출을 넣으면 그 사이에 세션이 끝나거나
	 같은 플레이어의 다음 요청이 끼어들어 골드/레벨이 어긋날 수 있다)
]]
local function process(player: Player, wantsProtect: boolean): Types.EnhanceResponse
	if LiveOpsService.isMaintenance() then
		return fail("maintenance")
	end

	local data = DataService.getActiveData(player)
	if data == nil then
		return fail("not_ready")
	end

	local level = data.weapon.level
	if level >= EnhanceTable.MAX_LEVEL then
		return fail("max_level")
	end

	local odds = finalOddsFor(level)
	if odds == nil then
		return fail("max_level")
	end

	if not EconomyService.canAfford(data, odds.cost) then
		return fail("not_enough_gold")
	end

	-- 여기서부터 실제 변경. 실패할 수 있는 조건은 위에서 모두 걸렀다.
	EconomyService.spendGold(player, data, odds.cost, "enhance_cost")

	local result = EnhanceLogic.resolve({
		level = level,
		maxLevel = EnhanceTable.MAX_LEVEL,
		odds = odds,
		roll = rng:NextNumber() * 100,
		useProtect = wantsProtect,
		protectTickets = data.protectTickets,
		shardExponent = EnhanceTable.SHARD_EXPONENT,
	})

	data.weapon.level = result.newLevel
	data.stats.enhanceTries += 1

	if result.outcome == "success" then
		data.stats.enhanceSuccess += 1
		if result.newLevel > data.stats.highestLevel then
			data.stats.highestLevel = result.newLevel
		end
		recordCodex(data, result.newLevel)
	elseif result.outcome == "destroy" then
		data.stats.destroyed += 1
		if result.shardsGained > 0 then
			EconomyService.addShards(player, data, result.shardsGained, "enhance_destroy")
		end
	elseif result.outcome == "protected" then
		EconomyService.spendTickets(player, data, result.ticketsUsed, "enhance_protect")
	end

	AnalyticsService.logEnhance(player, level, result.outcome, odds.cost)

	if result.outcome == "success" then
		broadcastIfNotable(player, data, result.newLevel)
	end

	return {
		ok = true,
		result = result.outcome,
		newLevel = result.newLevel,
		gold = data.gold,
		shardsGained = result.shardsGained,
		odds = buildDisplayOdds(result.newLevel),
	}
end

--[[
	강화 1회 요청의 입구.
	useProtect: 파괴 방지권을 쓸지 여부. 이것이 클라이언트가 보내는 유일한 값이다.
]]
local function handleEnhance(player: Player, useProtect: any): Types.EnhanceResponse
	-- 1) 입력 타입 검증 (nil 은 "사용 안 함"으로 본다)
	if useProtect ~= nil and type(useProtect) ~= "boolean" then
		return fail("invalid_argument")
	end
	local wantsProtect: boolean = useProtect == true

	-- 2) 레이트 리밋
	if not limiter:consume(player.UserId) then
		return fail("too_fast")
	end

	-- 3) 동시 처리 1건
	if not limiter:tryLock(player.UserId) then
		return fail("busy")
	end

	-- 처리 중 예기치 못한 오류가 나도 락은 반드시 풀어야 한다.
	-- (락이 남으면 그 플레이어는 다시는 강화할 수 없게 된다)
	local ok, response = xpcall(process, debug.traceback, player, wantsProtect)

	limiter:unlock(player.UserId)

	if not ok then
		warn(`[EnhanceService] 처리 중 오류 ({player.UserId}):\n{response}`)
		return fail("unknown")
	end

	if response.ok then
		DataService.replicate(player)
	end

	return response
end

local function handleGetOdds(player: Player): Types.DisplayOdds | Types.Failure
	local data = DataService.getData(player)
	if data == nil then
		return fail("not_ready")
	end
	return buildDisplayOdds(data.weapon.level)
end

-- 접속 직후 클라이언트가 현재 상태를 한 번에 받아 가는 경로
local function handleGetState(player: Player): { ok: true, data: Types.PlayerData, odds: Types.DisplayOdds } | Types.Failure
	local data = DataService.getData(player)
	if data == nil then
		return fail("not_ready")
	end

	return {
		ok = true,
		data = data,
		odds = buildDisplayOdds(data.weapon.level),
	}
end

function EnhanceService.Init()
	-- 확률표가 깨진 채로 서버가 뜨는 일이 없도록 시작할 때 검사한다.
	local problem = EnhanceTable.validate()
	if problem ~= nil then
		error(`[EnhanceService] 확률표가 잘못되었습니다: {problem}`, 0)
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)

	local enhanceRemote = remotesFolder:WaitForChild(Remotes.Functions.Enhance) :: RemoteFunction
	enhanceRemote.OnServerInvoke = handleEnhance

	local oddsRemote = remotesFolder:WaitForChild(Remotes.Functions.GetOdds) :: RemoteFunction
	oddsRemote.OnServerInvoke = handleGetOdds

	local stateRemote = remotesFolder:WaitForChild(Remotes.Functions.GetState) :: RemoteFunction
	stateRemote.OnServerInvoke = handleGetState

	feedRemote = remotesFolder:WaitForChild(Remotes.Events.FeedMessage) :: RemoteEvent
end

function EnhanceService.Start()
	Players.PlayerRemoving:Connect(function(player)
		limiter:clear(player.UserId)
	end)
end

-- 다른 서비스/테스트에서 쓸 수 있도록 공개
function EnhanceService.getDisplayOdds(level: number): Types.DisplayOdds
	return buildDisplayOdds(level)
end

return EnhanceService
