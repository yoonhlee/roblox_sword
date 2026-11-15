--!strict
--[[
	Components — 모든 화면이 쓰는 부품 (통합 기획서 8-1절 공통 규칙).

	- 닫기는 언제나 오른쪽 위 빨간 네모 X
	- 못 누르는 버튼은 회색 (setEnabled)
	- 모든 버튼은 누르면 살짝 작아졌다 돌아온다
	- 밝은 버튼의 글자는 흰색 + 검은 테두리 (결정 2)
	- 아이콘은 이미지 없이 도형으로 그린다 (결정 6). 이미지 ID 가 생기면 iconImage 자리에 넣는다.

	크기는 전부 "디자인 칸"이다. ScreenGui 의 UIScale 이 실제 화면에 맞춰 곱한다.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local Components = {}

export type ButtonStyle = "primary" | "secondary" | "danger" | "ghost"

local C = Theme.color

--------------------------------------------------------------------------------
-- 기본 장식
--------------------------------------------------------------------------------

function Components.corner(parent: Instance, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.radius)
	corner.Parent = parent
	return corner
end

function Components.round(parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = parent
	return corner
end

function Components.padding(parent: Instance, all: number, horizontal: number?)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, all)
	pad.PaddingBottom = UDim.new(0, all)
	pad.PaddingLeft = UDim.new(0, horizontal or all)
	pad.PaddingRight = UDim.new(0, horizontal or all)
	pad.Parent = parent
	return pad
end

-- 테두리 선 (Border) 또는 글자 테두리 (Contextual)
function Components.stroke(parent: Instance, color: Color3, thickness: number, onText: boolean?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = if onText
		then Enum.ApplyStrokeMode.Contextual
		else Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Components.list(
	parent: Instance,
	direction: "vertical" | "horizontal",
	gap: number,
	align: Enum.HorizontalAlignment?
): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = if direction == "vertical"
		then Enum.FillDirection.Vertical
		else Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	if align then
		layout.HorizontalAlignment = align
	end
	if direction == "horizontal" then
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	layout.Parent = parent
	return layout
end

-- 위는 밝고 아래로 갈수록 어두운 입체감 (버튼·칩)
function Components.bevel(parent: Instance, strength: number?)
	local gradient = Instance.new("UIGradient")
	local bottom = 1 - (strength or 0.25)
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(bottom, bottom, bottom))
	gradient.Rotation = 90
	gradient.Parent = parent
	return gradient
end

--------------------------------------------------------------------------------
-- 틀
--------------------------------------------------------------------------------

function Components.frame(parent: Instance, props: { [string]: any }?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	if props then
		for key, value in props do
			(frame :: any)[key] = value
		end
	end
	frame.Parent = parent
	return frame
end

-- 창 바탕: 어두운 쇳빛 + 얇은 테두리
function Components.panel(parent: Instance, props: { [string]: any }?): Frame
	local frame = Components.frame(parent, props)
	frame.BackgroundColor3 = C.panel
	frame.BackgroundTransparency = 0.04
	Components.corner(frame, Theme.radiusLarge)
	Components.stroke(frame, C.line, 1.5)
	return frame
end

--------------------------------------------------------------------------------
-- 글자
--------------------------------------------------------------------------------

export type LabelOptions = {
	text: string?,
	size: number?, -- Theme.text 의 값
	color: Color3?,
	font: Enum.Font?,
	outline: boolean?, -- 굵은 검은 테두리 (밝은 큰 글씨용)
	align: Enum.TextXAlignment?,
	wrap: boolean?,
	order: number?,
	height: number?,
}

function Components.label(parent: Instance, options: LabelOptions?): TextLabel
	local o = options or {}
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = o.font or Theme.font.body
	label.TextSize = o.size or Theme.text.body
	label.TextColor3 = o.color or C.text
	label.Text = o.text or ""
	label.TextXAlignment = o.align or Enum.TextXAlignment.Left
	label.TextWrapped = o.wrap == true
	label.TextTruncate = if o.wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd
	label.Size = UDim2.new(1, 0, 0, o.height or math.ceil((o.size or Theme.text.body) * 1.35))
	label.LayoutOrder = o.order or 0
	if o.outline then
		Components.stroke(label, C.outline, Theme.strokeText, true)
	end
	label.Parent = parent
	return label
end

--------------------------------------------------------------------------------
-- 버튼
--------------------------------------------------------------------------------

local STYLE_COLORS: { [string]: { bg: Color3, text: Color3, outline: boolean } } = {
	primary = { bg = C.ember, text = C.white, outline = true },
	secondary = { bg = C.sub, text = C.text, outline = false },
	danger = { bg = C.danger, text = C.white, outline = true },
	ghost = { bg = C.panel, text = C.muted, outline = false },
}

-- 누르면 살짝 작아졌다 돌아온다
local function attachPress(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Parent = button

	button.MouseButton1Down:Connect(function()
		if button.Active then
			TweenService:Create(scale, Theme.motion.press, { Scale = 0.94 }):Play()
		end
	end)
	local function release()
		TweenService:Create(scale, Theme.motion.release, { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
end

export type ButtonOptions = {
	text: string?,
	style: ButtonStyle?,
	size: number?,
	order: number?,
	height: number?,
	width: UDim?, -- 기본은 부모 너비 전체
}

function Components.button(parent: Instance, options: ButtonOptions?): TextButton
	local o = options or {}
	local style = o.style or "secondary"
	local colors = STYLE_COLORS[style]

	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = colors.bg
	button.Font = Theme.font.display
	button.TextSize = o.size or Theme.text.label
	button.TextColor3 = colors.text
	button.Text = o.text or ""
	button.TextWrapped = true
	button.Size = UDim2.new(o.width or UDim.new(1, 0), UDim.new(0, o.height or Theme.touchHeight))
	button.LayoutOrder = o.order or 0
	button:SetAttribute("Style", style)

	Components.corner(button)
	Components.bevel(button)
	Components.stroke(button, Theme.shade(colors.bg, -0.5), 2)
	if colors.outline then
		Components.stroke(button, C.outline, Theme.strokeText, true)
	end
	attachPress(button)

	button.Parent = parent
	return button
end

-- 버튼을 누를 수 있게/없게 (못 누르면 회색, 관례)
function Components.setEnabled(button: TextButton, enabled: boolean)
	local style = button:GetAttribute("Style")
	local colors = STYLE_COLORS[if type(style) == "string" then style else "secondary"]
		or STYLE_COLORS.secondary

	button.Active = enabled
	button.AutoButtonColor = false
	button.BackgroundColor3 = if enabled then colors.bg else C.disabled
	button.TextColor3 = if enabled then colors.text else C.muted
end

-- 버튼 스타일 바꾸기 (토글 켜짐/꺼짐 등)
function Components.setStyle(button: TextButton, style: ButtonStyle)
	button:SetAttribute("Style", style)
	Components.setEnabled(button, button.Active)
end

-- 오른쪽 위 빨간 네모 X (모든 창의 닫기, 관례)
function Components.closeButton(parent: Instance, onClose: () -> ()): TextButton
	local button = Components.button(
		parent,
		{ text = "X", style = "danger", size = Theme.text.title, height = 44 }
	)
	button.Size = UDim2.fromOffset(44, 44)
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -Theme.space.sm, 0, Theme.space.sm)
	button.ZIndex = 5
	button.Activated:Connect(onClose)
	return button
end

--------------------------------------------------------------------------------
-- 도형 아이콘 (이미지 없이)
--------------------------------------------------------------------------------

local function block(
	parent: Instance,
	color: Color3,
	x: number,
	y: number,
	w: number,
	h: number,
	rotation: number?
): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.Rotation = rotation or 0
	f.Parent = parent
	return f
end

export type Glyph =
	"coin"
	| "shard"
	| "ticket"
	| "anvil"
	| "sword"
	| "book"
	| "bag"
	| "flag"
	| "table"

--[[
	도형으로 그린 작은 아이콘. 정사각형 틀 안에 그린다.
	coin=골드(동그라미), shard=파편(마름모), ticket=방지권(방패 모양), anvil=대장간, sword=검,
	book=도감, bag=상점, flag=경주, table=확률표
]]
function Components.glyph(parent: Instance, kind: Glyph, color: Color3?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Glyph"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = holder
	holder.Parent = parent

	local main = color or C.text
	local dark = Theme.shade(main, -0.45)

	if kind == "coin" then
		local outer = block(holder, main, 0.5, 0.5, 0.8, 0.8)
		Components.round(outer)
		Components.stroke(outer, dark, 2)
		local inner = block(holder, Theme.shade(main, 0.25), 0.5, 0.5, 0.42, 0.42)
		Components.round(inner)
	elseif kind == "shard" then
		local gem = block(holder, main, 0.5, 0.5, 0.56, 0.56, 45)
		Components.stroke(gem, dark, 2)
		block(holder, Theme.shade(main, 0.35), 0.42, 0.42, 0.14, 0.14, 45)
	elseif kind == "ticket" then
		local top = block(holder, main, 0.5, 0.4, 0.66, 0.5)
		Components.corner(top, 4)
		local tip = block(holder, main, 0.5, 0.64, 0.46, 0.46, 45)
		tip.ZIndex = top.ZIndex
		block(holder, Theme.shade(main, 0.35), 0.5, 0.42, 0.1, 0.36)
	elseif kind == "anvil" then
		block(holder, main, 0.5, 0.36, 0.86, 0.18)
		block(holder, main, 0.5, 0.56, 0.3, 0.26)
		block(holder, main, 0.5, 0.78, 0.66, 0.16)
		block(holder, main, 0.12, 0.4, 0.14, 0.1)
	elseif kind == "sword" then
		block(holder, main, 0.5, 0.36, 0.13, 0.62)
		block(holder, Theme.shade(main, 0.3), 0.5, 0.36, 0.04, 0.56)
		block(holder, main, 0.5, 0.7, 0.5, 0.09)
		block(holder, dark, 0.5, 0.84, 0.1, 0.2)
	elseif kind == "book" then
		local left = block(holder, main, 0.3, 0.52, 0.36, 0.66)
		Components.corner(left, 3)
		local right = block(holder, Theme.shade(main, -0.15), 0.7, 0.52, 0.36, 0.66)
		Components.corner(right, 3)
		block(holder, dark, 0.5, 0.52, 0.05, 0.68)
	elseif kind == "bag" then
		local body = block(holder, main, 0.5, 0.6, 0.72, 0.6)
		Components.corner(body, 6)
		local handle = block(holder, Color3.new(0, 0, 0), 0.5, 0.26, 0.36, 0.24)
		handle.BackgroundTransparency = 1
		Components.corner(handle, 8)
		Components.stroke(handle, main, 3)
		block(holder, Theme.shade(main, 0.3), 0.5, 0.6, 0.18, 0.18, 45)
	elseif kind == "flag" then
		block(holder, dark, 0.28, 0.52, 0.07, 0.8)
		block(holder, main, 0.56, 0.3, 0.5, 0.32)
	elseif kind == "table" then
		local sheet = block(holder, main, 0.5, 0.5, 0.74, 0.74)
		Components.corner(sheet, 4)
		for row = 1, 3 do
			block(holder, dark, 0.5, 0.22 + row * 0.16, 0.56, 0.05)
		end
	end

	return holder
end

--[[
	메뉴 타일: 정사각형 버튼 안에 도형 아이콘 + 짧은 이름. 로비 왼쪽 메뉴와 대장간 아래 줄에 쓴다.
	size 는 한 변(디자인 칸). 글자는 가장 작은 단계(17)라 60칸 타일에 들어간다.
]]
function Components.tile(
	parent: Instance,
	glyph: Glyph,
	text: string,
	size: number,
	order: number?
): TextButton
	local button = Components.button(parent, { style = "secondary", order = order, height = size })
	button.Size = UDim2.fromOffset(size, size)
	button.Text = ""

	local icon = Components.frame(button, {
		Size = UDim2.new(0.56, 0, 0.56, 0),
		Position = UDim2.new(0.5, 0, 0, 3),
		AnchorPoint = Vector2.new(0.5, 0),
	})
	Components.glyph(icon, glyph, C.gold)
	Components.iconImage(icon, nil)

	local caption = Components.label(button, {
		text = text,
		size = Theme.text.small,
		font = Theme.font.bodyBold,
		align = Enum.TextXAlignment.Center,
	})
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0, 1)
	caption.Position = UDim2.new(0, 0, 1, -2)
	caption.Size = UDim2.new(1, 0, 0, 20)

	return button
end

-- 타일 이름 바꾸기 (언어 변경)
function Components.setTileText(button: TextButton, text: string)
	local caption = button:FindFirstChild("Caption")
	if caption and caption:IsA("TextLabel") then
		caption.Text = text
	end
end

-- 나중에 이미지 아이콘을 넣을 자리. assetId 가 비어 있으면 숨겨지고 도형 아이콘이 보인다.
function Components.iconImage(parent: Instance, assetId: string?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "IconImage"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = assetId or ""
	image.Visible = assetId ~= nil and assetId ~= ""
	image.ZIndex = 3
	image.Parent = parent
	return image
end

--------------------------------------------------------------------------------
-- 재화 칩 · 진행 막대 · 확률 막대 · 탭
--------------------------------------------------------------------------------

export type Chip = { frame: Frame, value: TextLabel }

-- 재화 칩: 도형 아이콘 + 숫자 (색·모양 고정)
function Components.chip(parent: Instance, glyph: Glyph, color: Color3): Chip
	local frame = Components.frame(parent, {
		BackgroundTransparency = 0.15,
		BackgroundColor3 = C.bg,
	})
	Components.corner(frame, 18)
	Components.stroke(frame, Theme.shade(color, -0.35), 2)

	local icon = Components.frame(frame, {
		Size = UDim2.new(0, 28, 0, 28),
		Position = UDim2.new(0, 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
	})
	Components.glyph(icon, glyph, color)

	local value = Components.label(frame, {
		font = Theme.font.display,
		size = Theme.text.label,
		color = Theme.color.white,
		outline = true,
	})
	value.Position = UDim2.fromOffset(38, 0)
	value.Size = UDim2.new(1, -44, 1, 0)

	return { frame = frame, value = value }
end

export type ProgressBar = { frame: Frame, fill: Frame, set: (ratio: number) -> () }

function Components.progressBar(parent: Instance, color: Color3, height: number?): ProgressBar
	local frame = Components.frame(parent, {
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.1,
		Size = UDim2.new(1, 0, 0, height or 14),
	})
	Components.round(frame)
	Components.stroke(frame, C.line, 1.5)

	local fill = Components.frame(frame, {
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(0, 1),
	})
	Components.round(fill)
	Components.bevel(fill, 0.3)

	local function set(ratio: number)
		fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	end

	return { frame = frame, fill = fill, set = set }
end

export type OddsBar = {
	frame: Frame,
	set: (success: number, keep: number, fail: number) -> (),
}

--[[
	강화 확률 막대: 성공(주황) · 유지(회색) · 실패(빨강) 세 칸이 비율대로 한 줄.
	방지권을 켜면 실패 칸이 줄어 사라지고 유지 칸이 늘어나는 게 움직임으로 보인다.
]]
function Components.oddsBar(parent: Instance, height: number?): OddsBar
	local frame = Components.frame(parent, {
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0,
		Size = UDim2.new(1, 0, 0, height or 22),
		ClipsDescendants = true,
	})
	Components.round(frame)
	Components.stroke(frame, C.line, 1.5)

	local inner = Components.frame(frame)
	local listLayout = Components.list(inner, "horizontal", 0)
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	local function segment(color: Color3, order: number): Frame
		local seg = Components.frame(inner, {
			BackgroundColor3 = color,
			BackgroundTransparency = 0,
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = order,
		})
		Components.bevel(seg, 0.3)
		return seg
	end

	local success = segment(C.success, 1)
	local keep = segment(C.keep, 2)
	local fail = segment(C.fail, 3)

	local function set(s: number, k: number, f: number)
		local total = math.max(1e-6, s + k + f)
		TweenService:Create(success, Theme.motion.fade, { Size = UDim2.fromScale(s / total, 1) })
			:Play()
		TweenService:Create(keep, Theme.motion.fade, { Size = UDim2.fromScale(k / total, 1) })
			:Play()
		TweenService:Create(fail, Theme.motion.fade, { Size = UDim2.fromScale(f / total, 1) })
			:Play()
	end

	return { frame = frame, set = set }
end

export type Tabs = {
	frame: Frame,
	buttons: { [string]: TextButton },
	select: (key: string) -> (),
}

function Components.tabs(parent: Instance, keys: { string }, onSelect: (key: string) -> ()): Tabs
	local frame = Components.frame(parent, { Size = UDim2.new(1, 0, 0, Theme.rowHeight) })
	Components.list(frame, "horizontal", Theme.space.sm)

	local buttons: { [string]: TextButton } = {}
	local function selectTab(key: string)
		for name, button in buttons do
			Components.setStyle(button, if name == key then "primary" else "ghost")
		end
	end

	for index, key in keys do
		local button = Components.button(frame, {
			style = "ghost",
			order = index,
			height = Theme.rowHeight,
			width = UDim.new(1 / #keys, -Theme.space.sm),
		})
		button.Activated:Connect(function()
			selectTab(key)
			onSelect(key)
		end)
		buttons[key] = button
	end

	return { frame = frame, buttons = buttons, select = selectTab }
end

-- 스크롤 목록
function Components.scroller(parent: Instance, gap: number?): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = C.line
	scroll.Parent = parent
	Components.list(scroll, "vertical", gap or Theme.space.sm)
	return scroll
end

-- 목록 안의 자식(레이아웃 제외)을 지운다
function Components.clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

--[[
	떠오르며 사라지는 글자 ("+100" 등). parent 안 (x, y) 에서 시작한다.
]]
function Components.floatText(
	parent: Instance,
	text: string,
	color: Color3,
	position: UDim2,
	size: number?
)
	local label = Components.label(parent, {
		text = text,
		font = Theme.font.display,
		size = size or Theme.text.title,
		color = color,
		outline = true,
		align = Enum.TextXAlignment.Center,
	})
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = UDim2.fromOffset(200, 40)
	label.ZIndex = 20

	local tween = TweenService:Create(
		label,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = position - UDim2.fromOffset(0, 46), TextTransparency = 1 }
	)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(1.2), { Transparency = 1 }):Play()
	end
	tween.Completed:Connect(function()
		label:Destroy()
	end)
	tween:Play()
end

return Components
