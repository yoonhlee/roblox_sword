--!strict
--[[
	방지권 상품·뽑기 규칙 (통합 기획서 3-4절, 7절).
	실제 확률은 아직 미정(D12)이라 Config 가 비어 있다. 그래서
	  - 확정된 규칙(확정 1개, 천장 3점, 파편 50개)은 Config 값으로 고정하고
	  - 뽑기 동작은 예시 결과 목록으로 검사한다.
	나중에 Config 에 확률을 채우면 "Config 에 채워진 확률" 묶음의 검사가 자동으로 적용된다.
]]

local t = require("./harness")
local Products = require("../src/shared/Config/Products")
local DrawLogic = require("../src/shared/Pure/DrawLogic")
local SwordLogic = require("../src/shared/Pure/SwordLogic")

local PER_MISS = Products.PITY_PER_MISS
local THRESHOLD = Products.PITY_THRESHOLD
local PITY_TICKETS = Products.PITY_TICKETS

-- 예시 결과 목록 (테스트 전용. 게임에 쓰는 값이 아니다)
local SAMPLE: { DrawLogic.Outcome } = {
	{ tickets = 3, weight = 1 },
	{ tickets = 1, weight = 2 },
	{ tickets = 0, weight = 7 },
}

local function percentSum(outcomes: { DrawLogic.Outcome }): number
	local percents = SwordLogic.exactPercents(DrawLogic.weights(outcomes), 2)
	local units = 0
	for _, percent in percents do
		units += math.floor(percent * 100 + 0.5)
	end
	return units / 100
end

t.describe("Products 설정", function()
	t.it("validate() 가 문제를 찾지 못한다", function()
		t.expectNil(Products.validate())
	end)

	t.it("상품은 확정 1개 / 확정 묶음 / 확률형 세 가지뿐이다", function()
		local count = 0
		for _ in Products.DeveloperProducts do
			count += 1
		end
		t.expectEqual(count, 3)
		t.expectEqual(Products.DeveloperProducts.ticketSingle.kind, "fixed")
		t.expectEqual(Products.DeveloperProducts.ticketBundle.kind, "fixed")
		t.expectEqual(Products.DeveloperProducts.ticketRandom.kind, "random")
	end)

	t.it("확정 1개는 방지권 1개다", function()
		t.expectEqual(Products.DeveloperProducts.ticketSingle.ticketAmount, 1)
	end)

	t.it("유료 확률형은 1종뿐이다", function()
		local randoms = 0
		for _, product in Products.DeveloperProducts do
			if product.kind == "random" then
				randoms += 1
			end
		end
		t.expectEqual(randoms, 1)
	end)

	t.it("천장: 꽝 1점, 3점이면 방지권 1개", function()
		t.expectEqual(PER_MISS, 1)
		t.expectEqual(THRESHOLD, 3)
		t.expectEqual(PITY_TICKETS, 1)
	end)

	t.it("파편 뽑기는 1회에 파편 50개다", function()
		t.expectEqual(Products.SHARD_DRAW.cost, 50)
	end)

	t.it("ID 가 없는 상품은 팔 수 없다", function()
		for key, product in Products.DeveloperProducts do
			if product.productId == 0 then
				t.expect(not Products.isSellable(product), `{key} 가 ID 없이 팔린다`)
			end
		end
	end)

	t.it("ID 가 있어도 내용이 비어 있으면 팔 수 없다", function()
		local emptyBundle: Products.DeveloperProduct = {
			key = "ticketBundle",
			productId = 123,
			kind = "fixed",
			ticketAmount = 0,
			outcomes = {},
		}
		local emptyRandom: Products.DeveloperProduct = {
			key = "ticketRandom",
			productId = 456,
			kind = "random",
			ticketAmount = 0,
			outcomes = {},
		}
		t.expect(not Products.isSellable(emptyBundle), "개수 0 인 묶음이 팔린다")
		t.expect(not Products.isSellable(emptyRandom), "확률이 없는 확률형이 팔린다")
	end)

	t.it("ID 와 내용이 모두 있으면 팔 수 있다", function()
		local single: Products.DeveloperProduct = {
			key = "ticketSingle",
			productId = 123,
			kind = "fixed",
			ticketAmount = 1,
			outcomes = {},
		}
		local random: Products.DeveloperProduct = {
			key = "ticketRandom",
			productId = 456,
			kind = "random",
			ticketAmount = 0,
			outcomes = SAMPLE,
		}
		t.expect(Products.isSellable(single), "확정 1개가 안 팔린다")
		t.expect(Products.isSellable(random), "확률형이 안 팔린다")
	end)

	t.it("잘못된 결과 목록은 준비된 것으로 보지 않는다", function()
		t.expect(not Products.isDrawReady({}), "빈 목록")
		t.expect(not Products.isDrawReady({ { tickets = 1, weight = 0 } }), "비중 0")
		t.expect(not Products.isDrawReady({ { tickets = 1, weight = -2 } }), "음수 비중")
		t.expect(not Products.isDrawReady({ { tickets = -1, weight = 1 } }), "음수 개수")
		t.expect(not Products.isDrawReady({ { tickets = 1.5, weight = 1 } }), "소수 개수")
		t.expect(not Products.isDrawReady({ { tickets = 1, weight = 0 / 0 } }), "NaN 비중")
		t.expect(Products.isDrawReady(SAMPLE), "정상 목록이 거부됨")
	end)
end)

t.describe("Config 에 채워진 확률", function()
	-- 지금은 비어 있어서 아래 검사가 건너뛰어진다. 확률을 채우는 순간부터 적용된다.
	local lists: { [string]: { DrawLogic.Outcome } } = {
		shardDraw = Products.SHARD_DRAW.outcomes,
	}
	for key, product in Products.DeveloperProducts do
		if product.kind == "random" then
			lists[key] = product.outcomes
		end
	end

	t.it(
		"채워진 결과 목록은 모두 올바르고 표시 확률의 합이 정확히 100 이다",
		function()
			for key, outcomes in lists do
				if #outcomes > 0 then
					t.expect(Products.isDrawReady(outcomes), `{key} 결과 목록이 잘못됨`)
					t.expectEqual(percentSum(outcomes), 100, `{key} 표시 확률 합`)
				end
			end
		end
	)

	t.it("유료 확률형에는 방지권이 나오는 결과가 하나 이상 있다", function()
		local outcomes = Products.DeveloperProducts.ticketRandom.outcomes
		if #outcomes > 0 then
			local best = 0
			for _, outcome in outcomes do
				best = math.max(best, outcome.tickets)
			end
			t.expect(best > 0, "전부 꽝이다")
		end
	end)
end)

t.describe("DrawLogic 표시 확률", function()
	t.it("합이 정확히 100 이다", function()
		t.expectEqual(percentSum(SAMPLE), 100)
		t.expectEqual(
			percentSum({
				{ tickets = 5, weight = 1 },
				{ tickets = 2, weight = 1 },
				{ tickets = 0, weight = 1 },
			}),
			100,
			"3등분(33.33…)"
		)
		t.expectEqual(
			percentSum({
				{ tickets = 10, weight = 0.5 },
				{ tickets = 3, weight = 7 },
				{ tickets = 1, weight = 21.3 },
				{ tickets = 0, weight = 71.2 },
			}),
			100,
			"소수 비중"
		)
	end)

	t.it("비중대로 나뉜다", function()
		local percents = SwordLogic.exactPercents(DrawLogic.weights(SAMPLE), 2)
		t.expectEqual(percents[1], 10)
		t.expectEqual(percents[2], 20)
		t.expectEqual(percents[3], 70)
	end)
end)

t.describe("DrawLogic.pick", function()
	t.it("구간은 목록 순서대로 붙어 있다", function()
		t.expectEqual(DrawLogic.pick(SAMPLE, 0), 1)
		t.expectEqual(DrawLogic.pick(SAMPLE, 0.0999), 1)
		t.expectEqual(DrawLogic.pick(SAMPLE, 0.1), 2)
		t.expectEqual(DrawLogic.pick(SAMPLE, 0.2999), 2)
		t.expectEqual(DrawLogic.pick(SAMPLE, 0.3), 3)
		t.expectEqual(DrawLogic.pick(SAMPLE, 0.9999), 3)
	end)

	t.it("범위를 벗어난 난수에도 목록 안의 결과를 준다", function()
		t.expectEqual(DrawLogic.pick(SAMPLE, 1), 3)
		t.expectEqual(DrawLogic.pick(SAMPLE, 5), 3)
		t.expectEqual(DrawLogic.pick(SAMPLE, -1), 1)
	end)

	t.it("빈 목록이면 nil 이다", function()
		t.expectNil(DrawLogic.pick({}, 0.5))
		t.expectNil(DrawLogic.resolveFree({}, 0.5))
		t.expectNil(DrawLogic.resolvePaid({}, 0.5, 0, PER_MISS, THRESHOLD, PITY_TICKETS))
	end)

	t.it("많이 뽑으면 비중에 가까워진다", function()
		local counts = { 0, 0, 0 }
		local total = 20000
		for step = 0, total - 1 do
			local index = DrawLogic.pick(SAMPLE, (step + 0.5) / total)
			if index then
				counts[index] += 1
			end
		end
		t.expectNear(counts[1] / total, 0.1, 0.001)
		t.expectNear(counts[2] / total, 0.2, 0.001)
		t.expectNear(counts[3] / total, 0.7, 0.001)
	end)
end)

t.describe("DrawLogic 파편 뽑기", function()
	t.it("뽑힌 결과의 방지권 수를 그대로 준다", function()
		local win = DrawLogic.resolveFree(SAMPLE, 0.05)
		t.expect(win ~= nil, "결과 없음")
		if win then
			t.expectEqual(win.tickets, 3)
		end

		local miss = DrawLogic.resolveFree(SAMPLE, 0.9)
		t.expect(miss ~= nil, "결과 없음")
		if miss then
			t.expectEqual(miss.tickets, 0)
		end
	end)
end)

t.describe("DrawLogic 확률형 상품과 천장 포인트", function()
	local function paid(roll: number, pity: number): DrawLogic.PaidResult
		local result = DrawLogic.resolvePaid(SAMPLE, roll, pity, PER_MISS, THRESHOLD, PITY_TICKETS)
		assert(result, "결과 없음")
		return result
	end

	t.it("당첨이면 그 개수를 받고 천장 포인트는 그대로다", function()
		local result = paid(0.05, 2)
		t.expectEqual(result.isMiss, false)
		t.expectEqual(result.totalTickets, 3)
		t.expectEqual(result.pityTickets, 0)
		t.expectEqual(result.pityAfter, 2)
	end)

	t.it("꽝이면 천장 포인트가 1 오른다", function()
		local result = paid(0.9, 0)
		t.expectEqual(result.isMiss, true)
		t.expectEqual(result.totalTickets, 0)
		t.expectEqual(result.pityAfter, 1)

		t.expectEqual(paid(0.9, 1).pityAfter, 2)
	end)

	t.it("세 번째 꽝에서 방지권 1개를 받고 포인트가 0 이 된다", function()
		local result = paid(0.9, 2)
		t.expectEqual(result.isMiss, true)
		t.expectEqual(result.pityTickets, 1)
		t.expectEqual(result.totalTickets, 1)
		t.expectEqual(result.pityAfter, 0)
	end)

	t.it("꽝만 계속 나와도 3번마다 방지권 1개를 받는다", function()
		local pity = 0
		local tickets = 0
		for _ = 1, 9 do
			local result = paid(0.99, pity)
			pity = result.pityAfter
			tickets += result.totalTickets
		end
		t.expectEqual(tickets, 3)
		t.expectEqual(pity, 0)
	end)

	t.it("다음 꽝에서 천장이 차는지 알 수 있다", function()
		t.expect(not DrawLogic.isPityNext(0, PER_MISS, THRESHOLD))
		t.expect(not DrawLogic.isPityNext(1, PER_MISS, THRESHOLD))
		t.expect(DrawLogic.isPityNext(2, PER_MISS, THRESHOLD))
	end)

	t.it("저장된 포인트가 이상해도 음수가 되지 않는다", function()
		local result = paid(0.9, -5)
		t.expectEqual(result.pityAfter, 1)

		local high = paid(0.9, 10)
		t.expectEqual(high.pityAfter, 0)
		t.expectEqual(high.pityTickets, 1)
	end)
end)
