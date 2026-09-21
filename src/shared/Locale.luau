--!strict
--[[
	Locale — 화면에 보이는 모든 문자열을 키로 관리한다.
	코드 어디에도 표시용 문장을 직접 쓰지 않는다.

	[확인 필요 / Phase 7] 출시 전에는 이 테이블을 Roblox LocalizationTable 로 옮겨
	자동 번역·번역가 워크플로를 쓸 수 있게 한다. 지금은 외부 의존 없이 동작하도록
	순수 Luau 테이블로 둔다. 키 이름은 그대로 유지할 예정이라 이전 비용이 작다.

	치환은 string.format 규칙을 따른다(%s, %d). 언어별로 인자 순서는 같아야 한다.
]]

local Locale = {}

Locale.DEFAULT_LANGUAGE = "ko"

Locale.Strings = {
	ko = {
		["game.title"] = "강화의 대장간",
		["npc.anvilElder.name"] = "모루 영감",

		-- 무기 이름
		["weapon.ironBlade.name"] = "무쇠 검",
		["weapon.emberEdge.name"] = "잉걸불 검",
		["weapon.tideFang.name"] = "물결 송곳니",
		["weapon.stormNeedle.name"] = "폭풍 바늘",
		["weapon.dawnbreaker.name"] = "새벽가르기",

		-- UI
		["ui.enhance"] = "강화하기",
		["ui.enhancing"] = "두드리는 중...",
		["ui.level"] = "+%d",
		["ui.gold"] = "골드 %s",
		["ui.shards"] = "파편 %s",
		["ui.tickets"] = "방지권 %d",
		["ui.cost"] = "비용 %s 골드",
		["ui.useProtect"] = "방지권 사용",
		["ui.odds"] = "성공 %s · 유지 %s · 파괴 %s",
		["ui.maxLevel"] = "더 올릴 수 없다. 이게 끝이야.",
		["ui.loading"] = "대장간 문을 여는 중...",
		["ui.sell"] = "판매",
		["ui.sellConfirm"] = "이 무기를 %s 골드에 팝니다. 레벨은 0 으로 돌아갑니다.",
		["ui.confirm"] = "판다",
		["ui.cancel"] = "그만둔다",
		["ui.oddsTable"] = "확률표",
		["ui.oddsTableTitle"] = "강화 확률표",
		["ui.close"] = "닫기",
		["ui.column.level"] = "레벨",
		["ui.column.success"] = "성공",
		["ui.column.keep"] = "유지",
		["ui.column.destroy"] = "파괴",
		["ui.column.cost"] = "비용",
		["ui.column.sell"] = "판매가",
		["ui.eventActive"] = "이벤트 적용 중: %s",
		["ui.feedToggle"] = "기록",
		["ui.battle"] = "배틀",
		["ui.battleTitle"] = "도전할 상대",
		["ui.battleRandom"] = "아무나 매칭",
		["ui.battleRow"] = "%s  +%d  (%d점)",
		["ui.noOpponent"] = "지금 서버에 도전할 사람이 없다.",
		["ui.accept"] = "받는다",
		["ui.decline"] = "거절한다",

		["battle.sent"] = "%s 에게 도전장을 보냈다.",
		["battle.timeout"] = "%s 가 끝내 답하지 않았다.",
		["battle.declined"] = "%s 가 도전을 거절했다.",
		["battle.invite"] = "%s (+%d) 이(가) 겨루자고 한다.",
		["battle.win"] = "이겼다!",
		["battle.loss"] = "졌다.",
		["battle.reward"] = "골드 +%s",
		["battle.rating"] = "레이팅 %d → %d",
		["battle.odds"] = "이길 확률은 %s 였다.",
		["battle.capped"] = "오늘 보상 한도를 다 썼다. 승패만 남는다.",
		["battle.feedWin"] = "%s 를 눕혔다.",
		["battle.feedLoss"] = "%s 에게 밀렸다.",

		["chat.battleUsage"] = "/배틀 [닉네임] · 닉네임을 비우면 아무나 매칭",

		["error.self_challenge"] = "자기 자신과는 겨룰 수 없다.",
		["error.opponent_not_ready"] = "상대 쪽 준비가 안 됐다.",
		["error.opponent_busy"] = "그 사람은 이미 도전을 받았다.",
		["error.opponent_cooldown"] = "그 사람은 방금 싸웠다. 숨 돌릴 시간을 줘라.",
		["error.battle_cooldown"] = "아직 숨이 차다. 잠시 뒤에.",
		["error.already_challenging"] = "이미 도전장을 보냈다.",
		["error.answer_first"] = "받은 도전에 먼저 답해라.",
		["error.no_opponent"] = "도전할 사람이 없다.",
		["error.opponent_left"] = "상대가 떠났다.",
		["error.no_invite"] = "받은 도전이 없다.",
		["error.not_found"] = "그런 사람을 못 찾겠다.",

		-- 채팅 명령어 응답
		["chat.result.success"] = "성공! 이제 +%d 다.",
		["chat.result.keep"] = "변화 없음. 여전히 +%d.",
		["chat.result.destroy"] = "깨졌다. +%d 부터 다시.",
		["chat.result.protected"] = "방지권이 막았다. +%d 유지.",
		["chat.sold"] = "무기를 팔아 %s 골드를 받았다.",
		["chat.odds"] = "+%d → 성공 %s · 유지 %s · 파괴 %s · 비용 %s 골드",
		["chat.info"] = "강화 +%d · 골드 %s · 파편 %s · 방지권 %d · 시도 %d회 · 파괴 %d회 · 최고 +%d",
		["chat.help"] = "/강화 [보호] · /판매 · /배틀 [닉네임] · /확률 · /정보",

		["error.nothing_to_sell"] = "팔 게 없다. 맨 처음 무기다.",

		-- 결과 피드 (모루 영감의 대사)
		["feed.success.1"] = "좋아, 한 단계 올랐다.",
		["feed.success.2"] = "불이 제대로 먹었군.",
		["feed.success.3"] = "이번 건 잘 들어갔어.",
		["feed.keep.1"] = "쇳덩이가 버텼다. 그대로야.",
		["feed.keep.2"] = "흠... 변한 게 없군.",
		["feed.keep.3"] = "아직 멀었다. 다시.",
		["feed.destroy.1"] = "깨졌다. 파편이나 챙겨라.",
		["feed.destroy.2"] = "쯧. 이런 날도 있는 거지.",
		["feed.destroy.3"] = "내 탓은 아니야.",
		["feed.protected.1"] = "방지권이 막았다. 운 좋은 줄 알아.",
		["feed.protected.2"] = "하마터면 가루가 될 뻔했군.",
		["feed.max.1"] = "여기까지다. 더는 못 올려.",
		["feed.broadcast"] = "%s 님이 %s +%d 을(를) 완성했다!",

		-- 실패 사유
		["error.not_ready"] = "데이터를 불러오는 중이다. 잠시만.",
		["error.too_fast"] = "망치질이 너무 빠르다. 숨 좀 돌려라.",
		["error.busy"] = "아직 앞의 것을 두드리는 중이다.",
		["error.not_enough_gold"] = "골드가 모자란다.",
		["error.max_level"] = "이미 끝까지 올렸다.",
		["error.maintenance"] = "대장간 점검 중이다. 곧 돌아오마.",
		["error.invalid_argument"] = "요청이 이상하다.",
		["error.banned"] = "출입이 금지되었다.",
		["error.unknown"] = "알 수 없는 문제가 생겼다.",
		["error.load_fail"] = "데이터를 불러오지 못했다. 다시 들어와 주게.",
		["error.session_end"] = "다른 서버에서 데이터가 열렸다. 다시 들어와 주게.",
	},

	en = {
		["game.title"] = "Forge Fever",
		["npc.anvilElder.name"] = "Old Anvil",

		["weapon.ironBlade.name"] = "Iron Blade",
		["weapon.emberEdge.name"] = "Ember Edge",
		["weapon.tideFang.name"] = "Tide Fang",
		["weapon.stormNeedle.name"] = "Storm Needle",
		["weapon.dawnbreaker.name"] = "Dawnbreaker",

		["ui.enhance"] = "Forge",
		["ui.enhancing"] = "Hammering...",
		["ui.level"] = "+%d",
		["ui.gold"] = "%s Gold",
		["ui.shards"] = "%s Shards",
		["ui.tickets"] = "%d Tickets",
		["ui.cost"] = "Cost %s Gold",
		["ui.useProtect"] = "Use ticket",
		["ui.odds"] = "Up %s · Hold %s · Break %s",
		["ui.maxLevel"] = "This is as far as it goes.",
		["ui.loading"] = "Opening the forge...",
		["ui.sell"] = "Sell",
		["ui.sellConfirm"] = "Sell this weapon for %s gold. Its level returns to 0.",
		["ui.confirm"] = "Sell it",
		["ui.cancel"] = "Never mind",
		["ui.oddsTable"] = "Odds",
		["ui.oddsTableTitle"] = "Forge Odds",
		["ui.close"] = "Close",
		["ui.column.level"] = "Lv",
		["ui.column.success"] = "Up",
		["ui.column.keep"] = "Hold",
		["ui.column.destroy"] = "Break",
		["ui.column.cost"] = "Cost",
		["ui.column.sell"] = "Sell",
		["ui.eventActive"] = "Event active: %s",
		["ui.feedToggle"] = "Log",
		["ui.battle"] = "Battle",
		["ui.battleTitle"] = "Pick an opponent",
		["ui.battleRandom"] = "Match anyone",
		["ui.battleRow"] = "%s  +%d  (%d)",
		["ui.noOpponent"] = "Nobody here to fight right now.",
		["ui.accept"] = "Accept",
		["ui.decline"] = "Decline",

		["battle.sent"] = "Challenge sent to %s.",
		["battle.timeout"] = "%s never answered.",
		["battle.declined"] = "%s declined.",
		["battle.invite"] = "%s (+%d) wants to fight.",
		["battle.win"] = "You won!",
		["battle.loss"] = "You lost.",
		["battle.reward"] = "+%s gold",
		["battle.rating"] = "Rating %d → %d",
		["battle.odds"] = "Your odds were %s.",
		["battle.capped"] = "Daily reward cap reached. Win or lose only.",
		["battle.feedWin"] = "Beat %s.",
		["battle.feedLoss"] = "Lost to %s.",

		["chat.battleUsage"] = "/battle [name] · leave the name out to match anyone",

		["error.self_challenge"] = "You cannot fight yourself.",
		["error.opponent_not_ready"] = "They are not ready.",
		["error.opponent_busy"] = "They already have a challenge.",
		["error.opponent_cooldown"] = "They just fought. Give them a moment.",
		["error.battle_cooldown"] = "Catch your breath first.",
		["error.already_challenging"] = "You already sent a challenge.",
		["error.answer_first"] = "Answer the challenge you received first.",
		["error.no_opponent"] = "No one to challenge.",
		["error.opponent_left"] = "They left.",
		["error.no_invite"] = "No challenge to answer.",
		["error.not_found"] = "Cannot find them.",

		["chat.result.success"] = "Success! Now +%d.",
		["chat.result.keep"] = "No change. Still +%d.",
		["chat.result.destroy"] = "Shattered. Back to +%d.",
		["chat.result.protected"] = "The ticket held it at +%d.",
		["chat.sold"] = "Sold the weapon for %s gold.",
		["chat.odds"] = "+%d → up %s · hold %s · break %s · cost %s gold",
		["chat.info"] = "Level +%d · %s gold · %s shards · %d tickets · %d tries · %d breaks · best +%d",
		["chat.help"] = "/enhance [protect] · /sell · /battle [name] · /odds · /info",

		["error.nothing_to_sell"] = "Nothing to sell. That's the starter blade.",

		["feed.success.1"] = "There. One step higher.",
		["feed.success.2"] = "The fire took it well.",
		["feed.success.3"] = "That one landed clean.",
		["feed.keep.1"] = "It held. No change.",
		["feed.keep.2"] = "Hm... nothing moved.",
		["feed.keep.3"] = "Not yet. Again.",
		["feed.destroy.1"] = "Shattered. Take the shards.",
		["feed.destroy.2"] = "Tsk. Some days go like that.",
		["feed.destroy.3"] = "Don't look at me.",
		["feed.protected.1"] = "The ticket caught it. Lucky you.",
		["feed.protected.2"] = "That was nearly dust.",
		["feed.max.1"] = "That's the end of it.",
		["feed.broadcast"] = "%s forged %s +%d!",

		["error.not_ready"] = "Your data is still loading.",
		["error.too_fast"] = "Easy on the hammer.",
		["error.busy"] = "Still working the last one.",
		["error.not_enough_gold"] = "Not enough gold.",
		["error.max_level"] = "Already at the top.",
		["error.maintenance"] = "The forge is closed for maintenance.",
		["error.invalid_argument"] = "That request makes no sense.",
		["error.banned"] = "You are barred from the forge.",
		["error.unknown"] = "Something went wrong.",
		["error.load_fail"] = "Could not load your data. Please rejoin.",
		["error.session_end"] = "Your data was opened on another server. Please rejoin.",
	},
} :: { [string]: { [string]: string } }

--[[
	키를 해당 언어의 문자열로 바꾼다.
	해당 언어에 키가 없으면 기본 언어로, 그것도 없으면 키 자체를 돌려준다
	(빈 화면 대신 무엇이 빠졌는지 보이도록).
]]
function Locale.get(language: string?, key: string, ...: any): string
	local lang = language or Locale.DEFAULT_LANGUAGE
	local table_ = Locale.Strings[lang] or Locale.Strings[Locale.DEFAULT_LANGUAGE]
	local template = table_[key] or Locale.Strings[Locale.DEFAULT_LANGUAGE][key]

	if not template then
		return key
	end

	if select("#", ...) == 0 then
		return template
	end

	local ok, formatted = pcall(string.format, template, ...)
	return if ok then formatted else template
end

-- 같은 접두사를 가진 변형 중 하나를 고른다. (예: "feed.success" → feed.success.1~3)
-- 연출용 문구 선택이라 클라이언트에서 뽑아도 되는 값이다.
function Locale.variantCount(language: string?, prefix: string): number
	local lang = language or Locale.DEFAULT_LANGUAGE
	local table_ = Locale.Strings[lang] or Locale.Strings[Locale.DEFAULT_LANGUAGE]

	local count = 0
	while table_[`{prefix}.{count + 1}`] ~= nil do
		count += 1
	end
	return count
end

return Locale
