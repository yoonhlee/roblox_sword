--!strict
--[[
	Theme — 화면에서 쓰는 색·글꼴·크기·움직임 (통합 기획서 8-1절).

	숫자 색표는 shared/Config/Palette 에 있고, 여기서는 Color3 로 바꿔 둔다.
	컨트롤러는 색 숫자를 직접 쓰지 않고 Theme 만 쓴다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")
local Palette = require(ConfigFolder:WaitForChild("Palette"))
local VisualConfig = require(ConfigFolder:WaitForChild("VisualConfig"))
local VisualLogic = require(Shared:WaitForChild("Pure"):WaitForChild("VisualLogic"))

local Theme = {}

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

Theme.rgb = rgb

local ui = Palette.UI

Theme.color = {
	bg = rgb(ui.bg),
	panel = rgb(ui.panel),
	sub = rgb(ui.sub),
	line = rgb(ui.line),
	text = rgb(ui.text),
	muted = rgb(ui.muted),
	ember = rgb(ui.ember),
	emberDark = rgb(ui.emberDark),
	ink = rgb(ui.ink),
	outline = rgb(ui.outline),
	disabled = rgb(ui.disabled),
	danger = rgb(ui.danger),
	gold = rgb(ui.gold),
	shard = rgb(ui.shard),
	ticket = rgb(ui.ticket),
	success = rgb(ui.success),
	keep = rgb(ui.keep),
	fail = rgb(ui.fail),
	protect = rgb(ui.protect),
	event = rgb(ui.event),
	white = Color3.new(1, 1, 1),
	black = Color3.new(0, 0, 0),
}

--[[
	글꼴. 제목·숫자는 둥글고 두꺼운 카툰체, 설명은 기본체 (결정 7).
	한글이 카툰 글꼴에 없으면 로블록스가 다른 글꼴로 대신 보여 준다 → Studio 에서 확인할 것.
]]
Theme.font = {
	display = Enum.Font.FredokaOne,
	body = Enum.Font.BuilderSans,
	bodyBold = Enum.Font.BuilderSansBold,
}

Theme.text = VisualConfig.Text

Theme.space = {
	xs = 4,
	sm = 8,
	md = 12,
	lg = 16,
	xl = 24,
}

Theme.radius = 10
Theme.radiusLarge = 14
-- 버튼 높이 (디자인 칸). 60 × 최소 배율 0.74 ≈ 44px. 목록 안의 줄 버튼은 52 (폰 대부분에서 44px 안팎).
Theme.touchHeight = 60
Theme.rowHeight = 52
Theme.strokeText = 2 -- 굵은 글자 테두리 두께

Theme.motion = {
	press = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	release = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	fade = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	slow = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
}

-- 검 등급 색
function Theme.rarityColor(rarity: string): Color3
	local values = Palette.RARITY[rarity]
	return if values then rgb(values) else Theme.color.muted
end

-- 레벨 색 단계 (쇠를 달구는 색, 결정 4)
function Theme.heatTier(level: number): Palette.HeatTier
	return VisualLogic.heatTier(level, Palette.HEAT_TIERS)
end

function Theme.heatColor(level: number): Color3
	return rgb(Theme.heatTier(level).rgb)
end

-- 같은 색을 조금 밝게(amount > 0) 또는 어둡게(amount < 0)
function Theme.shade(color: Color3, amount: number): Color3
	if amount >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), amount)
	end
	return color:Lerp(Color3.new(0, 0, 0), -amount)
end

return Theme
