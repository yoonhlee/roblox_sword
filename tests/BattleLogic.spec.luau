--!strict
local t = require("./harness")
local BattleLogic = require("../src/shared/Pure/BattleLogic")
local BattleConfig = require("../src/shared/Config/BattleConfig")

t.describe("BattleLogic.winProbability", function()
	t.it("같은 레벨이면 50%", function()
		t.expectNear(BattleLogic.winProbability(5, 5, BattleConfig.K), 0.5, 1e-9)
	end)

	t.it("4레벨 차이면 상위 쪽이 약 91%", function()
		local p = BattleLogic.winProbability(9, 5, BattleConfig.K)
		t.expectNear(p, 0.909, 0.002)
	end)

	t.it("양쪽 확률의 합은 항상 1", function()
		for levelA = 0, 20 do
			for levelB = 0, 20 do
				local a = BattleLogic.winProbability(levelA, levelB, BattleConfig.K)
				local b = BattleLogic.winProbability(levelB, levelA, BattleConfig.K)
				t.expectNear(a + b, 1, 1e-9, `{levelA} vs {levelB}`)
			end
		end
	end)

	t.it("레벨이 높을수록 승률이 높다", function()
		local previous = -1
		for levelA = 0, 20 do
			local p = BattleLogic.winProbability(levelA, 10, BattleConfig.K)
			t.expect(p > previous, `레벨 {levelA} 에서 승률이 줄었습니다`)
			previous = p
		end
	end)
end)

t.describe("BattleLogic.upsetMultiplier", function()
	t.it("유리한 쪽은 배율이 1 에 가깝다", function()
		local multiplier = BattleLogic.upsetMultiplier(0.95, BattleConfig.UPSET_MULTIPLIER_CAP)
		t.expectNear(multiplier, 1.0526, 0.001)
	end)

	t.it("불리할수록 커지되 상한을 넘지 않는다", function()
		t.expectEqual(
			BattleLogic.upsetMultiplier(0.01, BattleConfig.UPSET_MULTIPLIER_CAP),
			BattleConfig.UPSET_MULTIPLIER_CAP
		)
		t.expectEqual(
			BattleLogic.upsetMultiplier(0, BattleConfig.UPSET_MULTIPLIER_CAP),
			BattleConfig.UPSET_MULTIPLIER_CAP
		)
	end)

	t.it("배율은 1 미만으로 내려가지 않는다", function()
		t.expectEqual(BattleLogic.upsetMultiplier(1, BattleConfig.UPSET_MULTIPLIER_CAP), 1)
	end)
end)

t.describe("BattleLogic.updateRating", function()
	t.it("예상대로 이기면 조금 오른다", function()
		local expected = BattleLogic.expectedScore(1000, 1000)
		local updated = BattleLogic.updateRating(1000, expected, 1, BattleConfig.ELO_K)
		t.expectEqual(updated, 1012)
	end)

	t.it("예상대로 지면 조금 내린다", function()
		local expected = BattleLogic.expectedScore(1000, 1000)
		local updated = BattleLogic.updateRating(1000, expected, 0, BattleConfig.ELO_K)
		t.expectEqual(updated, 988)
	end)

	t.it("레이팅은 음수가 되지 않는다", function()
		local expected = BattleLogic.expectedScore(5, 2000)
		local updated = BattleLogic.updateRating(5, expected, 0, BattleConfig.ELO_K)
		t.expect(updated >= 0, `레이팅이 음수입니다: {updated}`)
	end)

	t.it("두 사람의 레이팅 변화량 합은 0 에 가깝다", function()
		local challengerExpected = BattleLogic.expectedScore(1200, 1000)
		local opponentExpected = 1 - challengerExpected

		local challengerAfter =
			BattleLogic.updateRating(1200, challengerExpected, 1, BattleConfig.ELO_K)
		local opponentAfter = BattleLogic.updateRating(1000, opponentExpected, 0, BattleConfig.ELO_K)

		local delta = (challengerAfter - 1200) + (opponentAfter - 1000)
		t.expect(math.abs(delta) <= 1, `레이팅 총합이 {delta} 만큼 변했습니다`)
	end)
end)

t.describe("BattleLogic.playMatch", function()
	local function match(overrides: { [string]: any }): BattleLogic.MatchParams
		local base = {
			challengerLevel = 10,
			opponentLevel = 10,
			challengerRating = 1000,
			opponentRating = 1000,
			roll = 0,
			k = BattleConfig.K,
			eloK = BattleConfig.ELO_K,
			baseReward = BattleConfig.BASE_REWARD,
			levelBonusPerLevel = BattleConfig.LEVEL_BONUS_PER_LEVEL,
			upsetCap = BattleConfig.UPSET_MULTIPLIER_CAP,
			loserReward = BattleConfig.LOSER_REWARD,
			challengerAgeMultiplier = 1,
			opponentAgeMultiplier = 1,
			challengerRewardAllowed = true,
			opponentRewardAllowed = true,
		}
		for key, value in overrides do
			base[key] = value
		end
		return base :: any
	end

	t.it("낮은 난수면 도전자가 이긴다", function()
		local result = BattleLogic.playMatch(match({ roll = 0 }))
		t.expectEqual(result.challengerWon, true)
		t.expect(result.challengerGold > result.opponentGold, "승자 보상이 더 커야 합니다")
		t.expectEqual(result.opponentGold, BattleConfig.LOSER_REWARD)
	end)

	t.it("높은 난수면 도전자가 진다", function()
		local result = BattleLogic.playMatch(match({ roll = 0.999 }))
		t.expectEqual(result.challengerWon, false)
		t.expectEqual(result.challengerGold, BattleConfig.LOSER_REWARD)
		t.expect(result.opponentGold > result.challengerGold, "승자 보상이 더 커야 합니다")
	end)

	t.it("약자가 강자를 이기면 보상이 더 크다", function()
		local underdog = BattleLogic.playMatch(match({
			challengerLevel = 2,
			opponentLevel = 14,
			roll = 0,
		}))
		local even = BattleLogic.playMatch(match({
			challengerLevel = 14,
			opponentLevel = 14,
			roll = 0,
		}))

		t.expect(
			underdog.challengerGold > even.challengerGold,
			`역전 보상({underdog.challengerGold})이 동급 보상({even.challengerGold})보다 크지 않습니다`
		)
	end)

	t.it("일일 한도를 넘으면 보상이 0 이다", function()
		local result = BattleLogic.playMatch(match({ roll = 0, challengerRewardAllowed = false }))
		t.expectEqual(result.challengerWon, true)
		t.expectEqual(result.challengerGold, 0)
		t.expect(result.challengerRating > 1000, "보상이 없어도 레이팅은 변해야 합니다")
	end)

	t.it("신규 계정은 보상이 절반이다", function()
		local normal = BattleLogic.playMatch(match({ roll = 0 }))
		local fresh = BattleLogic.playMatch(match({
			roll = 0,
			challengerAgeMultiplier = BattleConfig.NEW_ACCOUNT_REWARD_MULTIPLIER,
		}))

		t.expectEqual(fresh.challengerGold, math.floor(normal.challengerGold * 0.5))
	end)

	t.it("배틀 결과에 무기 레벨 변경 항목이 없다", function()
		local result = BattleLogic.playMatch(match({ roll = 0 }))
		t.expectNil((result :: any).challengerLevel, "배틀은 무기 레벨을 건드리면 안 됩니다")
		t.expectNil((result :: any).newLevel, "배틀은 무기 레벨을 건드리면 안 됩니다")
	end)
end)

t.describe("배틀 승률 시뮬레이션", function()
	local function makeRng(seed: number): () -> number
		local state = seed
		return function(): number
			state = bit32.bxor(state, bit32.lshift(state, 13))
			state = bit32.bxor(state, bit32.rshift(state, 17))
			state = bit32.bxor(state, bit32.lshift(state, 5))
			return state / 4294967296
		end
	end

	t.it("실제 승리 비율이 공식과 맞는다", function()
		for _, pair in { { 10, 10 }, { 12, 8 }, { 5, 13 } } do
			local nextRoll = makeRng(4242 + pair[1] * 31 + pair[2])
			local expected = BattleLogic.winProbability(pair[1], pair[2], BattleConfig.K)
			local wins = 0
			local trials = 100000

			for _ = 1, trials do
				if BattleLogic.resolve(nextRoll(), expected) then
					wins += 1
				end
			end

			t.expectNear(wins / trials, expected, 0.01, `{pair[1]} vs {pair[2]}`)
		end
	end)
end)
