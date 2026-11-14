--!strict
local t = require("./harness")
local EnhanceTable = require("../src/shared/Config/EnhanceTable")
local EnhanceLogic = require("../src/shared/Pure/EnhanceLogic")

local function round(value: number): number
	return math.floor(value + 0.5)
end

local function cost(level: number, swordCount: number): number
	return EnhanceLogic.cost(
		level,
		swordCount,
		EnhanceTable.COST_BASE,
		EnhanceTable.SWORD_COUNT_EXPONENT
	)
end

t.describe("EnhanceTable 확률표", function()
	t.it("validate() 가 문제를 찾지 못한다", function()
		t.expectNil(EnhanceTable.validate())
	end)

	t.it("모든 행의 성공+유지+실패 합이 100 이다", function()
		for level = 0, EnhanceTable.MAX_LEVEL - 1 do
			local odds = EnhanceTable.Odds[level]
			t.expectEqual(odds.success + odds.keep + odds.fail, 100, `레벨 {level} 확률 합`)
		end
	end)

	t.it("최대 레벨에는 강화 확률이 없다", function()
		t.expectNil(EnhanceTable.Odds[EnhanceTable.MAX_LEVEL])
	end)

	t.it("1구간(0~9강) 성공 확률이 기획서 공식과 표 그대로다", function()
		local expected = { 100, 97, 94, 89, 84, 76, 66, 53, 37, 15 } -- 0강부터
		for level = 0, 9 do
			local formula = round(100 - 85 * (1.3 ^ level - 1) / (1.3 ^ 9 - 1))
			t.expectEqual(
				EnhanceTable.Odds[level].success,
				expected[level + 1],
				`레벨 {level} 성공(표)`
			)
			t.expectEqual(
				EnhanceTable.Odds[level].success,
				formula,
				`레벨 {level} 성공(공식)`
			)
			t.expectEqual(EnhanceTable.Odds[level].fail, 0, `레벨 {level} 실패`)
		end
	end)

	t.it("2구간(10~19강) 확률이 기획서 공식과 표 그대로다", function()
		local success = { 66, 53, 43, 35, 27, 21, 16, 11, 6, 2 } -- 10강부터
		local fail = { 5, 7, 8, 10, 12, 13, 15, 17, 18, 20 }
		for level = 10, 19 do
			local k = level - 10
			local formula = round(66 - 64 * math.log(1 + 0.3 * k) / math.log(1 + 0.3 * 9))
			t.expectEqual(
				EnhanceTable.Odds[level].success,
				success[k + 1],
				`레벨 {level} 성공(표)`
			)
			t.expectEqual(
				EnhanceTable.Odds[level].success,
				formula,
				`레벨 {level} 성공(공식)`
			)
			t.expectEqual(EnhanceTable.Odds[level].fail, fail[k + 1], `레벨 {level} 실패`)
		end
	end)

	t.it("실패하면 돌아가는 레벨은 10강이다", function()
		t.expectEqual(EnhanceTable.SAFE_LEVEL, 10)
	end)
end)

t.describe("강화 비용 100 × (1 + 2^L) × n^1.1", function()
	t.it("검이 1개일 때 기획서 표와 같다", function()
		t.expectEqual(cost(0, 1), 200)
		t.expectEqual(cost(1, 1), 300)
		t.expectEqual(cost(4, 1), 1700)
		t.expectEqual(cost(9, 1), 51300)
		t.expectEqual(cost(14, 1), 1638500)
		t.expectEqual(cost(19, 1), 52428900)
	end)

	t.it("레벨이 오를수록 비싸진다", function()
		for level = 1, EnhanceTable.MAX_LEVEL do
			t.expect(cost(level, 1) > cost(level - 1, 1), `레벨 {level} 비용`)
		end
	end)

	t.it("검이 많을수록 할증이 붙는다 (2개 약 2.14배, 10개 약 12.6배)", function()
		t.expectNear(cost(10, 2) / cost(10, 1), 2 ^ 1.1, 0.001)
		t.expectNear(cost(10, 10) / cost(10, 1), 10 ^ 1.1, 0.001)
		t.expectNear(cost(10, 2) / cost(10, 1), 2.14, 0.01)
		t.expectNear(cost(10, 10) / cost(10, 1), 12.59, 0.01)
	end)

	t.it("비용은 항상 정수 골드다", function()
		for level = 0, EnhanceTable.MAX_LEVEL do
			for swordCount = 1, 20 do
				local value = cost(level, swordCount)
				t.expectEqual(value, math.floor(value), `레벨 {level}, 검 {swordCount}개`)
			end
		end
	end)

	t.it("검 수가 0 이하로 들어와도 1개로 계산한다", function()
		t.expectEqual(cost(3, 0), cost(3, 1))
	end)
end)
