--!strict
--[[
	ForgeLayout — 대장간 화면 안쪽 배치 (디자인 칸).

	대장간 패널(UILayout 의 forgePanel) 하나를 왼쪽 무대(검 미리보기·레벨·피드)와
	오른쪽 조작부(확률·방지권·비용·강화 버튼)로 나눈다. 피드는 다른 ScreenGui(FeedController)가
	그리므로 화면 전체 기준 위치(feedAbsolute)도 같이 돌려준다.
]]

local ForgeLayout = {}

export type Rect = { x: number, y: number, w: number, h: number }

export type Result = {
	padding: number,
	left: Rect, -- 패널 안 좌표
	stage: Rect, -- 검 미리보기 + 레벨 (패널 안 좌표)
	feed: Rect, -- 패널 안 좌표
	feedAbsolute: Rect, -- 화면 전체 좌표
	right: Rect, -- 패널 안 좌표
}

ForgeLayout.NAME_ROW = 40

function ForgeLayout.compute(panel: Rect): Result
	local pad = 16
	local leftWidth = math.floor(panel.w * 0.38)
	local innerHeight = panel.h - 2 * pad

	local left = { x = pad, y = pad, w = leftWidth - pad, h = innerHeight }
	local feedHeight = math.clamp(math.floor(panel.h * 0.3), 84, 150)
	local feed = { x = pad, y = panel.h - pad - feedHeight, w = left.w, h = feedHeight }
	local stageTop = left.y + ForgeLayout.NAME_ROW + 6
	local stage = { x = pad, y = stageTop, w = left.w, h = math.max(60, feed.y - 8 - stageTop) }
	local right =
		{ x = leftWidth + pad, y = pad, w = panel.w - leftWidth - 2 * pad, h = innerHeight }

	return {
		padding = pad,
		left = left,
		stage = stage,
		feed = feed,
		feedAbsolute = { x = panel.x + feed.x, y = panel.y + feed.y, w = feed.w, h = feed.h },
		right = right,
	}
end

return ForgeLayout
