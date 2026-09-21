--!strict
--[[
	FeedController — 결과 피드.
	채팅 로그처럼 최근 결과가 한 줄씩 쌓인다. 모루 영감의 대사로 출력한다.

	Phase 2 에서 연출(페이드, 강조색, 접이식 모바일 레이아웃)을 다듬는다.
	지금은 "서버 응답을 받은 뒤에만 한 줄 추가된다"는 흐름을 먼저 세운다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local FeedController = {}
FeedController.Name = "FeedController"

local MAX_LINES = 7
local NARROW_WIDTH = 700

local OUTCOME_COLOR: { [string]: Color3 } = {
	system = Color3.fromRGB(230, 226, 220),
	success = Color3.fromRGB(255, 208, 112),
	keep = Color3.fromRGB(198, 198, 198),
	destroy = Color3.fromRGB(255, 120, 108),
	protected = Color3.fromRGB(140, 210, 255),
	broadcast = Color3.fromRGB(180, 255, 190),
}

local container: Frame? = nil
local toggleButton: TextButton? = nil
local lineCount = 0
local collapsed = false

local function layout()
	local frame = container
	if frame == nil then
		return
	end

	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
	local isNarrow = viewport ~= nil and viewport.X < NARROW_WIDTH

	local button = toggleButton

	if isNarrow then
		-- 모바일: 화면 위쪽에 가로로 넓게, 접을 수 있게
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Position = UDim2.new(0.5, 0, 0, 64)
		frame.Size = UDim2.new(1, -24, 0, if collapsed then 0 else 132)
		frame.Visible = not collapsed

		if button then
			button.Visible = true
			button.AnchorPoint = Vector2.new(0.5, 0)
			button.Position = UDim2.new(0.5, 0, 0, if collapsed then 64 else 200)
		end
	else
		-- 데스크톱: 우측 세로 (항상 펼침)
		frame.AnchorPoint = Vector2.new(1, 0)
		frame.Position = UDim2.new(1, -16, 0, 72)
		frame.Size = UDim2.new(0, 320, 0, 220)
		frame.Visible = true

		if button then
			button.Visible = false
		end
	end
end

local function build()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "ForgeFeed"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Lines"
	frame.BackgroundColor3 = Color3.fromRGB(18, 16, 20)
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = frame

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.Padding = UDim.new(0, 2)
	list.Parent = frame

	-- 모바일에서 피드를 접었다 펼치는 버튼 (최소 터치 영역 44px)
	local toggle = Instance.new("TextButton")
	toggle.Name = "FeedToggle"
	toggle.BackgroundColor3 = Color3.fromRGB(52, 46, 58)
	toggle.BorderSizePixel = 0
	toggle.Font = Enum.Font.GothamMedium
	toggle.TextSize = 13
	toggle.TextColor3 = Color3.fromRGB(230, 226, 220)
	toggle.Size = UDim2.fromOffset(84, 44)
	toggle.Visible = false
	toggle.Parent = gui

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 10)
	toggleCorner.Parent = toggle

	toggle.Activated:Connect(function()
		collapsed = not collapsed
		layout()
	end)

	container = frame
	toggleButton = toggle
	layout()

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
end

--[[
	기본 채팅창에도 같은 내용을 띄운다.
	TextChannel:DisplaySystemMessage() 는 공식 문서상 클라이언트에서만 호출할 수 있고,
	그 메시지는 이 플레이어에게만 보인다. 그래서 전체 공지는 서버가 리모트로
	모든 클라이언트에 보내고, 각자 자기 채팅창에 띄우는 구조를 쓴다.
]]
local function displayInChat(text: string)
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return
	end

	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = channels and channels:FindFirstChild("RBXGeneral")

	if general and general:IsA("TextChannel") then
		local ok, err = pcall(function()
			general:DisplaySystemMessage(text)
		end)
		if not ok then
			warn(`[FeedController] 채팅 표시 실패: {err}`)
		end
	end
end

local function push(text: string, color: Color3)
	local frame = container
	if frame == nil then
		return
	end

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 18)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = text
	lineCount += 1
	label.LayoutOrder = lineCount
	label.Parent = frame

	-- 오래된 줄부터 지운다.
	local labels: { TextLabel } = {}
	for _, child in frame:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end

	if #labels > MAX_LINES then
		table.sort(labels, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for index = 1, #labels - MAX_LINES do
			labels[index]:Destroy()
		end
	end
end

-- 강화 결과 한 줄. 서버 응답을 받은 뒤에만 호출한다.
function FeedController.pushOutcome(outcome: string)
	local language = ClientState.getLanguage()
	local npc = Locale.get(language, "npc.anvilElder.name")

	local variants = Locale.variantCount(language, `feed.{outcome}`)
	local key = if variants > 0
		then `feed.{outcome}.{math.random(1, variants)}`
		else `feed.{outcome}.1`

	push(`{npc}: {Locale.get(language, key)}`, OUTCOME_COLOR[outcome] or Color3.new(1, 1, 1))
end

function FeedController.pushRaw(text: string, color: Color3?)
	push(text, color or Color3.new(1, 1, 1))
end

function FeedController.Init()
	build()

	local button = toggleButton
	if button then
		button.Text = Locale.get(ClientState.getLanguage(), "ui.feedToggle")
	end
end

function FeedController.Start()
	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	local feedRemote = remotesFolder:WaitForChild(Remotes.Events.FeedMessage) :: RemoteEvent

	feedRemote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end

		if payload.kind == "broadcast" then
			local language = ClientState.getLanguage()
			local text = Locale.get(
				language,
				"feed.broadcast",
				tostring(payload.playerName),
				Locale.get(language, tostring(payload.weaponKey)),
				tonumber(payload.level) or 0
			)
			push(text, OUTCOME_COLOR.broadcast)
			displayInChat(text)
		elseif payload.kind == "system" and type(payload.text) == "string" then
			-- 채팅 명령어의 응답. 채팅창과 피드 양쪽에 남긴다.
			push(payload.text, OUTCOME_COLOR.system)
			displayInChat(payload.text)
		end
	end)
end

return FeedController
