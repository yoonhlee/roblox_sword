--!strict
--[[
	Palette — 화면(UI)과 세계(로비·코스·검)가 함께 쓰는 색 (통합 기획서 8-1·8-2절).

	숫자(0~255)로만 둔다. Roblox 의 Color3 로 바꾸는 일은 쓰는 쪽이 한다
	(그래서 Studio 밖 테스트에서도 읽을 수 있다).
	값은 추천치(Claude 초기값)이고 Studio 에서 다듬는다. 방향은 확정이다.
]]

export type RGB = { number }

local Palette = {}

-- 화면 기본색
Palette.UI = {
	bg = { 24, 21, 26 }, -- 바탕
	panel = { 34, 30, 38 }, -- 창
	sub = { 52, 46, 58 }, -- 보조 칸
	line = { 70, 62, 78 }, -- 구분선
	text = { 240, 236, 230 },
	muted = { 168, 160, 172 },
	ember = { 226, 142, 58 }, -- 불꽃 주황 (강조)
	emberDark = { 150, 84, 28 }, -- 강조 버튼 아래 띠
	ink = { 24, 18, 10 }, -- 밝은 버튼 위 글자
	outline = { 12, 10, 14 }, -- 굵은 글자 테두리
	disabled = { 72, 68, 76 },
	danger = { 220, 64, 56 }, -- 닫기 X
	gold = { 255, 208, 112 },
	shard = { 140, 210, 255 },
	ticket = { 120, 220, 150 },
	success = { 226, 142, 58 },
	keep = { 198, 198, 198 },
	fail = { 255, 120, 108 },
	protect = { 140, 210, 255 },
	event = { 140, 210, 255 },
}

-- 검 등급 색 (관례: 일반 회색, 희귀 파랑, 영웅 보라, 전설 금색)
Palette.RARITY = {
	common = { 180, 180, 180 },
	rare = { 79, 163, 255 },
	epic = { 181, 101, 255 },
	legend = { 255, 200, 61 },
} :: { [string]: RGB }

--[[
	레벨 색: 쇠를 달구는 색. minLevel 이상이면 그 단계다(위에서부터 차례로 확인한다).
	glow: 칼날 주위로 빛이 번지는 정도(0 없음 ~ 1 최대), sparks: 불티를 날리는지.
	nameKey: 단계 이름 Locale 키.
]]
export type HeatTier = {
	minLevel: number,
	rgb: RGB,
	glow: number,
	sparks: boolean,
	nameKey: string,
}

Palette.HEAT_TIERS = {
	{ minLevel = 0, rgb = { 154, 160, 168 }, glow = 0, sparks = false, nameKey = "heat.cold" },
	{ minLevel = 5, rgb = { 224, 80, 58 }, glow = 0.2, sparks = false, nameKey = "heat.red" },
	{ minLevel = 10, rgb = { 255, 138, 42 }, glow = 0.4, sparks = false, nameKey = "heat.orange" },
	{ minLevel = 15, rgb = { 255, 224, 112 }, glow = 0.7, sparks = true, nameKey = "heat.yellow" },
	{ minLevel = 20, rgb = { 255, 255, 255 }, glow = 1, sparks = true, nameKey = "heat.white" },
} :: { HeatTier }

-- 세계(블록) 재료 색
Palette.WORLD = {
	stone = { 74, 66, 80 }, -- 검은 돌: 바닥·담·관문
	stoneDark = { 52, 46, 58 },
	cobble = { 110, 98, 104 }, -- 돌길
	wood = { 106, 70, 48 }, -- 그을린 나무
	iron = { 58, 60, 66 }, -- 무쇠
	steel = { 91, 95, 102 }, -- 칼날 바탕
	roof = { 91, 47, 42 }, -- 지붕
	brick = { 77, 58, 63 }, -- 화덕·굴뚝
	leather = { 138, 96, 68 }, -- 풀무
	beard = { 232, 226, 216 },
	skin = { 217, 180, 140 },
	apron = { 90, 58, 38 },
	ember = { 226, 142, 58 },
	molten = { 255, 90, 30 },
	moltenHot = { 255, 160, 64 },
	gold = { 255, 208, 112 },
	mountain = { 59, 35, 53 },
	glass = { 140, 210, 255 },
}

return Palette
