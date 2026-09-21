--!strict
--[[
	ChatCommandService — 채팅 텍스트 명령어.

	버튼과 명령어는 "같은 서버 경로"를 탄다. 명령어 처리기는 직접 데이터를
	건드리지 않고 EnhanceService 의 공개 함수를 호출하므로, 검증·레이트 리밋·락이
	버튼과 똑같이 적용된다.

	확인한 공식 문서 내용:
	- TextChatCommand 는 TextChatService 아래에 있어야 동작한다.
	- Triggered(originTextSource: TextSource, unfilteredText: string) 는
	  서버 Script 에서 연결하는 것이 공식 예제의 방식이고,
	  textSource.UserId 로 Players:GetPlayerByUserId() 해서 플레이어를 얻는다.
	- TextChannel:DisplaySystemMessage() 는 클라이언트에서만 호출할 수 있으므로,
	  명령 결과 안내는 서버가 리모트로 보내고 클라이언트가 채팅에 표시한다.

	[확인 필요] TextChatCommand 인스턴스를 서버에서 런타임에 만들어 붙이는 방식은
	Studio 에서 한 번 확인해 줘. 공식 예제는 Studio 에서 미리 만들어 둔 인스턴스를
	WaitForChild 로 찾는 형태였다. 만약 런타임 생성이 동작하지 않으면
	Studio 의 TextChatService 아래에 TextChatCommand 를 직접 만들고
	아래 COMMANDS 의 이름과 맞추면 된다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))

local services = script.Parent
local DataService = require(services:WaitForChild("DataService"))
local EnhanceService = require(services:WaitForChild("EnhanceService"))

local ChatCommandService = {}
ChatCommandService.Name = "ChatCommandService"

local feedRemote: RemoteEvent? = nil

type CommandSpec = {
	name: string,
	primary: string,
	secondary: string,
	handler: (player: Player, arguments: { string }) -> (),
}

local function languageOf(player: Player): string
	local data = DataService.getData(player)
	if data and data.settings and data.settings.language then
		return data.settings.language
	end
	return Locale.DEFAULT_LANGUAGE
end

-- 명령 결과를 그 플레이어에게만 보낸다. 클라이언트가 채팅창에 표시한다.
local function reply(player: Player, text: string)
	if feedRemote == nil then
		return
	end
	feedRemote:FireClient(player, { kind = "system", text = text })
end

local function replyKey(player: Player, key: string, ...: any)
	reply(player, Locale.get(languageOf(player), key, ...))
end

local function onEnhanceCommand(player: Player, arguments: { string })
	-- "/강화 보호" 처럼 뒤에 보호 옵션을 붙일 수 있다.
	local wantsProtect = false
	for _, argument in arguments do
		local lowered = string.lower(argument)
		if lowered == "보호" or lowered == "protect" then
			wantsProtect = true
		end
	end

	local response = EnhanceService.requestEnhance(player, wantsProtect)

	if not response.ok then
		replyKey(player, `error.{response.reason}`)
		return
	end

	replyKey(player, `chat.result.{response.result}`, response.newLevel)
end

local function onSellCommand(player: Player)
	local response = EnhanceService.requestSell(player)

	if not response.ok then
		replyKey(player, `error.{response.reason}`)
		return
	end

	replyKey(player, "chat.sold", Format.comma(response.goldGained))
end

local function onOddsCommand(player: Player)
	local data = DataService.getData(player)
	if data == nil then
		replyKey(player, "error.not_ready")
		return
	end

	local odds = EnhanceService.getDisplayOdds(data.weapon.level)

	if odds.cost <= 0 then
		replyKey(player, "ui.maxLevel")
		return
	end

	replyKey(
		player,
		"chat.odds",
		odds.level,
		Format.percent(odds.success),
		Format.percent(odds.keep),
		Format.percent(odds.destroy),
		Format.comma(odds.cost)
	)
end

local function onInfoCommand(player: Player)
	local data = DataService.getData(player)
	if data == nil then
		replyKey(player, "error.not_ready")
		return
	end

	replyKey(
		player,
		"chat.info",
		data.weapon.level,
		Format.comma(data.gold),
		Format.comma(data.shards),
		data.protectTickets,
		data.stats.enhanceTries,
		data.stats.destroyed,
		data.stats.highestLevel
	)
end

local function onHelpCommand(player: Player)
	replyKey(player, "chat.help")
end

local COMMANDS: { CommandSpec } = {
	{
		name = "ForgeEnhanceCommand",
		primary = "/강화",
		secondary = "/enhance",
		handler = onEnhanceCommand,
	},
	{
		name = "ForgeSellCommand",
		primary = "/판매",
		secondary = "/sell",
		handler = function(player, _)
			onSellCommand(player)
		end,
	},
	{
		name = "ForgeOddsCommand",
		primary = "/확률",
		secondary = "/odds",
		handler = function(player, _)
			onOddsCommand(player)
		end,
	},
	{
		name = "ForgeInfoCommand",
		primary = "/정보",
		secondary = "/info",
		handler = function(player, _)
			onInfoCommand(player)
		end,
	},
	{
		name = "ForgeHelpCommand",
		primary = "/도움말",
		secondary = "/forgehelp",
		handler = function(player, _)
			onHelpCommand(player)
		end,
	},
}

local function register(spec: CommandSpec)
	local existing = TextChatService:FindFirstChild(spec.name)
	local command = if existing and existing:IsA("TextChatCommand")
		then existing
		else Instance.new("TextChatCommand")

	command.Name = spec.name
	command.PrimaryAlias = spec.primary
	command.SecondaryAlias = spec.secondary
	command.AutocompleteVisible = true
	command.Enabled = true
	command.Parent = TextChatService

	command.Triggered:Connect(function(textSource: TextSource, message: string)
		local player = Players:GetPlayerByUserId(textSource.UserId)
		if player == nil then
			return
		end

		-- 첫 토큰은 명령어 자체이므로 버린다.
		local words = string.split(message, " ")
		local arguments: { string } = {}
		for index = 2, #words do
			if words[index] ~= "" then
				table.insert(arguments, words[index])
			end
		end

		local ok, err = xpcall(spec.handler, debug.traceback, player, arguments)
		if not ok then
			warn(`[ChatCommandService] {spec.primary} 처리 중 오류:\n{err}`)
			replyKey(player, "error.unknown")
		end
	end)
end

function ChatCommandService.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	feedRemote = remotesFolder:WaitForChild(Remotes.Events.FeedMessage) :: RemoteEvent
end

function ChatCommandService.Start()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn(
			"[ChatCommandService] TextChatService 가 아닌 레거시 채팅이 켜져 있어 "
				.. "텍스트 명령어를 등록하지 않았습니다. "
				.. "게임 설정에서 ChatVersion 을 TextChatService 로 바꿔 주세요."
		)
		return
	end

	for _, spec in COMMANDS do
		local ok, err = pcall(register, spec)
		if not ok then
			warn(`[ChatCommandService] {spec.primary} 등록 실패: {err}`)
		end
	end

	print(`[ChatCommandService] 명령어 {#COMMANDS}개 등록`)
end

return ChatCommandService
