--!strict
local t = require("./harness")
local SwordLogic = require("../src/shared/Pure/SwordLogic")
local EnhanceLogic = require("../src/shared/Pure/EnhanceLogic")
local EnhanceTable = require("../src/shared/Config/EnhanceTable")
local Weapons = require("../src/shared/Config/Weapons")

local function sumPercents(drawTable: SwordLogic.DrawTable): (number, number)
	-- 소수 오차를 피하려고 0.01% 칸 단위 정수로 더한다.
	local entries, rarities = 0, 0
	for _, entry in drawTable.entries do
		entries += math.floor(entry.percent * 100 + 0.5)
	end
	for _, share in drawTable.rarities do
		rarities += math.floor(share.percent * 100 + 0.5)
	end
	return entries, rarities
end

-- 기획서의 기본 20종 구성(일반 8 · 희귀 6 · 영웅 4 · 전설 2)을 흉내 낸 가짜 목록
local function fullRoster(): ({ string }, { [string]: string })
	local order: { string } = {}
	local rarityOf: { [string]: string } = {}
	for _, group in { { "common", 8 }, { "rare", 6 }, { "epic", 4 }, { "legend", 2 } } do
		for index = 1, group[2] :: number do
			local id = `{group[1]}{index}`
			table.insert(order, id)
			rarityOf[id] = group[1] :: string
		end
	end
	return order, rarityOf
end

t.describe("소지 상한 가격", function()
	t.it("검이 1개일 때 491,535,000 골드다 (150 × 15강 강화 비용)", function()
		local base = EnhanceLogic.cost(
			Weapons.SLOT_PRICE_LEVEL,
			1,
			EnhanceTable.COST_BASE,
			EnhanceTable.SWORD_COUNT_EXPONENT
		)
		t.expectEqual(SwordLogic.slotPrice(base, Weapons.SLOT_PRICE_MULTIPLIER), 491535000)
	end)

	t.it("검이 많을수록 비싸진다", function()
		local previous = 0
		for swordCount = 1, 19 do
			local base = EnhanceLogic.cost(
				Weapons.SLOT_PRICE_LEVEL,
				swordCount,
				EnhanceTable.COST_BASE,
				EnhanceTable.SWORD_COUNT_EXPONENT
			)
			local price = SwordLogic.slotPrice(base, Weapons.SLOT_PRICE_MULTIPLIER)
			t.expect(price > previous, `검 {swordCount}개일 때 가격`)
			t.expectEqual(price, math.floor(price))
			previous = price
		end
	end)
end)

t.describe("뽑기 확률표", function()
	t.it("기본 20종에서 첫 뽑기 등급 확률이 약 64 / 28 / 7 / 1 % 다", function()
		local order, rarityOf = fullRoster()
		local drawTable = SwordLogic.buildDrawTable(
			order,
			rarityOf,
			Weapons.DRAW_WEIGHTS,
			{ common1 = true } -- 기본 검은 이미 가지고 있다
		)

		t.expectEqual(#drawTable.entries, 19)
		t.expectEqual(drawTable.totalWeight, 109)

		local byRarity: { [string]: number } = {}
		for _, share in drawTable.rarities do
			byRarity[share.rarity] = share.percent
		end
		t.expectNear(byRarity.common, 64.2, 0.1)
		t.expectNear(byRarity.rare, 27.5, 0.1)
		t.expectNear(byRarity.epic, 7.3, 0.1)
		t.expectNear(byRarity.legend, 0.9, 0.1)
	end)

	t.it(
		"가진 검이 몇 개든 검별 합계와 등급별 합계가 정확히 100% 다",
		function()
			local order, rarityOf = fullRoster()
			local owned: { [string]: boolean } = {}

			for _, id in order do
				owned[id] = true
				local drawTable =
					SwordLogic.buildDrawTable(order, rarityOf, Weapons.DRAW_WEIGHTS, owned)

				if #drawTable.entries > 0 then
					local entries, rarities = sumPercents(drawTable)
					t.expectEqual(
						entries,
						10000,
						`검 {#drawTable.entries}개 남았을 때 검별 합`
					)
					t.expectEqual(
						rarities,
						10000,
						`검 {#drawTable.entries}개 남았을 때 등급별 합`
					)
				end
			end
		end
	)

	t.it("이미 가진 검은 표에 없고 뽑히지도 않는다", function()
		local owned = { ironBlade = true, tideFang = true }
		local drawTable = SwordLogic.buildDrawTable(
			Weapons.Order,
			Weapons.rarityMap(),
			Weapons.DRAW_WEIGHTS,
			owned
		)

		for _, entry in drawTable.entries do
			t.expect(owned[entry.id] == nil, `가진 검이 표에 있습니다: {entry.id}`)
		end

		for step = 0, 999 do
			local id = SwordLogic.pick(drawTable, step / 1000)
			t.expect(
				id ~= nil and owned[id :: string] == nil,
				`가진 검이 뽑혔습니다: {tostring(id)}`
			)
		end
	end)

	t.it("지금 있는 5종에서도 합계가 100% 다", function()
		local drawTable = SwordLogic.buildDrawTable(
			Weapons.Order,
			Weapons.rarityMap(),
			Weapons.DRAW_WEIGHTS,
			{ ironBlade = true }
		)
		local entries, rarities = sumPercents(drawTable)
		t.expectEqual(#drawTable.entries, 4)
		t.expectEqual(entries, 10000)
		t.expectEqual(rarities, 10000)
	end)

	t.it("마지막 남은 검은 100% 다", function()
		local order, rarityOf = fullRoster()
		local owned: { [string]: boolean } = {}
		for _, id in order do
			owned[id] = true
		end
		owned.legend2 = nil

		local drawTable = SwordLogic.buildDrawTable(order, rarityOf, Weapons.DRAW_WEIGHTS, owned)
		t.expectEqual(#drawTable.entries, 1)
		t.expectEqual(drawTable.entries[1].percent, 100)
		t.expectEqual(SwordLogic.pick(drawTable, 0.999), "legend2")
	end)

	t.it("전부 가졌으면 뽑을 것이 없다", function()
		local order, rarityOf = fullRoster()
		local owned: { [string]: boolean } = {}
		for _, id in order do
			owned[id] = true
		end

		local drawTable = SwordLogic.buildDrawTable(order, rarityOf, Weapons.DRAW_WEIGHTS, owned)
		t.expectEqual(#drawTable.entries, 0)
		t.expectNil(SwordLogic.pick(drawTable, 0.5))
	end)

	t.it("난수 구간이 가중치 비율대로 나뉜다", function()
		local drawTable = SwordLogic.buildDrawTable(
			{ "a", "b", "c" },
			{ a = "common", b = "rare", c = "epic" },
			{ common = 10, rare = 5, epic = 5 },
			{}
		)
		t.expectEqual(SwordLogic.pick(drawTable, 0), "a")
		t.expectEqual(SwordLogic.pick(drawTable, 0.4999), "a")
		t.expectEqual(SwordLogic.pick(drawTable, 0.5), "b")
		t.expectEqual(SwordLogic.pick(drawTable, 0.7499), "b")
		t.expectEqual(SwordLogic.pick(drawTable, 0.75), "c")
		t.expectEqual(SwordLogic.pick(drawTable, 0.9999), "c")
		t.expectEqual(drawTable.entries[1].percent, 50)
		t.expectEqual(drawTable.entries[2].percent, 25)
	end)
end)

t.describe("SwordLogic.exactPercents", function()
	t.it("반올림으로 합이 어긋나는 경우에도 정확히 100 이 된다", function()
		local percents = SwordLogic.exactPercents({ 1, 1, 1 }, 2)
		local total = 0
		for _, value in percents do
			total += math.floor(value * 100 + 0.5)
		end
		t.expectEqual(total, 10000)
		t.expectEqual(percents[1], 33.34)
		t.expectEqual(percents[2], 33.33)
	end)
end)
