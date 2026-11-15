--!strict
--[[
	FeedController — 결과 피드 (모루 영감의 대사, 통합 기획서 8절).

	보이는 곳이 화면 상태에 따라 바뀐다.
	  대장간: 패널 왼쪽 아래 칸에 최근 몇 줄 (ForgeLayout 의 feed 자리)
	  로비:   위쪽 가운데 한 줄 (최근 것 하나, 6초 뒤 흐려짐). 공지 배너가 떠 있으면 숨는다
	  경주:   숨김
	최근 7줄을 기억한다. 기본 채팅창에도 같은 내용을 띄운다(시스템 메시지·서버 공지).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local client = script.Parent.Parent
local ClientState = require(client:WaitForChild("ClientState"))
local ui = client:WaitForChild("ui")
local Theme = require(ui:WaitForChild("Theme"))
local Components = require(ui:WaitForChild("Components"))
local ScreenManager = require(ui:WaitForChild("ScreenManager"))
local ForgeLayout = require(ui:WaitForChild("ForgeLayout"))

local FeedController = {}
FeedController.Name = "FeedController"

local MAX_LINES = 7
local LINE_HEIGHT = 24
local LOBBY_FADE_SECONDS = 6

local C = Theme.color

local OUTCOME_COLOR: { [string]: Color3 } = {
	system = C.text,
	success = C.ember,
	keep = C.keep,
	fail = C.fail,
	protected = C.protect,
	max = C.white,
	broadcast = Color3.fromRGB(180, 255, 190),
}

type Line = { text: string, color: Color3 }

local lines: { Line } = {}

local gui: ScreenGui
local forgeBox: Frame
local forgeList: Frame
local lobbyLine: TextLabel
local lobbyFadeToken = 0
local forgeCapacity = 3 -- 대장간 피드 칸에 들어가는 줄 수 (배치 때 다시 계산)

-- 다른 컨트롤러가 "배너가 떠 있는지" 알려 주는 함수 (HudController 가 등록)
local isBannerVisible: () -> boolean = function()
	return false
end

local function redrawForge()
	Components.clear(forgeList)

	-- 칸 높이에 들어가는 만큼만, 최근 것이 맨 아래
	local first = math.max(1, #lines - forgeCapacity + 1)
	for index = first, #lines do
		local line = lines[index]
		local label = Components.label(forgeList, {
			text = line.text,
			color = line.color,
			size = Theme.text.small,
			order = index,
			height = LINE_HEIGHT,
		})
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end
end

local function place()
	local layout = ScreenManager.getLayout()
	if layout == nil then
		return
	end

	local forge = ForgeLayout.compute(layout.forgePanel)
	ScreenManager.place(forgeBox, forge.feedAbsolute)
	forgeList.Size = UDim2.new(1, -16, 1, -12)
	forgeCapacity = math.max(1, math.floor((forge.feedAbsolute.h - 12) / LINE_HEIGHT))
	ScreenManager.place(lobbyLine, layout.feedLobby)
	redrawForge()
end

local function render()
	local mode = ScreenManager.getMode()
	gui.Enabled = not ScreenManager.isRacing()
	forgeBox.Visible = mode == "forge"
	lobbyLine.Visible = mode == "lobby" and not isBannerVisible() and lobbyLine.Text ~= ""
end

local function showInLobby(line: Line)
	lobbyLine.Text = line.text
	lobbyLine.TextColor3 = line.color
	lobbyLine.TextTransparency = 0
	lobbyLine.BackgroundTransparency = 0.25
	render()

	lobbyFadeToken += 1
	local token = lobbyFadeToken
	task.delay(LOBBY_FADE_SECONDS, function()
		if token ~= lobbyFadeToken then
			return
		end
		TweenService:Create(lobbyLine, TweenInfo.new(0.8), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		}):Play()
	end)
end

--[[
	기본 채팅창에도 같은 내용을 띄운다.
	TextChannel:DisplaySystemMessage() 는 공식 문서상 클라이언트에서만 호출할 수 있고,
	그 메시지는 이 플레이어에게만 보인다.
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
	local line = { text = text, color = color }
	table.insert(lines, line)
	while #lines > MAX_LINES do
		table.remove(lines, 1)
	end

	redrawForge()
	showInLobby(line)
end

-- 강화 결과 한 줄. 서버 응답을 받은 뒤(연출이 끝난 뒤)에만 호출한다.
function FeedController.pushOutcome(outcome: string)
	local language = ClientState.getLanguage()
	local npc = Locale.get(language, "npc.anvilElder.name")

	local variants = Locale.variantCount(language, `feed.{outcome}`)
	local key = if variants > 0
		then `feed.{outcome}.{math.random(1, variants)}`
		else `feed.{outcome}.1`

	push(`{npc}: {Locale.get(language, key)}`, OUTCOME_COLOR[outcome] or C.text)
end

function FeedController.pushRaw(text: string, color: Color3?)
	push(text, color or C.text)
end

function FeedController.setBannerCheck(check: () -> boolean)
	isBannerVisible = check
	render()
end

function FeedController.Init()
	gui = ScreenManager.createScreen("ForgeFeed", 6)

	forgeBox = Components.frame(gui, {
		Name = "ForgeFeed",
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.25,
	})
	Components.corner(forgeBox, 10)
	forgeList = Components.frame(forgeBox, {
		Position = UDim2.fromOffset(8, 6),
	})
	local listLayout = Components.list(forgeList, "vertical", 0)
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom

	lobbyLine = Components.label(gui, {
		size = Theme.text.small,
		font = Theme.font.bodyBold,
		align = Enum.TextXAlignment.Center,
	})
	lobbyLine.Name = "LobbyLine"
	lobbyLine.BackgroundColor3 = C.bg
	lobbyLine.BackgroundTransparency = 1
	Components.corner(lobbyLine, 10)

	ScreenManager.onLayout(place)
	ScreenManager.onStateChanged(render)
	ClientState.onChanged(render)
	render()
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
			-- 채팅 명령어의 응답 등. 채팅창과 피드 양쪽에 남긴다.
			push(payload.text, OUTCOME_COLOR.system)
			displayInChat(payload.text)
		end
	end)
end

return FeedController
