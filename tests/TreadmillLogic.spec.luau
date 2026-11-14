--!strict
local t = require("./harness")
local EconomyConfig = require("../src/shared/Config/EconomyConfig")
local World = require("../src/shared/Config/World")
local TreadmillLogic = require("../src/shared/Pure/TreadmillLogic")

t.describe("트레드밀 설정", function()
	t.it("1단계는 20초당 100골드다", function()
		local tier = EconomyConfig.treadmillTier("tier1")
		t.expect(tier ~= nil, "tier1 이 없다")
		if tier then
			t.expectEqual(tier.intervalSeconds, 20)
			t.expectEqual(tier.gold, 100)
		end
	end)

	t.it("단계 id 가 겹치지 않고 수입이 양수다", function()
		local seen: { [string]: boolean } = {}
		for _, tier in EconomyConfig.TREADMILL_TIERS do
			t.expect(not seen[tier.id], `겹치는 단계 id: {tier.id}`)
			seen[tier.id] = true
			t.expect(tier.intervalSeconds > 0 and tier.gold > 0, `잘못된 단계: {tier.id}`)
		end
	end)

	t.it("모든 발판이 정의된 단계를 쓰고 로비 안에 있다", function()
		t.expect(#World.TREADMILL_PADS > 0, "발판이 없다")
		for _, pad in World.TREADMILL_PADS do
			t.expect(
				EconomyConfig.treadmillTier(pad.tierId) ~= nil,
				`모르는 단계: {pad.tierId}`
			)
			t.expect(
				math.abs(pad.x) + World.TREADMILL_PAD.sizeX / 2 <= World.LOBBY.sizeX / 2,
				"발판이 로비 밖(X)"
			)
			t.expect(
				math.abs(pad.z) + World.TREADMILL_PAD.sizeZ / 2 <= World.LOBBY.sizeZ / 2,
				"발판이 로비 밖(Z)"
			)
		end
	end)

	t.it("없는 단계는 nil 이다", function()
		t.expectNil(EconomyConfig.treadmillTier("없는단계"))
	end)
end)

t.describe("TreadmillLogic.advance", function()
	t.it("20초를 채우면 한 번 지급한다", function()
		local progress = 0
		local total = 0
		for _ = 1, 20 do
			local rest, payouts = TreadmillLogic.advance(progress, 1, 20)
			progress = rest
			total += payouts
		end
		t.expectEqual(total, 1)
		t.expectNear(progress, 0, 1e-6)
	end)

	t.it("19초까지는 지급하지 않는다", function()
		local rest, payouts = TreadmillLogic.advance(0, 19, 20)
		t.expectEqual(payouts, 0)
		t.expectEqual(rest, 19)
	end)

	t.it("한 번에 여러 번 채우면 그만큼 지급하고 나머지는 남긴다", function()
		local rest, payouts = TreadmillLogic.advance(5, 50, 20)
		t.expectEqual(payouts, 2)
		t.expectNear(rest, 15, 1e-6)
	end)

	t.it("1시간이면 180번 = 18,000골드다", function()
		local progress = 0
		local total = 0
		for _ = 1, 3600 do
			local rest, payouts = TreadmillLogic.advance(progress, 1, 20)
			progress = rest
			total += payouts
		end
		t.expectEqual(total, 180)
		t.expectEqual(total * 100, 18000)
	end)

	t.it("잘못된 값에도 음수나 오류가 나지 않는다", function()
		local rest, payouts = TreadmillLogic.advance(-3, -1, 20)
		t.expectEqual(rest, 0)
		t.expectEqual(payouts, 0)

		local rest2, payouts2 = TreadmillLogic.advance(10, 5, 0)
		t.expectEqual(rest2, 0)
		t.expectEqual(payouts2, 0)
	end)
end)

t.describe("TreadmillLogic.isOnPad", function()
	local pad: TreadmillLogic.Pad = {
		x = -44,
		z = 12,
		sizeX = 12,
		sizeZ = 18,
		topY = 0.6,
		reach = 12,
	}

	t.it("발판 위에 서 있으면 참", function()
		t.expect(TreadmillLogic.isOnPad(-44, 3.6, 12, pad))
		t.expect(TreadmillLogic.isOnPad(-49, 3.6, 20, pad))
	end)

	t.it("발판 옆이면 거짓", function()
		t.expect(not TreadmillLogic.isOnPad(-30, 3.6, 12, pad))
		t.expect(not TreadmillLogic.isOnPad(-44, 3.6, 40, pad))
	end)

	t.it("너무 높이 떠 있거나 바닥 아래면 거짓", function()
		t.expect(not TreadmillLogic.isOnPad(-44, 50, 12, pad))
		t.expect(not TreadmillLogic.isOnPad(-44, -5, 12, pad))
	end)
end)
