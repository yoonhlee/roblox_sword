--!strict
--[[
	FeedController — 결과 피드.
	채팅 로그처럼 최근 결과가 한 줄씩 쌓인다. 모루 영감의 대사로 출력한다.

	Phase 2 에서 연출(페이드, 강조색, 접이식 모바일 레이아웃)을 다듬는다.
	지금은 "서버 응답을 받은 뒤에만 한 줄 추가된다"는 흐름을 먼저 세운다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	success = Color3.fromRGB(255, 208, 112),
	keep = Color3.fromRGB(198, 198, 198),
	destroy = Color3.fromRGB(255, 120, 108),
	protected = Color3.fromRGB(140, 210, 255),
	broadcast = Color3.fromRGB(180, 255, 190),
}

local container: Frame? = nil
local lineCount = 0

local function layout()
	local frame = container
	if frame == nil then
		return
	end

	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
	local isNarrow = viewport ~= nil and viewport.X < NARROW_WIDTH

	if isNarrow then
		-- 모바일: 화면 위쪽에 가로로 넓게
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Position = UDim2.new(0.5, 0, 0, 64)
		frame.Size = UDim2.new(1, -24, 0, 132)
	else
		-- 데스크톱: 우측 세로
		frame.AnchorPoint = Vector2.new(1, 0)
		frame.Position = UDim2.new(1, -16, 0, 72)
		frame.Size = UDim2.new(0, 320, 0, 220)
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

	container = frame
	layout()

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
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
			push(
				Locale.get(
					language,
					"feed.broadcast",
					tostring(payload.playerName),
					Locale.get(language, tostring(payload.weaponKey)),
					tonumber(payload.level) or 0
				),
				OUTCOME_COLOR.broadcast
			)
		end
	end)
end

return FeedController
