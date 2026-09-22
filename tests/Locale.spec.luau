--!strict
--[[
	화면에 나갈 문자열이 빠지는 건 조용히 일어나는 실수다.
	키가 없으면 사람이 읽을 문장 대신 "ui.something" 같은 키가 그대로 보인다.
	그래서 "코드가 만들어 낼 수 있는 키"가 전부 정의돼 있는지 여기서 고정해 둔다.
]]

local t = require("./harness")
local Locale = require("../src/shared/Locale")
local Weapons = require("../src/shared/Config/Weapons")
local Achievements = require("../src/shared/Config/Achievements")
local Products = require("../src/shared/Config/Products")

local ko = Locale.Strings.ko
local en = Locale.Strings.en

local function has(key: string): boolean
	return ko[key] ~= nil
end

t.describe("Locale 한국어/영어 대응", function()
	t.it("두 언어의 키 목록이 같다", function()
		for key in ko do
			t.expect(en[key] ~= nil, `영어에 없는 키: {key}`)
		end
		for key in en do
			t.expect(ko[key] ~= nil, `한국어에 없는 키: {key}`)
		end
	end)

	t.it("빈 문자열인 키가 없다", function()
		for key, value in ko do
			t.expect(value ~= "", `한국어 값이 비어 있음: {key}`)
		end
		for key, value in en do
			t.expect(value ~= "", `영어 값이 비어 있음: {key}`)
		end
	end)
end)

t.describe("설정 데이터에 대응하는 문자열", function()
	t.it("모든 무기에 이름 키가 있다", function()
		for _, weapon in Weapons.List do
			t.expect(has(weapon.nameKey), `무기 이름 키 없음: {weapon.nameKey}`)
		end
	end)

	t.it("모든 업적에 이름 키가 있다", function()
		for _, achievement in Achievements.List do
			t.expect(
				has(`achv.{achievement.id}.name`),
				`업적 이름 키 없음: achv.{achievement.id}.name`
			)
		end
	end)

	t.it("모든 상점 항목에 이름 키가 있다", function()
		for key in Products.GamePasses do
			t.expect(has(`shop.{key}`), `게임패스 이름 키 없음: shop.{key}`)
		end
		for key in Products.DeveloperProducts do
			t.expect(has(`shop.{key}`), `개발자 상품 이름 키 없음: shop.{key}`)
		end
	end)
end)

t.describe("결과별 문자열", function()
	local OUTCOMES = { "success", "keep", "destroy", "protected" }

	t.it("모든 강화 결과에 피드 대사가 있다", function()
		for _, outcome in OUTCOMES do
			local count = Locale.variantCount("ko", `feed.{outcome}`)
			t.expect(count > 0, `피드 대사 없음: feed.{outcome}`)
			t.expectEqual(
				Locale.variantCount("en", `feed.{outcome}`),
				count,
				`feed.{outcome} 의 변형 개수가 언어마다 다름`
			)
		end
	end)

	t.it("최대 레벨 대사가 있다", function()
		t.expect(Locale.variantCount("ko", "feed.max") > 0, "feed.max 대사 없음")
	end)

	t.it("모든 강화 결과에 채팅 응답이 있다", function()
		for _, outcome in OUTCOMES do
			t.expect(has(`chat.result.{outcome}`), `채팅 응답 없음: chat.result.{outcome}`)
		end
	end)

	t.it("튜토리얼 3단계가 모두 있다", function()
		for step = 1, 3 do
			t.expect(has(`tutorial.step{step}`), `튜토리얼 문구 없음: tutorial.step{step}`)
		end
		t.expect(has("tutorial.done"), "tutorial.done 없음")
	end)
end)

t.describe("실패 사유 문자열", function()
	--[[
		서버가 { ok = false, reason = "..." } 로 돌려줄 수 있는 사유 전체.
		새 사유를 만들면 이 목록과 Locale 양쪽에 추가해야 한다.
	]]
	local REASONS = {
		"already_challenging",
		"answer_first",
		"banned",
		"battle_cooldown",
		"busy",
		"filter_failed",
		"invalid_argument",
		"invalid_name",
		"load_fail",
		"maintenance",
		"max_level",
		"no_invite",
		"no_opponent",
		"not_available",
		"not_enough_gold",
		"not_enough_shards",
		"not_found",
		"not_ready",
		"nothing_to_sell",
		"opponent_busy",
		"opponent_cooldown",
		"opponent_left",
		"opponent_not_ready",
		"self_challenge",
		"session_end",
		"too_fast",
		"unknown",
	}

	t.it("모든 실패 사유에 안내 문구가 있다", function()
		for _, reason in REASONS do
			t.expect(has(`error.{reason}`), `실패 사유 문구 없음: error.{reason}`)
		end
	end)
end)

t.describe("Locale.get 동작", function()
	t.it("없는 키는 키 자체를 돌려준다", function()
		t.expectEqual(Locale.get("ko", "정의되지.않은.키"), "정의되지.않은.키")
	end)

	t.it("모르는 언어는 기본 언어로 대체된다", function()
		t.expectEqual(Locale.get("fr", "ui.enhance"), ko["ui.enhance"])
	end)

	t.it("치환이 동작한다", function()
		t.expectEqual(Locale.get("ko", "ui.level", 7), "+7")
	end)

	t.it("인자 개수가 맞지 않아도 터지지 않는다", function()
		local result = Locale.get("ko", "ui.gold")
		t.expect(type(result) == "string", "문자열이 아님")
	end)
end)
