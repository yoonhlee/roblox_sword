--!strict
--[[
	추격 생존 경주 수치가 통합 기획서 4절의 표·공식과 맞는지 고정해 둔다.
]]

local t = require("./harness")
local RaceConfig = require("../src/shared/Config/RaceConfig")
local EnhanceTable = require("../src/shared/Config/EnhanceTable")
local EnhanceLogic = require("../src/shared/Pure/EnhanceLogic")
local RaceLogic = require("../src/shared/Pure/RaceLogic")

local CURVE: RaceLogic.Curve = {
	minTime = RaceConfig.MIN_TIME_SECONDS,
	maxTime = RaceConfig.MAX_TIME_SECONDS,
	maxLevel = EnhanceTable.MAX_LEVEL,
	accel = RaceConfig.CHASER_ACCEL,
	headStart = RaceConfig.HEAD_START,
	baseSpeed = RaceConfig.BASE_SPEED,
}

local COURSE = RaceConfig.Course

local function costAt(level: number): number
	return EnhanceLogic.cost(level, 1, EnhanceTable.COST_BASE, EnhanceTable.SWORD_COUNT_EXPONENT)
end

local function multiplier(level: number): number
	local odds = EnhanceTable.Odds[level]
	return RaceLogic.rewardMultiplier(
		level,
		if odds then odds.success else 0,
		RaceConfig.Multiplier
	)
end

local function round2(value: number): number
	return math.floor(value * 100 + 0.5) / 100
end

-- 테스트용 난수: 씨앗이 같으면 같은 순서를 낸다.
local function seeded(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

t.describe("RaceLogic 시간·거리·속도", function()
	t.it(
		"기준 시간: 0~1강 20초, 20강 90초, 그 사이는 일정하게 늘어난다",
		function()
			t.expectNear(RaceLogic.baseTime(0, CURVE), 20)
			t.expectNear(RaceLogic.baseTime(1, CURVE), 20)
			t.expectNear(RaceLogic.baseTime(20, CURVE), 90)

			local step = 70 / 19
			for level = 2, 20 do
				t.expectNear(
					RaceLogic.baseTime(level, CURVE) - RaceLogic.baseTime(level - 1, CURVE),
					step,
					1e-9,
					`레벨 {level} 증가폭`
				)
			end
		end
	)

	t.it("추격자는 출발선보다 30칸 뒤에서 출발한다", function()
		t.expectNear(RaceLogic.chaserFront(0, CURVE), -30)
		t.expectNear(RaceLogic.chaserTravel(0, CURVE), 0)
	end)

	t.it("추격자 처음 속도 c0 가 기획서 공식과 같다", function()
		local expected = (16 * 20 + 30) * 0.02 / (math.exp(20 * 0.02) - 1)
		t.expectNear(RaceLogic.chaserStartSpeed(CURVE), expected)
		t.expectNear(RaceLogic.chaserSpeed(0, CURVE), expected)
	end)

	t.it("추격자는 갈수록 빨라진다 (초당 약 2%)", function()
		local before = RaceLogic.chaserSpeed(10, CURVE)
		local after = RaceLogic.chaserSpeed(11, CURVE)
		t.expectNear(after / before, math.exp(0.02), 1e-9)
	end)

	t.it("최대 거리: 1강 320칸, 10강 약 1,320칸, 20강 약 3,560칸", function()
		t.expectNear(RaceLogic.maxDistance(1, CURVE), 320, 1e-6)
		t.expectNear(RaceLogic.maxDistance(0, CURVE), 320, 1e-6)
		t.expectNear(RaceLogic.maxDistance(10, CURVE), 1320, 15)
		t.expectNear(RaceLogic.maxDistance(20, CURVE), 3560, 15)
	end)

	t.it("이동 속도: 0~1강 16, 20강 약 40, 레벨이 오르면 빨라진다", function()
		t.expectNear(RaceLogic.runSpeed(0, CURVE), 16, 1e-9)
		t.expectNear(RaceLogic.runSpeed(1, CURVE), 16, 1e-9)
		t.expectNear(RaceLogic.runSpeed(20, CURVE), 40, 1)

		for level = 2, 20 do
			t.expect(
				RaceLogic.runSpeed(level, CURVE) > RaceLogic.runSpeed(level - 1, CURVE),
				`레벨 {level} 속도가 {level - 1} 보다 빠르지 않음`
			)
		end
	end)

	t.it("자기 속도로 쉬지 않고 달리면 정확히 기준 시간에 잡힌다", function()
		for _, level in { 0, 1, 5, 10, 15, 20 } do
			local speed = RaceLogic.runSpeed(level, CURVE)
			local limit = RaceLogic.baseTime(level, CURVE)
			local caughtAt: number? = nil

			local elapsed = 0
			while elapsed < limit + 5 do
				elapsed += 0.01
				if RaceLogic.chaserFront(elapsed, CURVE) >= speed * elapsed then
					caughtAt = elapsed
					break
				end
			end

			t.expect(caughtAt ~= nil, `레벨 {level} 이 잡히지 않음`)
			t.expectNear(caughtAt :: number, limit, 0.02, `레벨 {level} 잡힌 시간`)
		end
	end)
end)

t.describe("RaceLogic 보상", function()
	t.it("1구간 배율이 기획서 표와 같다 (소수 둘째 자리)", function()
		local expected = { 2.00, 2.11, 2.21, 2.39, 2.56, 2.85, 3.20, 3.66, 4.22, 5.00 }
		for level = 0, 9 do
			t.expectNear(round2(multiplier(level)), expected[level + 1], 1e-9, `레벨 {level}`)
		end
	end)

	t.it("2구간 배율이 기획서 표와 같다 (소수 둘째 자리)", function()
		local expected = { 5.00, 5.36, 5.74, 6.16, 6.60, 7.07, 7.58, 8.12, 8.71, 9.33, 10.00 }
		for level = 10, 20 do
			t.expectNear(round2(multiplier(level)), expected[level - 9], 1e-9, `레벨 {level}`)
		end
	end)

	t.it("9강과 10강의 배율이 이어진다 (둘 다 5)", function()
		t.expectNear(multiplier(9), 5)
		t.expectNear(multiplier(10), 5)
	end)

	t.it("최대 보상이 기획서 표와 같다", function()
		-- 표는 만·억 단위로 반올림한 값이라 0.5% 안에서 맞는지 본다.
		local expected: { [number]: number } = {
			[10] = 510000,
			[11] = 1100000,
			[12] = 2350000,
			[13] = 5040000,
			[14] = 10810000,
			[15] = 23170000,
			[16] = 49670000,
			[17] = 106000000,
			[18] = 228000000,
			[19] = 489000000,
			[20] = 1050000000,
		}
		for level, value in expected do
			local distance = RaceLogic.maxDistance(level, CURVE)
			local reward = RaceLogic.reward(costAt(level), multiplier(level), distance, distance)
			t.expect(
				math.abs(reward - value) / value < 0.005,
				`레벨 {level} 최대 보상 {reward} (표 {value})`
			)
		end
	end)

	t.it("20강은 강화가 없어도 100 × (1 + 2^20) 을 기준 비용으로 쓴다", function()
		t.expectEqual(costAt(20), 100 * (1 + 2 ^ 20))
		local distance = RaceLogic.maxDistance(20, CURVE)
		t.expectEqual(RaceLogic.reward(costAt(20), multiplier(20), distance, distance), 1048577000)
	end)

	t.it("레벨이 하나 오를 때마다 최대 보상이 약 2~2.4배가 된다", function()
		for level = 1, 20 do
			local ratio = (costAt(level) * multiplier(level))
				/ (costAt(level - 1) * multiplier(level - 1))
			t.expect(ratio > 1.5 and ratio < 2.45, `레벨 {level - 1}→{level} 배수 {ratio}`)
		end
	end)

	t.it(
		"보상은 달린 비율에 비례하고 최대 거리를 넘어도 더 받지 않는다",
		function()
			t.expectEqual(RaceLogic.reward(1000, 2, 50, 100), 1000)
			t.expectEqual(RaceLogic.reward(1000, 2, 100, 100), 2000)
			t.expectEqual(RaceLogic.reward(1000, 2, 250, 100), 2000)
		end
	)

	t.it("가만히 있으면 0 이다", function()
		t.expectEqual(RaceLogic.reward(1000, 2, 0, 100), 0)
		t.expectEqual(RaceLogic.reward(1000, 2, -5, 100), 0)
		t.expectEqual(RaceLogic.creditedDistance(0.4, RaceConfig.DEAD_ZONE), 0)
		t.expectEqual(RaceLogic.creditedDistance(-3, RaceConfig.DEAD_ZONE), 0)
		t.expectEqual(RaceLogic.creditedDistance(25, RaceConfig.DEAD_ZONE), 25)
	end)

	t.it("보상은 0 이상의 정수다", function()
		local reward = RaceLogic.reward(costAt(7), multiplier(7), 123.456, 800)
		t.expectEqual(reward, math.floor(reward))
		t.expect(reward >= 0, "음수 보상")
	end)
end)

t.describe("RaceLogic 서버 거리 검증", function()
	local TOLERANCE = RaceConfig.SPEED_TOLERANCE
	local SLACK = RaceConfig.DISTANCE_SLACK

	t.it("정상 속도로 달린 위치는 그대로 인정한다", function()
		local position = RaceLogic.effectivePosition(16 * 10, 10, 16, TOLERANCE, SLACK)
		t.expectEqual(position, 160)
	end)

	t.it("허용 속도보다 빨리 간 만큼은 인정하지 않는다", function()
		-- 속도 16 인데 10초에 1,000칸 앞에 있다(속도 조작)
		local position = RaceLogic.effectivePosition(1000, 10, 16, TOLERANCE, SLACK)
		t.expectNear(position, 16 * 10 * TOLERANCE + SLACK)
	end)

	t.it("속도를 조작해도 정상 유저보다 오래 버티지 못한다", function()
		local level = 5
		local speed = RaceLogic.runSpeed(level, CURVE)
		local limit = RaceLogic.baseTime(level, CURVE)
		local caughtAt: number? = nil

		local elapsed = 0
		while elapsed < limit * 2 do
			elapsed += 0.01
			-- 캐릭터는 한없이 앞에 있다고 주장한다.
			local position = RaceLogic.effectivePosition(1e9, elapsed, speed, TOLERANCE, SLACK)
			if RaceLogic.chaserFront(elapsed, CURVE) >= position then
				caughtAt = elapsed
				break
			end
		end

		t.expect(caughtAt ~= nil, "속도 조작 유저가 잡히지 않음")
		-- 검증 여유(10% + 6칸)만큼만 더 버틴다.
		t.expect((caughtAt :: number) < limit * 1.25, `너무 오래 버팀: {caughtAt}`)
	end)

	t.it("뒤로 간 위치는 그대로 본다 (추격자에게 잡히는 판정용)", function()
		t.expectEqual(RaceLogic.effectivePosition(-12, 5, 16, TOLERANCE, SLACK), -12)
	end)

	t.it("숫자가 아닌 위치는 가장 뒤로 본다", function()
		local position = RaceLogic.effectivePosition(0 / 0, 5, 16, TOLERANCE, SLACK)
		t.expect(position < -1e9, "NaN 이 걸러지지 않음")
		t.expectEqual(RaceLogic.creditedDistance(0 / 0, 1), 0)
	end)
end)

t.describe("RaceLogic 매칭", function()
	local WINDOW = RaceConfig.MATCH_WINDOW_SECONDS
	local LINEUP = RaceConfig.LINEUP_SECONDS
	local FULL = RaceConfig.MATCH_FULL_COUNT

	t.it("매칭을 누르면 10초 안에 출발한다", function()
		t.expectEqual(WINDOW, 10)
		t.expect(LINEUP < WINDOW, "카운트다운이 매칭 시간보다 길다")
		-- 대기열이 닫히는 시각 + 카운트다운 = 매칭 시간
		t.expect(not RaceLogic.shouldDepart(1, WINDOW - LINEUP - 0.01, WINDOW, LINEUP, FULL))
		t.expect(RaceLogic.shouldDepart(1, WINDOW - LINEUP, WINDOW, LINEUP, FULL))
	end)

	t.it("혼자여도 출발한다", function()
		t.expect(RaceLogic.shouldDepart(1, WINDOW, WINDOW, LINEUP, FULL))
	end)

	t.it("20명이 차면 기다리지 않는다", function()
		t.expectEqual(FULL, 20)
		t.expect(RaceLogic.shouldDepart(FULL, 0, WINDOW, LINEUP, FULL))
		t.expect(not RaceLogic.shouldDepart(FULL - 1, 0, WINDOW, LINEUP, FULL))
	end)

	t.it("대기열이 비어 있으면 출발하지 않는다", function()
		t.expect(not RaceLogic.shouldDepart(0, 999, WINDOW, LINEUP, FULL))
	end)

	t.it("남은 시간은 0 아래로 내려가지 않는다", function()
		t.expectEqual(RaceLogic.secondsUntilStart(3, WINDOW), 7)
		t.expectEqual(RaceLogic.secondsUntilStart(30, WINDOW), 0)
	end)

	t.it("출발 자리는 모두 트랙 안이고 가운데 정렬이다", function()
		for count = 1, FULL do
			local offsets =
				RaceLogic.lineupOffsets(count, COURSE.lineupWidth, COURSE.lineupMaxSpacing)
			t.expectEqual(#offsets, count)

			local sum = 0
			for _, offset in offsets do
				sum += offset
				t.expect(
					math.abs(offset) <= COURSE.lineupWidth / 2 + 1e-9,
					`{count}명일 때 자리가 트랙 밖: {offset}`
				)
			end
			t.expectNear(sum, 0, 1e-6, `{count}명 가운데 정렬`)
		end
		t.expectEqual(#RaceLogic.lineupOffsets(0, 40, 4), 0)
	end)
end)

t.describe("RaceLogic 코스", function()
	t.it("20강이 끼면 코스가 4,000칸 이상이다", function()
		local length = RaceLogic.courseLength(RaceLogic.maxDistance(20, CURVE), COURSE)
		t.expect(length >= 4000, `코스 길이 {length}`)
	end)

	t.it("코스는 언제나 그 판의 최대 거리보다 길다", function()
		for level = 0, 20 do
			local distance = RaceLogic.maxDistance(level, CURVE)
			local length = RaceLogic.courseLength(distance, COURSE)
			t.expect(
				length > distance * 1.2,
				`레벨 {level}: 코스 {length}, 최대 거리 {distance}`
			)
		end
	end)

	t.it(
		"장애물은 출발 직후와 코스 끝을 비워 두고, 앞에서부터 순서대로 놓인다",
		function()
			local length = 2000
			local obstacles = RaceLogic.generateObstacles(length, COURSE, seeded(7))
			t.expect(#obstacles > 10, "장애물이 너무 적다")

			local previous = 0
			for _, obstacle in obstacles do
				t.expect(
					obstacle.z >= COURSE.firstObstacleAt,
					`출발선에 너무 가깝다: {obstacle.z}`
				)
				t.expect(
					obstacle.z < length - COURSE.endMargin,
					`코스 끝에 너무 가깝다: {obstacle.z}`
				)
				t.expect(
					obstacle.z - previous >= COURSE.minSpacing - 1e-9,
					"장애물 간격이 좁다"
				)
				previous = obstacle.z
			end
		end
	)

	t.it("어느 줄이든 지나갈 길이 있고 트랙 밖으로 나가지 않는다", function()
		local half = COURSE.trackWidth / 2

		for seed = 1, 25 do
			for _, obstacle in RaceLogic.generateObstacles(4600, COURSE, seeded(seed)) do
				local left = obstacle.x - obstacle.width / 2
				local right = obstacle.x + obstacle.width / 2
				t.expect(left >= -half - 1e-9 and right <= half + 1e-9, "트랙 밖으로 나감")

				if obstacle.kind == "block" then
					-- 기둥 양옆 중 넓은 쪽이 캐릭터가 지나갈 만큼 넓어야 한다.
					local widest = math.max(left + half, half - right)
					t.expect(widest >= 10, `기둥 옆 길이 좁다: {widest}`)
				elseif obstacle.kind == "gate" then
					t.expectEqual(obstacle.width, COURSE.gateGap)
					t.expect(obstacle.width >= 10, "문 틈이 좁다")
				else
					t.expectEqual(obstacle.kind, "hurdle")
					t.expectEqual(obstacle.width, COURSE.trackWidth)
				end
			end
		end
	end)

	t.it("세 종류가 모두 나온다", function()
		local seen: { [string]: boolean } = {}
		for _, obstacle in RaceLogic.generateObstacles(4600, COURSE, seeded(3)) do
			seen[obstacle.kind] = true
		end
		t.expect(seen.block and seen.hurdle and seen.gate, "빠진 장애물 종류가 있다")
	end)

	t.it("난수가 같으면 같은 코스, 다르면 다른 코스다", function()
		local a = RaceLogic.generateObstacles(1500, COURSE, seeded(11))
		local b = RaceLogic.generateObstacles(1500, COURSE, seeded(11))
		local c = RaceLogic.generateObstacles(1500, COURSE, seeded(12))

		t.expectEqual(#a, #b)
		for index, obstacle in a do
			t.expectEqual(obstacle.kind, b[index].kind)
			t.expectEqual(obstacle.z, b[index].z)
			t.expectEqual(obstacle.x, b[index].x)
		end

		local different = #a ~= #c
		for index, obstacle in a do
			local other = c[index]
			if other == nil or other.z ~= obstacle.z or other.x ~= obstacle.x then
				different = true
			end
		end
		t.expect(different, "씨앗이 달라도 코스가 같다")
	end)
end)
