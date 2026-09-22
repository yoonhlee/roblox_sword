--!strict
--[[
	BattleConfig — 배틀 승률/보상/레이팅/어뷰징 방지 수치.
	배틀로 무기가 파괴되거나 레벨이 내려가는 일은 없다. 걸리는 건 골드와 레이팅뿐.
]]

local BattleConfig = {}

-- 승률 공식: P(A승) = 1 / (1 + 10 ^ ((LvB - LvA) / K))
BattleConfig.K = 4

-- 보상
BattleConfig.BASE_REWARD = 30
BattleConfig.LEVEL_BONUS_PER_LEVEL = 0.1 -- 상대 레벨 1당 +10%
BattleConfig.UPSET_MULTIPLIER_CAP = 3 -- 역전 배율(1 / P(승))의 상한
BattleConfig.LOSER_REWARD = 5 -- 패자 참가 보상

-- 레이팅 (Elo)
BattleConfig.START_RATING = 1000
BattleConfig.ELO_K = 24

-- 어뷰징 방지
BattleConfig.DAILY_BATTLE_REWARD_CAP = 30 -- 하루 보상 지급 횟수 상한(초과 시 배틀은 가능, 보상 0)
BattleConfig.PER_OPPONENT_DAILY_CAP = 3 -- 같은 상대와 하루 보상 최대 횟수
BattleConfig.COOLDOWN_SECONDS = 10 -- 배틀 쿨다운
BattleConfig.INVITE_TIMEOUT_SECONDS = 15 -- 무응답은 거절로 처리
BattleConfig.NEW_ACCOUNT_AGE_DAYS = 3 -- Player.AccountAge 기준
BattleConfig.NEW_ACCOUNT_REWARD_MULTIPLIER = 0.5 -- 부계정 파밍 방지

return BattleConfig
