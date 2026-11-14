--!strict
--[[
	RaceLogic — 추격 생존 경주의 순수 함수 (통합 기획서 4절).

	Roblox API 와 require 가 없다. 수치는 전부 인자로 받는다(Config/RaceConfig).
	서버(RaceService)가 실제 판정에 쓰고, 클라이언트는 같은 함수로 "최대 거리·최대 보상"을 보여 준다.

	기호 (기획서와 같다):
	  T(L)    그 레벨이 방해 없이 쉬지 않고 달렸을 때 잡히는 시간
	  C(t)    추격자가 t 초 동안 움직인 거리 = c0 / k × (e^(k·t) − 1)
	  H       출발할 때 추격자가 뒤처진 거리
	  Dmax(L) = C(T(L)) − H   그 레벨의 최대 거리
	  v(L)    = Dmax(L) / T(L) 그 레벨의 이동 속도
	위치는 전부 "출발선에서 앞쪽으로 몇 칸"이다. 추격자는 −H 에서 출발한다.
]]

local RaceLogic = {}

export type Curve = {
	minTime: number, -- T(0) = T(1)
	maxTime: number, -- T(maxLevel)
	maxLevel: number,
	accel: number, -- k
	headStart: number, -- H
	baseSpeed: number, -- v(1)
}

export type MultiplierConfig = {
	tier1Base: number,
	tier1Span: number,
	tier1Divisor: number,
	tier2Start: number,
	tier2Base: number,
	tier2Growth: number,
	tier2Span: number,
}

export type CourseConfig = {
	trackWidth: number,
	lengthMargin: number,
	extraLength: number,
	minLength: number,
	firstObstacleAt: number,
	minSpacing: number,
	maxSpacing: number,
	endMargin: number,
	blockMinWidth: number,
	blockMaxWidth: number,
	gateGap: number,
	weightBlock: number,
	weightHurdle: number,
	weightGate: number,
	lineupWidth: number,
	lineupMaxSpacing: number,
}

--[[
	장애물 한 줄.
	  block   폭 width 의 기둥. x 는 기둥의 중심. 옆으로 피한다.
	  hurdle  트랙 전체를 가로지르는 낮은 턱. 뛰어넘는다. (x = 0, width = 트랙 폭)
	  gate    트랙을 막는 벽에 폭 width 의 틈. x 는 틈의 중심.
	x 는 트랙 중심 기준 좌우 위치, z 는 출발선에서 앞쪽 거리.
]]
export type Obstacle = {
	kind: "block" | "hurdle" | "gate",
	z: number,
	x: number,
	width: number,
}

--------------------------------------------------------------------------------
-- 시간 · 거리 · 속도
--------------------------------------------------------------------------------

-- T(L) = minTime + (maxTime − minTime) × (max(L, 1) − 1) / (maxLevel − 1)
function RaceLogic.baseTime(level: number, curve: Curve): number
	if curve.maxLevel <= 1 then
		return curve.minTime
	end

	local effective = math.clamp(level, 1, curve.maxLevel)
	return curve.minTime + (curve.maxTime - curve.minTime) * (effective - 1) / (curve.maxLevel - 1)
end

-- c0: 1강(속도 baseSpeed)이 정확히 minTime 초에 잡히도록 맞춘 추격자의 처음 속도
function RaceLogic.chaserStartSpeed(curve: Curve): number
	local k = curve.accel
	local t1 = curve.minTime
	return (curve.baseSpeed * t1 + curve.headStart) * k / (math.exp(k * t1) - 1)
end

-- C(t): 추격자가 출발 후 elapsed 초 동안 움직인 거리
function RaceLogic.chaserTravel(elapsed: number, curve: Curve): number
	local t = math.max(0, elapsed)
	return RaceLogic.chaserStartSpeed(curve) / curve.accel * (math.exp(curve.accel * t) - 1)
end

-- 추격자의 지금 속도 (화면 표시용)
function RaceLogic.chaserSpeed(elapsed: number, curve: Curve): number
	return RaceLogic.chaserStartSpeed(curve) * math.exp(curve.accel * math.max(0, elapsed))
end

-- 추격자 앞면의 위치 (출발선 기준). 출발 순간 −H.
function RaceLogic.chaserFront(elapsed: number, curve: Curve): number
	return RaceLogic.chaserTravel(elapsed, curve) - curve.headStart
end

-- Dmax(L)
function RaceLogic.maxDistance(level: number, curve: Curve): number
	return RaceLogic.chaserTravel(RaceLogic.baseTime(level, curve), curve) - curve.headStart
end

-- v(L). 모든 검의 기본 능력치는 같으므로 착용 검 레벨로만 정해진다.
function RaceLogic.runSpeed(level: number, curve: Curve): number
	return RaceLogic.maxDistance(level, curve) / RaceLogic.baseTime(level, curve)
end

--------------------------------------------------------------------------------
-- 보상
--------------------------------------------------------------------------------

--[[
	보상 배율 m(L).
	successPercent 는 그 레벨의 "표에 적힌" 강화 성공 확률이다(이벤트 버프를 넣지 않은 값).
	2구간에서는 쓰지 않으므로 아무 값이나 넘겨도 된다.
]]
function RaceLogic.rewardMultiplier(
	level: number,
	successPercent: number,
	config: MultiplierConfig
): number
	if level >= config.tier2Start then
		return config.tier2Base
			* config.tier2Growth ^ ((level - config.tier2Start) / config.tier2Span)
	end
	return config.tier1Base + config.tier1Span * (100 - successPercent) / config.tier1Divisor
end

--[[
	보상 = 그 레벨의 강화 비용(검 1개 기준) × 배율 × min(1, 거리 / 최대 거리). 정수 골드로 반올림.
	costAtLevel 에는 검 수 할증을 넣지 않은 값을 넘긴다(기획서 4-3: 보상에는 할증이 없다).
	거리가 0 이면 보상도 0 이다.
]]
function RaceLogic.reward(
	costAtLevel: number,
	multiplier: number,
	distance: number,
	maxDistance: number
): number
	if maxDistance <= 0 or distance <= 0 or distance ~= distance then
		return 0
	end

	local ratio = math.min(1, distance / maxDistance)
	return math.floor(costAtLevel * multiplier * ratio + 0.5)
end

--------------------------------------------------------------------------------
-- 서버 거리 검증
--------------------------------------------------------------------------------

--[[
	서버가 인정하는 위치.
	observed 는 서버가 본 캐릭터의 위치(출발선 기준)다. 캐릭터 이동은 플레이어 기기가 계산하므로
	속도를 조작하면 이 값이 터무니없이 커질 수 있다. 그래서
	    허용 최대 속도 × 지난 시간 × tolerance + slack
	보다 앞은 인정하지 않는다. 뒤로 가는 것은 그대로 인정한다(추격자에게 잡히는 판정에 쓴다).
	값이 숫자가 아니면(NaN) 가장 뒤에 있는 것으로 본다.
]]
function RaceLogic.effectivePosition(
	observed: number,
	elapsed: number,
	allowedSpeed: number,
	tolerance: number,
	slack: number
): number
	if observed ~= observed then
		return -math.huge
	end

	local cap = math.max(0, elapsed) * math.max(0, allowedSpeed) * tolerance + slack
	return math.min(observed, cap)
end

-- 보상에 쓰는 거리. deadZone 미만은 0 (가만히 서 있으면 0 이어야 한다).
function RaceLogic.creditedDistance(bestPosition: number, deadZone: number): number
	if bestPosition ~= bestPosition or bestPosition < deadZone then
		return 0
	end
	return bestPosition
end

--------------------------------------------------------------------------------
-- 매칭
--------------------------------------------------------------------------------

--[[
	대기열을 닫고 출발선에 세울 때인지.
	  - 대기 인원이 fullCount 이상이면 바로
	  - 아니면 첫 사람이 누른 뒤 (window − lineup) 초가 지났을 때
	    (출발선 카운트다운 lineup 초까지 더해 "누른 뒤 window 초 안에 출발"이 된다)
]]
function RaceLogic.shouldDepart(
	queueCount: number,
	waited: number,
	window: number,
	lineup: number,
	fullCount: number
): boolean
	if queueCount <= 0 then
		return false
	end
	if queueCount >= fullCount then
		return true
	end
	return waited >= window - lineup
end

-- 출발 신호까지 남은 시간(초). 화면 표시용.
function RaceLogic.secondsUntilStart(waited: number, window: number): number
	return math.max(0, window - waited)
end

--[[
	출발선에 설 자리(트랙 중심 기준 좌우 위치). 모두 같은 줄(출발선 위)에 선다.
	간격은 maxSpacing 을 넘지 않고, 사람이 많으면 usableWidth 안에 들어가도록 좁힌다.
]]
function RaceLogic.lineupOffsets(count: number, usableWidth: number, maxSpacing: number): { number }
	local offsets: { number } = {}
	if count <= 0 then
		return offsets
	end
	if count == 1 then
		return { 0 }
	end

	local spacing = math.min(maxSpacing, usableWidth / (count - 1))
	local first = -spacing * (count - 1) / 2

	for index = 1, count do
		offsets[index] = first + spacing * (index - 1)
	end
	return offsets
end

--------------------------------------------------------------------------------
-- 코스
--------------------------------------------------------------------------------

-- 그 판에서 가장 멀리 갈 수 있는 사람의 최대 거리로 코스 길이를 정한다.
function RaceLogic.courseLength(topMaxDistance: number, config: CourseConfig): number
	local wanted = math.ceil(topMaxDistance * config.lengthMargin + config.extraLength)
	return math.max(config.minLength, wanted)
end

--[[
	장애물 줄을 만든다. nextNumber 는 [0, 1) 난수를 주는 함수(서버가 Random 으로 만들어 넘긴다).
	같은 난수 순서를 넣으면 같은 코스가 나온다 → 테스트할 수 있다.
	z 오름차순으로 돌려준다.
]]
function RaceLogic.generateObstacles(
	length: number,
	config: CourseConfig,
	nextNumber: () -> number
): { Obstacle }
	local obstacles: { Obstacle } = {}
	local half = config.trackWidth / 2
	local limit = length - config.endMargin
	local totalWeight = config.weightBlock + config.weightHurdle + config.weightGate

	local function unit(): number
		return math.clamp(nextNumber(), 0, 0.999999)
	end

	local z = config.firstObstacleAt

	while z < limit do
		local pick = unit() * totalWeight

		if totalWeight <= 0 or pick < config.weightBlock then
			local width = config.blockMinWidth
				+ (config.blockMaxWidth - config.blockMinWidth) * unit()
			local range = half - width / 2 -- 중심이 움직일 수 있는 범위
			table.insert(obstacles, {
				kind = "block" :: "block",
				z = z,
				x = (unit() * 2 - 1) * range,
				width = width,
			})
		elseif pick < config.weightBlock + config.weightHurdle then
			table.insert(obstacles, {
				kind = "hurdle" :: "hurdle",
				z = z,
				x = 0,
				width = config.trackWidth,
			})
		else
			local range = half - config.gateGap / 2
			table.insert(obstacles, {
				kind = "gate" :: "gate",
				z = z,
				x = (unit() * 2 - 1) * range,
				width = config.gateGap,
			})
		end

		z += config.minSpacing + (config.maxSpacing - config.minSpacing) * unit()
	end

	return obstacles
end

return RaceLogic
