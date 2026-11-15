--!strict
--[[
	화면 디자인 결정(통합 기획서 8-1절)이 설정값과 맞는지 고정해 둔다.
]]

local t = require("./harness")
local Palette = require("../src/shared/Config/Palette")
local VisualConfig = require("../src/shared/Config/VisualConfig")
local Weapons = require("../src/shared/Config/Weapons")
local EnhanceTable = require("../src/shared/Config/EnhanceTable")
local VisualLogic = require("../src/shared/Pure/VisualLogic")
local Locale = require("../src/shared/Locale")

local function isRgb(value: any): boolean
	if type(value) ~= "table" or #value ~= 3 then
		return false
	end
	for _, channel in value do
		if
			type(channel) ~= "number"
			or channel < 0
			or channel > 255
			or channel ~= math.floor(channel)
		then
			return false
		end
	end
	return true
end

t.describe("Palette", function()
	t.it("모든 색이 0~255 정수 세 개다", function()
		for group, colors in { UI = Palette.UI, WORLD = Palette.WORLD, RARITY = Palette.RARITY } do
			for name, rgb in colors :: any do
				t.expect(isRgb(rgb), `{group}.{name} 색이 잘못됨`)
			end
		end
		for index, tier in Palette.HEAT_TIERS do
			t.expect(isRgb(tier.rgb), `HEAT_TIERS[{index}] 색이 잘못됨`)
		end
	end)

	t.it("모든 검 등급에 색이 있다", function()
		for _, rarity in Weapons.RARITY_ORDER do
			t.expect(Palette.RARITY[rarity] ~= nil, `등급 색 없음: {rarity}`)
		end
	end)

	t.it("강조색은 기획서의 불꽃 주황(226,142,58)이다", function()
		t.expectEqual(table.concat(Palette.UI.ember, ","), "226,142,58")
	end)
end)

t.describe("레벨 색 (쇠를 달구는 색)", function()
	local tiers = Palette.HEAT_TIERS

	t.it("단계는 0강에서 시작하고 올라갈수록 minLevel 이 커진다", function()
		t.expectEqual(tiers[1].minLevel, 0)
		for index = 2, #tiers do
			t.expect(tiers[index].minLevel > tiers[index - 1].minLevel, `단계 {index} 순서`)
			t.expect(tiers[index].glow >= tiers[index - 1].glow, `단계 {index} 빛 번짐`)
		end
	end)

	t.it(
		"기획서 구간: +0~4 회색 / +5~9 붉게 / +10~14 주황 / +15~19 노랗게 / +20 흰 불꽃",
		function()
			local expected = {
				[0] = "heat.cold",
				[4] = "heat.cold",
				[5] = "heat.red",
				[9] = "heat.red",
				[10] = "heat.orange",
				[14] = "heat.orange",
				[15] = "heat.yellow",
				[19] = "heat.yellow",
				[20] = "heat.white",
			}
			for level, key in expected do
				t.expectEqual(VisualLogic.heatTier(level, tiers).nameKey, key, `레벨 {level}`)
			end
		end
	)

	t.it("15강부터 불티가 난다", function()
		t.expect(not VisualLogic.heatTier(14, tiers).sparks)
		t.expect(VisualLogic.heatTier(15, tiers).sparks)
	end)

	t.it("모든 레벨(0~20)에 단계가 있고 단계 이름 문구가 있다", function()
		for level = 0, EnhanceTable.MAX_LEVEL do
			local tier = VisualLogic.heatTier(level, tiers)
			t.expect(tier ~= nil, `레벨 {level} 단계 없음`)
			t.expect(Locale.Strings.ko[tier.nameKey] ~= nil, `문구 없음: {tier.nameKey}`)
		end
	end)

	t.it("레벨 색은 등급 색과 겹치지 않는다", function()
		for _, tier in tiers do
			for rarity, rgb in Palette.RARITY do
				t.expect(
					table.concat(tier.rgb, ",") ~= table.concat(rgb, ","),
					`{tier.nameKey} 와 {rarity} 색이 같다`
				)
			end
		end
	end)
end)

t.describe("강화 연출 길이", function()
	local steps = VisualConfig.Reveal

	t.it("0~9강 0.5초, 10~14강 1초, 15강 이상 2초", function()
		t.expectEqual(VisualLogic.reveal(0, steps).seconds, 0.5)
		t.expectEqual(VisualLogic.reveal(9, steps).seconds, 0.5)
		t.expectEqual(VisualLogic.reveal(10, steps).seconds, 1.0)
		t.expectEqual(VisualLogic.reveal(14, steps).seconds, 1.0)
		t.expectEqual(VisualLogic.reveal(15, steps).seconds, 2.0)
		t.expectEqual(VisualLogic.reveal(19, steps).seconds, 2.0)
	end)

	t.it("15강 이상은 망치질 3번", function()
		t.expectEqual(VisualLogic.reveal(15, steps).strikes, 3)
	end)
end)

t.describe("화면 배율", function()
	local L = VisualConfig.Layout

	t.it("기준 크기에서 1배", function()
		t.expectNear(
			VisualLogic.scaleFor(
				L.referenceWidth,
				L.referenceHeight,
				L.referenceWidth,
				L.referenceHeight,
				L.minScale,
				L.maxScale
			),
			1
		)
	end)

	t.it("범위를 넘지 않는다", function()
		t.expectEqual(
			VisualLogic.scaleFor(
				100,
				100,
				L.referenceWidth,
				L.referenceHeight,
				L.minScale,
				L.maxScale
			),
			L.minScale
		)
		t.expectEqual(
			VisualLogic.scaleFor(
				9999,
				9999,
				L.referenceWidth,
				L.referenceHeight,
				L.minScale,
				L.maxScale
			),
			L.maxScale
		)
	end)

	t.it("가장 작은 글자도 실제 12px 이상", function()
		t.expect(VisualConfig.Text.small * L.minScale >= 12, "작은 글자가 12px 아래")
	end)
end)
