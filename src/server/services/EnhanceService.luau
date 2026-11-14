--!strict
--[[
	EnhanceService — 강화 요청 처리 (통합 기획서 3절).

	강화 대상은 항상 "착용 중인 검"이다.

	흐름:
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
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ConfigFolder = Shared:WaitForChild("Config")
local EnhanceTable = require(ConfigFolder:WaitForChild("EnhanceTable"))
local Weapons = require(ConfigFolder:WaitForChild("Weapons"))

local Pure = Shared:WaitForChild("Pure")
local EnhanceLogic = require(Pure:WaitForChild("EnhanceLogic"))
local SwordLogic = require(Pure:WaitForChild("SwordLogic"))

local services = script.Parent
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local AnalyticsService = require(services:WaitForChild("AnalyticsService"))
local LiveOpsService = require(services:WaitForChild("LiveOpsService"))
local RateLimiter = require(services:WaitForChild("RateLimiter"))
local CodexService = require(services:WaitForChild("CodexService"))

local EnhanceService = {}
EnhanceService.Name = "EnhanceService"

-- 서버 난수. 요청마다 새로 만들지 않는다.
local rng = Random.new()

-- 플레이어당 초당 3회, 동시 처리 1건
local limiter = RateLimiter.new({ maxRequests = 3, windowSeconds = 1 })

-- 이름 변경은 필터링 API 를 부르므로 훨씬 드물게만 허용한다.
local renameLimiter = RateLimiter.new({ maxRequests = 2, windowSeconds = 30 })

local MAX_NAME_LENGTH = 16

local feedRemote: RemoteEvent? = nil

local function fail(reason: string): Types.Failure
	return { ok = false, reason = reason }
end

-- 레벨 level 에서 한 번 강화하는 비용 (가진 검 수 할증 포함)
local function costFor(level: number, swordCount: number): number
	return EnhanceLogic.cost(
		level,
		swordCount,
		EnhanceTable.COST_BASE,
		EnhanceTable.SWORD_COUNT_EXPONENT
	)
end

-- 현재 적용 중인 이벤트까지 반영한 최종 확률
local function finalOddsFor(level: number): EnhanceLogic.Odds?
	local base = EnhanceTable.Odds[level]
	if base == nil then
		return nil
	end
	return EnhanceLogic.applyBuff(base, LiveOpsService.getSuccessBuff())
end

-- 착용 검 기준으로 화면에 보여 줄 확률과 비용
local function buildDisplayOdds(data: Types.PlayerData): Types.DisplayOdds
	local sword = SwordLogic.equipped(data.swords, data.equippedId)
	local level = if sword then sword.level else 0
	local odds = finalOddsFor(level)
	local event = LiveOpsService.getActiveEvent()

	if odds == nil then
		-- 최대 레벨: 더 이상 강화할 수 없다.
		return {
			level = level,
			success = 0,
			keep = 0,
			fail = 0,
			cost = 0,
			eventName = if event then event.nameKey else nil,
		}
	end

	return {
		level = level,
		success = odds.success,
		keep = odds.keep,
		fail = odds.fail,
		cost = costFor(level, SwordLogic.count(data.swords)),
		eventName = if event then event.nameKey else nil,
	}
end

local function broadcastIfNotable(player: Player, swordId: string, level: number)
	if level < EnhanceTable.BROADCAST_MIN_LEVEL or feedRemote == nil then
		return
	end

	local weapon = Weapons.get(swordId)
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

	local sword = SwordLogic.equipped(data.swords, data.equippedId)
	if sword == nil then
		return fail("not_ready")
	end

	local level = sword.level
	if level >= EnhanceTable.MAX_LEVEL then
		return fail("max_level")
	end

	local odds = finalOddsFor(level)
	if odds == nil then
		return fail("max_level")
	end

	local cost = costFor(level, SwordLogic.count(data.swords))
	if not EconomyService.canAfford(data, cost) then
		return fail("not_enough_gold")
	end

	-- 여기서부터 실제 변경. 실패할 수 있는 조건은 위에서 모두 걸렀다.
	EconomyService.spendGold(player, data, cost, "enhance_cost")

	local result = EnhanceLogic.resolve({
		level = level,
		maxLevel = EnhanceTable.MAX_LEVEL,
		safeLevel = EnhanceTable.SAFE_LEVEL,
		odds = odds,
		roll = rng:NextNumber() * 100,
		useProtect = wantsProtect,
		protectTickets = data.protectTickets,
		shardsOnFail = EnhanceLogic.shardsFor(level, EnhanceTable.SHARD_EXPONENT),
	})

	sword.level = result.newLevel
	data.stats.enhanceTries += 1

	if result.outcome == "success" then
		data.stats.enhanceSuccess += 1
		if result.newLevel > data.stats.highestLevel then
			data.stats.highestLevel = result.newLevel
		end
		CodexService.recordSwordLevel(player, data, sword)
	elseif result.outcome == "fail" then
		data.stats.destroyed += 1
		if result.shardsGained > 0 then
			EconomyService.addShards(player, data, result.shardsGained, "enhance_fail")
		end
	elseif result.outcome == "protected" then
		EconomyService.spendTickets(player, data, result.ticketsUsed, "enhance_protect")
	end

	AnalyticsService.logEnhance(player, level, result.outcome, cost)

	-- 첫 1분 튜토리얼 퍼널: 몇 명이 1/2/3회차까지 오는지 본다.
	if data.stats.enhanceTries <= 3 then
		AnalyticsService.logFunnel(player, `tutorial_enhance_{data.stats.enhanceTries}`)
	end

	if result.outcome == "success" then
		broadcastIfNotable(player, sword.id, result.newLevel)
	end

	return {
		ok = true,
		result = result.outcome,
		newLevel = result.newLevel,
		gold = data.gold,
		shardsGained = result.shardsGained,
		odds = buildDisplayOdds(data),
	}
end

--[[
	강화 1회 요청의 입구.
	useProtect: 방지권을 쓸지 여부. 이것이 클라이언트가 보내는 유일한 값이다.
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

--[[
	착용 검 이름 짓기.

	필터링(FilterStringAsync)은 yield 하는 웹 요청이라 다른 처리와 성격이 다르다.
	그래서 순서를 이렇게 잡는다.
	  1) 형식 검사 (길이, 빈 문자열, 올바른 UTF-8)
	  2) 어느 검에 붙일 이름인지 기억해 둔다 (기다리는 동안 착용 검을 바꿀 수 있으므로)
	  3) 필터링 (여기서 yield)
	  4) yield 가 끝난 뒤에 데이터를 "다시" 가져와서 저장
	4번이 중요하다. 필터링을 기다리는 동안 플레이어가 나가거나 세션이 끝났을 수
	있으므로, yield 이전에 잡아 둔 데이터 참조를 그대로 쓰면 안 된다.

	저장하는 값도 표시하는 값도 전부 필터링을 통과한 문자열이다.
	지어 준 이름은 레벨이 바뀌어도(10강으로 돌아가도) 그대로 둔다.
]]
local function handleRename(player: Player, rawName: any): Types.RenameResponse
	if type(rawName) ~= "string" then
		return fail("invalid_argument")
	end

	local trimmed = string.match(rawName, "^%s*(.-)%s*$") or ""
	local length = utf8.len(trimmed)

	if length == nil or length == 0 or length > MAX_NAME_LENGTH then
		return fail("invalid_name")
	end

	local before = DataService.getActiveData(player)
	if before == nil then
		return fail("not_ready")
	end
	local targetId = before.equippedId

	if not renameLimiter:consume(player.UserId) then
		return fail("too_fast")
	end

	-- 여기서부터 yield 한다.
	local ok, filterResult = pcall(function()
		return TextService:FilterStringAsync(
			trimmed,
			player.UserId,
			Enum.TextFilterContext.PublicChat
		)
	end)

	if not ok then
		warn(`[EnhanceService] 이름 필터링 실패: {filterResult}`)
		return fail("filter_failed")
	end

	-- 다른 사람에게도 보이는 이름이므로 broadcast 용 결과를 쓴다.
	local okBroadcast, filtered = pcall(function()
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)

	if not okBroadcast or type(filtered) ~= "string" or filtered == "" then
		warn(`[EnhanceService] 필터 결과를 얻지 못했습니다: {filtered}`)
		return fail("filter_failed")
	end

	-- yield 가 끝났으니 데이터를 다시 가져온다.
	local data = DataService.getActiveData(player)
	if data == nil then
		return fail("not_ready")
	end

	local sword = data.swords[targetId]
	if sword == nil then
		return fail("not_owned")
	end

	sword.customName = filtered
	DataService.replicate(player)

	return { ok = true, name = filtered }
end

local function handleGetOdds(player: Player): Types.DisplayOdds | Types.Failure
	local data = DataService.getData(player)
	if data == nil then
		return fail("not_ready")
	end
	return buildDisplayOdds(data)
end

-- 접속 직후 클라이언트가 현재 상태를 한 번에 받아 가는 경로
local function handleGetState(player: Player): any
	local data = DataService.getData(player)
	if data == nil then
		return fail("not_ready")
	end

	local liveOps = LiveOpsService.getConfig()

	return {
		ok = true,
		data = data,
		odds = buildDisplayOdds(data),
		-- 이벤트·점검 상태는 바뀔 때만 방송되므로, 늦게 들어온 사람에게는 여기서 알려 준다.
		liveOps = {
			maintenance = liveOps.maintenance,
			notice = liveOps.notice,
			event = LiveOpsService.getActiveEvent(),
		},
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

	local renameRemote =
		remotesFolder:WaitForChild(Remotes.Functions.RenameWeapon) :: RemoteFunction
	renameRemote.OnServerInvoke = handleRename

	local oddsRemote = remotesFolder:WaitForChild(Remotes.Functions.GetOdds) :: RemoteFunction
	oddsRemote.OnServerInvoke = handleGetOdds

	local stateRemote = remotesFolder:WaitForChild(Remotes.Functions.GetState) :: RemoteFunction
	stateRemote.OnServerInvoke = handleGetState

	feedRemote = remotesFolder:WaitForChild(Remotes.Events.FeedMessage) :: RemoteEvent
end

function EnhanceService.Start()
	Players.PlayerRemoving:Connect(function(player)
		limiter:clear(player.UserId)
		renameLimiter:clear(player.UserId)
	end)
end

--[[
	버튼과 채팅 명령이 "같은 서버 경로"를 타도록 공개한다.
	ChatCommandService 는 이 함수를 호출하며, 리모트 핸들러와 완전히 같은
	검증·레이트 리밋·락을 거친다.
]]
function EnhanceService.requestEnhance(player: Player, useProtect: boolean?): Types.EnhanceResponse
	return handleEnhance(player, useProtect)
end

-- 착용 검 기준 표시 확률 (채팅 명령, 검 서비스가 쓴다)
function EnhanceService.getDisplayOdds(data: Types.PlayerData): Types.DisplayOdds
	return buildDisplayOdds(data)
end

-- 가진 검 수를 반영한 강화 비용 (소지 상한 가격 계산에 쓴다)
function EnhanceService.costFor(level: number, swordCount: number): number
	return costFor(level, swordCount)
end

return EnhanceService
