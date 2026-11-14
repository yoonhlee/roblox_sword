--!strict
--[[
	RaceController — 경주 화면 (통합 기획서 4절, 8절).

	출발선에 선 순간부터 로비로 돌아올 때까지의 화면을 맡는다.
	  출발 전   카운트다운
	  달리는 중 지금 거리 / 내 최대 거리, 추격자와의 간격
	  탈락 후   결과(순위·거리·보상), 관전(다른 사람 화면), "로비로" 버튼
	  판 종료   최종 순위표

	클라이언트는 표시만 한다.
	- 화면의 "지금 거리"와 "추격자와의 간격"은 내 화면에 보이는 위치로 계산한 참고 값이다.
	- 결과(인정 거리·순위·보상)는 전부 서버가 보낸 값을 그대로 보여 준다.
	- 서버로 보내는 것은 "로비로" 요청 하나뿐이다. 거리나 위치는 보내지 않는다.

	[미정 D16] 특수 능력 버튼은 능력이 정해지면 이 화면에 추가한다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))
local World = require(Shared:WaitForChild("Config"):WaitForChild("World"))

local controllers = script.Parent
local ClientState = require(controllers.Parent:WaitForChild("ClientState"))
local FeedController = require(controllers:WaitForChild("FeedController"))
local SoundController = require(controllers:WaitForChild("SoundController"))

local RaceController = {}
RaceController.Name = "RaceController"

local COLOR_PANEL = Color3.fromRGB(34, 30, 38)
local COLOR_SUB = Color3.fromRGB(52, 46, 58)
local COLOR_TEXT = Color3.fromRGB(240, 236, 230)
local COLOR_MUTED = Color3.fromRGB(200, 194, 204)
local COLOR_ACCENT = Color3.fromRGB(226, 142, 58)
local COLOR_DANGER = Color3.fromRGB(255, 120, 108)
local COLOR_GOLD = Color3.fromRGB(255, 208, 112)

local TOUCH_MIN = 44
local MAX_RANK_ROWS = 5
local HUD_INTERVAL_SECONDS = 0.1
local GO_TEXT_SECONDS = 1

type Entrant = {
	userId: number,
	name: string,
	level: number,
	alive: boolean,
}

type RaceView = {
	id: number,
	originZ: number,
	level: number,
	maxDistance: number,
	entrants: { Entrant }, -- 서버가 보낸 순서
}

-- none: 경주 중 아님 / lineup: 출발 전 / racing: 달리는 중 / out: 탈락(관전)
local mode: "none" | "lineup" | "racing" | "out" = "none"
local view: RaceView? = nil
local goAt = 0 -- 출발 예정 시각 (os.clock)
local startedAt = 0
local spectateUserId: number? = nil
local resultPayload: any = nil
local finishedPayload: any = nil
local returnAt = 0
local chaserPart: BasePart? = nil

local gui: ScreenGui
local distanceLabel: TextLabel
local gapLabel: TextLabel
local countdownLabel: TextLabel
local resultPanel: Frame
local resultTitle: TextLabel
local resultBody: TextLabel
local nextButton: TextButton
local lobbyButton: TextButton

local lobbyRemote: RemoteFunction

local function corner(parent: Instance, radius: number)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function makeLabel(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = COLOR_TEXT
	label.TextSize = 18
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

local function build()
	local player = Players.LocalPlayer

	gui = Instance.new("ScreenGui")
	gui.Name = "ForgeRace"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- 위쪽 가운데: 거리와 추격자 간격
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundColor3 = Color3.fromRGB(18, 16, 20)
	top.BackgroundTransparency = 0.35
	top.BorderSizePixel = 0
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 44)
	top.Size = UDim2.fromOffset(300, 62)
	top.Parent = gui
	corner(top, 10)

	distanceLabel = makeLabel(top, {
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.fromOffset(0, 2),
		TextSize = 20,
	})
	gapLabel = makeLabel(top, {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 34),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		TextColor3 = COLOR_DANGER,
	})

	-- 가운데: 출발 카운트다운
	countdownLabel = makeLabel(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(320, 110),
		TextSize = 84,
		TextColor3 = COLOR_ACCENT,
		Visible = false,
	})

	-- 아래쪽 가운데: 결과와 관전 조작
	resultPanel = Instance.new("Frame")
	resultPanel.Name = "Result"
	resultPanel.BackgroundColor3 = COLOR_PANEL
	resultPanel.BackgroundTransparency = 0.08
	resultPanel.BorderSizePixel = 0
	resultPanel.AnchorPoint = Vector2.new(0.5, 1)
	resultPanel.Position = UDim2.new(0.5, 0, 1, -16)
	resultPanel.Size = UDim2.new(0.9, 0, 0, 236)
	resultPanel.Visible = false
	resultPanel.Parent = gui
	corner(resultPanel, 14)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(380, math.huge)
	sizeConstraint.Parent = resultPanel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = resultPanel

	resultTitle = makeLabel(resultPanel, {
		Size = UDim2.new(1, 0, 0, 26),
		TextSize = 20,
		TextColor3 = COLOR_ACCENT,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	resultBody = makeLabel(resultPanel, {
		Size = UDim2.new(1, 0, 1, -(26 + 6 + TOUCH_MIN + 6)),
		Position = UDim2.fromOffset(0, 32),
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		TextColor3 = COLOR_MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	})

	nextButton = makeButton(resultPanel, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0.5, -4, 0, TOUCH_MIN),
		Font = Enum.Font.GothamMedium,
	})
	lobbyButton = makeButton(resultPanel, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0.5, -4, 0, TOUCH_MIN),
		BackgroundColor3 = COLOR_ACCENT,
		TextColor3 = Color3.fromRGB(24, 18, 10),
	})
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

-- 카메라가 따라갈 사람을 정한다. nil 이면 나 자신.
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

-- 아직 달리고 있는 다른 사람 중 after 다음 사람을 고른다. 없으면 nil.
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

--------------------------------------------------------------------------------
-- 그리기
--------------------------------------------------------------------------------

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
		table.insert(
			lines,
			Locale.get(language, "ui.race.reward", Format.comma(tonumber(result.reward) or 0))
		)

		local bonus = tonumber(result.bonus) or 0
		if bonus > 0 then
			table.insert(lines, Locale.get(language, "ui.race.bonus", Format.comma(bonus)))
		end
	end

	local finished = finishedPayload
	if type(finished) == "table" and type(finished.ranking) == "table" then
		local secondsLeft = math.max(0, math.ceil(returnAt - os.clock()))
		table.insert(lines, Locale.get(language, "ui.race.finished", secondsLeft))

		for index, row in finished.ranking do
			if index > MAX_RANK_ROWS then
				break
			end
			if type(row) == "table" then
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

local function render()
	local language = ClientState.getLanguage()
	local current = view

	gui.Enabled = mode ~= "none"
	if mode == "none" or current == nil then
		return
	end

	local now = os.clock()

	-- 카운트다운 / 출발 표시
	if mode == "lineup" then
		countdownLabel.Visible = true
		countdownLabel.Text = tostring(math.max(1, math.ceil(goAt - now)))
	elseif mode == "racing" and now - startedAt < GO_TEXT_SECONDS then
		countdownLabel.Visible = true
		countdownLabel.Text = Locale.get(language, "ui.race.go")
	else
		countdownLabel.Visible = false
	end

	-- 거리와 추격자 간격. 관전 중이면 보고 있는 사람 기준.
	local watchedPlayer = Players.LocalPlayer
	local watchedMax = current.maxDistance
	if mode == "out" and spectateUserId ~= nil then
		local other = Players:GetPlayerByUserId(spectateUserId)
		if other then
			watchedPlayer = other
			watchedMax = 0
		end
	end

	local root = rootOf(watchedPlayer)
	local chaser = findChaser()

	if root then
		local distance = math.max(0, math.floor(root.Position.Z - current.originZ))

		if watchedMax > 0 then
			distanceLabel.Text = Locale.get(
				language,
				"ui.race.distance",
				Format.comma(distance),
				Format.comma(math.floor(watchedMax))
			)
		else
			distanceLabel.Text =
				Locale.get(language, "ui.race.distanceOnly", Format.comma(distance))
		end

		if chaser then
			local front = chaser.Position.Z + chaser.Size.Z / 2
			local gap = math.max(0, math.floor(root.Position.Z - front))
			gapLabel.Text = Locale.get(language, "ui.race.gap", Format.comma(gap))
		else
			gapLabel.Text = ""
		end
	else
		distanceLabel.Text = ""
		gapLabel.Text = ""
	end

	-- 결과 패널
	resultPanel.Visible = mode == "out"
	if mode == "out" then
		resultTitle.Text = Locale.get(language, "ui.race.caught")
		resultBody.Text = resultText(language)
		nextButton.Text = Locale.get(language, "ui.race.next")
		lobbyButton.Text = Locale.get(language, "ui.race.toLobby")

		local canSwitch = finishedPayload == nil and nextAlive(spectateUserId) ~= nil
		nextButton.Visible = canSwitch
	end
end

--------------------------------------------------------------------------------
-- 서버 알림
--------------------------------------------------------------------------------

local function leaveRaceView()
	mode = "none"
	view = nil
	spectateUserId = nil
	resultPayload = nil
	finishedPayload = nil
	chaserPart = nil

	setCameraSubject(nil)
	ClientState.setInRace(false)
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

	mode = "lineup"
	goAt = os.clock() + (tonumber(payload.countdown) or 0)
	spectateUserId = nil
	resultPayload = nil
	finishedPayload = nil
	chaserPart = nil

	setCameraSubject(nil)
	ClientState.setInRace(true)
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

	-- 아래 알림은 지금 보고 있는 판의 것만 받는다.
	local current = view
	if current == nil or payload.raceId ~= current.id then
		return
	end

	if kind == "start" then
		if mode == "lineup" then
			mode = "racing"
			startedAt = os.clock()
		end
	elseif kind == "eliminated" then
		local entrant = findEntrant(tonumber(payload.userId))
		if entrant then
			entrant.alive = false
		end

		-- 보고 있던 사람이 잡혔으면 다른 사람으로 넘어간다.
		if mode == "out" and spectateUserId == payload.userId then
			spectate(nextAlive(spectateUserId))
		end
	elseif kind == "result" then
		mode = "out"
		resultPayload = payload

		local mine = findEntrant(Players.LocalPlayer.UserId)
		if mine then
			mine.alive = false
		end

		SoundController.play("fail")
		FeedController.pushRaw(
			Locale.get(
				ClientState.getLanguage(),
				"ui.race.rewardFeed",
				Format.comma(tonumber(payload.reward) or 0),
				Format.comma(tonumber(payload.distance) or 0)
			),
			COLOR_GOLD
		)

		spectate(nextAlive(nil))
	elseif kind == "finished" then
		finishedPayload = payload
		returnAt = os.clock() + (tonumber(payload.returnIn) or 0)
		if mode == "out" then
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
		-- 서버도 kind = "lobby" 를 보내지만, 놓쳤을 때를 대비해 여기서도 화면을 닫는다.
		leaveRaceView()
		return
	end

	local reason = if ok and type(response) == "table" then tostring(response.reason) else "unknown"
	FeedController.pushRaw(Locale.get(ClientState.getLanguage(), `error.{reason}`), COLOR_DANGER)
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

	render()
end

function RaceController.Start()
	-- 경주 화면이 떠 있는 동안 숫자를 다시 그린다.
	task.spawn(function()
		while true do
			task.wait(HUD_INTERVAL_SECONDS)

			if mode == "none" then
				continue
			end

			-- 관전하던 사람이 나갔으면 다른 사람으로 넘어간다.
			if mode == "out" and spectateUserId ~= nil and finishedPayload == nil then
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

return RaceController
