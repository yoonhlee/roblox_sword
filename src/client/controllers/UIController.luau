--!strict
--[[
	UIController — 강화 화면.

	규칙:
	- 여기 있는 숫자는 전부 서버가 보내 준 값이다. 클라이언트가 계산하지 않는다.
	- 요청 중에는 버튼을 잠근다(중복 입력 방지).
	- 결과 연출은 서버 응답을 받은 뒤에만 시작한다.
	- 표시 문자열은 전부 Locale 키를 거친다.
	- 터치 영역은 44px 이상, 배율은 UIScale 로 화면 크기에 맞춘다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))

local ConfigFolder = Shared:WaitForChild("Config")
local Weapons = require(ConfigFolder:WaitForChild("Weapons"))
local EnhanceTable = require(ConfigFolder:WaitForChild("EnhanceTable"))
local EnhanceLogic = require(Shared:WaitForChild("Pure"):WaitForChild("EnhanceLogic"))

local controllers = script.Parent
local ClientState = require(controllers.Parent:WaitForChild("ClientState"))
local FeedController = require(controllers:WaitForChild("FeedController"))
local SoundController = require(controllers:WaitForChild("SoundController"))
local EffectsController = require(controllers:WaitForChild("EffectsController"))
local OddsTableController = require(controllers:WaitForChild("OddsTableController"))
local ShopController = require(controllers:WaitForChild("ShopController"))
local SwordController = require(controllers:WaitForChild("SwordController"))
local CollectionController = require(controllers:WaitForChild("CollectionController"))

local UIController = {}
UIController.Name = "UIController"

local COLOR_BG = Color3.fromRGB(24, 21, 26)
local COLOR_PANEL = Color3.fromRGB(34, 30, 38)
local COLOR_SUB = Color3.fromRGB(52, 46, 58)
local COLOR_TEXT = Color3.fromRGB(240, 236, 230)
local COLOR_MUTED = Color3.fromRGB(168, 160, 172)
local COLOR_ACCENT = Color3.fromRGB(226, 142, 58)
local COLOR_DISABLED = Color3.fromRGB(72, 68, 76)

local TOUCH_MIN = 44 -- 최소 터치 영역(px)
local NARROW_WIDTH = 700

local busy = false

local gui: ScreenGui
local uiScale: UIScale
local goldLabel: TextLabel
local shardLabel: TextLabel
local ticketLabel: TextLabel
local centerFrame: Frame
local weaponButton: TextButton
local renamePanel: Frame
local renameBox: TextBox
local renameConfirm: TextButton
local renameCancel: TextButton
local levelLabel: TextLabel
local eventLabel: TextLabel
local bottomPanel: Frame
local oddsLabel: TextLabel
local costLabel: TextLabel
local statusLabel: TextLabel
local bannerLabel: TextLabel
local hintLabel: TextLabel
local protectButton: TextButton
local oddsTableButton: TextButton
local swordsButton: TextButton
local shopButton: TextButton
local recordsButton: TextButton
local enhanceButton: TextButton

local enhanceRemote: RemoteFunction
local renameRemote: RemoteFunction

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
	button.BackgroundColor3 = COLOR_SUB
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = COLOR_TEXT
	button.TextSize = 16
	button.Text = ""
	for key, value in props do
		(button :: any)[key] = value
	end
	button.Parent = parent
	corner(button, 10)
	return button
end

-- 화면 크기에 따라 전체 UI 배율과 세로/가로 배치를 조정한다(모바일 우선).
local function applyLayout()
	local camera = Workspace.CurrentCamera
	if camera == nil or uiScale == nil then
		return
	end

	local viewport = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(viewport.X / 900, viewport.Y / 760), 0.7, 1.25)

	local isNarrow = viewport.X < NARROW_WIDTH
	-- 좁은 화면에서는 피드가 위쪽을 차지하므로 무기를 조금 아래로 내린다.
	centerFrame.Position = UDim2.new(0.5, 0, if isNarrow then 0.44 else 0.36, 0)
end

local function build()
	local player = Players.LocalPlayer

	gui = Instance.new("ScreenGui")
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
	topBar.Parent = gui

	local topList = Instance.new("UIListLayout")
	topList.FillDirection = Enum.FillDirection.Horizontal
	topList.VerticalAlignment = Enum.VerticalAlignment.Center
	topList.Padding = UDim.new(0, 14)
	topList.Parent = topBar

	local topPadding = Instance.new("UIPadding")
	topPadding.PaddingLeft = UDim.new(0, 16)
	topPadding.PaddingRight = UDim.new(0, 16)
	topPadding.Parent = topBar

	goldLabel = makeLabel(topBar, {
		Size = UDim2.new(0, 150, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR_ACCENT,
		Font = Enum.Font.GothamBold,
		LayoutOrder = 1,
	})
	shardLabel = makeLabel(topBar, {
		Size = UDim2.new(0, 120, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR_MUTED,
		LayoutOrder = 2,
	})
	ticketLabel = makeLabel(topBar, {
		Size = UDim2.new(0, 150, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR_MUTED,
		LayoutOrder = 3,
	})

	-- 공지 / 점검 배너 (내용이 있을 때만 보인다)
	bannerLabel = makeLabel(gui, {
		BackgroundColor3 = Color3.fromRGB(64, 48, 24),
		BackgroundTransparency = 0.15,
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.new(0.5, 0, 0, 56),
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = 14,
		TextWrapped = true,
		Visible = false,
	})
	corner(bannerLabel, 8)

	-- 중앙: 무기와 강화 레벨
	centerFrame = Instance.new("Frame")
	centerFrame.Name = "Center"
	centerFrame.BackgroundTransparency = 1
	centerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	centerFrame.Position = UDim2.new(0.5, 0, 0.36, 0)
	centerFrame.Size = UDim2.new(0.9, 0, 0, 170)
	centerFrame.Parent = gui

	local centerList = Instance.new("UIListLayout")
	centerList.FillDirection = Enum.FillDirection.Vertical
	centerList.SortOrder = Enum.SortOrder.LayoutOrder
	centerList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	centerList.VerticalAlignment = Enum.VerticalAlignment.Center
	centerList.Padding = UDim.new(0, 4)
	centerList.Parent = centerFrame

	-- 무기 이름은 눌러서 바꿀 수 있다.
	weaponButton = makeButton(centerFrame, {
		Size = UDim2.new(1, 0, 0, TOUCH_MIN),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = Enum.Font.GothamMedium,
		TextSize = 22,
		TextColor3 = COLOR_MUTED,
		LayoutOrder = 1,
	})
	levelLabel = makeLabel(centerFrame, {
		Size = UDim2.new(1, 0, 0, 90),
		TextSize = 72,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLOR_ACCENT,
		LayoutOrder = 2,
	})
	eventLabel = makeLabel(centerFrame, {
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 15,
		TextColor3 = Color3.fromRGB(140, 210, 255),
		LayoutOrder = 3,
		Visible = false,
	})

	-- 하단 조작 패널
	bottomPanel = Instance.new("Frame")
	bottomPanel.Name = "Bottom"
	bottomPanel.BackgroundColor3 = COLOR_PANEL
	bottomPanel.BackgroundTransparency = 0.1
	bottomPanel.BorderSizePixel = 0
	bottomPanel.AnchorPoint = Vector2.new(0.5, 1)
	bottomPanel.Position = UDim2.new(0.5, 0, 1, -12)
	bottomPanel.Size = UDim2.new(1, -24, 0, 292)
	bottomPanel.Parent = gui
	corner(bottomPanel, 14)

	local bottomSize = Instance.new("UISizeConstraint")
	bottomSize.MaxSize = Vector2.new(560, math.huge)
	bottomSize.Parent = bottomPanel

	local bottomPadding = Instance.new("UIPadding")
	bottomPadding.PaddingTop = UDim.new(0, 12)
	bottomPadding.PaddingBottom = UDim.new(0, 12)
	bottomPadding.PaddingLeft = UDim.new(0, 14)
	bottomPadding.PaddingRight = UDim.new(0, 14)
	bottomPadding.Parent = bottomPanel

	local bottomList = Instance.new("UIListLayout")
	bottomList.FillDirection = Enum.FillDirection.Vertical
	bottomList.SortOrder = Enum.SortOrder.LayoutOrder
	bottomList.Padding = UDim.new(0, 6)
	bottomList.Parent = bottomPanel

	oddsLabel = makeLabel(bottomPanel, {
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 17,
		LayoutOrder = 1,
	})
	costLabel = makeLabel(bottomPanel, {
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 15,
		TextColor3 = COLOR_MUTED,
		LayoutOrder = 2,
	})
	protectButton = makeButton(bottomPanel, {
		Size = UDim2.new(1, 0, 0, TOUCH_MIN),
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 3,
	})

	-- 보조 버튼 한 줄 (확률표 / 검 / 기록 / 상점)
	local actionRow = Instance.new("Frame")
	actionRow.BackgroundTransparency = 1
	actionRow.Size = UDim2.new(1, 0, 0, TOUCH_MIN)
	actionRow.LayoutOrder = 4
	actionRow.Parent = bottomPanel

	local actionList = Instance.new("UIListLayout")
	actionList.FillDirection = Enum.FillDirection.Horizontal
	actionList.SortOrder = Enum.SortOrder.LayoutOrder
	actionList.Padding = UDim.new(0, 8)
	actionList.Parent = actionRow

	oddsTableButton = makeButton(actionRow, {
		Size = UDim2.new(0.25, -6, 1, 0),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 1,
	})
	swordsButton = makeButton(actionRow, {
		Size = UDim2.new(0.25, -6, 1, 0),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 2,
	})
	recordsButton = makeButton(actionRow, {
		Size = UDim2.new(0.25, -6, 1, 0),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 3,
	})
	shopButton = makeButton(actionRow, {
		Size = UDim2.new(0.25, -6, 1, 0),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 4,
	})

	enhanceButton = makeButton(bottomPanel, {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = COLOR_ACCENT,
		TextColor3 = Color3.fromRGB(24, 18, 10),
		TextSize = 24,
		LayoutOrder = 5,
	})
	statusLabel = makeLabel(bottomPanel, {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 14,
		TextColor3 = Color3.fromRGB(255, 140, 130),
		LayoutOrder = 6,
	})

	-- 튜토리얼 안내. 첫 3회 강화까지만 보인다.
	hintLabel = makeLabel(bottomPanel, {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 14,
		TextColor3 = COLOR_ACCENT,
		LayoutOrder = 0,
		Visible = false,
	})

	-- 이름 짓기 창
	renamePanel = Instance.new("Frame")
	renamePanel.Name = "Rename"
	renamePanel.BackgroundColor3 = COLOR_PANEL
	renamePanel.BorderSizePixel = 0
	renamePanel.AnchorPoint = Vector2.new(0.5, 0.5)
	renamePanel.Position = UDim2.fromScale(0.5, 0.5)
	renamePanel.Size = UDim2.new(0.86, 0, 0, 210)
	renamePanel.Visible = false
	renamePanel.ZIndex = 30
	renamePanel.Parent = gui
	corner(renamePanel, 14)

	local renameSize = Instance.new("UISizeConstraint")
	renameSize.MaxSize = Vector2.new(420, math.huge)
	renameSize.Parent = renamePanel

	local renamePadding = Instance.new("UIPadding")
	renamePadding.PaddingTop = UDim.new(0, 16)
	renamePadding.PaddingBottom = UDim.new(0, 16)
	renamePadding.PaddingLeft = UDim.new(0, 16)
	renamePadding.PaddingRight = UDim.new(0, 16)
	renamePadding.Parent = renamePanel

	local renameList = Instance.new("UIListLayout")
	renameList.FillDirection = Enum.FillDirection.Vertical
	renameList.SortOrder = Enum.SortOrder.LayoutOrder
	renameList.Padding = UDim.new(0, 10)
	renameList.Parent = renamePanel

	local renamePromptLabel = makeLabel(renamePanel, {
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 15,
		TextColor3 = COLOR_MUTED,
		ZIndex = 31,
		LayoutOrder = 1,
	})
	renamePromptLabel.Name = "Prompt"

	renameBox = Instance.new("TextBox")
	renameBox.BackgroundColor3 = COLOR_SUB
	renameBox.BorderSizePixel = 0
	renameBox.Font = Enum.Font.GothamMedium
	renameBox.TextSize = 18
	renameBox.TextColor3 = COLOR_TEXT
	renameBox.PlaceholderColor3 = COLOR_DISABLED
	renameBox.ClearTextOnFocus = false
	renameBox.Text = ""
	renameBox.Size = UDim2.new(1, 0, 0, TOUCH_MIN)
	renameBox.ZIndex = 31
	renameBox.LayoutOrder = 2
	renameBox.Parent = renamePanel
	corner(renameBox, 10)

	renameConfirm = makeButton(renamePanel, {
		Size = UDim2.new(1, 0, 0, TOUCH_MIN),
		BackgroundColor3 = COLOR_ACCENT,
		TextColor3 = Color3.fromRGB(24, 18, 10),
		ZIndex = 31,
		LayoutOrder = 3,
	})
	renameCancel = makeButton(renamePanel, {
		Size = UDim2.new(1, 0, 0, TOUCH_MIN),
		ZIndex = 31,
		LayoutOrder = 4,
	})

	EffectsController.bind(gui, centerFrame, levelLabel)

	applyLayout()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
end

-- 착용 검의 이름 (지어 준 이름이 있으면 그것)
local function weaponDisplayName(language: string, sword: any): string
	if sword == nil then
		return ""
	end

	if sword.customName and sword.customName ~= "" then
		return sword.customName
	end

	local info = Weapons.get(sword.id)
	return if info then Locale.get(language, info.nameKey) else sword.id
end

local function render()
	local language = ClientState.getLanguage()
	local data = ClientState.getData()

	oddsTableButton.Text = Locale.get(language, "ui.oddsTable")
	swordsButton.Text = Locale.get(language, "ui.swords")
	shopButton.Text = Locale.get(language, "ui.shop")
	recordsButton.Text = Locale.get(language, "ui.records")
	renameConfirm.Text = Locale.get(language, "ui.rename")
	renameCancel.Text = Locale.get(language, "ui.cancel")

	local prompt = renamePanel:FindFirstChild("Prompt")
	if prompt and prompt:IsA("TextLabel") then
		prompt.Text = Locale.get(language, "ui.renamePrompt")
	end

	if data == nil then
		enhanceButton.Text = Locale.get(language, "ui.loading")
		enhanceButton.BackgroundColor3 = COLOR_DISABLED
		enhanceButton.Active = false
		return
	end

	-- 공지/점검 배너
	local liveOps = ClientState.getLiveOps()
	if liveOps.maintenance then
		bannerLabel.Visible = true
		bannerLabel.Text = Locale.get(language, "ui.maintenance")
	elseif liveOps.notice ~= "" then
		bannerLabel.Visible = true
		bannerLabel.Text = liveOps.notice
	else
		bannerLabel.Visible = false
	end

	-- 첫 1분 안에 강화를 세 번 경험하게 하는 안내
	local tries = data.stats.enhanceTries
	if tries < 3 then
		hintLabel.Visible = true
		hintLabel.Text = Locale.get(language, `tutorial.step{tries + 1}`)
	elseif tries == 3 then
		hintLabel.Visible = true
		hintLabel.Text = Locale.get(language, "tutorial.done")
	else
		hintLabel.Visible = false
	end

	goldLabel.Text = Locale.get(language, "ui.gold", Format.comma(data.gold))
	shardLabel.Text = Locale.get(language, "ui.shards", Format.comma(data.shards))
	ticketLabel.Text = Locale.get(language, "ui.tickets", data.protectTickets)

	local sword = ClientState.getEquipped()
	local useProtect = ClientState.getUseProtect()

	weaponButton.Text = weaponDisplayName(language, sword)
	levelLabel.Text = Locale.get(language, "ui.level", if sword then sword.level else 0)

	protectButton.Text = `{if useProtect then "[v]" else "[ ]"} {Locale.get(
		language,
		"ui.useProtect"
	)} ({data.protectTickets})`
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
		eventLabel.Text =
			Locale.get(language, "ui.eventActive", Locale.get(language, odds.eventName))
	end

	if odds.cost <= 0 then
		-- 최대 레벨
		oddsLabel.Text = Locale.get(language, "ui.maxLevel")
		costLabel.Text = ""
		enhanceButton.Text = Locale.get(language, "ui.maxLevel")
		enhanceButton.BackgroundColor3 = COLOR_DISABLED
		enhanceButton.Active = false
		return
	end

	-- 방지권이 효과를 내는 동안에는 바뀐 확률(실패 0, 그만큼 유지)을 보여 준다.
	local shown: EnhanceLogic.Odds = odds
	if ClientState.isProtectActive() then
		shown = EnhanceLogic.applyProtect(odds)
	end

	oddsLabel.Text = Locale.get(
		language,
		"ui.odds",
		Format.percent(shown.success),
		Format.percent(shown.keep),
		Format.percent(shown.fail)
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

local function showError(reason: string)
	statusLabel.Text = Locale.get(ClientState.getLanguage(), `error.{reason}`)
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
		return enhanceRemote:InvokeServer(ClientState.getUseProtect())
	end)

	busy = false

	if not ok or type(response) ~= "table" then
		showError("unknown")
		render()
		return
	end

	if response.ok ~= true then
		showError(tostring(response.reason))
		render()
		return
	end

	-- 서버 응답을 받은 뒤에만 연출을 시작한다.
	ClientState.setOdds(response.odds)
	FeedController.pushOutcome(response.result)
	SoundController.play(response.result)

	if response.result == "success" and response.newLevel >= EnhanceTable.MAX_LEVEL then
		FeedController.pushOutcome("max")
		EffectsController.playMaxLevel()
	else
		EffectsController.play(response.result)
	end

	render()
end

local function requestRename()
	local text = renameBox.Text
	renamePanel.Visible = false

	if text == "" then
		return
	end

	local ok, response = pcall(function()
		return renameRemote:InvokeServer(text)
	end)

	if not ok or type(response) ~= "table" then
		showError("unknown")
		return
	end

	if response.ok ~= true then
		showError(tostring(response.reason))
		return
	end

	-- 서버가 돌려준 "필터링을 통과한" 이름만 화면에 쓴다.
	FeedController.pushRaw(
		Locale.get(ClientState.getLanguage(), "ui.renamed", response.name),
		COLOR_ACCENT
	)
	render()
end

function UIController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	enhanceRemote = remotesFolder:WaitForChild(Remotes.Functions.Enhance) :: RemoteFunction
	renameRemote = remotesFolder:WaitForChild(Remotes.Functions.RenameWeapon) :: RemoteFunction

	local dataChanged = remotesFolder:WaitForChild(Remotes.Events.DataChanged) :: RemoteEvent
	dataChanged.OnClientEvent:Connect(function(data: any)
		if type(data) == "table" then
			ClientState.setData(data)
		end
	end)

	local liveOpsRemote = remotesFolder:WaitForChild(Remotes.Events.LiveOpsChanged) :: RemoteEvent
	liveOpsRemote.OnClientEvent:Connect(function(config: any)
		if type(config) == "table" then
			ClientState.setLiveOps(config)
		end
	end)

	ClientState.onChanged(render)

	enhanceButton.Activated:Connect(function()
		task.spawn(requestEnhance)
	end)

	protectButton.Activated:Connect(function()
		SoundController.play("click")
		ClientState.setUseProtect(not ClientState.getUseProtect())
	end)

	swordsButton.Activated:Connect(function()
		SwordController.toggle()
	end)

	oddsTableButton.Activated:Connect(function()
		OddsTableController.toggle()
	end)

	shopButton.Activated:Connect(function()
		ShopController.toggle()
	end)

	recordsButton.Activated:Connect(function()
		CollectionController.toggle()
	end)

	weaponButton.Activated:Connect(function()
		local sword = ClientState.getEquipped()
		renameBox.Text = if sword and sword.customName then sword.customName else ""
		renamePanel.Visible = true
	end)

	renameConfirm.Activated:Connect(function()
		task.spawn(requestRename)
	end)

	renameCancel.Activated:Connect(function()
		renamePanel.Visible = false
	end)

	render()
end

function UIController.Start()
	-- 접속 직후 현재 상태를 한 번 받아 온다.
	-- (프로필 로드가 아직 끝나지 않았을 수 있어 잠시 재시도한다)
	task.spawn(function()
		local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
		local stateRemote = remotesFolder:WaitForChild(Remotes.Functions.GetState) :: RemoteFunction

		for _ = 1, 30 do
			local ok, response = pcall(function()
				return stateRemote:InvokeServer()
			end)

			if ok and type(response) == "table" and response.ok == true then
				if type(response.liveOps) == "table" then
					ClientState.setLiveOps(response.liveOps)
				end
				ClientState.setData(response.data)
				ClientState.setOdds(response.odds)
				return
			end

			task.wait(1)
		end

		warn("[UIController] 상태를 받아 오지 못했습니다")
	end)
end

return UIController
