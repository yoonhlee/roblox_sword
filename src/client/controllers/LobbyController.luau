--!strict
--[[
	LobbyController — 로비에서 쓰는 화면 (통합 기획서 4-1·4-4·6절).

	- "경주 매칭" 버튼: 누르면 서버 대기열에 들어간다. 대기 중에는 "대기 취소"로 바뀌고
	  출발까지 남은 시간과 대기 인원을 보여 준다.
	- "대장간 접기/열기" 버튼: 무기·강화 패널을 접어서 로비를 돌아다니기 편하게 한다.
	- 트레드밀: 발판 위에 안내 글자를 띄우고, 올라가 있는 동안 진행 상황을 보여 준다.

	여기 있는 숫자 중 "착용 검의 최대 거리·최대 보상"은 서버와 같은 Pure/RaceLogic 함수로 계산한
	안내용 값이다. 실제 거리·보상·트레드밀 수입은 전부 서버가 정한다.
	경주 화면(출발선 ~ 결과)은 RaceController 가 맡는다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Pure = Shared:WaitForChild("Pure")
local Format = require(Pure:WaitForChild("Format"))
local EnhanceLogic = require(Pure:WaitForChild("EnhanceLogic"))
local RaceLogic = require(Pure:WaitForChild("RaceLogic"))

local ConfigFolder = Shared:WaitForChild("Config")
local EnhanceTable = require(ConfigFolder:WaitForChild("EnhanceTable"))
local EconomyConfig = require(ConfigFolder:WaitForChild("EconomyConfig"))
local RaceConfig = require(ConfigFolder:WaitForChild("RaceConfig"))
local World = require(ConfigFolder:WaitForChild("World"))

local controllers = script.Parent
local ClientState = require(controllers.Parent:WaitForChild("ClientState"))
local FeedController = require(controllers:WaitForChild("FeedController"))
local SoundController = require(controllers:WaitForChild("SoundController"))

local LobbyController = {}
LobbyController.Name = "LobbyController"

local COLOR_SUB = Color3.fromRGB(52, 46, 58)
local COLOR_TEXT = Color3.fromRGB(240, 236, 230)
local COLOR_MUTED = Color3.fromRGB(200, 194, 204)
local COLOR_ACCENT = Color3.fromRGB(226, 142, 58)
local COLOR_ERROR = Color3.fromRGB(255, 140, 130)
local COLOR_GOLD = Color3.fromRGB(255, 208, 112)

local NARROW_WIDTH = 700
local BUTTON_WIDTH = 150
local BUTTON_HEIGHT = 46 -- 최소 터치 영역 44px 이상

local CURVE: RaceLogic.Curve = {
	minTime = RaceConfig.MIN_TIME_SECONDS,
	maxTime = RaceConfig.MAX_TIME_SECONDS,
	maxLevel = EnhanceTable.MAX_LEVEL,
	accel = RaceConfig.CHASER_ACCEL,
	headStart = RaceConfig.HEAD_START,
	baseSpeed = RaceConfig.BASE_SPEED,
}

local gui: ScreenGui
local cluster: Frame
local matchButton: TextButton
local forgeButton: TextButton
local statusLabel: TextLabel
local treadmillLabel: TextLabel

local joinRemote: RemoteFunction
local leaveRemote: RemoteFunction

local busy = false
local queued = false
local queueCount = 0
local queueDeadline = 0 -- 출발 신호 예정 시각 (os.clock)

local onPad = false
local padProgress = 0
local padInterval = 0
local padGold = 0

-- 발판 위 안내판: 발판 파트 → 글자 라벨
local padLabels: { [Instance]: TextLabel } = {}

local function makeButton(parent: Instance, order: number): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = COLOR_SUB
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = COLOR_TEXT
	button.Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.LayoutOrder = order
	button.Text = ""
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	return button
end

local function makeLabel(parent: Instance, order: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.fromRGB(18, 16, 20)
	label.BackgroundTransparency = 0.35
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Size = UDim2.fromOffset(BUTTON_WIDTH * 2 + 8, 40)
	label.LayoutOrder = order
	label.Text = ""
	label.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = label

	return label
end

-- 좁은 화면(세로 모바일)에서는 결과 피드가 위쪽을 차지하므로 그 아래에 둔다.
local function applyLayout()
	local camera = Workspace.CurrentCamera
	if camera == nil or cluster == nil then
		return
	end

	local isNarrow = camera.ViewportSize.X < NARROW_WIDTH
	cluster.Position = UDim2.fromOffset(12, if isNarrow then 252 else 64)
end

local function build()
	local player = Players.LocalPlayer

	gui = Instance.new("ScreenGui")
	gui.Name = "ForgeLobby"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	gui.Parent = player:WaitForChild("PlayerGui")

	cluster = Instance.new("Frame")
	cluster.Name = "Cluster"
	cluster.BackgroundTransparency = 1
	cluster.Size = UDim2.fromOffset(BUTTON_WIDTH * 2 + 8, 200)
	cluster.Parent = gui

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = cluster

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(BUTTON_WIDTH * 2 + 8, BUTTON_HEIGHT)
	row.LayoutOrder = 1
	row.Parent = cluster

	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Padding = UDim.new(0, 8)
	rowList.Parent = row

	matchButton = makeButton(row, 1)
	matchButton.BackgroundColor3 = COLOR_ACCENT
	matchButton.TextColor3 = Color3.fromRGB(24, 18, 10)

	forgeButton = makeButton(row, 2)
	forgeButton.Font = Enum.Font.GothamMedium

	statusLabel = makeLabel(cluster, 2, COLOR_MUTED)
	treadmillLabel = makeLabel(cluster, 3, COLOR_GOLD)
	treadmillLabel.Size = UDim2.fromOffset(BUTTON_WIDTH * 2 + 8, 28)
	treadmillLabel.Visible = false

	applyLayout()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
end

-- 착용 검 레벨 기준 "최대 거리 · 최대 보상" 안내 문구
local function raceInfoText(language: string): string
	local sword = ClientState.getEquipped()
	if sword == nil then
		return ""
	end

	local level = sword.level
	local maxDistance = RaceLogic.maxDistance(level, CURVE)

	local odds = EnhanceTable.Odds[level]
	local multiplier =
		RaceLogic.rewardMultiplier(level, if odds then odds.success else 0, RaceConfig.Multiplier)
	local cost =
		EnhanceLogic.cost(level, 1, EnhanceTable.COST_BASE, EnhanceTable.SWORD_COUNT_EXPONENT)
	local maxReward = RaceLogic.reward(cost, multiplier, maxDistance, maxDistance)

	return Locale.get(
		language,
		"ui.race.info",
		level,
		Format.comma(math.floor(maxDistance)),
		Format.comma(maxReward)
	)
end

local function tierText(language: string, tierId: any): string
	local tier = if type(tierId) == "string" then EconomyConfig.treadmillTier(tierId) else nil
	if tier == nil then
		return ""
	end
	return Locale.get(language, "ui.treadmill.label", tier.intervalSeconds, Format.comma(tier.gold))
end

local function render()
	local language = ClientState.getLanguage()

	-- 경주 화면이 떠 있는 동안에는 로비 버튼을 숨긴다.
	gui.Enabled = not ClientState.isInRace()

	matchButton.Text = Locale.get(language, if queued then "ui.race.cancel" else "ui.race.match")
	matchButton.BackgroundColor3 = if queued then COLOR_SUB else COLOR_ACCENT
	matchButton.TextColor3 = if queued then COLOR_TEXT else Color3.fromRGB(24, 18, 10)

	forgeButton.Text =
		Locale.get(language, if ClientState.isForgeOpen() then "ui.forge.hide" else "ui.forge.show")

	if queued then
		local secondsLeft = math.max(0, math.ceil(queueDeadline - os.clock()))
		statusLabel.TextColor3 = COLOR_ACCENT
		statusLabel.Text = Locale.get(language, "ui.race.queue", secondsLeft, queueCount)
	else
		statusLabel.TextColor3 = COLOR_MUTED
		statusLabel.Text = raceInfoText(language)
	end

	treadmillLabel.Visible = onPad
	if onPad then
		treadmillLabel.Text = Locale.get(
			language,
			"ui.treadmill.progress",
			math.floor(padProgress),
			padInterval,
			Format.comma(padGold)
		)
	end

	for part, label in padLabels do
		label.Text = tierText(language, part:GetAttribute(World.TREADMILL_TIER_ATTRIBUTE))
	end
end

local function showError(reason: string)
	FeedController.pushRaw(Locale.get(ClientState.getLanguage(), `error.{reason}`), COLOR_ERROR)
end

local function requestMatch()
	if busy then
		return
	end
	busy = true

	local remote = if queued then leaveRemote else joinRemote
	local ok, response = pcall(function()
		return remote:InvokeServer()
	end)

	busy = false

	if not ok or type(response) ~= "table" then
		showError("unknown")
		return
	end
	if response.ok ~= true then
		showError(tostring(response.reason))
	end
	-- 대기열에 들어갔는지는 서버가 RaceUpdate(kind = "queue") 로 알려 준다.
end

-- 발판 위에 안내 글자를 띄운다. 글자는 플레이어 언어로 써야 해서 서버가 아니라 여기서 붙인다.
local function attachPadLabel(part: Instance)
	if not part:IsA("BasePart") or padLabels[part] ~= nil then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TreadmillLabel"
	billboard.Adornee = part
	billboard.Size = UDim2.fromOffset(190, 52)
	billboard.StudsOffset = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 140
	billboard.ResetOnSpawn = false
	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.fromRGB(18, 16, 20)
	label.BackgroundTransparency = 0.3
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextColor3 = COLOR_GOLD
	label.TextWrapped = true
	label.Text = ""
	label.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	padLabels[part] = label

	part.Destroying:Connect(function()
		padLabels[part] = nil
		billboard:Destroy()
	end)
end

local function watchTreadmills()
	local lobby = Workspace:WaitForChild(World.LOBBY_FOLDER, 60)
	local folder = if lobby then lobby:WaitForChild(World.TREADMILL_FOLDER, 60) else nil
	if folder == nil then
		warn("[LobbyController] 트레드밀 발판을 찾지 못했습니다")
		return
	end

	for _, child in folder:GetChildren() do
		attachPadLabel(child)
	end
	folder.ChildAdded:Connect(attachPadLabel)

	render()
end

local function onRaceUpdate(payload: any)
	if type(payload) ~= "table" then
		return
	end

	if payload.kind == "queue" then
		queued = payload.queued == true
		queueCount = tonumber(payload.count) or 0
		queueDeadline = os.clock() + (tonumber(payload.secondsLeft) or 0)
		render()
	elseif payload.kind == "lineup" or payload.kind == "lobby" then
		-- 출발선에 섰거나 로비로 돌아왔다. 어느 쪽이든 대기는 끝났다.
		queued = false
		render()
	end
end

local function onTreadmillUpdate(payload: any)
	if type(payload) ~= "table" then
		return
	end

	onPad = payload.onPad == true
	padProgress = tonumber(payload.progress) or 0
	padInterval = tonumber(payload.interval) or 0
	padGold = tonumber(payload.gold) or 0

	local paid = tonumber(payload.paid) or 0
	if paid > 0 then
		FeedController.pushRaw(
			Locale.get(ClientState.getLanguage(), "ui.treadmill.paid", Format.comma(paid)),
			COLOR_GOLD
		)
	end

	render()
end

function LobbyController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	joinRemote = remotesFolder:WaitForChild(Remotes.Functions.JoinRace) :: RemoteFunction
	leaveRemote = remotesFolder:WaitForChild(Remotes.Functions.LeaveRaceQueue) :: RemoteFunction

	local raceRemote = remotesFolder:WaitForChild(Remotes.Events.RaceUpdate) :: RemoteEvent
	raceRemote.OnClientEvent:Connect(onRaceUpdate)

	local treadmillRemote =
		remotesFolder:WaitForChild(Remotes.Events.TreadmillUpdate) :: RemoteEvent
	treadmillRemote.OnClientEvent:Connect(onTreadmillUpdate)

	matchButton.Activated:Connect(function()
		SoundController.play("click")
		task.spawn(requestMatch)
	end)

	forgeButton.Activated:Connect(function()
		SoundController.play("click")
		ClientState.setForgeOpen(not ClientState.isForgeOpen())
	end)

	ClientState.onChanged(render)
	render()
end

function LobbyController.Start()
	task.spawn(watchTreadmills)

	-- 대기 중에는 남은 시간을 다시 그린다.
	task.spawn(function()
		while true do
			task.wait(0.25)
			if queued then
				render()
			end
		end
	end)
end

return LobbyController
