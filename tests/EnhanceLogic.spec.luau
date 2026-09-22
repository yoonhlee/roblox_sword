--!strict
local t = require("./harness")
local EnhanceLogic = require("../src/shared/Pure/EnhanceLogic")
local EnhanceTable = require("../src/shared/Config/EnhanceTable")

local function odds(success: number, keep: number, destroy: number): EnhanceLogic.Odds
	return { success = success, keep = keep, destroy = destroy, cost = 100 }
end

t.describe("EnhanceLogic.roll", function()
	t.it("구간 경계에서 정확히 갈린다", function()
		local o = odds(45, 50, 5)
		t.expectEqual(EnhanceLogic.roll(o, 0), "success")
		t.expectEqual(EnhanceLogic.roll(o, 44.999), "success")
		t.expectEqual(EnhanceLogic.roll(o, 45), "keep")
		t.expectEqual(EnhanceLogic.roll(o, 94.999), "keep")
		t.expectEqual(EnhanceLogic.roll(o, 95), "destroy")
		t.expectEqual(EnhanceLogic.roll(o, 99.999), "destroy")
	end)

	t.it("성공 100%면 어떤 난수든 성공", function()
		local o = odds(100, 0, 0)
		for roll = 0, 99 do
			t.expectEqual(EnhanceLogic.roll(o, roll), "success", `roll={roll}`)
		end
	end)

	t.it("실제 확률표 전 구간에서 세 결과만 나온다", function()
		for level = 0, EnhanceTable.MAX_LEVEL - 1 do
			local o = EnhanceTable.Odds[level]
			for step = 0, 999 do
				local result = EnhanceLogic.roll(o, step / 10)
				t.expect(
					result == "success" or result == "keep" or result == "destroy",
					`레벨 {level} 에서 예상 밖의 결과: {result}`
				)
			end
		end
	end)
end)

t.describe("EnhanceLogic.applyBuff", function()
	t.it("성공에 더한 만큼 유지에서 뺀다", function()
		local buffed = EnhanceLogic.applyBuff(odds(45, 50, 5), 10)
		t.expectEqual(buffed.success, 55)
		t.expectEqual(buffed.keep, 40)
		t.expectEqual(buffed.destroy, 5)
	end)

	t.it("파괴 확률은 절대 건드리지 않는다", function()
		for level = 0, EnhanceTable.MAX_LEVEL - 1 do
			local base = EnhanceTable.Odds[level]
			local buffed = EnhanceLogic.applyBuff(base, 100)
			t.expectEqual(buffed.destroy, base.destroy, `레벨 {level} 파괴 확률`)
		end
	end)

	t.it("유지 확률보다 큰 버프는 유지 확률만큼만 적용된다", function()
		local buffed = EnhanceLogic.applyBuff(odds(95, 5, 0), 30)
		t.expectEqual(buffed.success, 100)
		t.expectEqual(buffed.keep, 0)
		t.expectEqual(buffed.success + buffed.keep + buffed.destroy, 100)
	end)

	t.it("버프를 걸어도 합은 항상 100", function()
		for level = 0, EnhanceTable.MAX_LEVEL - 1 do
			for _, bonus in { 0, 1, 5, 15, 50, 200 } do
				local b = EnhanceLogic.applyBuff(EnhanceTable.Odds[level], bonus)
				t.expectEqual(b.success + b.keep + b.destroy, 100, `레벨 {level}, 버프 {bonus}`)
			end
		end
	end)

	t.it("음수 버프는 무시한다", function()
		local buffed = EnhanceLogic.applyBuff(odds(45, 50, 5), -10)
		t.expectEqual(buffed.success, 45)
		t.expectEqual(buffed.keep, 50)
	end)
end)

t.describe("EnhanceLogic.shardsFor", function()
	t.it("floor(레벨 ^ 1.5)", function()
		t.expectEqual(EnhanceLogic.shardsFor(0, 1.5), 0)
		t.expectEqual(EnhanceLogic.shardsFor(1, 1.5), 1)
		t.expectEqual(EnhanceLogic.shardsFor(4, 1.5), 8)
		t.expectEqual(EnhanceLogic.shardsFor(10, 1.5), 31)
		t.expectEqual(EnhanceLogic.shardsFor(19, 1.5), 82)
	end)
end)

t.describe("EnhanceLogic.resolve", function()
	local function params(overrides: { [string]: any }): EnhanceLogic.ResolveParams
		local base = {
			level = 12,
			maxLevel = EnhanceTable.MAX_LEVEL,
			odds = odds(35, 55, 10),
			roll = 0,
			useProtect = false,
			protectTickets = 0,
			shardExponent = 1.5,
		}
		for key, value in overrides do
			base[key] = value
		end
		return base :: any
	end

	t.it("성공하면 레벨이 1 오른다", function()
		local result = EnhanceLogic.resolve(params({ roll = 0 }))
		t.expectEqual(result.outcome, "success")
		t.expectEqual(result.newLevel, 13)
		t.expectEqual(result.ticketsUsed, 0)
	end)

	t.it("유지면 레벨이 그대로다", function()
		local result = EnhanceLogic.resolve(params({ roll = 50 }))
		t.expectEqual(result.outcome, "keep")
		t.expectEqual(result.newLevel, 12)
	end)

	t.it("파괴면 레벨 0 으로 떨어지고 파편을 준다", function()
		local result = EnhanceLogic.resolve(params({ roll = 95 }))
		t.expectEqual(result.outcome, "destroy")
		t.expectEqual(result.newLevel, 0)
		t.expectEqual(result.shardsGained, EnhanceLogic.shardsFor(12, 1.5))
		t.expectEqual(result.ticketsUsed, 0)
	end)

	t.it("방지권이 있으면 파괴가 유지로 바뀌고 1개 소모된다", function()
		local result = EnhanceLogic.resolve(params({ roll = 95, useProtect = true, protectTickets = 2 }))
		t.expectEqual(result.outcome, "protected")
		t.expectEqual(result.newLevel, 12)
		t.expectEqual(result.ticketsUsed, 1)
		t.expectEqual(result.shardsGained, 0)
	end)

	t.it("방지권이 0개면 사용 설정이 켜져 있어도 파괴된다", function()
		local result = EnhanceLogic.resolve(params({ roll = 95, useProtect = true, protectTickets = 0 }))
		t.expectEqual(result.outcome, "destroy")
		t.expectEqual(result.newLevel, 0)
		t.expectEqual(result.ticketsUsed, 0)
	end)

	t.it("파괴 확률 0인 구간에서는 방지권이 소모되지 않는다", function()
		for level = 0, 9 do
			local o = EnhanceTable.Odds[level]
			for step = 0, 999 do
				local result = EnhanceLogic.resolve(params({
					level = level,
					odds = o,
					roll = step / 10,
					useProtect = true,
					protectTickets = 5,
				}))
				t.expectEqual(result.ticketsUsed, 0, `레벨 {level}, roll={step / 10}`)
				t.expect(result.outcome ~= "destroy", `레벨 {level} 에서 파괴가 발생했습니다`)
			end
		end
	end)

	t.it("최대 레벨을 넘지 않는다", function()
		local result = EnhanceLogic.resolve(params({ level = 19, odds = odds(5, 70, 25), roll = 0 }))
		t.expectEqual(result.newLevel, EnhanceTable.MAX_LEVEL)
	end)
end)

t.describe("강화 분포(고정 시드 시뮬레이션)", function()
	-- 테스트를 결정적으로 만들기 위한 xorshift32 생성기.
	-- 게임 코드에서는 쓰지 않는다(서버는 Roblox 의 Random.new() 를 쓴다).
	-- 단순 선형 합동 생성기(LCG)는 균일성이 나빠 이 검사에 쓸 수 없었다.
	local function makeRng(seed: number): () -> number
		local state = seed
		return function(): number
			state = bit32.bxor(state, bit32.lshift(state, 13))
			state = bit32.bxor(state, bit32.rshift(state, 17))
			state = bit32.bxor(state, bit32.lshift(state, 5))
			return (state / 4294967296) * 100
		end
	end

	t.it("레벨 10 의 실제 결과 비율이 확률표와 맞는다", function()
		local nextRoll = makeRng(20260921)
		local o = EnhanceTable.Odds[10] -- 45 / 50 / 5
		local counts = { success = 0, keep = 0, destroy = 0 }
		local trials = 200000

		for _ = 1, trials do
			local outcome = EnhanceLogic.roll(o, nextRoll())
			counts[outcome] += 1
		end

		t.expectNear(counts.success / trials * 100, o.success, 0.5, "성공 비율")
		t.expectNear(counts.keep / trials * 100, o.keep, 0.5, "유지 비율")
		t.expectNear(counts.destroy / trials * 100, o.destroy, 0.5, "파괴 비율")
	end)

	t.it("방지권을 넉넉히 들고 있으면 파괴가 한 번도 없다", function()
		local nextRoll = makeRng(7777)
		local destroyed = 0

		for _ = 1, 50000 do
			local result = EnhanceLogic.resolve({
				level = 19,
				maxLevel = EnhanceTable.MAX_LEVEL,
				odds = EnhanceTable.Odds[19],
				roll = nextRoll(),
				useProtect = true,
				protectTickets = 999,
				shardExponent = EnhanceTable.SHARD_EXPONENT,
			})
			if result.outcome == "destroy" then
				destroyed += 1
			end
		end

		t.expectEqual(destroyed, 0)
	end)
end)
