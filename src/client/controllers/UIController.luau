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

local controllers = script.Parent
local ClientState = require(controllers.Parent:WaitForChild("ClientState"))
local FeedController = require(controllers:WaitForChild("FeedController"))
local SoundController = require(controllers:WaitForChild("SoundController"))
local EffectsController = require(controllers:WaitForChild("EffectsController"))
local OddsTableController = require(controllers:WaitForChild("OddsTableController"))
local BattleController = require(controllers:WaitForChild("BattleController"))
local ShopController = require(controllers:WaitForChild("ShopController"))
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
local useProtect = false

local gui: ScreenGui
local uiScale: UIScale
local goldLabel: TextLabel
local shardLabel: TextLabel
local ticketButton: TextButton
local centerFrame: Frame
local weaponLabel: TextLabel
local levelLabel: TextLabel
local eventLabel: TextLabel
local bottomPanel: Frame
local oddsLabel: TextLabel
local costLabel: TextLabel
local statusLabel: TextLabel
local protectButton: TextButton
local oddsTableButton: TextButton
local sellButton: TextButton
local battleButton: TextButton
local shopButton: TextButton
local recordsButton: TextButton
local enhanceButton: TextButton
local confirmPanel: Frame
local confirmLabel: TextLabel
local confirmYes: TextButton
local confirmNo: TextButton

local enhanceRemote: RemoteFunction
local sellRemote: RemoteFunction
local ticketRemote: RemoteFunction

-- 확인 창은 하나를 돌려 쓴다. "예" 를 눌렀을 때 할 일을 여기에 담아 둔다.
local confirmAction: (() -> ())? = nil

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
	-- 방지권 표시는 눌러서 파편 교환까지 할 수 있게 버튼으로 둔다.
	ticketButton = makeButton(topBar, {
		Size = UDim2.new(0, 150, 0, TOUCH_MIN),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR_MUTED,
		LayoutOrder = 3,
	})

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

	weaponLabel = makeLabel(centerFrame, {
		Size = UDim2.new(1, 0, 0, 26),
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
	bottomPanel.Size = UDim2.new(1, -24, 0, 312)
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

	-- 보조 버튼 두 줄. 한 줄에 다섯 개를 넣으면 모바일에서 누르기 어려워진다.
	local function makeActionRow(order: number): Frame
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, TOUCH_MIN)
		row.LayoutOrder = order
		row.Parent = bottomPanel

		local rowList = Instance.new("UIListLayout")
		rowList.FillDirection = Enum.FillDirection.Horizontal
		rowList.SortOrder = Enum.SortOrder.LayoutOrder
		rowList.Padding = UDim.new(0, 8)
		rowList.Parent = row

		return row
	end

	local actionRowTop = makeActionRow(4)
	local actionRowBottom = makeActionRow(5)

	oddsTableButton = makeButton(actionRowTop, {
		Size = UDim2.new(1 / 3, -6, 1, 0),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 1,
	})
	battleButton = makeButton(actionRowTop, {
		Size = UDim2.new(1 / 3, -6, 1, 0),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 2,
	})
	recordsButton = makeButton(actionRowTop, {
		Size = UDim2.new(1 / 3, -6, 1, 0),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 3,
	})

	sellButton = makeButton(actionRowBottom, {
		Size = UDim2.new(0.5, -4, 1, 0),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 1,
	})
	shopButton = makeButton(actionRowBottom, {
		Size = UDim2.new(0.5, -4, 1, 0),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 2,
	})

	enhanceButton = makeButton(bottomPanel, {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = COLOR_ACCENT,
		TextColor3 = Color3.fromRGB(24, 18, 10),
		TextSize = 24,
		LayoutOrder = 6,
	})
	statusLabel = makeLabel(bottomPanel, {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 14,
		TextColor3 = Color3.fromRGB(255, 140, 130),
		LayoutOrder = 7,
	})

	-- 판매 확인 창
	confirmPanel = Instance.new("Frame")
	confirmPanel.Name = "SellConfirm"
	confirmPanel.BackgroundColor3 = COLOR_PANEL
	confirmPanel.BorderSizePixel = 0
	confirmPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmPanel.Position = UDim2.fromScale(0.5, 0.5)
	confirmPanel.Size = UDim2.new(0.86, 0, 0, 170)
	confirmPanel.Visible = false
	confirmPanel.ZIndex = 30
	confirmPanel.Parent = gui
	corner(confirmPanel, 14)

	local confirmSize = Instance.new("UISizeConstraint")
	confirmSize.MaxSize = Vector2.new(420, math.huge)
	confirmSize.Parent = confirmPanel

	local confirmPadding = Instance.new("UIPadding")
	confirmPadding.PaddingTop = UDim.new(0, 16)
	confirmPadding.PaddingBottom = UDim.new(0, 16)
	confirmPadding.PaddingLeft = UDim.new(0, 16)
	confirmPadding.PaddingRight = UDim.new(0, 16)
	confirmPadding.Parent = confirmPanel

	local confirmList = Instance.new("UIListLayout")
	confirmList.FillDirection = Enum.FillDirection.Vertical
	confirmList.SortOrder = Enum.SortOrder.LayoutOrder
	confirmList.Padding = UDim.new(0, 10)
	confirmList.Parent = confirmPanel

	confirmLabel = makeLabel(confirmPanel, {
		Size = UDim2.new(1, 0, 0, 56),
		TextSize = 16,
		TextWrapped = true,
		ZIndex = 31,
		LayoutOrder = 1,
	})
	confirmYes = makeButton(confirmPanel, {
		Size = UDim2.new(1, 0, 0, TOUCH_MIN),
		BackgroundColor3 = COLOR_ACCENT,
		TextColor3 = Color3.fromRGB(24, 18, 10),
		ZIndex = 31,
		LayoutOrder = 2,
	})
	confirmNo = makeButton(confirmPanel, {
		Size = UDim2.new(1, 0, 0, TOUCH_MIN),
		ZIndex = 31,
		LayoutOrder = 3,
	})

	EffectsController.bind(gui, centerFrame, levelLabel)

	applyLayout()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
end

local function weaponDisplayName(language: string, data: any): string
	if data.weapon.customName and data.weapon.customName ~= "" then
		return data.weapon.customName
	end

	local info = Weapons.get(data.weapon.id)
	return if info then Locale.get(language, info.nameKey) else data.weapon.id
end

local function render()
	local language = ClientState.getLanguage()
	local data = ClientState.getData()

	oddsTableButton.Text = Locale.get(language, "ui.oddsTable")
	battleButton.Text = Locale.get(language, "ui.battle")
	shopButton.Text = Locale.get(language, "ui.shop")
	recordsButton.Text = Locale.get(language, "ui.records")
	sellButton.Text = Locale.get(language, "ui.sell")
	confirmYes.Text = Locale.get(language, "ui.confirm")
	confirmNo.Text = Locale.get(language, "ui.cancel")

	if data == nil then
		enhanceButton.Text = Locale.get(language, "ui.loading")
		enhanceButton.BackgroundColor3 = COLOR_DISABLED
		enhanceButton.Active = false
		sellButton.Active = false
		return
	end

	goldLabel.Text = Locale.get(language, "ui.gold", Format.comma(data.gold))
	shardLabel.Text = Locale.get(language, "ui.shards", Format.comma(data.shards))
	local exchangeable = math.floor(data.shards / EnhanceTable.SHARDS_PER_TICKET)
	ticketButton.Text = if exchangeable > 0
		then `{Locale.get(language, "ui.tickets", data.protectTickets)}  +`
		else Locale.get(language, "ui.tickets", data.protectTickets)
	ticketButton.TextColor3 = if exchangeable > 0 then COLOR_ACCENT else COLOR_MUTED

	weaponLabel.Text = weaponDisplayName(language, data)
	levelLabel.Text = Locale.get(language, "ui.level", data.weapon.level)

	protectButton.Text = `{if useProtect then "[v]" else "[ ]"} {Locale.get(language, "ui.useProtect")} ({data.protectTickets})`
	protectButton.TextColor3 = if useProtect then COLOR_ACCENT else COLOR_MUTED

	-- 레벨 0 무기는 판매가가 0 이라 팔 게 없다.
	local sellValue = EnhanceTable.SellValue[data.weapon.level] or 0
	sellButton.Active = not busy and sellValue > 0
	sellButton.TextColor3 = if sellValue > 0 then COLOR_TEXT else COLOR_DISABLED

	local odds = ClientState.getOdds()
	if odds == nil then
		oddsLabel.Text = ""
		costLabel.Text = ""
		eventLabel.Visible = false
		return
	end

	eventLabel.Visible = odds.eventName ~= nil
	if odds.eventName ~= nil then
		eventLabel.Text = Locale.get(language, "ui.eventActive", Locale.get(language, odds.eventName))
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
		return enhanceRemote:InvokeServer(useProtect)
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

local function requestSell()
	if busy then
		return
	end

	busy = true
	statusLabel.Text = ""
	render()

	local ok, response = pcall(function()
		return sellRemote:InvokeServer()
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

	ClientState.setOdds(response.odds)
	FeedController.pushRaw(
		Locale.get(ClientState.getLanguage(), "chat.sold", Format.comma(response.goldGained)),
		COLOR_ACCENT
	)
	SoundController.play("click")
	render()
end

-- 확인 창을 띄운다. 예를 누르면 action 이 실행된다.
local function showConfirm(text: string, action: () -> ())
	confirmLabel.Text = text
	confirmAction = action
	confirmPanel.Visible = true
end

local function requestTicketExchange()
	if busy then
		return
	end
	busy = true
	render()

	local ok, response = pcall(function()
		return ticketRemote:InvokeServer("shards", 1)
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

	FeedController.pushRaw(
		Locale.get(ClientState.getLanguage(), "ui.exchanged", response.tickets),
		COLOR_ACCENT
	)
	SoundController.play("click")
	render()
end

local function openExchangeConfirm()
	local data = ClientState.getData()
	if data == nil then
		return
	end

	if data.shards < EnhanceTable.SHARDS_PER_TICKET then
		showError("not_enough_shards")
		return
	end

	showConfirm(
		Locale.get(
			ClientState.getLanguage(),
			"ui.exchangeConfirm",
			EnhanceTable.SHARDS_PER_TICKET,
			Format.comma(data.shards)
		),
		function()
			task.spawn(requestTicketExchange)
		end
	)
end

local function openSellConfirm()
	local data = ClientState.getData()
	if data == nil then
		return
	end

	local value = EnhanceTable.SellValue[data.weapon.level] or 0
	if value <= 0 then
		showError("nothing_to_sell")
		return
	end

	showConfirm(
		Locale.get(ClientState.getLanguage(), "ui.sellConfirm", Format.comma(value)),
		function()
			task.spawn(requestSell)
		end
	)
end

function UIController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	enhanceRemote = remotesFolder:WaitForChild(Remotes.Functions.Enhance) :: RemoteFunction
	sellRemote = remotesFolder:WaitForChild(Remotes.Functions.SellWeapon) :: RemoteFunction
	ticketRemote =
		remotesFolder:WaitForChild(Remotes.Functions.BuyProtectTicket) :: RemoteFunction

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

	oddsTableButton.Activated:Connect(function()
		OddsTableController.toggle()
	end)

	battleButton.Activated:Connect(function()
		BattleController.openTargetList()
	end)

	shopButton.Activated:Connect(function()
		ShopController.toggle()
	end)

	recordsButton.Activated:Connect(function()
		CollectionController.toggle()
	end)

	sellButton.Activated:Connect(openSellConfirm)

	confirmYes.Activated:Connect(function()
		confirmPanel.Visible = false
		local action = confirmAction
		confirmAction = nil
		if action then
			action()
		end
	end)

	confirmNo.Activated:Connect(function()
		confirmPanel.Visible = false
		confirmAction = nil
	end)

	ticketButton.Activated:Connect(openExchangeConfirm)

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
