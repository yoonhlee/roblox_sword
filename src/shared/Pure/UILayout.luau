--!strict
--[[
	UILayout — 화면 구역 배치 계산 (순수 함수, 통합 기획서 8-1절).

	입력: 화면에서 쓸 수 있는 영역의 실제 크기(px). 로블록스 위쪽 메뉴 줄과 노치는 이미 빠진 크기다
	(모든 ScreenGui 가 ScreenInsets = CoreUISafeInsets 를 쓴다). touch 는 휴대폰처럼 이동 컨트롤이 있는지.

	출력: 배율(scale)과 "디자인 칸" 단위의 구역 사각형. 화면 코드는 모든 ScreenGui 에 UIScale = scale 을 걸고,
	이 사각형 그대로 Position/Size 를 정한다. 그래서 구역끼리 겹치지 않는다는 것을 여기 테스트로 보장할 수 있다.

	화면 상태별로 동시에 보이는 구역:
	  로비   chips, menu, raceCluster, feedLobby, lobbyStatus  (+ 비워 둘 자리 joystick, jump)
	  대장간 chips, forgePanel   (이동 컨트롤은 숨긴다)
	  창     modal               (어둡게 덮고 맨 위)
	  경주   raceHud, raceAbility (+ joystick, jump) / 탈락 후 raceResult (이동 컨트롤 숨김)
]]

local UILayout = {}

export type Rect = { x: number, y: number, w: number, h: number }

export type Config = {
	referenceWidth: number,
	referenceHeight: number,
	minScale: number,
	maxScale: number,
	margin: number,
	gap: number,
	chipHeight: number,
	chipWidth: number,
	chipCount: number,
	menuButton: number,
	menuCount: number,
	raceButtonWidth: number,
	raceButtonHeight: number,
	raceStatusHeight: number,
	lobbyStatusWidth: number,
	lobbyStatusHeight: number,
	feedLineHeight: number,
	modalMaxWidth: number,
	forgeMaxWidth: number,
	raceHudWidth: number,
	raceHudHeight: number,
	abilitySize: number,
	resultWidth: number,
	resultHeight: number,
	joystickWidth: number,
	joystickHeight: number,
	jumpWidth: number,
	jumpHeight: number,
	minTouchPx: number,
}

export type Layout = {
	scale: number,
	width: number, -- 디자인 칸 단위 화면 크기
	height: number,
	touch: boolean,

	chips: Rect,
	menu: Rect,
	menuColumns: number, -- 1 = 세로 한 줄, 2 = 두 줄, 4 = 가로 한 줄
	raceCluster: Rect,
	feedLobby: Rect,
	lobbyStatus: Rect,
	forgePanel: Rect,
	modal: Rect,
	raceHud: Rect,
	raceAbility: Rect,
	raceResult: Rect,

	joystick: Rect, -- touch 가 false 면 크기 0
	jump: Rect,
}

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = math.max(0, w), h = math.max(0, h) }
end

function UILayout.overlaps(a: Rect, b: Rect): boolean
	if a.w <= 0 or a.h <= 0 or b.w <= 0 or b.h <= 0 then
		return false
	end
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function UILayout.inside(inner: Rect, width: number, height: number): boolean
	local eps = 1e-6
	return inner.x >= -eps
		and inner.y >= -eps
		and inner.x + inner.w <= width + eps
		and inner.y + inner.h <= height + eps
end

function UILayout.compute(realWidth: number, realHeight: number, touch: boolean, c: Config): Layout
	local scale = math.clamp(
		math.min(realWidth / c.referenceWidth, realHeight / c.referenceHeight),
		c.minScale,
		c.maxScale
	)
	local W = realWidth / scale
	local H = realHeight / scale
	local m = c.margin
	local g = c.gap

	-- 이동 컨트롤 자리 (실제 px → 디자인 칸)
	local joystick = if touch
		then rect(
			0,
			H - c.joystickHeight / scale,
			c.joystickWidth / scale,
			c.joystickHeight / scale
		)
		else rect(0, H, 0, 0)
	local jump = if touch
		then rect(
			W - c.jumpWidth / scale,
			H - c.jumpHeight / scale,
			c.jumpWidth / scale,
			c.jumpHeight / scale
		)
		else rect(W, H, 0, 0)

	-- 위쪽 왼쪽: 재화 칩 한 줄
	local chipsWidth = c.chipCount * c.chipWidth + (c.chipCount - 1) * g
	local chips = rect(m, m, chipsWidth, c.chipHeight)

	-- 왼쪽 메뉴: 칩 아래. 세로 한 줄 → 두 줄 → 가로 한 줄 순서로 들어가는 모양을 고른다.
	local menuTop = chips.y + chips.h + g
	local menuBottomLimit = (if touch then joystick.y else H) - g
	local b = c.menuButton
	local count = c.menuCount

	local function menuRect(columns: number): Rect
		local rows = math.ceil(count / columns)
		return rect(m, menuTop, columns * b + (columns - 1) * g, rows * b + (rows - 1) * g)
	end

	local menuColumns = 1
	local menu = menuRect(1)
	if menu.y + menu.h > menuBottomLimit then
		menuColumns = 2
		menu = menuRect(2)
		if menu.y + menu.h > menuBottomLimit then
			menuColumns = count
			menu = menuRect(count)
		end
	end

	-- 오른쪽 위: 경주 버튼 + 상태 한 줄
	local raceCluster = rect(
		W - m - c.raceButtonWidth,
		m,
		c.raceButtonWidth,
		c.raceButtonHeight + g + c.raceStatusHeight
	)

	-- 위쪽 가운데: 피드 한 줄 (왼쪽 칩·메뉴와 오른쪽 경주 버튼 사이)
	-- (메뉴는 어떤 모양이든 칩 줄보다 아래에서 시작하므로 칩 오른쪽이 기준이다.)
	local feedLeft = chips.x + chips.w + g
	local feedRight = raceCluster.x - g
	local feedLobby = rect(feedLeft, m, feedRight - feedLeft, c.feedLineHeight)

	-- 아래 가운데: 트레드밀 진행 막대 (조이스틱과 점프 버튼 사이)
	local bottomLeft = joystick.x + joystick.w + g
	local bottomRight = jump.x - g
	local statusWidth = math.min(c.lobbyStatusWidth, bottomRight - bottomLeft)
	local lobbyStatus = rect(
		bottomLeft + ((bottomRight - bottomLeft) - statusWidth) / 2,
		H - m - c.lobbyStatusHeight,
		statusWidth,
		c.lobbyStatusHeight
	)
	if not touch then
		lobbyStatus = rect(
			(W - c.lobbyStatusWidth) / 2,
			H - m - c.lobbyStatusHeight,
			c.lobbyStatusWidth,
			c.lobbyStatusHeight
		)
	end

	-- 대장간: 칩 아래 화면 대부분 (이동 컨트롤은 숨기므로 신경 쓰지 않는다)
	local forgeTop = chips.y + chips.h + g
	local forgeWidth = math.min(c.forgeMaxWidth, W - 2 * m)
	local forgePanel = rect((W - forgeWidth) / 2, forgeTop, forgeWidth, H - forgeTop - m)

	-- 큰 창 (확률표·검·기록·상점)
	local modalWidth = math.min(c.modalMaxWidth, W - 2 * m)
	local modal = rect((W - modalWidth) / 2, m, modalWidth, H - 2 * m)

	-- 경주
	local hudWidth = math.min(c.raceHudWidth, W - 2 * m)
	local raceHud = rect((W - hudWidth) / 2, m, hudWidth, c.raceHudHeight)
	local abilityRight = (if touch then jump.x else W - m) - g
	local raceAbility =
		rect(abilityRight - c.abilitySize, H - m - c.abilitySize, c.abilitySize, c.abilitySize)
	local resultWidth = math.min(c.resultWidth, W - 2 * m)
	local resultHeight = math.min(c.resultHeight, H - raceHud.y - raceHud.h - g - m)
	local raceResult = rect((W - resultWidth) / 2, H - m - resultHeight, resultWidth, resultHeight)

	return {
		scale = scale,
		width = W,
		height = H,
		touch = touch,
		chips = chips,
		menu = menu,
		menuColumns = menuColumns,
		raceCluster = raceCluster,
		feedLobby = feedLobby,
		lobbyStatus = lobbyStatus,
		forgePanel = forgePanel,
		modal = modal,
		raceHud = raceHud,
		raceAbility = raceAbility,
		raceResult = raceResult,
		joystick = joystick,
		jump = jump,
	}
end

-- 화면 상태별로 함께 보이는 구역 이름 (테스트와 ScreenManager 가 같은 목록을 쓴다)
UILayout.MODE_ZONES = {
	lobby = { "chips", "menu", "raceCluster", "feedLobby", "lobbyStatus", "joystick", "jump" },
	forge = { "chips", "forgePanel" },
	modal = { "modal" },
	race = { "raceHud", "raceAbility", "joystick", "jump" },
	raceOut = { "raceHud", "raceResult" },
} :: { [string]: { string } }

return UILayout
