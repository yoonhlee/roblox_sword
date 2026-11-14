--!strict
--[[
	RaceConfig — 추격 생존 경주 수치 (통합 기획서 4절).
	계산은 Pure/RaceLogic 이 하고, 여기에는 숫자만 둔다.

	표시:
	  [확정]   승인된 기획. 개발자 승인 없이 바꾸지 않는다.
	  [추천치] Claude 가 채운 초기값. 다른 값이 정해지면 바꾼다.
	  [기술]   기획 수치가 아니라 구현에 필요한 값(검증 여유, 코스 모양 등).
	  [미정]   결정 대기. 값이 없고 넣을 자리만 있다.
]]

local RaceConfig = {}

-- [확정] 방해 없이 쉬지 않고 달렸을 때 잡히는 시간(초). 0~1강 20초 → 20강 90초, 그 사이는 일정하게.
RaceConfig.MIN_TIME_SECONDS = 20
RaceConfig.MAX_TIME_SECONDS = 90

-- [추천치] 추격자 속도 = c0 × e^(CHASER_ACCEL × t). c0 는 아래 두 값에서 계산된다.
RaceConfig.CHASER_ACCEL = 0.02
-- [추천치] 출발할 때 추격자가 출발선보다 이만큼 뒤에 있다(칸).
RaceConfig.HEAD_START = 30
-- [추천치] 0~1강의 이동 속도 (로블록스 기본 걷기 속도)
RaceConfig.BASE_SPEED = 16

--[[
	[확정] 보상 배율 m(L) (통합 기획서 4-3절)
	  1구간 (L < tier2Start): tier1Base + tier1Span × (100 − 그 레벨의 성공 확률) / tier1Divisor
	  2구간 (L ≥ tier2Start): tier2Base × tier2Growth ^ ((L − tier2Start) / tier2Span)
]]
RaceConfig.Multiplier = {
	tier1Base = 2,
	tier1Span = 3,
	tier1Divisor = 85,
	tier2Start = 10,
	tier2Base = 5,
	tier2Growth = 2,
	tier2Span = 10,
}

-- [확정] "매칭"을 누르면 이 시간 안에 출발한다(초).
RaceConfig.MATCH_WINDOW_SECONDS = 10
-- [확정 P43, 추후 조절] 대기열이 이 인원이 되면 기다리지 않고 바로 출발 준비에 들어간다.
RaceConfig.MATCH_FULL_COUNT = 20
-- [기술] 출발선에 세운 뒤 출발 신호까지의 카운트다운(초). MATCH_WINDOW_SECONDS 안에 포함된다.
-- (대기열은 10 − 3 = 7초에 닫히고, 출발선에서 3초를 센 뒤 달린다.)
RaceConfig.LINEUP_SECONDS = 3

--[[
	[기술] 서버 거리 검증 (통합 기획서 4-5절).
	서버는 매 순간 "허용 최대 속도 × 지난 시간 × SPEED_TOLERANCE + DISTANCE_SLACK" 까지만 거리를 인정한다.
	그보다 앞에 있는 캐릭터(속도 조작)는 그 한계 위치에 있는 것으로 보고 추격자에게 잡힌다.
]]
RaceConfig.SPEED_TOLERANCE = 1.1
RaceConfig.DISTANCE_SLACK = 6
-- [기술] 이 거리 미만은 0 으로 본다. 출발선에 가만히 서 있을 때 생기는 미세한 흔들림을 보상하지 않기 위함.
RaceConfig.DEAD_ZONE = 1

-- [기술] 모두 탈락한 뒤 결과를 보여 주는 시간(초). 지나면 남아 있는 사람을 로비로 돌려보낸다.
RaceConfig.RESULT_SECONDS = 8

--[[
	[기술] 코스 모양. 코스는 판마다 새로 만든다(장애물 위치가 매번 다르다).
	길이 = max(minLength, 그 판 최고 레벨의 최대 거리 × lengthMargin + extraLength)
	20강이 끼면 약 4,600칸이 된다(기획서: 20강 기준 4,000칸 이상).

	장애물 세 가지: block(옆으로 피한다) · hurdle(뛰어넘는다) · gate(틈으로 지나간다).
	어느 줄이든 반드시 지나갈 길이 있다.
]]
RaceConfig.Course = {
	trackWidth = 48,
	lengthMargin = 1.25,
	extraLength = 150,
	minLength = 500,

	firstObstacleAt = 60, -- 출발선에서 첫 장애물까지
	minSpacing = 50, -- 장애물 줄 사이 간격(칸)
	maxSpacing = 90,
	endMargin = 40, -- 코스 끝 이만큼 앞부터는 장애물을 두지 않는다

	blockMinWidth = 8,
	blockMaxWidth = 18,
	gateGap = 16,

	-- 장애물 종류가 뽑히는 비중 (합은 아무 값이어도 된다)
	weightBlock = 5,
	weightHurdle = 3,
	weightGate = 2,

	-- 출발선에 서는 자리
	lineupWidth = 40,
	lineupMaxSpacing = 4,
}

--[[
	[미정] 아직 값이 없는 것. 서버(RaceService)에 넣을 자리만 만들어 두었다.
	  D6  1~3위 보너스: 크기, 지급 최소 인원 → RaceService 의 rankBonusFor
	  D16 특수 능력·도감 기념 업그레이드 → RaceService 의 allowedSpeedFor / rewardBonusFor
	  D17 신규 유저 보호 (처음 몇 판 방해 금지) → 방해 능력이 생길 때 함께 만든다
]]

return RaceConfig
