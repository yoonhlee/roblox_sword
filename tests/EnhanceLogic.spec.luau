--!strict
local t = require("./harness")
local EnhanceLogic = require("../src/shared/Pure/EnhanceLogic")
local EnhanceTable = require("../src/shared/Config/EnhanceTable")

local function odds(success: number, keep: number, fail: number): EnhanceLogic.Odds
	return { success = success, keep = keep, fail = fail }
end

t.describe("EnhanceLogic.roll", function()
	t.it("구간 경계에서 정확히 갈린다", function()
		local o = odds(66, 29, 5)
		t.expectEqual(EnhanceLogic.roll(o, 0), "success")
		t.expectEqual(EnhanceLogic.roll(o, 65.999), "success")
		t.expectEqual(EnhanceLogic.roll(o, 66), "keep")
		t.expectEqual(EnhanceLogic.roll(o, 94.999), "keep")
		t.expectEqual(EnhanceLogic.roll(o, 95), "fail")
		t.expectEqual(EnhanceLogic.roll(o, 99.999), "fail")
	end)

	t.it("성공 100%면 어떤 난수든 성공", function()
		local o = odds(100, 0, 0)
		for roll = 0, 99 do
			t.expectEqual(EnhanceLogic.roll(o, roll), "success", `roll={roll}`)
		end
	end)

	t.it("1구간(0~9강)에서는 어떤 난수로도 실패가 나오지 않는다", function()
		for level = 0, 9 do
			for step = 0, 999 do
				local result = EnhanceLogic.roll(EnhanceTable.Odds[level], step / 10)
				t.expect(
					result ~= "fail",
					`레벨 {level} 에서 실패가 나왔습니다 (roll={step / 10})`
				)
			end
		end
	end)
end)

t.describe("EnhanceLogic.applyBuff (확률 버프 이벤트)", function()
	t.it("성공에 더한 만큼 유지에서 뺀다", function()
		local buffed = EnhanceLogic.applyBuff(odds(66, 29, 5), 10)
		t.expectEqual(buffed.success, 76)
		t.expectEqual(buffed.keep, 19)
		t.expectEqual(buffed.fail, 5)
	end)

	t.it("실패 확률은 절대 건드리지 않는다", function()
		for level = 0, EnhanceTable.MAX_LEVEL - 1 do
			local base = EnhanceTable.Odds[level]
			local buffed = EnhanceLogic.applyBuff(base, 100)
			t.expectEqual(buffed.fail, base.fail, `레벨 {level} 실패 확률`)
		end
	end)

	t.it("유지 확률보다 큰 버프는 유지 확률만큼만 적용된다", function()
		local buffed = EnhanceLogic.applyBuff(odds(97, 3, 0), 30)
		t.expectEqual(buffed.success, 100)
		t.expectEqual(buffed.keep, 0)
	end)

	t.it("음수 버프는 무시한다", function()
		local buffed = EnhanceLogic.applyBuff(odds(66, 29, 5), -10)
		t.expectEqual(buffed.success, 66)
		t.expectEqual(buffed.keep, 29)
	end)
end)

t.describe("EnhanceLogic.applyProtect (방지권을 켰을 때 보여 줄 확률)", function()
	t.it("실패는 0 이 되고 그만큼 유지에 더해진다", function()
		local shown = EnhanceLogic.applyProtect(odds(2, 78, 20))
		t.expectEqual(shown.success, 2)
		t.expectEqual(shown.keep, 98)
		t.expectEqual(shown.fail, 0)
	end)

	t.it("버프와 방지권을 어떻게 겹쳐도 모든 행의 합은 100 이다", function()
		for level = 0, EnhanceTable.MAX_LEVEL - 1 do
			for _, bonus in { 0, 1, 5, 15, 50, 200 } do
				local buffed = EnhanceLogic.applyBuff(EnhanceTable.Odds[level], bonus)
				t.expectEqual(
					buffed.success + buffed.keep + buffed.fail,
					100,
					`레벨 {level}, 버프 {bonus}`
				)

				local shown = EnhanceLogic.applyProtect(buffed)
				t.expectEqual(
					shown.success + shown.keep + shown.fail,
					100,
					`레벨 {level}, 버프 {bonus}, 방지권`
				)
				t.expectEqual(shown.fail, 0, `레벨 {level} 방지권 실패 확률`)
				t.expectEqual(
					shown.success,
					buffed.success,
					`레벨 {level} 방지권은 성공을 안 바꾼다`
				)
			end
		end
	end)
end)

t.describe("EnhanceLogic.shardsFor", function()
	t.it("floor(레벨 ^ 1.5)", function()
		t.expectEqual(EnhanceLogic.shardsFor(0, 1.5), 0)
		t.expectEqual(EnhanceLogic.shardsFor(10, 1.5), 31)
		t.expectEqual(EnhanceLogic.shardsFor(19, 1.5), 82)
	end)
end)

t.describe("EnhanceLogic.resolve", function()
	local function params(overrides: { [string]: any }): EnhanceLogic.ResolveParams
		local base = {
			level = 13,
			maxLevel = EnhanceTable.MAX_LEVEL,
			safeLevel = EnhanceTable.SAFE_LEVEL,
			odds = odds(35, 55, 10),
			roll = 0,
			useProtect = false,
			protectTickets = 0,
			shardsOnFail = 46,
		}
		for key, value in overrides do
			base[key] = value
		end
		return base :: any
	end

	t.it("성공하면 레벨이 1 오른다", function()
		local result = EnhanceLogic.resolve(params({ roll = 0 }))
		t.expectEqual(result.outcome, "success")
		t.expectEqual(result.newLevel, 14)
		t.expectEqual(result.ticketsUsed, 0)
		t.expectEqual(result.shardsGained, 0)
	end)

	t.it("유지면 레벨이 그대로다", function()
		local result = EnhanceLogic.resolve(params({ roll = 50 }))
		t.expectEqual(result.outcome, "keep")
		t.expectEqual(result.newLevel, 13)
	end)

	t.it("실패하면 0강이 아니라 10강으로 돌아가고 파편을 받는다", function()
		local result = EnhanceLogic.resolve(params({ roll = 95 }))
		t.expectEqual(result.outcome, "fail")
		t.expectEqual(result.newLevel, 10)
		t.expectEqual(result.shardsGained, 46)
		t.expectEqual(result.ticketsUsed, 0)
	end)

	t.it("10강에서 실패하면 10강 그대로다", function()
		local result =
			EnhanceLogic.resolve(params({ level = 10, odds = odds(66, 29, 5), roll = 99 }))
		t.expectEqual(result.outcome, "fail")
		t.expectEqual(result.newLevel, 10)
	end)

	t.it("방지권이 있으면 실패가 유지로 바뀌고 1개 소모된다", function()
		local result =
			EnhanceLogic.resolve(params({ roll = 95, useProtect = true, protectTickets = 2 }))
		t.expectEqual(result.outcome, "protected")
		t.expectEqual(result.newLevel, 13)
		t.expectEqual(result.ticketsUsed, 1)
		t.expectEqual(result.shardsGained, 0)
	end)

	t.it("방지권이 0개면 사용 설정이 켜져 있어도 실패한다", function()
		local result =
			EnhanceLogic.resolve(params({ roll = 95, useProtect = true, protectTickets = 0 }))
		t.expectEqual(result.outcome, "fail")
		t.expectEqual(result.newLevel, 10)
		t.expectEqual(result.ticketsUsed, 0)
	end)

	t.it("방지권은 실패가 나왔을 때만 소모된다 (전 레벨, 전 난수)", function()
		for level = 0, EnhanceTable.MAX_LEVEL - 1 do
			local o = EnhanceTable.Odds[level]
			for step = 0, 999 do
				local roll = step / 10
				local result = EnhanceLogic.resolve(params({
					level = level,
					odds = o,
					roll = roll,
					useProtect = true,
					protectTickets = 5,
				}))
				local rolledFail = EnhanceLogic.roll(o, roll) == "fail"
				t.expectEqual(
					result.ticketsUsed,
					if rolledFail then 1 else 0,
					`레벨 {level}, roll={roll}`
				)
				t.expect(
					result.outcome ~= "fail",
					`레벨 {level} 에서 방지권이 있는데 실패했습니다`
				)
				if level < EnhanceTable.SAFE_LEVEL then
					t.expectEqual(
						result.ticketsUsed,
						0,
						`1구간 레벨 {level} 에서 방지권 소모`
					)
				end
			end
		end
	end)

	t.it("최대 레벨을 넘지 않는다", function()
		local result =
			EnhanceLogic.resolve(params({ level = 19, odds = odds(2, 78, 20), roll = 0 }))
		t.expectEqual(result.newLevel, EnhanceTable.MAX_LEVEL)
	end)
end)

t.describe("강화 분포(고정 시드 시뮬레이션)", function()
	-- 테스트를 결정적으로 만들기 위한 xorshift32 생성기.
	-- 게임 코드에서는 쓰지 않는다(서버는 Roblox 의 Random.new() 를 쓴다).
	local function makeRng(seed: number): () -> number
		local state = seed
		return function(): number
			state = bit32.bxor(state, bit32.lshift(state, 13))
			state = bit32.bxor(state, bit32.rshift(state, 17))
			state = bit32.bxor(state, bit32.lshift(state, 5))
			return (state / 4294967296) * 100
		end
	end

	t.it("레벨 13 의 실제 결과 비율이 확률표와 맞는다", function()
		local nextRoll = makeRng(20260921)
		local o = EnhanceTable.Odds[13] -- 35 / 55 / 10
		local counts = { success = 0, keep = 0, fail = 0 }
		local trials = 200000

		for _ = 1, trials do
			counts[EnhanceLogic.roll(o, nextRoll())] += 1
		end

		t.expectNear(counts.success / trials * 100, o.success, 0.5, "성공 비율")
		t.expectNear(counts.keep / trials * 100, o.keep, 0.5, "유지 비율")
		t.expectNear(counts.fail / trials * 100, o.fail, 0.5, "실패 비율")
	end)

	t.it(
		"0강에서 20강까지 평균 시도 횟수가 기획서 수치(약 9,400회)와 맞는다",
		function()
			-- 정확 계산: 레벨 L 에서 L+1 에 처음 닿을 때까지의 기대 시도.
			-- 1구간은 1/p. 2구간은 실패하면 10강으로 가므로 E_L = (1 + r × D_L) / p,
			-- D_L = 10강에서 L 강까지 다시 오는 기대 시도.
			local total = 0
			local fromSafe = 0 -- 10강에서 현재 레벨까지의 기대 시도 합

			for level = 0, EnhanceTable.MAX_LEVEL - 1 do
				local o = EnhanceTable.Odds[level]
				local p = o.success / 100
				local r = o.fail / 100
				local step = (1 + r * fromSafe) / p

				total += step
				if level >= EnhanceTable.SAFE_LEVEL then
					fromSafe += step
				end
			end

			t.expectNear(total, 9400, 150, "0강 → 20강 기대 시도 횟수")
		end
	)
end)
