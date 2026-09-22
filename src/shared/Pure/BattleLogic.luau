--!strict
--[[
	BattleLogic — 배틀 승률·보상·레이팅 계산의 순수 함수.

	원칙은 EnhanceLogic 과 같다. Roblox API 도, 전역 상태도, 다른 모듈 require 도 없다.
	난수는 서버가 뽑아서 숫자로 넘겨준다.

	배틀로 무기가 파괴되거나 레벨이 내려가는 일은 없다. 걸리는 건 골드와 레이팅뿐.
]]

local BattleLogic = {}

export type RewardParams = {
	baseReward: number,
	opponentLevel: number,
	levelBonusPerLevel: number,
	winProbability: number,
	upsetCap: number,
	accountAgeMultiplier: number, -- 부계정 파밍 방지용 배수 (보통 1, 신규 계정 0.5)
}

-- 0 으로 나누는 것을 막기 위한 하한
local MIN_PROBABILITY = 1e-6

--[[
	레벨 차이로 승률을 구한다.
	P(A 승) = 1 / (1 + 10 ^ ((LvB - LvA) / K))

	같은 레벨이면 50%, K=4 기준 4레벨 차이면 상위 쪽이 약 91%.
]]
function BattleLogic.winProbability(levelA: number, levelB: number, k: number): number
	local exponent = (levelB - levelA) / k
	return 1 / (1 + 10 ^ exponent)
end

-- roll 은 [0, 1). true 면 A 의 승리.
function BattleLogic.resolve(roll: number, winProbability: number): boolean
	return roll < winProbability
end

--[[
	역전 배율. 이길 확률이 낮았을수록 커지고, upsetCap 에서 멈춘다.
	확률이 100% 에 가까우면 1 에 수렴한다(배율 하한도 1).
]]
function BattleLogic.upsetMultiplier(winProbability: number, upsetCap: number): number
	local probability = math.max(winProbability, MIN_PROBABILITY)
	return math.clamp(1 / probability, 1, upsetCap)
end

-- 승자 보상: 기본 보상 × (1 + 레벨 보너스) × 역전 배율 × 계정 배수
function BattleLogic.winnerReward(params: RewardParams): number
	local levelBonus = 1 + params.levelBonusPerLevel * params.opponentLevel
	local upset = BattleLogic.upsetMultiplier(params.winProbability, params.upsetCap)

	local reward = params.baseReward * levelBonus * upset * params.accountAgeMultiplier
	return math.max(0, math.floor(reward))
end

function BattleLogic.loserReward(baseLoserReward: number, accountAgeMultiplier: number): number
	return math.max(0, math.floor(baseLoserReward * accountAgeMultiplier))
end

--[[
	Elo 기대 승률. 레이팅 기준의 표준 공식(400점 차이 = 10배)이다.
	승패 자체는 레벨 기반 winProbability 로 정해지고, 레이팅은 그 결과를 누적한다.
]]
function BattleLogic.expectedScore(ratingA: number, ratingB: number): number
	return 1 / (1 + 10 ^ ((ratingB - ratingA) / 400))
end

-- score: 이겼으면 1, 졌으면 0
function BattleLogic.updateRating(
	rating: number,
	expected: number,
	score: number,
	kFactor: number
): number
	local updated = rating + kFactor * (score - expected)
	return math.max(0, math.floor(updated + 0.5))
end

--[[
	한 판의 결과를 한 번에 계산한다.
	challenger 가 도전자, opponent 가 상대. roll 은 [0, 1).
]]
export type MatchParams = {
	challengerLevel: number,
	opponentLevel: number,
	challengerRating: number,
	opponentRating: number,
	roll: number,
	k: number,
	eloK: number,
	baseReward: number,
	levelBonusPerLevel: number,
	upsetCap: number,
	loserReward: number,
	challengerAgeMultiplier: number,
	opponentAgeMultiplier: number,
	challengerRewardAllowed: boolean, -- 일일 보상 한도를 넘지 않았는지
	opponentRewardAllowed: boolean,
}

export type MatchResult = {
	challengerWon: boolean,
	challengerWinProbability: number,
	challengerGold: number,
	opponentGold: number,
	challengerRating: number,
	opponentRating: number,
}

function BattleLogic.playMatch(params: MatchParams): MatchResult
	local probability =
		BattleLogic.winProbability(params.challengerLevel, params.opponentLevel, params.k)
	local challengerWon = BattleLogic.resolve(params.roll, probability)

	local challengerExpected =
		BattleLogic.expectedScore(params.challengerRating, params.opponentRating)
	local opponentExpected = 1 - challengerExpected

	local challengerScore = if challengerWon then 1 else 0
	local opponentScore = 1 - challengerScore

	local challengerGold: number
	local opponentGold: number

	if challengerWon then
		challengerGold = BattleLogic.winnerReward({
			baseReward = params.baseReward,
			opponentLevel = params.opponentLevel,
			levelBonusPerLevel = params.levelBonusPerLevel,
			winProbability = probability,
			upsetCap = params.upsetCap,
			accountAgeMultiplier = params.challengerAgeMultiplier,
		})
		opponentGold = BattleLogic.loserReward(params.loserReward, params.opponentAgeMultiplier)
	else
		challengerGold = BattleLogic.loserReward(params.loserReward, params.challengerAgeMultiplier)
		opponentGold = BattleLogic.winnerReward({
			baseReward = params.baseReward,
			opponentLevel = params.challengerLevel,
			levelBonusPerLevel = params.levelBonusPerLevel,
			winProbability = 1 - probability,
			upsetCap = params.upsetCap,
			accountAgeMultiplier = params.opponentAgeMultiplier,
		})
	end

	-- 일일 보상 한도를 넘은 쪽은 배틀은 하되 보상이 0 이다.
	if not params.challengerRewardAllowed then
		challengerGold = 0
	end
	if not params.opponentRewardAllowed then
		opponentGold = 0
	end

	return {
		challengerWon = challengerWon,
		challengerWinProbability = probability,
		challengerGold = challengerGold,
		opponentGold = opponentGold,
		challengerRating = BattleLogic.updateRating(
			params.challengerRating,
			challengerExpected,
			challengerScore,
			params.eloK
		),
		opponentRating = BattleLogic.updateRating(
			params.opponentRating,
			opponentExpected,
			opponentScore,
			params.eloK
		),
	}
end

return BattleLogic
