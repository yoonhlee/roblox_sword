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
		["rarity.common"] = "일반",
		["rarity.rare"] = "희귀",
		["rarity.epic"] = "영웅",
		["rarity.legend"] = "전설",

		-- UI
		["ui.enhance"] = "강화하기",
		["ui.enhancing"] = "두드리는 중...",
		["ui.level"] = "+%d",
		["ui.gold"] = "골드 %s",
		["ui.shards"] = "파편 %s",
		["ui.tickets"] = "방지권 %d",
		["ui.cost"] = "비용 %s 골드",
		["ui.useProtect"] = "방지권 사용",
		["ui.protectNote"] = "방지권을 켜면 실패 확률이 0%% 가 되고 그만큼 유지가 늘어난다. 실패가 나왔을 때만 1개 쓴다.",
		["ui.odds"] = "성공 %s · 유지 %s · 실패 %s",
		["ui.maxLevel"] = "더 올릴 수 없다. 이게 끝이야.",
		["ui.loading"] = "대장간 문을 여는 중...",
		["ui.cancel"] = "그만둔다",
		["ui.oddsTable"] = "확률표",
		["ui.oddsTableTitle"] = "강화 확률표",
		["ui.close"] = "닫기",
		["ui.column.level"] = "레벨",
		["ui.column.success"] = "성공",
		["ui.column.keep"] = "유지",
		["ui.column.fail"] = "실패",
		["ui.column.cost"] = "비용",
		["ui.eventActive"] = "이벤트 적용 중: %s",
		["ui.feedToggle"] = "기록",
		["ui.tab.settings"] = "설정",
		["ui.sfxOn"] = "소리 켜짐",
		["ui.sfxOff"] = "소리 꺼짐",
		["ui.language"] = "언어: 한국어",
		["ui.maintenance"] = "점검 중이다. 곧 돌아오마.",
		["event.boost"] = "성공 확률 상승 이벤트",
		["event.default"] = "진행 중인 이벤트",
		["tutorial.step1"] = "아래 버튼을 눌러 한 번 두드려 봐라.",
		["tutorial.step2"] = "좋아. 한 번 더.",
		["tutorial.step3"] = "마지막으로 한 번 더 해 보자.",
		["tutorial.done"] = "이제 감을 잡았군. 마음대로 해라.",
		["ui.rename"] = "이름 짓기",
		["ui.renamePrompt"] = "검 이름을 지어라 (최대 16자)",
		["ui.renamed"] = "이제 '%s' 라 부르자.",
		["error.invalid_name"] = "그런 이름은 쓸 수 없다.",
		["error.filter_failed"] = "이름을 확인하지 못했다. 잠시 뒤에 다시.",
		["ui.records"] = "기록",
		["ui.tab.codex"] = "도감",
		["ui.tab.rank"] = "랭킹",
		["ui.rank.level"] = "최고 강화",
		["ui.rank.row"] = "%d위  %s  %s",
		["ui.rank.empty"] = "아직 기록이 없다.",
		["ui.codexOwned"] = "%s (%s)  최고 +%d",
		["ui.codexMissing"] = "%s (%s)  아직 없음",
		["ui.codexMilestones"] = "기념 %s",
		["codex.unlocked"] = "도감: %s +%d 달성.",
		["ui.swords"] = "검",
		["ui.swordsTitle"] = "검 보관함",
		["ui.swordRow"] = "%s (%s)  +%d",
		["ui.equipped"] = "[착용 중]",
		["ui.drawTitle"] = "새 검 뽑기",
		["ui.drawDesc"] = "소지 상한 1칸을 사면 새 검을 한 번 뽑는다. 이미 가진 검은 나오지 않고, 뽑힌 검은 +0 부터 시작한다. 검이 늘면 모든 검의 강화 비용이 오른다.",
		["ui.drawPrice"] = "가격 %s 골드",
		["ui.drawOddsTitle"] = "지금 뽑으면 나올 확률 (합계 100%%)",
		["ui.drawRarityRow"] = "%s 등급  %s",
		["ui.drawSwordRow"] = "· %s (%s)  %s",
		["ui.drawBuy"] = "칸 사고 뽑기",
		["ui.drawConfirm"] = "한 번 더 누르면 %s 골드를 쓴다",
		["ui.drawNone"] = "더 뽑을 검이 없다. 전부 모았다.",
		["ui.drawResult"] = "새 검이 나왔다: %s (%s)",

		["ui.shop"] = "상점",
		["ui.shopTitle"] = "상점",
		["ui.shopEmpty"] = "아직 상품이 등록되지 않았다.",
		["shop.ticketPack"] = "방지권 %d 개",
		["shop.notice"] = "골드는 Robux 로 못 산다. 확률은 전부 공개한다.",
		["error.not_available"] = "아직 준비되지 않은 상품이다.",

		-- 채팅 명령어 응답
		["chat.result.success"] = "성공! 이제 +%d 다.",
		["chat.result.keep"] = "변화 없음. 여전히 +%d.",
		["chat.result.fail"] = "실패. +%d 로 돌아갔다.",
		["chat.result.protected"] = "방지권이 막았다. +%d 유지.",
		["chat.odds"] = "+%d → 성공 %s · 유지 %s · 실패 %s · 비용 %s 골드",
		["chat.info"] = "착용 검 +%d · 골드 %s · 파편 %s · 방지권 %d · 시도 %d회 · 실패 %d회 · 최고 +%d",
		["chat.help"] = "/강화 [보호] · /확률 · /정보",

		-- 결과 피드 (모루 영감의 대사)
		["feed.success.1"] = "좋아, 한 단계 올랐다.",
		["feed.success.2"] = "불이 제대로 먹었군.",
		["feed.success.3"] = "이번 건 잘 들어갔어.",
		["feed.keep.1"] = "쇳덩이가 버텼다. 그대로야.",
		["feed.keep.2"] = "흠... 변한 게 없군.",
		["feed.keep.3"] = "아직 멀었다. 다시.",
		["feed.fail.1"] = "미끄러졌다. +10 부터 다시다.",
		["feed.fail.2"] = "쯧. 이런 날도 있는 거지.",
		["feed.fail.3"] = "내 탓은 아니야. 파편이나 챙겨라.",
		["feed.protected.1"] = "방지권이 막았다. 운 좋은 줄 알아.",
		["feed.protected.2"] = "하마터면 +10 까지 굴러떨어질 뻔했군.",
		["feed.max.1"] = "여기까지다. 더는 못 올려.",
		["feed.broadcast"] = "%s 님이 %s +%d 을(를) 완성했다!",

		-- 실패 사유
		["error.not_ready"] = "데이터를 불러오는 중이다. 잠시만.",
		["error.too_fast"] = "망치질이 너무 빠르다. 숨 좀 돌려라.",
		["error.busy"] = "아직 앞의 것을 두드리는 중이다.",
		["error.not_enough_gold"] = "골드가 모자란다.",
		["error.max_level"] = "이미 끝까지 올렸다.",
		["error.not_owned"] = "가지지 않은 검이다.",
		["error.no_more_swords"] = "더 뽑을 검이 없다.",
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
		["rarity.common"] = "Common",
		["rarity.rare"] = "Rare",
		["rarity.epic"] = "Epic",
		["rarity.legend"] = "Legend",

		["ui.enhance"] = "Forge",
		["ui.enhancing"] = "Hammering...",
		["ui.level"] = "+%d",
		["ui.gold"] = "%s Gold",
		["ui.shards"] = "%s Shards",
		["ui.tickets"] = "%d Tickets",
		["ui.cost"] = "Cost %s Gold",
		["ui.useProtect"] = "Use ticket",
		["ui.protectNote"] = "With a ticket on, the fail chance becomes 0%% and that much is added to hold. One is used only when a fail is rolled.",
		["ui.odds"] = "Up %s · Hold %s · Fail %s",
		["ui.maxLevel"] = "This is as far as it goes.",
		["ui.loading"] = "Opening the forge...",
		["ui.cancel"] = "Never mind",
		["ui.oddsTable"] = "Odds",
		["ui.oddsTableTitle"] = "Forge Odds",
		["ui.close"] = "Close",
		["ui.column.level"] = "Lv",
		["ui.column.success"] = "Up",
		["ui.column.keep"] = "Hold",
		["ui.column.fail"] = "Fail",
		["ui.column.cost"] = "Cost",
		["ui.eventActive"] = "Event active: %s",
		["ui.feedToggle"] = "Log",
		["ui.tab.settings"] = "Settings",
		["ui.sfxOn"] = "Sound on",
		["ui.sfxOff"] = "Sound off",
		["ui.language"] = "Language: English",
		["ui.maintenance"] = "Under maintenance. Back soon.",
		["event.boost"] = "Success rate event",
		["event.default"] = "Event running",
		["tutorial.step1"] = "Press the button below and give it one swing.",
		["tutorial.step2"] = "Good. One more.",
		["tutorial.step3"] = "One last time.",
		["tutorial.done"] = "You have the feel of it. Go on.",
		["ui.rename"] = "Name it",
		["ui.renamePrompt"] = "Name your sword (16 characters max)",
		["ui.renamed"] = "We'll call it '%s' then.",
		["error.invalid_name"] = "That name will not do.",
		["error.filter_failed"] = "Could not check that name. Try again shortly.",
		["ui.records"] = "Records",
		["ui.tab.codex"] = "Codex",
		["ui.tab.rank"] = "Ranking",
		["ui.rank.level"] = "Top level",
		["ui.rank.row"] = "#%d  %s  %s",
		["ui.rank.empty"] = "No records yet.",
		["ui.codexOwned"] = "%s (%s)  best +%d",
		["ui.codexMissing"] = "%s (%s)  not owned",
		["ui.codexMilestones"] = "marks %s",
		["codex.unlocked"] = "Codex: %s reached +%d.",
		["ui.swords"] = "Swords",
		["ui.swordsTitle"] = "Sword Rack",
		["ui.swordRow"] = "%s (%s)  +%d",
		["ui.equipped"] = "[Equipped]",
		["ui.drawTitle"] = "Draw a new sword",
		["ui.drawDesc"] = "Buying one more slot draws one new sword. Swords you already own never come up, and a new sword starts at +0. More swords raise the forging cost of every sword.",
		["ui.drawPrice"] = "Price %s gold",
		["ui.drawOddsTitle"] = "Your odds right now (total 100%%)",
		["ui.drawRarityRow"] = "%s  %s",
		["ui.drawSwordRow"] = "· %s (%s)  %s",
		["ui.drawBuy"] = "Buy slot and draw",
		["ui.drawConfirm"] = "Press again to spend %s gold",
		["ui.drawNone"] = "Nothing left to draw. You have them all.",
		["ui.drawResult"] = "A new sword: %s (%s)",

		["ui.shop"] = "Shop",
		["ui.shopTitle"] = "Shop",
		["ui.shopEmpty"] = "No items yet.",
		["shop.ticketPack"] = "%d protection tickets",
		["shop.notice"] = "Gold is never sold for Robux. All odds are public.",
		["error.not_available"] = "That item is not ready yet.",

		["chat.result.success"] = "Success! Now +%d.",
		["chat.result.keep"] = "No change. Still +%d.",
		["chat.result.fail"] = "Failed. Back to +%d.",
		["chat.result.protected"] = "The ticket held it at +%d.",
		["chat.odds"] = "+%d → up %s · hold %s · fail %s · cost %s gold",
		["chat.info"] = "Equipped +%d · %s gold · %s shards · %d tickets · %d tries · %d fails · best +%d",
		["chat.help"] = "/enhance [protect] · /odds · /info",

		["feed.success.1"] = "There. One step higher.",
		["feed.success.2"] = "The fire took it well.",
		["feed.success.3"] = "That one landed clean.",
		["feed.keep.1"] = "It held. No change.",
		["feed.keep.2"] = "Hm... nothing moved.",
		["feed.keep.3"] = "Not yet. Again.",
		["feed.fail.1"] = "It slipped. Back to +10.",
		["feed.fail.2"] = "Tsk. Some days go like that.",
		["feed.fail.3"] = "Don't look at me. Take the shards.",
		["feed.protected.1"] = "The ticket caught it. Lucky you.",
		["feed.protected.2"] = "That nearly rolled back to +10.",
		["feed.max.1"] = "That's the end of it.",
		["feed.broadcast"] = "%s forged %s +%d!",

		["error.not_ready"] = "Your data is still loading.",
		["error.too_fast"] = "Easy on the hammer.",
		["error.busy"] = "Still working the last one.",
		["error.not_enough_gold"] = "Not enough gold.",
		["error.max_level"] = "Already at the top.",
		["error.not_owned"] = "You do not own that sword.",
		["error.no_more_swords"] = "No swords left to draw.",
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
