--!strict
--[[
	저장 데이터 전환 테스트. 가장 중요한 규칙은 "기존 데이터를 절대 버리지 않는다"이다.
]]
local t = require("./harness")
local DataMigration = require("../src/shared/Pure/DataMigration")
local Types = require("../src/shared/Types")
local Weapons = require("../src/shared/Config/Weapons")
local EnhanceTable = require("../src/shared/Config/EnhanceTable")

local OPTIONS: DataMigration.Options = {
	schemaVersion = Types.SCHEMA_VERSION,
	purchaseHistoryLimit = 200,
	defaultWeaponId = Weapons.DEFAULT_ID,
	maxLevel = EnhanceTable.MAX_LEVEL,
	isKnownWeapon = function(id: string): boolean
		return Weapons.get(id) ~= nil
	end,
}

-- 스키마 v3 시절(무기 하나, 배틀·업적 기록 있음)에 저장된 데이터
local function v3Data(): any
	return {
		schemaVersion = 3,
		gold = 123456,
		shards = 77,
		weapon = { id = "ironBlade", level = 12, customName = "내 검" },
		protectTickets = 3,
		stats = {
			enhanceTries = 500,
			enhanceSuccess = 200,
			destroyed = 9,
			highestLevel = 15,
			battleWins = 40,
			battleLosses = 22,
			rating = 1180,
			keepStreak = 2,
			bestKeepStreak = 11,
			ticketsUsed = 6,
		},
		codex = { ["ironBlade:5"] = true, ["ironBlade:10"] = true, ["ironBlade:15"] = true },
		achievements = { firstSwing = true, reach10 = true },
		daily = {
			lastLoginDay = 20500,
			streak = 4,
			battlesToday = 7,
			opponentsToday = { ["111"] = 2 },
		},
		purchaseHistory = { "p1", "p2" },
		settings = { sfx = false, language = "en" },
		-- 접속하면 ProfileStore 의 Reconcile 이 템플릿의 새 키를 먼저 채운다.
		swords = {},
		equippedId = "ironBlade",
		swordCapacity = 1,
		pityPoints = 0,
	}
end

t.describe("v3 → v4 (무기 하나 → 검 여러 개)", function()
	t.it("기존 무기가 첫 번째 검이 되고 착용된다", function()
		local data = DataMigration.migrate(v3Data(), OPTIONS)

		t.expectEqual(data.schemaVersion, 4)
		t.expectEqual(data.equippedId, "ironBlade")
		t.expectEqual(data.swordCapacity, 1)
		t.expectEqual(data.pityPoints, 0)

		local sword = data.swords.ironBlade
		t.expect(sword ~= nil, "기본 검이 없습니다")
		t.expectEqual(sword.id, "ironBlade")
		t.expectEqual(sword.level, 12)
		t.expectEqual(sword.customName, "내 검")
		-- 검이 하나뿐이었으니 역대 최고 레벨이 이 검의 최고 레벨이다
		t.expectEqual(sword.bestLevel, 15)
	end)

	t.it("재화·통계·도감·설정·구매 기록이 그대로다", function()
		local data = DataMigration.migrate(v3Data(), OPTIONS)

		t.expectEqual(data.gold, 123456)
		t.expectEqual(data.shards, 77)
		t.expectEqual(data.protectTickets, 3)
		t.expectEqual(data.stats.enhanceTries, 500)
		t.expectEqual(data.stats.highestLevel, 15)
		t.expectEqual(data.codex["ironBlade:15"], true)
		t.expectEqual(data.daily.streak, 4)
		t.expectEqual(#data.purchaseHistory, 2)
		t.expectEqual(data.settings.language, "en")
	end)

	t.it("기획에서 빠진 필드(배틀·업적·옛 weapon)를 지우지 않는다", function()
		local data = DataMigration.migrate(v3Data(), OPTIONS)

		t.expectEqual(data.stats.battleWins, 40)
		t.expectEqual(data.stats.battleLosses, 22)
		t.expectEqual(data.stats.rating, 1180)
		t.expectEqual(data.stats.bestKeepStreak, 11)
		t.expectEqual(data.stats.ticketsUsed, 6)
		t.expectEqual(data.achievements.reach10, true)
		t.expectEqual(data.daily.battlesToday, 7)
		t.expectEqual(data.daily.opponentsToday["111"], 2)
		t.expectEqual(data.weapon.level, 12)
		t.expectEqual(data.weapon.customName, "내 검")
	end)

	t.it("모르는 무기 id 는 기본 검으로 옮긴다", function()
		local old = v3Data()
		old.weapon.id = "removedWeapon"
		local data = DataMigration.migrate(old, OPTIONS)

		t.expectEqual(data.equippedId, Weapons.DEFAULT_ID)
		t.expectEqual(data.swords[Weapons.DEFAULT_ID].level, 12)
	end)

	t.it("이미 v4 인 데이터는 다시 옮기지 않는다", function()
		local data = DataMigration.migrate(v3Data(), OPTIONS)
		data.swords.emberEdge = { id = "emberEdge", level = 7, bestLevel = 9 }
		data.swordCapacity = 2
		data.equippedId = "emberEdge"
		data.swords.ironBlade.level = 3

		DataMigration.migrate(data, OPTIONS)

		t.expectEqual(data.equippedId, "emberEdge")
		t.expectEqual(data.swords.emberEdge.level, 7)
		t.expectEqual(data.swords.ironBlade.level, 3)
		t.expectEqual(data.swordCapacity, 2)
	end)
end)

t.describe("오래된 버전부터 한 번에", function()
	t.it("v1 (구매 기록이 딕셔너리) 데이터도 v4 까지 올라온다", function()
		local data: any = {
			gold = 500,
			shards = 0,
			weapon = { id = "ironBlade", level = 4 },
			protectTickets = 0,
			stats = { enhanceTries = 5, enhanceSuccess = 4, destroyed = 0, highestLevel = 4 },
			codex = {},
			daily = { lastLoginDay = 1, streak = 1 },
			purchaseHistory = { abc = true, def = true },
			settings = { sfx = true, language = "ko" },
		}

		DataMigration.migrate(data, OPTIONS)

		t.expectEqual(data.schemaVersion, 4)
		t.expectEqual(#data.purchaseHistory, 2)
		t.expectEqual(data.stats.ticketsUsed, 0)
		t.expectEqual(data.swords.ironBlade.level, 4)
		t.expectEqual(data.swords.ironBlade.bestLevel, 4)
		t.expectEqual(data.gold, 500)
	end)

	t.it("코드보다 새 버전의 데이터는 건드리지 않는다", function()
		local data: any = { schemaVersion = 99, gold = 1, future = { x = 1 } }
		local _, isNewer = DataMigration.migrate(data, OPTIONS)

		t.expectEqual(isNewer, true)
		t.expectEqual(data.schemaVersion, 99)
		t.expectNil(data.swords)
		t.expectEqual(data.future.x, 1)
	end)
end)

t.describe("DataMigration.repair", function()
	t.it("새 플레이어(검 없음)에게 기본 검을 준다", function()
		local data: any = { schemaVersion = 4, swords = {}, equippedId = "ironBlade" }
		DataMigration.repair(data, OPTIONS)

		t.expectEqual(data.swords.ironBlade.level, 0)
		t.expectEqual(data.swords.ironBlade.bestLevel, 0)
		t.expectEqual(data.equippedId, "ironBlade")
		t.expectEqual(data.swordCapacity, 1)
		t.expectEqual(data.pityPoints, 0)
	end)

	t.it("착용 검이 가진 검이 아니면 기본 검으로 바꾼다", function()
		local data: any = {
			swords = {
				ironBlade = { id = "ironBlade", level = 5, bestLevel = 5 },
				tideFang = { id = "tideFang", level = 2, bestLevel = 2 },
			},
			equippedId = "dawnbreaker",
			swordCapacity = 2,
		}
		DataMigration.repair(data, OPTIONS)
		t.expectEqual(data.equippedId, "ironBlade")
	end)

	t.it("레벨과 최고 레벨, 소지 상한을 올바른 범위로 맞춘다", function()
		local data: any = {
			swords = {
				ironBlade = { id = "wrong", level = 99, bestLevel = 3 },
				tideFang = { id = "tideFang", level = -4, bestLevel = 8.7 },
			},
			equippedId = "tideFang",
			swordCapacity = 0,
			pityPoints = -2,
		}
		DataMigration.repair(data, OPTIONS)

		t.expectEqual(data.swords.ironBlade.id, "ironBlade")
		t.expectEqual(data.swords.ironBlade.level, 20)
		t.expectEqual(data.swords.ironBlade.bestLevel, 20)
		t.expectEqual(data.swords.tideFang.level, 0)
		t.expectEqual(data.swords.tideFang.bestLevel, 8)
		t.expectEqual(data.swordCapacity, 2)
		t.expectEqual(data.pityPoints, 0)
		t.expectEqual(data.equippedId, "tideFang")
	end)

	t.it("여러 번 불러도 결과가 같다", function()
		local data = DataMigration.migrate(v3Data(), OPTIONS)
		local before = data.swords.ironBlade.level
		DataMigration.repair(data, OPTIONS)
		DataMigration.repair(data, OPTIONS)
		t.expectEqual(data.swords.ironBlade.level, before)
		t.expectEqual(data.swordCapacity, 1)
	end)
end)
