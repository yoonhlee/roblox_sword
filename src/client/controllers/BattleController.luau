--!strict
--[[
	BattleController — 도전 상대 고르기, 도전장 받기, 결과 보기.

	클라이언트는 "누구에게 도전할지"와 "수락/거절"만 보낸다.
	승패·보상·레이팅은 전부 서버가 정한 값을 그대로 보여 준다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))

local controllers = script.Parent
local ClientState = require(controllers.Parent:WaitForChild("ClientState"))
local FeedController = require(controllers:WaitForChild("FeedController"))
local SoundController = require(controllers:WaitForChild("SoundController"))

local BattleController = {}
BattleController.Name = "BattleController"

local COLOR_PANEL = Color3.fromRGB(34, 30, 38)
local COLOR_SUB = Color3.fromRGB(52, 46, 58)
local COLOR_TEXT = Color3.fromRGB(240, 236, 230)
local COLOR_MUTED = Color3.fromRGB(168, 160, 172)
local COLOR_ACCENT = Color3.fromRGB(226, 142, 58)
local COLOR_WIN = Color3.fromRGB(150, 230, 160)
local COLOR_LOSS = Color3.fromRGB(255, 130, 118)

local TOUCH_MIN = 44

local gui: ScreenGui
local listPanel: Frame
local listTitle: TextLabel
local listScroller: ScrollingFrame
local randomButton: TextButton
local listClose: TextButton

local invitePanel: Frame
local inviteLabel: TextLabel
local inviteTimer: TextLabel
local acceptButton: TextButton
local declineButton: TextButton

local resultPanel: Frame
local resultTitle: TextLabel
local resultDetail: TextLabel
local resultClose: TextButton

local challengeRemote: RemoteFunction
local respondRemote: RemoteFunction
local targetsRemote: RemoteFunction

local inviteExpiresAt = 0
local busy = false

local function corner(parent: Instance, radius: number)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function makePanel(name: string, height: number): Frame
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.BackgroundColor3 = COLOR_PANEL
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0, height)
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 14)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(460, 620)
	sizeConstraint.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = panel

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = panel

	return panel
end

local function makeLabel(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = COLOR_TEXT
	label.TextSize = 16
	label.Size = UDim2.new(1, 0, 0, 22)
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
	button.Size = UDim2.new(1, 0, 0, TOUCH_MIN)
	button.Text = ""
	for key, value in props do
		(button :: any)[key] = value
	end
	button.Parent = parent
	corner(button, 10)
	return button
end

local function closeAll()
	listPanel.Visible = false
	invitePanel.Visible = false
end

local function sendChallenge(targetUserId: number?)
	if busy then
		return
	end
	busy = true
	listPanel.Visible = false

	local ok, response = pcall(function()
		return challengeRemote:InvokeServer(targetUserId)
	end)

	busy = false

	if not ok or type(response) ~= "table" then
		FeedController.pushRaw(Locale.get(ClientState.getLanguage(), "error.unknown"), COLOR_LOSS)
		return
	end

	if response.ok ~= true then
		FeedController.pushRaw(
			Locale.get(ClientState.getLanguage(), `error.{tostring(response.reason)}`),
			COLOR_LOSS
		)
	end
end

local function refreshTargets()
	local language = ClientState.getLanguage()

	listTitle.Text = Locale.get(language, "ui.battleTitle")
	randomButton.Text = Locale.get(language, "ui.battleRandom")
	listClose.Text = Locale.get(language, "ui.close")

	for _, child in listScroller:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local ok, targets = pcall(function()
		return targetsRemote:InvokeServer()
	end)

	if not ok or type(targets) ~= "table" or #targets == 0 then
		local empty = makeLabel(listScroller, {
			Text = Locale.get(language, "ui.noOpponent"),
			TextColor3 = COLOR_MUTED,
			LayoutOrder = 1,
		})
		empty.Size = UDim2.new(1, 0, 0, 30)
		return
	end

	for index, target in targets do
		local row = makeButton(listScroller, {
			Text = Locale.get(language, "ui.battleRow", target.name, target.level, target.rating),
			TextSize = 15,
			Font = Enum.Font.GothamMedium,
			LayoutOrder = index,
		})
		row.Activated:Connect(function()
			sendChallenge(target.userId)
		end)
	end
end

local function showInvite(payload: any)
	local language = ClientState.getLanguage()

	inviteExpiresAt = tonumber(payload.expiresAt) or 0
	inviteLabel.Text = Locale.get(
		language,
		"battle.invite",
		tostring(payload.challengerName),
		tonumber(payload.challengerLevel) or 0
	)
	acceptButton.Text = Locale.get(language, "ui.accept")
	declineButton.Text = Locale.get(language, "ui.decline")

	listPanel.Visible = false
	invitePanel.Visible = true
	SoundController.play("click")
end

local function respond(accept: boolean)
	invitePanel.Visible = false

	task.spawn(function()
		local ok, response = pcall(function()
			return respondRemote:InvokeServer(accept)
		end)

		if ok and type(response) == "table" and response.ok ~= true then
			FeedController.pushRaw(
				Locale.get(ClientState.getLanguage(), `error.{tostring(response.reason)}`),
				COLOR_LOSS
			)
		end
	end)
end

local function showResult(payload: any)
	local language = ClientState.getLanguage()
	local won = payload.won == true

	resultTitle.Text = Locale.get(language, if won then "battle.win" else "battle.loss")
	resultTitle.TextColor3 = if won then COLOR_WIN else COLOR_LOSS

	local lines = {
		Locale.get(language, "battle.reward", Format.comma(payload.goldGained or 0)),
		Locale.get(
			language,
			"battle.rating",
			math.floor(payload.ratingBefore or 0),
			math.floor(payload.ratingAfter or 0)
		),
		Locale.get(language, "battle.odds", Format.ratio(payload.winProbability or 0)),
	}

	if payload.rewardCapped then
		table.insert(lines, Locale.get(language, "battle.capped"))
	end

	resultDetail.Text = table.concat(lines, "\n")
	resultClose.Text = Locale.get(language, "ui.close")
	resultPanel.Visible = true

	FeedController.pushRaw(
		Locale.get(
			language,
			if won then "battle.feedWin" else "battle.feedLoss",
			tostring(payload.opponentName)
		),
		if won then COLOR_WIN else COLOR_LOSS
	)
	SoundController.play(if won then "success" else "keep")
end

local function build()
	local player = Players.LocalPlayer

	gui = Instance.new("ScreenGui")
	gui.Name = "ForgeBattle"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")

	-- 상대 목록
	listPanel = makePanel("TargetList", 380)
	listTitle = makeLabel(listPanel, {
		TextSize = 20,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 1,
	})

	listScroller = Instance.new("ScrollingFrame")
	listScroller.BackgroundTransparency = 1
	listScroller.BorderSizePixel = 0
	listScroller.Size = UDim2.new(1, 0, 0, 220)
	listScroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	listScroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listScroller.ScrollBarThickness = 4
	listScroller.LayoutOrder = 2
	listScroller.Parent = listPanel

	local scrollList = Instance.new("UIListLayout")
	scrollList.FillDirection = Enum.FillDirection.Vertical
	scrollList.SortOrder = Enum.SortOrder.LayoutOrder
	scrollList.Padding = UDim.new(0, 6)
	scrollList.Parent = listScroller

	randomButton = makeButton(listPanel, {
		BackgroundColor3 = COLOR_ACCENT,
		TextColor3 = Color3.fromRGB(24, 18, 10),
		LayoutOrder = 3,
	})
	listClose = makeButton(listPanel, { LayoutOrder = 4 })

	-- 받은 도전
	invitePanel = makePanel("Invite", 210)
	inviteLabel = makeLabel(invitePanel, {
		TextSize = 17,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 1,
	})
	inviteTimer = makeLabel(invitePanel, {
		TextSize = 14,
		TextColor3 = COLOR_MUTED,
		LayoutOrder = 2,
	})
	acceptButton = makeButton(invitePanel, {
		BackgroundColor3 = COLOR_ACCENT,
		TextColor3 = Color3.fromRGB(24, 18, 10),
		LayoutOrder = 3,
	})
	declineButton = makeButton(invitePanel, { LayoutOrder = 4 })

	-- 결과
	resultPanel = makePanel("Result", 230)
	resultTitle = makeLabel(resultPanel, {
		TextSize = 26,
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 1,
	})
	resultDetail = makeLabel(resultPanel, {
		TextSize = 15,
		TextColor3 = COLOR_MUTED,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 84),
		LayoutOrder = 2,
	})
	resultClose = makeButton(resultPanel, { LayoutOrder = 3 })

	randomButton.Activated:Connect(function()
		sendChallenge(nil)
	end)
	listClose.Activated:Connect(function()
		listPanel.Visible = false
	end)
	acceptButton.Activated:Connect(function()
		respond(true)
	end)
	declineButton.Activated:Connect(function()
		respond(false)
	end)
	resultClose.Activated:Connect(function()
		resultPanel.Visible = false
	end)
end

function BattleController.openTargetList()
	if listPanel.Visible then
		listPanel.Visible = false
		return
	end

	listPanel.Visible = true
	task.spawn(refreshTargets)
end

function BattleController.Init()
	build()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	challengeRemote =
		remotesFolder:WaitForChild(Remotes.Functions.ChallengeBattle) :: RemoteFunction
	respondRemote = remotesFolder:WaitForChild(Remotes.Functions.RespondBattle) :: RemoteFunction
	targetsRemote =
		remotesFolder:WaitForChild(Remotes.Functions.GetBattleTargets) :: RemoteFunction

	local inviteRemote = remotesFolder:WaitForChild(Remotes.Events.BattleInvite) :: RemoteEvent
	inviteRemote.OnClientEvent:Connect(function(payload: any)
		if payload == false then
			invitePanel.Visible = false -- 시간 초과 또는 취소
		elseif type(payload) == "table" then
			showInvite(payload)
		end
	end)

	local resolvedRemote = remotesFolder:WaitForChild(Remotes.Events.BattleResolved) :: RemoteEvent
	resolvedRemote.OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" then
			closeAll()
			showResult(payload)
		end
	end)
end

function BattleController.Start()
	-- 남은 응답 시간을 1초마다 갱신한다.
	task.spawn(function()
		while true do
			task.wait(1)
			if invitePanel.Visible then
				local remaining = math.max(0, inviteExpiresAt - os.time())
				inviteTimer.Text = Format.duration(remaining)

				if remaining <= 0 then
					invitePanel.Visible = false
				end
			end
		end
	end)
end

return BattleController
