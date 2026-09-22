--!strict
--[[
	CollectionController — 도감 / 업적 / 랭킹을 탭 하나로 묶은 화면.

	세 화면을 따로 만들면 코드가 세 배가 되고 모바일에서 버튼도 자리를 잃는다.
	한 패널 안에서 탭으로 바꾸는 편이 화면도 코드도 단순하다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))
local Weapons = require(Shared:WaitForChild("Config"):WaitForChild("Weapons"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local CollectionController = {}
CollectionController.Name = "CollectionController"

local COLOR_PANEL = Color3.fromRGB(34, 30, 38)
local COLOR_ROW = Color3.fromRGB(44, 39, 50)
local COLOR_TEXT = Color3.fromRGB(240, 236, 230)
local COLOR_MUTED = Color3.fromRGB(120, 114, 126)
local COLOR_ACCENT = Color3.fromRGB(226, 142, 58)

local TOUCH_MIN = 44

type Tab = "codex" | "achv" | "rank" | "settings"

local gui: ScreenGui
local panel: Frame
local scroller: ScrollingFrame
local tabButtons: { [string]: TextButton } = {}
local rankToggle: TextButton
local closeButton: TextButton

local codexRemote: RemoteFunction
local boardRemote: RemoteFunction
local settingRemote: RemoteFunction
local settingsRow: Frame
local sfxButton: TextButton
local languageButton: TextButton

local activeTab: Tab = "codex"
local rankKind = "level"

local function makeRow(text: string, color: Color3, order: number)
	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = COLOR_ROW
	label.BackgroundTransparency = 0.4
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, 0, 0, 26)
	label.Text = "  " .. text
	label.LayoutOrder = order
	label.Parent = scroller

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
end

local function clearRows()
	for _, child in scroller:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function renderCodex()
	local language = ClientState.getLanguage()

	local ok, response = pcall(function()
		return codexRemote:InvokeServer()
	end)

	clearRows()

	if not ok or type(response) ~= "table" or response.entries == nil then
		makeRow(Locale.get(language, "error.not_ready"), COLOR_MUTED, 1)
		return
	end

	for index, entry in response.entries do
		local weapon = Weapons.get(entry.weaponId)
		local name = if weapon then Locale.get(language, weapon.nameKey) else entry.weaponId

		local text = Locale.get(language, "ui.codexRow", name, entry.milestone)
		if not entry.unlocked then
			text ..= `  ({Locale.get(language, "ui.locked")})`
		end

		makeRow(text, if entry.unlocked then COLOR_TEXT else COLOR_MUTED, index)
	end
end

local function renderAchievements()
	local language = ClientState.getLanguage()

	local ok, response = pcall(function()
		return codexRemote:InvokeServer()
	end)

	clearRows()

	if not ok or type(response) ~= "table" or response.achievements == nil then
		makeRow(Locale.get(language, "error.not_ready"), COLOR_MUTED, 1)
		return
	end

	for index, entry in response.achievements do
		local text = Locale.get(language, `achv.{entry.id}.name`)
			.. "  ·  "
			.. Locale.get(language, "ui.reward", Format.comma(entry.gold))

		if not entry.unlocked then
			text ..= `  ({Locale.get(language, "ui.locked")})`
		end

		makeRow(text, if entry.unlocked then COLOR_ACCENT else COLOR_MUTED, index)
	end
end

local function renderRanking()
	local language = ClientState.getLanguage()

	rankToggle.Text = Locale.get(language, `ui.rank.{rankKind}`)

	local ok, entries = pcall(function()
		return boardRemote:InvokeServer(rankKind)
	end)

	clearRows()

	if not ok or type(entries) ~= "table" or #entries == 0 then
		makeRow(Locale.get(language, "ui.rank.empty"), COLOR_MUTED, 1)
		return
	end

	local myUserId = Players.LocalPlayer.UserId

	for index, entry in entries do
		local value = if rankKind == "level"
			then Format.level(entry.value)
			else tostring(entry.value)

		makeRow(
			Locale.get(language, "ui.rank.row", entry.rank, entry.name, value),
			if entry.userId == myUserId then COLOR_ACCENT else COLOR_TEXT,
			index
		)
	end
end

local function applySetting(key: string, value: any)
	task.spawn(function()
		pcall(function()
			settingRemote:InvokeServer(key, value)
		end)
	end)
end

local function renderSettings()
	local language = ClientState.getLanguage()
	local data = ClientState.getData()

	clearRows()

	if data == nil then
		makeRow(Locale.get(language, "error.not_ready"), COLOR_MUTED, 1)
		return
	end

	sfxButton.Text = Locale.get(language, if data.settings.sfx then "ui.sfxOn" else "ui.sfxOff")
	sfxButton.TextColor3 = if data.settings.sfx then COLOR_ACCENT else COLOR_MUTED
	languageButton.Text = Locale.get(language, "ui.language")
end

local function refresh()
	local language = ClientState.getLanguage()

	for key, button in tabButtons do
		button.Text = Locale.get(language, `ui.tab.{key}`)
		button.TextColor3 = if key == activeTab then COLOR_ACCENT else COLOR_MUTED
	end

	closeButton.Text = Locale.get(language, "ui.close")
	rankToggle.Visible = activeTab == "rank"
	settingsRow.Visible = activeTab == "settings"

	if activeTab == "settings" then
		renderSettings()
		return
	end

	clearRows()
	makeRow("...", COLOR_MUTED, 0)

	task.spawn(function()
		if activeTab == "codex" then
			renderCodex()
		elseif activeTab == "achv" then
			renderAchievements()
		else
			renderRanking()
		end
	end)
end

local function makeButton(parent: Instance, props: { [string]: any }): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = COLOR_ROW
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = COLOR_TEXT
	button.TextSize = 15
	button.Size = UDim2.new(1, 0, 0, TOUCH_MIN)
	button.Text = ""
	for key, value in props do
		(button :: any)[key] = value
	end
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	return button
end

local function build()
	local player = Players.LocalPlayer

	gui = Instance.new("ScreenGui")
	gui.Name = "ForgeRecords"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 12
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local dim = Instance.new("TextButton")
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Parent = gui

	panel = Instance.new("Frame")
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

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = panel

	-- 탭 줄
	local tabRow = Instance.new("Frame")
	tabRow.BackgroundTransparency = 1
	tabRow.Size = UDim2.new(1, 0, 0, TOUCH_MIN)
	tabRow.LayoutOrder = 1
	tabRow.Parent = panel

	local tabList = Instance.new("UIListLayout")
	tabList.FillDirection = Enum.FillDirection.Horizontal
	tabList.SortOrder = Enum.SortOrder.LayoutOrder
	tabList.Padding = UDim.new(0, 6)
	tabList.Parent = tabRow

	local order = 0
	for _, key in { "codex", "achv", "rank", "settings" } do
		order += 1
		local button = makeButton(tabRow, {
			Size = UDim2.new(0.25, -5, 1, 0),
			TextSize = 13,
			LayoutOrder = order,
		})
		button.Activated:Connect(function()
			activeTab = key :: Tab
			refresh()
		end)
		tabButtons[key] = button
	end

	rankToggle = makeButton(panel, {
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		Visible = false,
		LayoutOrder = 2,
	})
	rankToggle.Activated:Connect(function()
		rankKind = if rankKind == "level" then "rating" else "level"
		refresh()
	end)

	-- 설정 탭에서만 보이는 줄
	settingsRow = Instance.new("Frame")
	settingsRow.BackgroundTransparency = 1
	settingsRow.Size = UDim2.new(1, 0, 0, TOUCH_MIN)
	settingsRow.Visible = false
	settingsRow.LayoutOrder = 2
	settingsRow.Parent = panel

	local settingsList = Instance.new("UIListLayout")
	settingsList.FillDirection = Enum.FillDirection.Horizontal
	settingsList.SortOrder = Enum.SortOrder.LayoutOrder
	settingsList.Padding = UDim.new(0, 8)
	settingsList.Parent = settingsRow

	sfxButton = makeButton(settingsRow, {
		Size = UDim2.new(0.5, -4, 1, 0),
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 1,
	})
	languageButton = makeButton(settingsRow, {
		Size = UDim2.new(0.5, -4, 1, 0),
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 2,
	})

	sfxButton.Activated:Connect(function()
		local data = ClientState.getData()
		if data then
			applySetting("sfx", not data.settings.sfx)
		end
	end)

	languageButton.Activated:Connect(function()
		local next_ = if ClientState.getLanguage() == "ko" then "en" else "ko"
		applySetting("language", next_)
	end)

	scroller = Instance.new("ScrollingFrame")
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Size = UDim2.new(1, 0, 1, -150)
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ScrollBarThickness = 4
	scroller.LayoutOrder = 3
	scroller.Parent = panel

	local scrollList = Instance.new("UIListLayout")
	scrollList.FillDirection = Enum.FillDirection.Vertical
	scrollList.SortOrder = Enum.SortOrder.LayoutOrder
	scrollList.Padding = UDim.new(0, 3)
	scrollList.Parent = scroller

	closeButton = makeButton(panel, { LayoutOrder = 4 })
	closeButton.Activated:Connect(function()
		gui.Enabled = false
	end)
	dim.Activated:Connect(function()
		gui.Enabled = false
	end)
end

function CollectionController.toggle()
	if gui.Enabled then
		gui.Enabled = false
		return
	end

	gui.Enabled = true
	refresh()
end

function CollectionController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	codexRemote = remotesFolder:WaitForChild(Remotes.Functions.GetCodex) :: RemoteFunction
	boardRemote = remotesFolder:WaitForChild(Remotes.Functions.GetLeaderboard) :: RemoteFunction
	settingRemote = remotesFolder:WaitForChild(Remotes.Functions.SetSetting) :: RemoteFunction
end

function CollectionController.Start()
	-- 설정을 바꾸면 서버가 데이터를 다시 내려 주므로, 그때 화면을 갱신한다.
	ClientState.onChanged(function()
		if gui.Enabled and activeTab == "settings" then
			renderSettings()
		end
	end)
end

return CollectionController
