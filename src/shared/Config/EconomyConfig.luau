--!strict
--[[
	EconomyConfig — 골드 획득처 수치.
	수치 변경은 개발자 승인을 받은 뒤에만.

	[주의] 시작 골드, 출석, 플레이 시간 보상은 프로토타입 때 임의로 넣은 값이다.
	승인된 값이 아니며 새 경제(통합 기획서 6절)에 맞춰 다시 정해야 한다.
]]

local EconomyConfig = {}

EconomyConfig.STARTING_GOLD = 100
EconomyConfig.STARTING_SHARDS = 0
EconomyConfig.STARTING_PROTECT_TICKETS = 0

-- 출석: 연속 일수에 따른 골드. 상한을 넘으면 마지막 값을 계속 지급한다.
EconomyConfig.DAILY_LOGIN_GOLD = { 100, 150, 200, 300, 400, 600, 1000 }

-- 플레이 시간 보상
EconomyConfig.PLAYTIME_REWARD_INTERVAL_SECONDS = 15 * 60
EconomyConfig.PLAYTIME_REWARD_GOLD = 120

-- 이상 탐지: 이 시간 안에 이만큼 이상 골드가 늘면 로그를 남긴다.
EconomyConfig.ANOMALY_WINDOW_SECONDS = 60
EconomyConfig.ANOMALY_GOLD_DELTA = 200000

return EconomyConfig
