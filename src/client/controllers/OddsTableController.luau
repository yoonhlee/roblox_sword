--!strict
--[[
	OddsTableController — 확률표 화면.

	강화 화면에서 언제든 열 수 있어야 한다(지시서 7절: 확률표는 상품 여부와
	관계없이 항상 열람 가능). 표시하는 값은 shared/Config/EnhanceTable 그대로다.

	이벤트 버프가 적용 중이면 상단에 배너로 알려 주고, 실제 적용된 최종 확률은
	강화 화면(서버가 내려 준 값)에서 확인하도록 안내한다.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))
local EnhanceTable = require(Shared:WaitForChild("Config"):WaitForChild("EnhanceTable"))

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
local COLUMN_WIDTHS = { 0.13, 0.17, 0.17, 0.17, 0.18, 0.18 }

local gui: ScreenGui
local panel: Frame
local scroller: ScrollingFrame
local titleLabel: TextLabel
local eventLabel: TextLabel
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

	-- 헤더
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	header.Position = UDim2.fromOffset(0, 54)
	header.Parent = panel

	local headerList = Instance.new("UIListLayout")
	headerList.FillDirection = Enum.FillDirection.Horizontal
	headerList.SortOrder = Enum.SortOrder.LayoutOrder
	headerList.VerticalAlignment = Enum.VerticalAlignment.Center
	headerList.Parent = header

	scroller = Instance.new("ScrollingFrame")
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Position = UDim2.fromOffset(0, 54 + ROW_HEIGHT + 4)
	scroller.Size = UDim2.new(1, 0, 1, -(54 + ROW_HEIGHT + 4))
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
		"ui.column.destroy",
		"ui.column.cost",
		"ui.column.sell",
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
	local data = ClientState.getData()
	local currentLevel = if data then data.weapon.level else -1

	titleLabel.Text = Locale.get(language, "ui.oddsTableTitle")
	closeButton.Text = Locale.get(language, "ui.close")

	local odds = ClientState.getOdds()
	if odds and odds.eventName then
		eventLabel.Visible = true
		eventLabel.Text = Locale.get(language, "ui.eventActive", Locale.get(language, odds.eventName))
	else
		eventLabel.Visible = false
	end

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

		local entry = EnhanceTable.Odds[level]
		makeCell(row, 1, Format.level(level), textColor)

		if entry then
			makeCell(row, 2, Format.percent(entry.success), textColor)
			makeCell(row, 3, Format.percent(entry.keep), COLOR_MUTED)
			makeCell(
				row,
				4,
				Format.percent(entry.destroy),
				if entry.destroy > 0 then Color3.fromRGB(255, 130, 118) else COLOR_MUTED
			)
			makeCell(row, 5, Format.comma(entry.cost), COLOR_MUTED)
		else
			makeCell(row, 2, "-", COLOR_MUTED)
			makeCell(row, 3, "-", COLOR_MUTED)
			makeCell(row, 4, "-", COLOR_MUTED)
			makeCell(row, 5, "-", COLOR_MUTED)
		end

		makeCell(row, 6, Format.comma(EnhanceTable.SellValue[level] or 0), COLOR_MUTED)
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
