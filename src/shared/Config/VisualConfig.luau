--!strict
--[[
	VisualConfig — 화면 배치와 연출 시간 (통합 기획서 8-1절). 전부 추천치·기술 값이다.

	배치 단위: "디자인 칸". 실제 화면 크기에 맞춰 배율(scale)을 곱한다.
	기준 화면(REFERENCE)은 휴대폰 가로에서 로블록스 위쪽 메뉴 줄을 뺀 크기쯤이다.
]]

local VisualConfig = {}

VisualConfig.Layout = {
	referenceWidth = 860,
	referenceHeight = 360,
	minScale = 0.74, -- 이보다 작게 줄이지 않는다 (버튼 60칸 × 0.74 ≈ 44px)
	maxScale = 1.5,

	margin = 12, -- 화면 가장자리 여백
	gap = 8,

	chipHeight = 36,
	chipWidth = 116,
	chipCount = 3, -- 골드 · 파편 · 방지권

	menuButton = 60, -- 메뉴 버튼 한 변
	menuCount = 4, -- 대장간 · 검 · 도감 · 상점

	raceButtonWidth = 180,
	raceButtonHeight = 60,
	raceStatusHeight = 44,

	lobbyStatusWidth = 220, -- 트레드밀 진행 막대
	lobbyStatusHeight = 44,
	feedLineHeight = 36,

	modalMaxWidth = 720,
	forgeMaxWidth = 900,

	raceHudWidth = 520,
	raceHudHeight = 76,
	abilitySize = 72, -- 특수 능력 버튼 자리 (D16, 지금은 숨김)
	resultWidth = 420,
	resultHeight = 232,

	-- 휴대폰 이동 컨트롤 자리 (실제 화면 px). 로비·경주 중에는 이 자리를 비운다.
	joystickWidth = 280,
	joystickHeight = 180,
	jumpWidth = 200,
	jumpHeight = 190,

	minTouchPx = 44, -- 가장 작은 버튼의 실제 크기
}

-- 강화 결과 연출 길이 (초). 레벨이 높을수록 길다. 화면을 한 번 더 누르면 건너뛴다.
VisualConfig.Reveal = {
	{ minLevel = 0, seconds = 0.5, strikes = 1 },
	{ minLevel = 10, seconds = 1.0, strikes = 2 },
	{ minLevel = 15, seconds = 2.0, strikes = 3 },
}

-- 글자 크기 단계 (디자인 칸). 가장 작은 단계 × minScale 이 12px 밑으로 내려가지 않게 17 이상 (17 × 0.74 ≈ 12.6).
VisualConfig.Text = {
	small = 17,
	body = 18,
	label = 20,
	title = 26,
	big = 34,
	huge = 96,
}

return VisualConfig
