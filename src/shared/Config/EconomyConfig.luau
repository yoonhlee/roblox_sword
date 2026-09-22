--!strict
--[[
	EconomyConfig — 골드 획득처/소비처 수치.
	Phase 4 의 시뮬레이션(tools/simulate_economy.luau)이 이 값을 그대로 읽는다.
	수치 변경은 시뮬레이션 결과를 보고 개발자 승인을 받은 뒤에만.
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

-- 도감 한 칸 달성 보상
EconomyConfig.CODEX_ENTRY_GOLD = 150

-- 파편 → 방지권 교환은 EnhanceTable.SHARDS_PER_TICKET 참조.
-- 골드로 방지권을 직접 사는 가격
EconomyConfig.PROTECT_TICKET_GOLD_PRICE = 2500

-- 무기 외형 변경 비용
EconomyConfig.SKIN_CHANGE_GOLD_PRICE = 500

-- 게임패스 "골드 획득 +20%"
EconomyConfig.GOLD_BOOST_MULTIPLIER = 1.2

-- 이상 탐지: 이 시간 안에 이만큼 이상 골드가 늘면 로그를 남긴다.
EconomyConfig.ANOMALY_WINDOW_SECONDS = 60
EconomyConfig.ANOMALY_GOLD_DELTA = 200000

return EconomyConfig
