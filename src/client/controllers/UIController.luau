--!strict
--[[
	UIController — 강화 화면.

	Phase 1 의 "최소 UI": 중앙에 강화 레벨, 하단에 큰 강화 버튼, 확률/비용 표시.
	레이아웃과 연출은 Phase 2 에서 다듬는다.

	규칙:
	- 여기 있는 숫자는 전부 서버가 보내 준 값이다. 클라이언트가 계산하지 않는다.
	- 요청 중에는 버튼을 잠근다(중복 입력 방지).
	- 결과 연출은 서버 응답을 받은 뒤에만 시작한다.
	- 표시 문자열은 전부 Locale 키를 거친다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))
local Weapons = require(Shared:WaitForChild("Config"):WaitForChild("Weapons"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local FeedController = require(script.Parent:WaitForChild("FeedController"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local UIController = {}
UIController.Name = "UIController"

local COLOR_BG = Color3.fromRGB(24, 21, 26)
local COLOR_PANEL = Color3.fromRGB(34, 30, 38)
local COLOR_TEXT = Color3.fromRGB(240, 236, 230)
local COLOR_MUTED = Color3.fromRGB(168, 160, 172)
local COLOR_ACCENT = Color3.fromRGB(226, 142, 58)
local COLOR_DISABLED = Color3.fromRGB(72, 68, 76)

local TOUCH_MIN_HEIGHT = 44

local busy = false
local useProtect = false

local uiScale: UIScale
local goldLabel: TextLabel
local shardLabel: TextLabel
local ticketLabel: TextLabel
local weaponLabel: TextLabel
local levelLabel: TextLabel
local eventLabel: TextLabel
local oddsLabel: TextLabel
local costLabel: TextLabel
local statusLabel: TextLabel
local protectButton: TextButton
local enhanceButton: TextButton
local enhanceRemote: RemoteFunction

local function corner(parent: Instance, radius: number)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function makeLabel(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = COLOR_TEXT
	label.TextSize = 16
	label.Size = UDim2.new(1, 0, 0, 20)
	label.Text = ""
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, props: { [string]: any }): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = COLOR_PANEL
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = COLOR_TEXT
	button.TextSize = 18
	button.Text = ""
	for key, value in props do
		(button :: any)[key] = value
	end
	button.Parent = parent
	corner(button, 10)
	return button
end

-- 화면 크기에 따라 전체 UI 배율을 조정한다(모바일 우선).
local function applyScale()
	local camera = Workspace.CurrentCamera
	if camera == nil or uiScale == nil then
		return
	end

	local viewport = camera.ViewportSize
	local scale = math.clamp(math.min(viewport.X / 900, viewport.Y / 700), 0.75, 1.25)
	uiScale.Scale = scale
end

local function build()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "ForgeMain"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	uiScale = Instance.new("UIScale")
	uiScale.Parent = gui

	-- 상단 재화 바
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.BackgroundColor3 = COLOR_BG
	topBar.BackgroundTransparency = 0.25
	topBar.BorderSizePixel = 0
	topBar.Size = UDim2.new(1, 0, 0, 48)
	topBar.Position = UDim2.new(0, 0, 0, 0)
	topBar.Parent = gui

	local topList = Instance.new("UIListLayout")
	topList.FillDirection = Enum.FillDirection.Horizontal
	topList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	topList.VerticalAlignment = Enum.VerticalAlignment.Center
	topList.Padding = UDim.new(0, 16)
	topList.Parent = topBar

	local topPadding = Instance.new("UIPadding")
	topPadding.PaddingLeft = UDim.new(0, 16)
	topPadding.PaddingRight = UDim.new(0, 16)
	topPadding.Parent = topBar

	goldLabel = makeLabel(topBar, {
		Size = UDim2.new(0, 160, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR_ACCENT,
		Font = Enum.Font.GothamBold,
	})
	shardLabel = makeLabel(topBar, {
		Size = UDim2.new(0, 130, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR_MUTED,
	})
	ticketLabel = makeLabel(topBar, {
		Size = UDim2.new(0, 130, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR_MUTED,
	})

	-- 중앙: 무기와 강화 레벨
	local center = Instance.new("Frame")
	center.Name = "Center"
	center.BackgroundTransparency = 1
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.new(0.5, 0, 0.36, 0)
	center.Size = UDim2.new(0.9, 0, 0, 160)
	center.Parent = gui

	local centerList = Instance.new("UIListLayout")
	centerList.FillDirection = Enum.FillDirection.Vertical
	centerList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	centerList.VerticalAlignment = Enum.VerticalAlignment.Center
	centerList.Padding = UDim.new(0, 4)
	centerList.Parent = center

	weaponLabel = makeLabel(center, {
		Size = UDim2.new(1, 0, 0, 26),
		TextSize = 22,
		TextColor3 = COLOR_MUTED,
		LayoutOrder = 1,
	})
	levelLabel = makeLabel(center, {
		Size = UDim2.new(1, 0, 0, 84),
		TextSize = 72,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLOR_ACCENT,
		LayoutOrder = 2,
	})
	eventLabel = makeLabel(center, {
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 15,
		TextColor3 = Color3.fromRGB(140, 210, 255),
		LayoutOrder = 3,
		Visible = false,
	})

	-- 하단 패널
	local bottom = Instance.new("Frame")
	bottom.Name = "Bottom"
	bottom.BackgroundColor3 = COLOR_PANEL
	bottom.BackgroundTransparency = 0.1
	bottom.BorderSizePixel = 0
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.Position = UDim2.new(0.5, 0, 1, -12)
	bottom.Size = UDim2.new(1, -24, 0, 208)
	bottom.Parent = gui
	corner(bottom, 14)

	local bottomSize = Instance.new("UISizeConstraint")
	bottomSize.MaxSize = Vector2.new(560, math.huge)
	bottomSize.Parent = bottom

	local bottomPadding = Instance.new("UIPadding")
	bottomPadding.PaddingTop = UDim.new(0, 12)
	bottomPadding.PaddingBottom = UDim.new(0, 12)
	bottomPadding.PaddingLeft = UDim.new(0, 14)
	bottomPadding.PaddingRight = UDim.new(0, 14)
	bottomPadding.Parent = bottom

	local bottomList = Instance.new("UIListLayout")
	bottomList.FillDirection = Enum.FillDirection.Vertical
	bottomList.SortOrder = Enum.SortOrder.LayoutOrder
	bottomList.Padding = UDim.new(0, 6)
	bottomList.Parent = bottom

	oddsLabel = makeLabel(bottom, {
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 17,
		LayoutOrder = 1,
	})
	costLabel = makeLabel(bottom, {
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 15,
		TextColor3 = COLOR_MUTED,
		LayoutOrder = 2,
	})
	protectButton = makeButton(bottom, {
		Size = UDim2.new(1, 0, 0, TOUCH_MIN_HEIGHT),
		TextSize = 16,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 3,
	})
	enhanceButton = makeButton(bottom, {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = COLOR_ACCENT,
		TextColor3 = Color3.fromRGB(24, 18, 10),
		TextSize = 24,
		LayoutOrder = 4,
	})
	statusLabel = makeLabel(bottom, {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 14,
		TextColor3 = Color3.fromRGB(255, 140, 130),
		LayoutOrder = 5,
	})

	applyScale()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end
end

local function weaponDisplayName(language: string, data: any): string
	if data.weapon.customName and data.weapon.customName ~= "" then
		return data.weapon.customName
	end

	local info = Weapons.get(data.weapon.id)
	if info == nil then
		return data.weapon.id
	end
	return Locale.get(language, info.nameKey)
end

local function render()
	local language = ClientState.getLanguage()
	local data = ClientState.getData()

	if data == nil then
		enhanceButton.Text = Locale.get(language, "ui.loading")
		enhanceButton.BackgroundColor3 = COLOR_DISABLED
		enhanceButton.Active = false
		return
	end

	goldLabel.Text = Locale.get(language, "ui.gold", Format.comma(data.gold))
	shardLabel.Text = Locale.get(language, "ui.shards", Format.comma(data.shards))
	ticketLabel.Text = Locale.get(language, "ui.tickets", data.protectTickets)

	weaponLabel.Text = weaponDisplayName(language, data)
	levelLabel.Text = Locale.get(language, "ui.level", data.weapon.level)

	protectButton.Text = `{if useProtect then "[v]" else "[ ]"} {Locale.get(language, "ui.useProtect")} ({data.protectTickets})`
	protectButton.TextColor3 = if useProtect then COLOR_ACCENT else COLOR_MUTED

	local odds = ClientState.getOdds()

	if odds == nil then
		oddsLabel.Text = ""
		costLabel.Text = ""
		eventLabel.Visible = false
		return
	end

	eventLabel.Visible = odds.eventName ~= nil
	if odds.eventName ~= nil then
		eventLabel.Text = Locale.get(language, odds.eventName)
	end

	-- 최대 레벨이면 강화할 수 없다.
	if odds.cost <= 0 then
		oddsLabel.Text = Locale.get(language, "ui.maxLevel")
		costLabel.Text = ""
		enhanceButton.Text = Locale.get(language, "ui.maxLevel")
		enhanceButton.BackgroundColor3 = COLOR_DISABLED
		enhanceButton.Active = false
		return
	end

	oddsLabel.Text = Locale.get(
		language,
		"ui.odds",
		Format.percent(odds.success),
		Format.percent(odds.keep),
		Format.percent(odds.destroy)
	)
	costLabel.Text = Locale.get(language, "ui.cost", Format.comma(odds.cost))

	if busy then
		enhanceButton.Text = Locale.get(language, "ui.enhancing")
		enhanceButton.BackgroundColor3 = COLOR_DISABLED
		enhanceButton.Active = false
	else
		local affordable = data.gold >= odds.cost
		enhanceButton.Text = Locale.get(language, "ui.enhance")
		enhanceButton.BackgroundColor3 = if affordable then COLOR_ACCENT else COLOR_DISABLED
		enhanceButton.Active = affordable
	end
end

local function requestEnhance()
	if busy then
		return
	end

	local odds = ClientState.getOdds()
	local data = ClientState.getData()
	if odds == nil or data == nil or odds.cost <= 0 then
		return
	end

	busy = true
	statusLabel.Text = ""
	render()

	local ok, response = pcall(function()
		return enhanceRemote:InvokeServer(useProtect)
	end)

	busy = false

	local language = ClientState.getLanguage()

	if not ok or type(response) ~= "table" then
		statusLabel.Text = Locale.get(language, "error.unknown")
		render()
		return
	end

	if response.ok ~= true then
		statusLabel.Text = Locale.get(language, `error.{tostring(response.reason)}`)
		render()
		return
	end

	-- 서버 응답을 받은 뒤에만 연출을 시작한다.
	ClientState.setOdds(response.odds)
	FeedController.pushOutcome(response.result)
	SoundController.play(response.result)
	render()
end

function UIController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	enhanceRemote = remotesFolder:WaitForChild(Remotes.Functions.Enhance) :: RemoteFunction

	local dataChanged = remotesFolder:WaitForChild(Remotes.Events.DataChanged) :: RemoteEvent
	dataChanged.OnClientEvent:Connect(function(data: any)
		if type(data) == "table" then
			ClientState.setData(data)
		end
	end)

	ClientState.onChanged(render)

	enhanceButton.Activated:Connect(function()
		task.spawn(requestEnhance)
	end)

	protectButton.Activated:Connect(function()
		useProtect = not useProtect
		SoundController.play("click")
		render()
	end)

	render()
end

function UIController.Start()
	-- 접속 직후 현재 상태를 한 번 받아 온다.
	-- (DataChanged 복제가 이 컨트롤러보다 먼저 도착했을 수도 있으므로 보정용으로도 쓴다)
	task.spawn(function()
		local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
		local stateRemote = remotesFolder:WaitForChild(Remotes.Functions.GetState) :: RemoteFunction

		for _ = 1, 30 do
			local ok, response = pcall(function()
				return stateRemote:InvokeServer()
			end)

			if ok and type(response) == "table" and response.ok == true then
				ClientState.setData(response.data)
				ClientState.setOdds(response.odds)
				return
			end

			task.wait(1) -- 프로필 로드가 끝날 때까지 기다린다.
		end

		warn("[UIController] 상태를 받아 오지 못했습니다")
	end)
end

return UIController
