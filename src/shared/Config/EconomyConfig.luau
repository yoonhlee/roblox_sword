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

--[[
	로비 트레드밀 (통합 기획서 6절). 발판 위에 있으면 intervalSeconds 마다 gold 를 받는다.
	[확정] 1단계: 20초당 100골드. 무료만(유료 트레드밀 없음). 자리 비움 제한 없음.
	[미정 D18] 2단계 이상의 단계 수·수입·해금 방법은 아직 정해지지 않았다.
	정해지면 여기에 줄을 추가하고 Config/World 의 TREADMILL_PADS 에 발판 위치를 넣으면 된다.
]]
export type TreadmillTier = {
	id: string,
	intervalSeconds: number,
	gold: number,
}

EconomyConfig.TREADMILL_TIERS = {
	{ id = "tier1", intervalSeconds = 20, gold = 100 },
} :: { TreadmillTier }

function EconomyConfig.treadmillTier(id: string): TreadmillTier?
	for _, tier in EconomyConfig.TREADMILL_TIERS do
		if tier.id == id then
			return tier
		end
	end
	return nil
end

-- 이상 탐지: 이 시간 안에 이만큼 이상 골드가 늘면 로그를 남긴다.
EconomyConfig.ANOMALY_WINDOW_SECONDS = 60
EconomyConfig.ANOMALY_GOLD_DELTA = 200000

--[[
	이상 탐지에서 빼는 획득 사유.
	경주 보상은 서버가 거리와 레벨로 계산한 값이고 한 판에 수억 골드까지 정상적으로 나온다.
	탐지에 넣으면 고레벨 유저마다 경고가 울려서 진짜 이상을 가린다.
]]
EconomyConfig.ANOMALY_EXEMPT_REASONS = {
	race_reward = true,
} :: { [string]: boolean }

return EconomyConfig
