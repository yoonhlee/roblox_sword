--!strict
--[[
	LobbyController — 로비에서 보이는 화면 (통합 기획서 4·6·8-1절).

	왼쪽: 메뉴 타일 4개 (대장간 · 검 · 도감 · 상점). 태블릿·PC 는 세로 한 줄,
	      화면이 낮은 휴대폰은 재화 칩 아래 가로 한 줄 (Pure/UILayout 이 정한다).
	오른쪽 위: "경주" 버튼과 상태 한 줄. 대기 중이면 버튼이 "대기 취소"로 바뀌고 남은 시간·인원과 막대.
	아래 가운데: 풀무 러닝머신 위에 있을 때 20초 진행 막대.
	가운데와 왼쪽 아래(조이스틱)·오른쪽 아래(점프)는 비운다.

	"착용 검의 최대 거리·최대 보상" 은 서버와 같은 Pure/RaceLogic 으로 계산한 안내용 값이다.
	실제 거리·보상·트레드밀 수입은 전부 서버가 정한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Pure = Shared:WaitForChild("Pure")
local Format = require(Pure:WaitForChild("Format"))
local EnhanceLogic = require(Pure:WaitForChild("EnhanceLogic"))
local RaceLogic = require(Pure:WaitForChild("RaceLogic"))

local ConfigFolder = Shared:WaitForChild("Config")
local EnhanceTable = require(ConfigFolder:WaitForChild("EnhanceTable"))
local RaceConfig = require(ConfigFolder:WaitForChild("RaceConfig"))

local client = script.Parent.Parent
local ClientState = require(client:WaitForChild("ClientState"))
local ui = client:WaitForChild("ui")
local Theme = require(ui:WaitForChild("Theme"))
local Components = require(ui:WaitForChild("Components"))
local ScreenManager = require(ui:WaitForChild("ScreenManager"))

local controllers = script.Parent
local FeedController = require(controllers:WaitForChild("FeedController"))
local SoundController = require(controllers:WaitForChild("SoundController"))

local LobbyController = {}
LobbyController.Name = "LobbyController"

local C = Theme.color

local CURVE: RaceLogic.Curve = {
	minTime = RaceConfig.MIN_TIME_SECONDS,
	maxTime = RaceConfig.MAX_TIME_SECONDS,
	maxLevel = EnhanceTable.MAX_LEVEL,
	accel = RaceConfig.CHASER_ACCEL,
	headStart = RaceConfig.HEAD_START,
	baseSpeed = RaceConfig.BASE_SPEED,
}

type MenuEntry = { key: string, glyph: Components.Glyph, textKey: string, button: TextButton? }

local MENU: { MenuEntry } = {
	{ key = "forge", glyph = "anvil", textKey = "ui.menu.forge" },
	{ key = "swords", glyph = "sword", textKey = "ui.swords" },
	{ key = "records", glyph = "book", textKey = "ui.menu.codex" },
	{ key = "shop", glyph = "bag", textKey = "ui.shop" },
}

local gui: ScreenGui
local menuFrame: Frame
local raceFrame: Frame
local raceButton: TextButton
local raceStatus: TextLabel
local queueBar: Components.ProgressBar
local treadmillFrame: Frame
local treadmillLabel: TextLabel
local treadmillBar: Components.ProgressBar

local joinRemote: RemoteFunction
local leaveRemote: RemoteFunction

local busy = false
local queued = false
local queueCount = 0
local queueDeadline = 0
local queueWindow = RaceConfig.MATCH_WINDOW_SECONDS

local onPad = false
local padProgress = 0
local padInterval = 0
local padGold = 0

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
		"ui.race.infoShort",
		Format.comma(math.floor(maxDistance)),
		Format.short(maxReward, language)
	)
end

local function place()
	local layout = ScreenManager.getLayout()
	if layout == nil then
		return
	end

	ScreenManager.place(menuFrame, layout.menu)
	local size = 60
	local gap = 8
	for index, entry in MENU do
		local button = entry.button
		if button then
			local column, row
			if layout.menuColumns == 1 then
				column, row = 0, index - 1
			elseif layout.menuColumns == 2 then
				column, row = (index - 1) % 2, math.floor((index - 1) / 2)
			else
				column, row = index - 1, 0
			end
			button.Position = UDim2.fromOffset(column * (size + gap), row * (size + gap))
			button.Size = UDim2.fromOffset(size, size)
		end
	end

	ScreenManager.place(raceFrame, layout.raceCluster)
	ScreenManager.place(treadmillFrame, layout.lobbyStatus)
end

local function render()
	local language = ClientState.getLanguage()
	gui.Enabled = ScreenManager.getMode() == "lobby"

	for _, entry in MENU do
		if entry.button then
			Components.setTileText(entry.button, Locale.get(language, entry.textKey))
		end
	end

	raceButton.Text = "      "
		.. Locale.get(language, if queued then "ui.race.cancel" else "ui.race.match")
	Components.setStyle(raceButton, if queued then "secondary" else "primary")

	if queued then
		local left = math.max(0, queueDeadline - os.clock())
		raceStatus.Text = Locale.get(language, "ui.race.queue", math.ceil(left), queueCount)
		raceStatus.TextColor3 = C.ember
		queueBar.frame.Visible = true
		queueBar.set(if queueWindow > 0 then left / queueWindow else 0)
	else
		raceStatus.Text = raceInfoText(language)
		raceStatus.TextColor3 = C.muted
		queueBar.frame.Visible = false
	end

	treadmillFrame.Visible = onPad
	if onPad then
		treadmillLabel.Text = Locale.get(
			language,
			"ui.treadmill.progress",
			math.floor(padProgress),
			padInterval,
			Format.comma(padGold)
		)
		treadmillBar.set(if padInterval > 0 then padProgress / padInterval else 0)
	end
end

local function showError(reason: string)
	FeedController.pushRaw(Locale.get(ClientState.getLanguage(), `error.{reason}`), C.fail)
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
	elseif response.ok ~= true then
		showError(tostring(response.reason))
	end
	-- 대기열에 들어갔는지는 서버가 RaceUpdate(kind = "queue") 로 알려 준다.
end

local function onMenu(key: string)
	SoundController.play("click")
	if key == "forge" then
		ScreenManager.setForgeOpen(true)
	else
		ScreenManager.openModal(key)
	end
end

local function build()
	gui = ScreenManager.createScreen("ForgeLobby", 4)

	menuFrame = Components.frame(gui, { Name = "Menu" })
	for index, entry in MENU do
		local button = Components.tile(menuFrame, entry.glyph, "", 60, index)
		entry.button = button
		button.Activated:Connect(function()
			onMenu(entry.key)
		end)
	end

	raceFrame = Components.frame(gui, { Name = "Race" })
	raceButton = Components.button(raceFrame, { style = "primary", size = Theme.text.label })
	raceButton.Size = UDim2.new(1, 0, 0, 60)
	local flag = Components.frame(raceButton, {
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
	})
	Components.glyph(flag, "flag", C.white)

	raceStatus = Components.label(raceFrame, {
		size = Theme.text.small,
		font = Theme.font.bodyBold,
		align = Enum.TextXAlignment.Center,
		wrap = true,
	})
	raceStatus.Position = UDim2.fromOffset(0, 66)
	raceStatus.Size = UDim2.new(1, 0, 0, 30)
	raceStatus.BackgroundColor3 = C.bg
	raceStatus.BackgroundTransparency = 0.25
	Components.corner(raceStatus, 8)

	queueBar = Components.progressBar(raceFrame, C.ember, 8)
	queueBar.frame.Position = UDim2.new(0, 6, 0, 98)
	queueBar.frame.Size = UDim2.new(1, -12, 0, 8)

	treadmillFrame = Components.frame(gui, {
		Name = "Treadmill",
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.2,
		Visible = false,
	})
	Components.corner(treadmillFrame, 10)
	Components.stroke(treadmillFrame, C.gold, 1.5)
	treadmillLabel = Components.label(treadmillFrame, {
		size = Theme.text.small,
		font = Theme.font.bodyBold,
		color = C.gold,
		align = Enum.TextXAlignment.Center,
	})
	treadmillLabel.Position = UDim2.fromOffset(0, 2)
	treadmillLabel.Size = UDim2.new(1, 0, 0, 22)
	treadmillBar = Components.progressBar(treadmillFrame, C.gold, 10)
	treadmillBar.frame.Position = UDim2.new(0, 10, 1, -16)
	treadmillBar.frame.Size = UDim2.new(1, -20, 0, 10)

	raceButton.Activated:Connect(function()
		SoundController.play("click")
		task.spawn(requestMatch)
	end)
end

local function onRaceUpdate(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind == "queue" then
		queued = payload.queued == true
		queueCount = tonumber(payload.count) or 0
		local left = tonumber(payload.secondsLeft) or 0
		queueDeadline = os.clock() + left
		queueWindow = math.max(left, 0.001)
		render()
	elseif payload.kind == "lineup" or payload.kind == "lobby" then
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
		SoundController.play("coin")
		FeedController.pushRaw(
			Locale.get(ClientState.getLanguage(), "ui.treadmill.paid", Format.comma(paid)),
			C.gold
		)
		Components.floatText(
			treadmillFrame,
			"+" .. Format.comma(paid),
			C.gold,
			UDim2.new(0.5, 0, 0, -10),
			Theme.text.title
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

	ScreenManager.onLayout(place)
	ScreenManager.onStateChanged(render)
	ClientState.onChanged(render)
	render()
end

-- 지금 경주 대기 중인지 (월드 연출이 쓴다)
function LobbyController.isQueued(): boolean
	return queued
end

function LobbyController.Start()
	-- 대기 중에는 남은 시간과 막대를 다시 그린다.
	task.spawn(function()
		while true do
			task.wait(0.2)
			if queued then
				render()
			end
		end
	end)
end

return LobbyController
