--!strict
--[[
	BattleService — 도전/수락 흐름과 배틀 결과 처리.

	흐름:
	  1) A 가 같은 서버의 B 에게 도전 신청 (또는 "아무나 매칭")
	  2) B 가 15초 안에 수락/거절. 무응답은 거절
	  3) 서버가 승패를 계산하고 보상·레이팅을 지급
	  4) 양쪽 클라이언트에 결과를 보내 연출

	배틀로 무기가 파괴되거나 레벨이 내려가지 않는다. 걸리는 건 골드와 레이팅뿐.

	어뷰징 방지:
	  - 배틀 쿨다운 10초
	  - 하루 보상 지급 30회 상한 (초과 시 배틀은 되지만 보상 0)
	  - 같은 상대와는 하루 보상 3회까지
	  - 계정 생성 3일 미만이면 보상 50%
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Locale = require(Shared:WaitForChild("Locale"))

local ConfigFolder = Shared:WaitForChild("Config")
local BattleConfig = require(ConfigFolder:WaitForChild("BattleConfig"))

local BattleLogic = require(Shared:WaitForChild("Pure"):WaitForChild("BattleLogic"))

local services = script.Parent
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local AnalyticsService = require(services:WaitForChild("AnalyticsService"))
local LiveOpsService = require(services:WaitForChild("LiveOpsService"))
local RateLimiter = require(services:WaitForChild("RateLimiter"))

local BattleService = {}
BattleService.Name = "BattleService"

local rng = Random.new()

-- 도전 신청은 5초에 2번까지
local limiter = RateLimiter.new({ maxRequests = 2, windowSeconds = 5 })

type Invite = {
	challengerUserId: number,
	targetUserId: number,
	expiresAt: number,
}

-- 대상 userId → 받은 도전. 한 사람은 한 번에 하나만 받는다.
local invitesByTarget: { [number]: Invite } = {}
-- 도전자 userId → 보낸 도전. 한 사람은 한 번에 하나만 보낸다.
local invitesByChallenger: { [number]: Invite } = {}

local lastBattleAt: { [number]: number } = {}

local inviteRemote: RemoteEvent? = nil
local resolvedRemote: RemoteEvent? = nil
local feedRemote: RemoteEvent? = nil

local function fail(reason: string): Types.Failure
	return { ok = false, reason = reason }
end

local function languageOf(data: Types.PlayerData?): string
	if data and data.settings and data.settings.language then
		return data.settings.language
	end
	return Locale.DEFAULT_LANGUAGE
end

local function clearInvite(invite: Invite)
	if invitesByTarget[invite.targetUserId] == invite then
		invitesByTarget[invite.targetUserId] = nil
	end
	if invitesByChallenger[invite.challengerUserId] == invite then
		invitesByChallenger[invite.challengerUserId] = nil
	end
end

local function notify(player: Player, key: string, ...: any)
	if feedRemote == nil then
		return
	end
	local data = DataService.getData(player)
	feedRemote:FireClient(player, {
		kind = "system",
		text = Locale.get(languageOf(data), key, ...),
	})
end

-- 신규 계정 보상 배수
local function ageMultiplier(player: Player): number
	if player.AccountAge < BattleConfig.NEW_ACCOUNT_AGE_DAYS then
		return BattleConfig.NEW_ACCOUNT_REWARD_MULTIPLIER
	end
	return 1
end

--[[
	이 상대에게서 보상을 받을 수 있는지.
	하루 총 보상 횟수와 같은 상대 반복 횟수를 함께 본다.
]]
local function rewardAllowed(data: Types.PlayerData, opponentUserId: number): boolean
	if data.daily.battlesToday >= BattleConfig.DAILY_BATTLE_REWARD_CAP then
		return false
	end

	local perOpponent = data.daily.opponentsToday[tostring(opponentUserId)] or 0
	return perOpponent < BattleConfig.PER_OPPONENT_DAILY_CAP
end

local function markRewarded(data: Types.PlayerData, opponentUserId: number)
	data.daily.battlesToday += 1

	local key = tostring(opponentUserId)
	data.daily.opponentsToday[key] = (data.daily.opponentsToday[key] or 0) + 1
end

local function onCooldown(userId: number): boolean
	local last = lastBattleAt[userId]
	return last ~= nil and os.clock() - last < BattleConfig.COOLDOWN_SECONDS
end

--[[
	실제 대결. 여기에는 yield 가 없다.
	두 프로필을 동시에 만지므로 중간에 멈추면 한쪽만 반영되는 사고가 난다.
]]
local function runMatch(challenger: Player, opponent: Player): Types.BattleResponse
	local challengerData = DataService.getActiveData(challenger)
	local opponentData = DataService.getActiveData(opponent)

	if challengerData == nil or opponentData == nil then
		return fail("not_ready")
	end

	EconomyService.rolloverDaily(challengerData)
	EconomyService.rolloverDaily(opponentData)

	local challengerAllowed = rewardAllowed(challengerData, opponent.UserId)
	local opponentAllowed = rewardAllowed(opponentData, challenger.UserId)

	local challengerRatingBefore = challengerData.stats.rating
	local opponentRatingBefore = opponentData.stats.rating

	local result = BattleLogic.playMatch({
		challengerLevel = challengerData.weapon.level,
		opponentLevel = opponentData.weapon.level,
		challengerRating = challengerRatingBefore,
		opponentRating = opponentRatingBefore,
		roll = rng:NextNumber(),
		k = BattleConfig.K,
		eloK = BattleConfig.ELO_K,
		baseReward = BattleConfig.BASE_REWARD,
		levelBonusPerLevel = BattleConfig.LEVEL_BONUS_PER_LEVEL,
		upsetCap = BattleConfig.UPSET_MULTIPLIER_CAP,
		loserReward = BattleConfig.LOSER_REWARD,
		challengerAgeMultiplier = ageMultiplier(challenger),
		opponentAgeMultiplier = ageMultiplier(opponent),
		challengerRewardAllowed = challengerAllowed,
		opponentRewardAllowed = opponentAllowed,
	})

	challengerData.stats.rating = result.challengerRating
	opponentData.stats.rating = result.opponentRating

	if result.challengerWon then
		challengerData.stats.battleWins += 1
		opponentData.stats.battleLosses += 1
	else
		challengerData.stats.battleLosses += 1
		opponentData.stats.battleWins += 1
	end

	if result.challengerGold > 0 then
		EconomyService.addGold(challenger, challengerData, result.challengerGold, "battle", true)
	end
	if result.opponentGold > 0 then
		EconomyService.addGold(opponent, opponentData, result.opponentGold, "battle", true)
	end

	if challengerAllowed then
		markRewarded(challengerData, opponent.UserId)
	end
	if opponentAllowed then
		markRewarded(opponentData, challenger.UserId)
	end

	local now = os.clock()
	lastBattleAt[challenger.UserId] = now
	lastBattleAt[opponent.UserId] = now

	-- 여기부터는 데이터 변경이 끝난 뒤의 전달 작업이다.
	DataService.replicate(challenger)
	DataService.replicate(opponent)

	if resolvedRemote then
		resolvedRemote:FireClient(challenger, {
			won = result.challengerWon,
			goldGained = result.challengerGold,
			ratingBefore = challengerRatingBefore,
			ratingAfter = result.challengerRating,
			opponentName = opponent.DisplayName,
			opponentLevel = opponentData.weapon.level,
			myLevel = challengerData.weapon.level,
			winProbability = result.challengerWinProbability,
			rewardCapped = not challengerAllowed,
		} :: Types.BattleResultPayload)

		resolvedRemote:FireClient(opponent, {
			won = not result.challengerWon,
			goldGained = result.opponentGold,
			ratingBefore = opponentRatingBefore,
			ratingAfter = result.opponentRating,
			opponentName = challenger.DisplayName,
			opponentLevel = challengerData.weapon.level,
			myLevel = opponentData.weapon.level,
			winProbability = 1 - result.challengerWinProbability,
			rewardCapped = not opponentAllowed,
		} :: Types.BattleResultPayload)
	end

	AnalyticsService.logFunnel(challenger, "battle_finished", {
		won = result.challengerWon,
		opponentLevel = opponentData.weapon.level,
	})

	return { ok = true }
end

--[[
	도전할 수 있는 상대인지 확인한다.
	반환값은 실패 사유이며, 문제가 없으면 nil 이다.
]]
local function validateTarget(challenger: Player, target: Player): string?
	if target == challenger then
		return "self_challenge"
	end
	if not DataService.isReady(target) then
		return "opponent_not_ready"
	end
	if invitesByTarget[target.UserId] ~= nil then
		return "opponent_busy"
	end
	if onCooldown(target.UserId) then
		return "opponent_cooldown"
	end
	return nil
end

local function handleChallenge(challenger: Player, targetUserId: any): Types.BattleResponse
	-- 클라이언트가 보내는 값은 상대 userId 하나뿐이고, 숫자인지부터 본다.
	if targetUserId ~= nil and type(targetUserId) ~= "number" then
		return fail("invalid_argument")
	end

	if LiveOpsService.isMaintenance() then
		return fail("maintenance")
	end
	if not limiter:consume(challenger.UserId) then
		return fail("too_fast")
	end
	if not DataService.isReady(challenger) then
		return fail("not_ready")
	end
	if onCooldown(challenger.UserId) then
		return fail("battle_cooldown")
	end
	if invitesByChallenger[challenger.UserId] ~= nil then
		return fail("already_challenging")
	end
	if invitesByTarget[challenger.UserId] ~= nil then
		return fail("answer_first")
	end

	local target: Player? = nil

	if targetUserId == nil then
		-- "아무나 매칭": 조건에 맞는 사람 중 무작위
		local candidates: { Player } = {}
		for _, other in Players:GetPlayers() do
			if validateTarget(challenger, other) == nil then
				table.insert(candidates, other)
			end
		end

		if #candidates == 0 then
			return fail("no_opponent")
		end
		target = candidates[rng:NextInteger(1, #candidates)]
	else
		local found = Players:GetPlayerByUserId(targetUserId :: number)
		if found == nil then
			return fail("opponent_left")
		end

		local problem = validateTarget(challenger, found)
		if problem ~= nil then
			return fail(problem)
		end
		target = found
	end

	local resolvedTarget = target :: Player

	local invite: Invite = {
		challengerUserId = challenger.UserId,
		targetUserId = resolvedTarget.UserId,
		expiresAt = os.time() + BattleConfig.INVITE_TIMEOUT_SECONDS,
	}

	invitesByTarget[resolvedTarget.UserId] = invite
	invitesByChallenger[challenger.UserId] = invite

	local challengerData = DataService.getData(challenger)

	if inviteRemote then
		inviteRemote:FireClient(resolvedTarget, {
			challengerUserId = challenger.UserId,
			challengerName = challenger.DisplayName,
			challengerLevel = if challengerData then challengerData.weapon.level else 0,
			expiresAt = invite.expiresAt,
		} :: Types.BattleInvitePayload)
	end

	notify(challenger, "battle.sent", resolvedTarget.DisplayName)

	-- 무응답은 거절로 처리한다.
	task.delay(BattleConfig.INVITE_TIMEOUT_SECONDS, function()
		if invitesByTarget[resolvedTarget.UserId] ~= invite then
			return -- 이미 응답됨
		end

		clearInvite(invite)

		if challenger.Parent == Players then
			notify(challenger, "battle.timeout", resolvedTarget.DisplayName)
		end
		if resolvedTarget.Parent == Players and inviteRemote then
			inviteRemote:FireClient(resolvedTarget, false) -- 팝업 닫기
		end
	end)

	return { ok = true }
end

local function handleRespond(player: Player, accept: any): Types.BattleResponse
	if type(accept) ~= "boolean" then
		return fail("invalid_argument")
	end

	local invite = invitesByTarget[player.UserId]
	if invite == nil then
		return fail("no_invite")
	end

	local challenger = Players:GetPlayerByUserId(invite.challengerUserId)
	clearInvite(invite)

	if challenger == nil or challenger.Parent ~= Players then
		return fail("opponent_left")
	end

	if not accept then
		notify(challenger, "battle.declined", player.DisplayName)
		return { ok = true }
	end

	local ok, response = xpcall(runMatch, debug.traceback, challenger, player)

	if not ok then
		warn(`[BattleService] 배틀 처리 중 오류:\n{response}`)
		return fail("unknown")
	end

	return response
end

-- 같은 서버에서 도전할 수 있는 상대 목록 (공개해도 되는 정보만 담는다)
local function handleGetTargets(player: Player): { Types.BattleTarget }
	local targets: { Types.BattleTarget } = {}

	for _, other in Players:GetPlayers() do
		if validateTarget(player, other) ~= nil then
			continue
		end

		local data = DataService.getData(other)
		if data == nil then
			continue
		end

		table.insert(targets, {
			userId = other.UserId,
			name = other.DisplayName,
			level = data.weapon.level,
			rating = data.stats.rating,
		})
	end

	table.sort(targets, function(a, b)
		return a.rating > b.rating
	end)

	return targets
end

-- 채팅 명령어(/배틀)가 같은 경로를 타도록 공개한다.
function BattleService.requestChallenge(player: Player, targetUserId: number?): Types.BattleResponse
	return handleChallenge(player, targetUserId)
end

-- 닉네임으로 상대를 찾는다(채팅 명령어용). 부분 일치도 허용한다.
function BattleService.findTargetByName(name: string): Player?
	local lowered = string.lower(name)

	for _, player in Players:GetPlayers() do
		if string.lower(player.Name) == lowered or string.lower(player.DisplayName) == lowered then
			return player
		end
	end

	for _, player in Players:GetPlayers() do
		if
			string.find(string.lower(player.Name), lowered, 1, true)
			or string.find(string.lower(player.DisplayName), lowered, 1, true)
		then
			return player
		end
	end

	return nil
end

function BattleService.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)

	local challengeRemote =
		remotesFolder:WaitForChild(Remotes.Functions.ChallengeBattle) :: RemoteFunction
	challengeRemote.OnServerInvoke = handleChallenge

	local respondRemote =
		remotesFolder:WaitForChild(Remotes.Functions.RespondBattle) :: RemoteFunction
	respondRemote.OnServerInvoke = handleRespond

	local targetsRemote =
		remotesFolder:WaitForChild(Remotes.Functions.GetBattleTargets) :: RemoteFunction
	targetsRemote.OnServerInvoke = handleGetTargets

	inviteRemote = remotesFolder:WaitForChild(Remotes.Events.BattleInvite) :: RemoteEvent
	resolvedRemote = remotesFolder:WaitForChild(Remotes.Events.BattleResolved) :: RemoteEvent
	feedRemote = remotesFolder:WaitForChild(Remotes.Events.FeedMessage) :: RemoteEvent
end

function BattleService.Start()
	Players.PlayerRemoving:Connect(function(player)
		limiter:clear(player.UserId)
		lastBattleAt[player.UserId] = nil

		local incoming = invitesByTarget[player.UserId]
		if incoming then
			clearInvite(incoming)
		end

		local outgoing = invitesByChallenger[player.UserId]
		if outgoing then
			clearInvite(outgoing)

			local target = Players:GetPlayerByUserId(outgoing.targetUserId)
			if target and inviteRemote then
				inviteRemote:FireClient(target, false)
			end
		end
	end)

	-- 하루가 바뀌는 순간에 접속 중인 사람도 기록이 초기화되도록 주기적으로 확인한다.
	task.spawn(function()
		while true do
			task.wait(60)
			for player, data in DataService.getAllActive() do
				if EconomyService.rolloverDaily(data) then
					DataService.replicate(player)
				end
			end
		end
	end)
end

return BattleService
