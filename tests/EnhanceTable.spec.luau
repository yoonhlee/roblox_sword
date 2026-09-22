--!strict
local t = require("./harness")
local EnhanceTable = require("../src/shared/Config/EnhanceTable")

t.describe("EnhanceTable", function()
	t.it("validate() 가 문제를 찾지 못한다", function()
		t.expectNil(EnhanceTable.validate())
	end)

	t.it("모든 레벨의 성공+유지+파괴 합이 100 이다", function()
		for level = 0, EnhanceTable.MAX_LEVEL - 1 do
			local odds = EnhanceTable.Odds[level]
			t.expectEqual(
				odds.success + odds.keep + odds.destroy,
				100,
				`레벨 {level} 확률 합`
			)
		end
	end)

	t.it("최대 레벨에는 강화 확률이 없다", function()
		t.expectNil(EnhanceTable.Odds[EnhanceTable.MAX_LEVEL])
	end)

	t.it("강화 비용이 레벨에 따라 단조 증가한다", function()
		for level = 1, EnhanceTable.MAX_LEVEL - 1 do
			t.expect(
				EnhanceTable.Odds[level].cost > EnhanceTable.Odds[level - 1].cost,
				`레벨 {level} 비용이 이전 레벨보다 크지 않습니다`
			)
		end
	end)

	t.it("판매가가 0..MAX_LEVEL 전 구간에 있고 단조 증가한다", function()
		for level = 1, EnhanceTable.MAX_LEVEL do
			t.expect(
				EnhanceTable.SellValue[level] > EnhanceTable.SellValue[level - 1],
				`레벨 {level} 판매가가 이전 레벨보다 크지 않습니다`
			)
		end
	end)

	t.it("파괴 확률은 10강 미만에서 0 이고 이후 증가한다", function()
		for level = 0, 9 do
			t.expectEqual(EnhanceTable.Odds[level].destroy, 0, `레벨 {level} 파괴 확률`)
		end
		t.expect(EnhanceTable.Odds[10].destroy > 0, "레벨 10 파괴 확률이 0 입니다")

		for level = 11, EnhanceTable.MAX_LEVEL - 1 do
			t.expect(
				EnhanceTable.Odds[level].destroy >= EnhanceTable.Odds[level - 1].destroy,
				`레벨 {level} 파괴 확률이 이전 레벨보다 낮습니다`
			)
		end
	end)

	t.it("성공 확률은 레벨이 오를수록 낮아진다", function()
		for level = 1, EnhanceTable.MAX_LEVEL - 1 do
			t.expect(
				EnhanceTable.Odds[level].success <= EnhanceTable.Odds[level - 1].success,
				`레벨 {level} 성공 확률이 이전 레벨보다 높습니다`
			)
		end
	end)
end)
