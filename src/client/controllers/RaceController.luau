--!strict
--[[
	RaceController — 경주 화면 (통합 기획서 4·8-1절 결정 8).

	출발선에 선 순간부터 로비로 돌아올 때까지:
	  출발 전   화면 가운데 3 · 2 · 1 · 출발!
	  달리는 중 위쪽 가운데 진행 막대: 참가자 전원의 위치 점(나는 크고 주황), 추격자(빨강).
	            내 거리 / 내 최대 거리, 남은 사람 n/m, 추격자와의 간격(30칸 아래면 빨갛게 + 화면 가장자리 맥박)
	  탈락 후   결과 카드(순위·거리·최대 거리 대비 %·보상이 0부터 올라감), "다음 사람"·"로비로"
	  판 종료   순위표(상위 5명 + 내 순위), 자동 복귀 카운트다운
	특수 능력 버튼 자리(D16)는 점프 버튼 왼쪽에 만들어 두고 지금은 숨긴다.

	클라이언트는 표시만 한다. 진행 막대의 점·간격은 내 화면에 보이는 위치로 계산한 참고 값이고,
	결과(인정 거리·순위·보상)는 서버가 보낸 값을 그대로 보여 준다. 서버로 보내는 것은 "로비로" 하나뿐이다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))
local World = require(Shared:WaitForChild("Config"):WaitForChild("World"))

local client = script.Parent.Parent
local ClientState = require(client:WaitForChild("ClientState"))
local ui = client:WaitForChild("ui")
local Theme = require(ui:WaitForChild("Theme"))
local Components = require(ui:WaitForChild("Components"))
local ScreenManager = require(ui:WaitForChild("ScreenManager"))

local controllers = script.Parent
local FeedController = require(controllers:WaitForChild("FeedController"))
local SoundController = require(controllers:WaitForChild("SoundController"))

local RaceController = {}
RaceController.Name = "RaceController"

local C = Theme.color
local MAX_RANK_ROWS = 5
local HUD_INTERVAL = 0.08
local GO_TEXT_SECONDS = 1
local DANGER_GAP = 30

type Entrant = { userId: number, name: string, level: number, alive: boolean, dot: Frame? }

type RaceView = {
	id: number,
	originZ: number,
	level: number,
	maxDistance: number,
	entrants: { Entrant },
}

local phase: "none" | "lineup" | "racing" | "out" = "none"
local view: RaceView? = nil
local goAt = 0
local startedAt = 0
local spectateUserId: number? = nil
local resultPayload: any = nil
local finishedPayload: any = nil
local returnAt = 0
local chaserPart: BasePart? = nil
local lastCountdown = -1

local gui: ScreenGui
local hud: Frame
local distanceLabel: TextLabel
local aliveLabel: TextLabel
local track: Frame
local trackFill: Frame
local chaserMark: Frame
local dotsLayer: Frame
local gapLabel: TextLabel
local countdownLabel: TextLabel
local abilitySlot: Frame
local resultCard: Frame
local resultTitle: TextLabel
local resultBody: TextLabel
local rewardLabel: TextLabel
local nextButton: TextButton
local lobbyButton: TextButton

local edgeGui: ScreenGui
local edgeFrames: { Frame } = {}

local lobbyRemote: RemoteFunction

--------------------------------------------------------------------------------
-- 만들기
--------------------------------------------------------------------------------

local function build()
	gui = ScreenManager.createScreen("ForgeRace", 6)
	gui.Enabled = false

	hud = Components.panel(gui, { Name = "Hud", BackgroundColor3 = C.bg })
	distanceLabel = Components.label(
		hud,
		{ font = Theme.font.display, size = Theme.text.label, outline = true }
	)
	distanceLabel.Position = UDim2.fromOffset(14, 6)
	distanceLabel.Size = UDim2.new(0.6, -14, 0, 26)
	aliveLabel = Components.label(hud, {
		font = Theme.font.bodyBold,
		size = Theme.text.small,
		color = C.muted,
		align = Enum.TextXAlignment.Right,
	})
	aliveLabel.Position = UDim2.new(0.6, 0, 0, 6)
	aliveLabel.Size = UDim2.new(0.4, -14, 0, 26)

	track = Components.frame(hud, {
		BackgroundColor3 = C.sub,
		BackgroundTransparency = 0,
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -28, 0, 12),
	})
	Components.round(track)
	trackFill = Components.frame(track, {
		BackgroundColor3 = Theme.shade(C.ember, -0.3),
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(0, 1),
	})
	Components.round(trackFill)
	chaserMark = Components.frame(track, {
		BackgroundColor3 = C.fail,
		BackgroundTransparency = 0,
		Size = UDim2.new(0, 6, 1, 10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		ZIndex = 3,
	})
	Components.corner(chaserMark, 3)
	dotsLayer = Components.frame(track, { ZIndex = 4 })

	gapLabel = Components.label(
		hud,
		{ font = Theme.font.bodyBold, size = Theme.text.small, align = Enum.TextXAlignment.Center }
	)
	gapLabel.Position = UDim2.new(0, 0, 1, -24)
	gapLabel.Size = UDim2.new(1, 0, 0, 22)

	countdownLabel = Components.label(gui, {
		font = Theme.font.display,
		size = 120,
		color = C.ember,
		outline = true,
		align = Enum.TextXAlignment.Center,
	})
	countdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	countdownLabel.Size = UDim2.fromOffset(400, 150)
	countdownLabel.Visible = false
	local countStroke = countdownLabel:FindFirstChildOfClass("UIStroke")
	if countStroke then
		countStroke.Thickness = 5
	end
	local countScale = Instance.new("UIScale")
	countScale.Parent = countdownLabel

	-- 특수 능력 버튼 자리 (D16 미정이라 숨김)
	abilitySlot = Components.frame(gui, { Name = "AbilitySlot", Visible = false })

	resultCard = Components.panel(gui, { Name = "Result", Visible = false })
	resultTitle = Components.label(
		resultCard,
		{ font = Theme.font.display, size = Theme.text.title, color = C.ember, outline = true }
	)
	resultTitle.Position = UDim2.fromOffset(16, 10)
	resultTitle.Size = UDim2.new(0.5, -16, 0, 34)
	rewardLabel = Components.label(resultCard, {
		font = Theme.font.display,
		size = Theme.text.title,
		color = C.gold,
		outline = true,
		align = Enum.TextXAlignment.Right,
	})
	rewardLabel.Position = UDim2.new(0.5, 0, 0, 10)
	rewardLabel.Size = UDim2.new(0.5, -16, 0, 34)
	resultBody =
		Components.label(resultCard, { size = Theme.text.small, color = C.muted, wrap = true })
	resultBody.TextYAlignment = Enum.TextYAlignment.Top
	resultBody.Position = UDim2.fromOffset(16, 48)
	resultBody.Size = UDim2.new(1, -32, 1, -(48 + Theme.touchHeight + 20))

	nextButton = Components.button(resultCard, { style = "secondary", size = Theme.text.body })
	nextButton.AnchorPoint = Vector2.new(0, 1)
	nextButton.Position = UDim2.new(0, 16, 1, -12)
	nextButton.Size = UDim2.new(0.5, -20, 0, Theme.touchHeight)
	lobbyButton = Components.button(resultCard, { style = "primary", size = Theme.text.body })
	lobbyButton.AnchorPoint = Vector2.new(1, 1)
	lobbyButton.Position = UDim2.new(1, -16, 1, -12)
	lobbyButton.Size = UDim2.new(0.5, -20, 0, Theme.touchHeight)

	-- 추격자가 가까울 때 화면 가장자리가 붉게 맥박친다
	edgeGui = ScreenManager.createOverlay("ForgeRaceEdge", 2)
	edgeGui.Enabled = false
	local sides = {
		{ UDim2.new(1, 0, 0.2, 0), UDim2.fromScale(0, 0), 90 },
		{ UDim2.new(1, 0, 0.2, 0), UDim2.fromScale(0, 0.8), -90 },
		{ UDim2.new(0.15, 0, 1, 0), UDim2.fromScale(0, 0), 0 },
		{ UDim2.new(0.15, 0, 1, 0), UDim2.fromScale(0.85, 0), 180 },
	}
	for _, side in sides do
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = C.fail
		frame.Size = side[1]
		frame.Position = side[2]
		frame.Parent = edgeGui
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new(0.2, 1)
		gradient.Rotation = side[3]
		gradient.Parent = frame
		table.insert(edgeFrames, frame)
	end
end

local function place()
	local layout = ScreenManager.getLayout()
	if layout == nil then
		return
	end
	ScreenManager.place(hud, layout.raceHud)
	ScreenManager.place(abilitySlot, layout.raceAbility)
	ScreenManager.place(resultCard, layout.raceResult)
	countdownLabel.Position = UDim2.fromOffset(layout.width / 2, layout.height * 0.4)
end

--------------------------------------------------------------------------------
-- 참가자 · 관전
--------------------------------------------------------------------------------

local function findEntrant(userId: number?): Entrant?
	local current = view
	if current == nil or userId == nil then
		return nil
	end
	for _, entrant in current.entrants do
		if entrant.userId == userId then
			return entrant
		end
	end
	return nil
end

local function rootOf(player: Player?): BasePart?
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function setCameraSubject(player: Player?)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local target = player or Players.LocalPlayer
	local character = target.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function nextAlive(after: number?): number?
	local current = view
	if current == nil then
		return nil
	end
	local localId = Players.LocalPlayer.UserId
	local entrants = current.entrants
	local count = #entrants
	local startIndex = 0
	for index, entrant in entrants do
		if entrant.userId == after then
			startIndex = index
			break
		end
	end
	for offset = 1, count do
		local entrant = entrants[(startIndex + offset - 1) % count + 1]
		if
			entrant.alive
			and entrant.userId ~= localId
			and Players:GetPlayerByUserId(entrant.userId) ~= nil
		then
			return entrant.userId
		end
	end
	return nil
end

local function spectate(userId: number?)
	spectateUserId = userId
	setCameraSubject(if userId then Players:GetPlayerByUserId(userId) else nil)
end

local function findChaser(): BasePart?
	local current = view
	if current == nil then
		return nil
	end
	local cached = chaserPart
	if cached and cached.Parent ~= nil then
		return cached
	end
	local races = Workspace:FindFirstChild(World.RACES_FOLDER)
	local folder = if races
		then races:FindFirstChild(`{World.RACE_FOLDER_PREFIX}{current.id}`)
		else nil
	local part = if folder then folder:FindFirstChild(World.CHASER_NAME) else nil
	if part and part:IsA("BasePart") then
		chaserPart = part
		return part
	end
	return nil
end

-- 진행 막대의 참가자 점 (처음 한 번 만든다)
local function buildDots()
	Components.clear(dotsLayer)
	local current = view
	if current == nil then
		return
	end
	local localId = Players.LocalPlayer.UserId
	for _, entrant in current.entrants do
		local mine = entrant.userId == localId
		local size = if mine then 18 else 12
		local dot = Components.frame(dotsLayer, {
			BackgroundColor3 = if mine then C.ember else Theme.heatColor(entrant.level),
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(size, size),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			ZIndex = if mine then 6 else 5,
		})
		Components.round(dot)
		Components.stroke(dot, C.outline, if mine then 3 else 2)
		entrant.dot = dot
	end
end

--------------------------------------------------------------------------------
-- 그리기
--------------------------------------------------------------------------------

local function resultText(language: string): string
	local lines: { string } = {}

	local result = resultPayload
	if type(result) == "table" then
		local distance = tonumber(result.distance) or 0
		local maxDistance = tonumber(result.maxDistance) or 0
		local ratio = if maxDistance > 0 then math.min(1, distance / maxDistance) else 0
		table.insert(
			lines,
			Locale.get(
				language,
				"ui.race.result",
				tonumber(result.racerCount) or 1,
				tonumber(result.rank) or 1,
				Format.comma(distance),
				Format.ratio(ratio, 0)
			)
		)
		local bonus = tonumber(result.bonus) or 0
		if bonus > 0 then
			table.insert(lines, Locale.get(language, "ui.race.bonus", Format.comma(bonus)))
		end
	end

	local finished = finishedPayload
	if type(finished) == "table" and type(finished.ranking) == "table" then
		table.insert(
			lines,
			Locale.get(language, "ui.race.finished", math.max(0, math.ceil(returnAt - os.clock())))
		)
		local localId = Players.LocalPlayer.UserId
		local shownMine = false
		for index, row in finished.ranking do
			if type(row) ~= "table" then
				continue
			end
			local mine = row.userId == localId
			if index <= MAX_RANK_ROWS or (mine and not shownMine) then
				table.insert(
					lines,
					Locale.get(
						language,
						"ui.race.rankRow",
						tonumber(row.rank) or index,
						tostring(row.name),
						tonumber(row.level) or 0,
						Format.comma(tonumber(row.distance) or 0)
					)
				)
				if mine then
					shownMine = true
				end
			end
		end
	else
		local watched = findEntrant(spectateUserId)
		if watched then
			table.insert(
				lines,
				Locale.get(language, "ui.race.spectating", watched.name, watched.level)
			)
		end
	end

	return table.concat(lines, "\n")
end

local function setEdge(danger: boolean)
	edgeGui.Enabled = danger
	if danger then
		local pulse = 0.25 + 0.25 * math.sin(os.clock() * 8)
		for _, frame in edgeFrames do
			frame.BackgroundTransparency = pulse
		end
	end
end

local function render()
	local language = ClientState.getLanguage()
	local current = view

	gui.Enabled = phase ~= "none"
	if phase == "none" or current == nil then
		setEdge(false)
		return
	end

	local now = os.clock()

	-- 카운트다운
	if phase == "lineup" then
		local number = math.max(1, math.ceil(goAt - now))
		countdownLabel.Visible = true
		countdownLabel.Text = tostring(number)
		if number ~= lastCountdown then
			lastCountdown = number
			SoundController.play("tick")
			local scale = countdownLabel:FindFirstChildOfClass("UIScale") :: UIScale
			scale.Scale = 1.5
			TweenService:Create(scale, Theme.motion.pop, { Scale = 1 }):Play()
		end
	elseif phase == "racing" and now - startedAt < GO_TEXT_SECONDS then
		countdownLabel.Visible = true
		countdownLabel.Text = Locale.get(language, "ui.race.go")
	else
		countdownLabel.Visible = false
	end

	-- 진행 막대
	local localPlayer = Players.LocalPlayer
	local watched = localPlayer
	if phase == "out" and spectateUserId ~= nil then
		watched = Players:GetPlayerByUserId(spectateUserId) or localPlayer
	end

	local chaser = findChaser()
	local chaserFront = if chaser
		then chaser.Position.Z + chaser.Size.Z / 2 - current.originZ
		else -30

	local trackMax = math.max(current.maxDistance, 1)
	local positions: { [number]: number } = {}
	local aliveCount = 0
	for _, entrant in current.entrants do
		if entrant.alive then
			aliveCount += 1
		end
		local root = rootOf(Players:GetPlayerByUserId(entrant.userId))
		if root then
			local distance = math.max(0, root.Position.Z - current.originZ)
			positions[entrant.userId] = distance
			trackMax = math.max(trackMax, distance * 1.05)
		end
	end

	for _, entrant in current.entrants do
		local dot = entrant.dot
		if dot then
			local distance = positions[entrant.userId]
			dot.Visible = distance ~= nil and entrant.alive
			if distance then
				dot.Position = UDim2.fromScale(math.clamp(distance / trackMax, 0, 1), 0.5)
			end
		end
	end
	chaserMark.Position = UDim2.fromScale(math.clamp(chaserFront / trackMax, 0, 1), 0.5)

	local myDistance = positions[watched.UserId] or 0
	trackFill.Size = UDim2.fromScale(math.clamp(myDistance / trackMax, 0, 1), 1)

	if watched == localPlayer then
		distanceLabel.Text = Locale.get(
			language,
			"ui.race.distance",
			Format.comma(math.floor(myDistance)),
			Format.comma(math.floor(current.maxDistance))
		)
	else
		distanceLabel.Text =
			Locale.get(language, "ui.race.distanceOnly", Format.comma(math.floor(myDistance)))
	end
	aliveLabel.Text = Locale.get(language, "ui.race.alive", aliveCount, #current.entrants)

	local gap = math.max(0, math.floor(myDistance - chaserFront))
	gapLabel.Text = Locale.get(language, "ui.race.gap", Format.comma(gap))
	local danger = phase == "racing" and gap < DANGER_GAP
	gapLabel.TextColor3 = if danger then C.fail else C.text
	setEdge(danger)

	-- 결과 카드
	resultCard.Visible = phase == "out"
	if phase == "out" then
		resultTitle.Text = Locale.get(language, "ui.race.caught")
		resultBody.Text = resultText(language)
		nextButton.Text = Locale.get(language, "ui.race.next")
		lobbyButton.Text = Locale.get(language, "ui.race.toLobby")
		nextButton.Visible = finishedPayload == nil and nextAlive(spectateUserId) ~= nil
	end
end

-- 보상 숫자가 0 부터 올라간다 (0.8초)
local function countUpReward(amount: number)
	local language = ClientState.getLanguage()
	task.spawn(function()
		local duration = 0.8
		local started = os.clock()
		while true do
			local t = math.min(1, (os.clock() - started) / duration)
			local eased = 1 - (1 - t) ^ 3
			rewardLabel.Text = "+" .. Format.short(math.floor(amount * eased), language)
			if t >= 1 then
				break
			end
			task.wait(0.03)
		end
		if amount > 0 then
			SoundController.play("coin")
		end
	end)
end

--------------------------------------------------------------------------------
-- 서버 알림
--------------------------------------------------------------------------------

local function leaveRaceView()
	phase = "none"
	view = nil
	spectateUserId = nil
	resultPayload = nil
	finishedPayload = nil
	chaserPart = nil
	lastCountdown = -1
	Components.clear(dotsLayer)

	setCameraSubject(nil)
	ScreenManager.setMode("lobby")
	render()
end

local function onLineup(payload: any)
	local entrants: { Entrant } = {}
	if type(payload.entrants) == "table" then
		for _, entry in payload.entrants do
			if type(entry) == "table" and type(entry.userId) == "number" then
				table.insert(entrants, {
					userId = entry.userId,
					name = tostring(entry.name),
					level = tonumber(entry.level) or 0,
					alive = true,
				})
			end
		end
	end

	view = {
		id = tonumber(payload.raceId) or 0,
		originZ = tonumber(payload.originZ) or 0,
		level = tonumber(payload.level) or 0,
		maxDistance = tonumber(payload.maxDistance) or 0,
		entrants = entrants,
	}

	phase = "lineup"
	goAt = os.clock() + (tonumber(payload.countdown) or 0)
	spectateUserId = nil
	resultPayload = nil
	finishedPayload = nil
	chaserPart = nil
	lastCountdown = -1
	rewardLabel.Text = ""

	buildDots()
	setCameraSubject(nil)
	ScreenManager.setMode("race")
	render()
end

local function onRaceUpdate(payload: any)
	if type(payload) ~= "table" then
		return
	end

	local kind = payload.kind
	if kind == "lineup" then
		onLineup(payload)
		return
	elseif kind == "lobby" then
		leaveRaceView()
		return
	end

	local current = view
	if current == nil or payload.raceId ~= current.id then
		return
	end

	if kind == "start" then
		if phase == "lineup" then
			phase = "racing"
			startedAt = os.clock()
			SoundController.play("go")
		end
	elseif kind == "eliminated" then
		local entrant = findEntrant(tonumber(payload.userId))
		if entrant then
			entrant.alive = false
		end
		if phase == "out" and spectateUserId == payload.userId then
			spectate(nextAlive(spectateUserId))
		end
	elseif kind == "result" then
		phase = "out"
		resultPayload = payload
		local mine = findEntrant(Players.LocalPlayer.UserId)
		if mine then
			mine.alive = false
		end

		SoundController.play("caught")
		local reward = tonumber(payload.reward) or 0
		FeedController.pushRaw(
			Locale.get(
				ClientState.getLanguage(),
				"ui.race.rewardFeed",
				Format.comma(reward),
				Format.comma(tonumber(payload.distance) or 0)
			),
			C.gold
		)
		countUpReward(reward)
		ScreenManager.setMode("raceOut")
		spectate(nextAlive(nil))
	elseif kind == "finished" then
		finishedPayload = payload
		returnAt = os.clock() + (tonumber(payload.returnIn) or 0)
		if phase == "out" then
			spectate(nil)
		end
	end

	render()
end

local function requestLobby()
	local ok, response = pcall(function()
		return lobbyRemote:InvokeServer()
	end)
	if ok and type(response) == "table" and response.ok == true then
		leaveRaceView()
		return
	end
	local reason = if ok and type(response) == "table" then tostring(response.reason) else "unknown"
	FeedController.pushRaw(Locale.get(ClientState.getLanguage(), `error.{reason}`), C.fail)
end

function RaceController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	lobbyRemote = remotesFolder:WaitForChild(Remotes.Functions.ReturnToLobby) :: RemoteFunction
	local raceRemote = remotesFolder:WaitForChild(Remotes.Events.RaceUpdate) :: RemoteEvent
	raceRemote.OnClientEvent:Connect(onRaceUpdate)

	nextButton.Activated:Connect(function()
		SoundController.play("click")
		spectate(nextAlive(spectateUserId))
		render()
	end)
	lobbyButton.Activated:Connect(function()
		SoundController.play("click")
		task.spawn(requestLobby)
	end)

	ScreenManager.onLayout(place)
	render()
end

function RaceController.Start()
	task.spawn(function()
		while true do
			task.wait(HUD_INTERVAL)
			if phase == "none" then
				continue
			end
			if phase == "out" and spectateUserId ~= nil and finishedPayload == nil then
				if Players:GetPlayerByUserId(spectateUserId) == nil then
					spectate(nextAlive(spectateUserId))
				end
			end
			local ok, err = pcall(render)
			if not ok then
				warn(`[RaceController] 화면 갱신 오류: {err}`)
			end
		end
	end)
end

-- 지금 경주 화면인지 (월드 연출이 쓴다)
function RaceController.isActive(): boolean
	return phase ~= "none"
end

return RaceController
