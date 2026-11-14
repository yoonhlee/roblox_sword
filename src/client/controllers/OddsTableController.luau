--!strict
--[[
	OddsTableController — 확률표 화면.

	강화 화면에서 언제든 열 수 있어야 한다(확률표는 상품 여부와 관계없이 항상 열람 가능).

	표에 보이는 값은 "지금 실제로 적용되는" 최종 확률과 비용이다.
	  - 기본값: shared/Config/EnhanceTable
	  - 확률 버프 이벤트가 있으면 성공 + / 유지 - (실패는 그대로)
	  - 방지권을 켜 두었고 방지권이 있으면 실패 0%, 그만큼 유지
	  - 비용에는 가진 검 수 할증이 들어간다
	서버가 쓰는 것과 같은 Pure/EnhanceLogic 함수로 계산하므로 실제 판정과 어긋나지 않는다.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))
local EnhanceTable = require(Shared:WaitForChild("Config"):WaitForChild("EnhanceTable"))
local EnhanceLogic = require(Shared:WaitForChild("Pure"):WaitForChild("EnhanceLogic"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local OddsTableController = {}
OddsTableController.Name = "OddsTableController"

local COLOR_PANEL = Color3.fromRGB(34, 30, 38)
local COLOR_ROW = Color3.fromRGB(44, 39, 50)
local COLOR_ROW_CURRENT = Color3.fromRGB(78, 58, 34)
local COLOR_TEXT = Color3.fromRGB(240, 236, 230)
local COLOR_MUTED = Color3.fromRGB(168, 160, 172)
local COLOR_ACCENT = Color3.fromRGB(226, 142, 58)

local ROW_HEIGHT = 26
local HEADER_TOP = 86 -- 제목, 이벤트 줄, 방지권 안내 아래
local COLUMN_WIDTHS = { 0.16, 0.2, 0.2, 0.2, 0.24 }

local gui: ScreenGui
local panel: Frame
local scroller: ScrollingFrame
local titleLabel: TextLabel
local eventLabel: TextLabel
local noteLabel: TextLabel
local closeButton: TextButton
local rows: { [number]: Frame } = {}

local function makeCell(parent: Instance, index: number, text: string, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextColor3 = color
	label.Text = text
	label.Size = UDim2.new(COLUMN_WIDTHS[index], 0, 1, 0)
	label.LayoutOrder = index
	label.Parent = parent
	return label
end

local function makeRow(parent: Instance, order: number): Frame
	local row = Instance.new("Frame")
	row.BackgroundColor3 = COLOR_ROW
	row.BackgroundTransparency = 0.4
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.LayoutOrder = order
	row.Parent = parent

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = row

	return row
end

local function build()
	local player = Players.LocalPlayer

	gui = Instance.new("ScreenGui")
	gui.Name = "ForgeOddsTable"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Parent = gui

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = COLOR_PANEL
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.8, 0)
	panel.Parent = gui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(520, 640)
	sizeConstraint.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = panel

	titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 20
	titleLabel.TextColor3 = COLOR_TEXT
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Size = UDim2.new(1, -80, 0, 28)
	titleLabel.Position = UDim2.fromOffset(0, 0)
	titleLabel.Parent = panel

	closeButton = Instance.new("TextButton")
	closeButton.BackgroundColor3 = COLOR_ROW
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 14
	closeButton.TextColor3 = COLOR_TEXT
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 0, 0, 0)
	closeButton.Size = UDim2.fromOffset(72, 44) -- 최소 터치 영역 확보
	closeButton.Parent = panel

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeButton

	eventLabel = Instance.new("TextLabel")
	eventLabel.BackgroundTransparency = 1
	eventLabel.Font = Enum.Font.GothamMedium
	eventLabel.TextSize = 13
	eventLabel.TextColor3 = Color3.fromRGB(140, 210, 255)
	eventLabel.TextXAlignment = Enum.TextXAlignment.Left
	eventLabel.Size = UDim2.new(1, 0, 0, 18)
	eventLabel.Position = UDim2.fromOffset(0, 32)
	eventLabel.Visible = false
	eventLabel.Parent = panel

	-- 방지권이 확률을 어떻게 바꾸는지 숫자로 적어 둔다.
	noteLabel = Instance.new("TextLabel")
	noteLabel.BackgroundTransparency = 1
	noteLabel.Font = Enum.Font.GothamMedium
	noteLabel.TextSize = 12
	noteLabel.TextColor3 = COLOR_MUTED
	noteLabel.TextXAlignment = Enum.TextXAlignment.Left
	noteLabel.TextWrapped = true
	noteLabel.Size = UDim2.new(1, 0, 0, 30)
	noteLabel.Position = UDim2.fromOffset(0, 52)
	noteLabel.Text = ""
	noteLabel.Parent = panel

	-- 헤더
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	header.Position = UDim2.fromOffset(0, HEADER_TOP)
	header.Parent = panel

	local headerList = Instance.new("UIListLayout")
	headerList.FillDirection = Enum.FillDirection.Horizontal
	headerList.SortOrder = Enum.SortOrder.LayoutOrder
	headerList.VerticalAlignment = Enum.VerticalAlignment.Center
	headerList.Parent = header

	scroller = Instance.new("ScrollingFrame")
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Position = UDim2.fromOffset(0, HEADER_TOP + ROW_HEIGHT + 4)
	scroller.Size = UDim2.new(1, 0, 1, -(HEADER_TOP + ROW_HEIGHT + 4))
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ScrollBarThickness = 4
	scroller.Parent = panel

	local scrollList = Instance.new("UIListLayout")
	scrollList.FillDirection = Enum.FillDirection.Vertical
	scrollList.SortOrder = Enum.SortOrder.LayoutOrder
	scrollList.Padding = UDim.new(0, 2)
	scrollList.Parent = scroller

	closeButton.Activated:Connect(function()
		OddsTableController.close()
	end)
	dim.Activated:Connect(function()
		OddsTableController.close()
	end)

	-- 행은 한 번만 만들고 이후에는 텍스트만 갱신한다.
	local language = Locale.DEFAULT_LANGUAGE
	local headers = {
		"ui.column.level",
		"ui.column.success",
		"ui.column.keep",
		"ui.column.fail",
		"ui.column.cost",
	}
	for index, key in headers do
		makeCell(header, index, Locale.get(language, key), COLOR_MUTED)
	end

	for level = 0, EnhanceTable.MAX_LEVEL do
		rows[level] = makeRow(scroller, level + 1)
	end
end

local function refresh()
	local language = ClientState.getLanguage()
	local sword = ClientState.getEquipped()
	local currentLevel = if sword then sword.level else -1
	local swordCount = ClientState.getSwordCount()

	titleLabel.Text = Locale.get(language, "ui.oddsTableTitle")
	closeButton.Text = Locale.get(language, "ui.close")
	noteLabel.Text = Locale.get(language, "ui.protectNote")

	-- 진행 중인 확률 버프 이벤트 (성공 +, 그만큼 유지 -, 실패는 그대로)
	local event = ClientState.getLiveOps().event
	local buff = 0
	if type(event) == "table" and type(event.successBuff) == "number" then
		buff = event.successBuff
		eventLabel.Visible = true
		eventLabel.Text =
			Locale.get(language, "ui.eventActive", Locale.get(language, tostring(event.nameKey)))
	else
		eventLabel.Visible = false
	end

	local protectActive = ClientState.isProtectActive()

	for level = 0, EnhanceTable.MAX_LEVEL do
		local row = rows[level]
		row:ClearAllChildren()

		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Parent = row

		local isCurrent = level == currentLevel
		row.BackgroundColor3 = if isCurrent then COLOR_ROW_CURRENT else COLOR_ROW
		local textColor = if isCurrent then COLOR_ACCENT else COLOR_TEXT

		local base = EnhanceTable.Odds[level]
		makeCell(row, 1, Format.level(level), textColor)

		if base then
			-- 화면에 보이는 값은 "지금 실제로 적용되는" 최종 확률이다.
			local entry = EnhanceLogic.applyBuff(base, buff)
			if protectActive then
				entry = EnhanceLogic.applyProtect(entry)
			end

			local cost = EnhanceLogic.cost(
				level,
				swordCount,
				EnhanceTable.COST_BASE,
				EnhanceTable.SWORD_COUNT_EXPONENT
			)

			makeCell(row, 2, Format.percent(entry.success), textColor)
			makeCell(row, 3, Format.percent(entry.keep), COLOR_MUTED)
			makeCell(
				row,
				4,
				Format.percent(entry.fail),
				if entry.fail > 0 then Color3.fromRGB(255, 130, 118) else COLOR_MUTED
			)
			makeCell(row, 5, Format.comma(cost), COLOR_MUTED)
		else
			makeCell(row, 2, "-", COLOR_MUTED)
			makeCell(row, 3, "-", COLOR_MUTED)
			makeCell(row, 4, "-", COLOR_MUTED)
			makeCell(row, 5, "-", COLOR_MUTED)
		end
	end
end

function OddsTableController.open()
	refresh()
	gui.Enabled = true
end

function OddsTableController.close()
	gui.Enabled = false
end

function OddsTableController.toggle()
	if gui.Enabled then
		OddsTableController.close()
	else
		OddsTableController.open()
	end
end

function OddsTableController.Init()
	build()
end

function OddsTableController.Start()
	ClientState.onChanged(function()
		if gui.Enabled then
			refresh()
		end
	end)
end

return OddsTableController
