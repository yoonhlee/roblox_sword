--!strict
--[[
	AdminService — 관리자 명령과 감사 로그.

	Config/Game.ADMIN_USER_IDS 에 들어 있는 UserId 만 쓸 수 있다.
	목록이 비어 있으면 아무도 쓸 수 없다(기본값이 "아무도 안 됨"이어야 안전하다).

	모든 관리자 행동은 print 로 남기고 서버 메모리에도 최근 기록을 보관한다.
	"누가 언제 무엇을 했는지"가 남아야 사고가 났을 때 되짚을 수 있다.

	명령은 채팅으로 쓴다:
	    /관리 도움말
	    /관리 골드 <닉네임> <양>
	    /관리 레벨 <닉네임> <레벨>
	    /관리 방지권 <닉네임> <개수>
	    /관리 차단 <닉네임> <시간>       (시간 단위, 0 이면 해제)
	    /관리 정보 <닉네임>
	    /관리 점검 켜기|끄기
	    /관리 이벤트 <성공확률+%p> <지속분>
	    /관리 이벤트끄기
	    /관리 이상기록
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("Game"))
local EnhanceTable = require(Shared:WaitForChild("Config"):WaitForChild("EnhanceTable"))

local services = script.Parent
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local AnalyticsService = require(services:WaitForChild("AnalyticsService"))
local LiveOpsService = require(services:WaitForChild("LiveOpsService"))
local BattleService = require(services:WaitForChild("BattleService"))

local AdminService = {}
AdminService.Name = "AdminService"

local COMMAND_NAME = "ForgeAdminCommand"
local MAX_AUDIT = 200

local auditLog: { string } = {}
local feedRemote: RemoteEvent? = nil

local function record(admin: Player, action: string)
	local entry = `[{os.date("!%Y-%m-%d %H:%M:%S")}] {admin.Name}({admin.UserId}) {action}`

	print(`[Admin] {entry}`)
	table.insert(auditLog, entry)

	while #auditLog > MAX_AUDIT do
		table.remove(auditLog, 1)
	end
end

local function reply(player: Player, text: string)
	if feedRemote == nil then
		return
	end
	feedRemote:FireClient(player, { kind = "system", text = text })
end

local function findPlayer(name: string): Player?
	return BattleService.findTargetByName(name)
end

--------------------------------------------------------------------------------
-- 개별 명령
--------------------------------------------------------------------------------

type Handler = (admin: Player, arguments: { string }) -> ()

local function requireTarget(admin: Player, arguments: { string }): Player?
	local name = arguments[2]
	if name == nil then
		reply(admin, "대상 닉네임이 필요하다.")
		return nil
	end

	local target = findPlayer(name)
	if target == nil then
		reply(admin, `'{name}' 을(를) 찾지 못했다.`)
		return nil
	end

	return target
end

local function cmdGold(admin: Player, arguments: { string })
	local target = requireTarget(admin, arguments)
	if target == nil then
		return
	end

	local amount = tonumber(arguments[3])
	if amount == nil or amount ~= math.floor(amount) then
		reply(admin, "양은 정수로 적어라.")
		return
	end

	local data = DataService.getActiveData(target)
	if data == nil then
		reply(admin, "그 사람 데이터가 아직 열리지 않았다.")
		return
	end

	if amount >= 0 then
		EconomyService.addGold(target, data, amount, "admin_grant", false)
	else
		-- 회수는 가진 만큼만
		EconomyService.spendGold(target, data, math.min(-amount, data.gold), "admin_revoke")
	end

	DataService.replicate(target)
	reply(admin, `{target.Name} 골드 {Format.comma(amount)} 처리. 현재 {Format.comma(data.gold)}`)
	record(admin, `골드 {amount} → {target.Name}({target.UserId})`)
end

local function cmdLevel(admin: Player, arguments: { string })
	local target = requireTarget(admin, arguments)
	if target == nil then
		return
	end

	local level = tonumber(arguments[3])
	if level == nil or level ~= math.floor(level) or level < 0 or level > EnhanceTable.MAX_LEVEL then
		reply(admin, `레벨은 0 ~ {EnhanceTable.MAX_LEVEL} 사이 정수여야 한다.`)
		return
	end

	local data = DataService.getActiveData(target)
	if data == nil then
		reply(admin, "그 사람 데이터가 아직 열리지 않았다.")
		return
	end

	data.weapon.level = level
	if level > data.stats.highestLevel then
		data.stats.highestLevel = level
	end

	DataService.replicate(target)
	reply(admin, `{target.Name} 레벨을 +{level} 로 설정.`)
	record(admin, `레벨 {level} → {target.Name}({target.UserId})`)
end

local function cmdTickets(admin: Player, arguments: { string })
	local target = requireTarget(admin, arguments)
	if target == nil then
		return
	end

	local count = tonumber(arguments[3])
	if count == nil or count ~= math.floor(count) then
		reply(admin, "개수는 정수로 적어라.")
		return
	end

	local data = DataService.getActiveData(target)
	if data == nil then
		reply(admin, "그 사람 데이터가 아직 열리지 않았다.")
		return
	end

	if count >= 0 then
		EconomyService.addTickets(target, data, count, "admin_grant")
	else
		EconomyService.spendTickets(
			target,
			data,
			math.min(-count, data.protectTickets),
			"admin_revoke"
		)
	end

	DataService.replicate(target)
	reply(admin, `{target.Name} 방지권 {count} 처리. 현재 {data.protectTickets}`)
	record(admin, `방지권 {count} → {target.Name}({target.UserId})`)
end

local function cmdBan(admin: Player, arguments: { string })
	local target = requireTarget(admin, arguments)
	if target == nil then
		return
	end

	local hours = tonumber(arguments[3])
	if hours == nil or hours < 0 then
		reply(admin, "시간은 0 이상 숫자여야 한다. 0 이면 해제.")
		return
	end

	local data = DataService.getActiveData(target)
	if data == nil then
		reply(admin, "그 사람 데이터가 아직 열리지 않았다.")
		return
	end

	if hours == 0 then
		data.bannedUntil = nil
		reply(admin, `{target.Name} 차단 해제.`)
		record(admin, `차단 해제 → {target.Name}({target.UserId})`)
		return
	end

	data.bannedUntil = os.time() + math.floor(hours * 3600)
	reply(admin, `{target.Name} {hours}시간 차단.`)
	record(admin, `차단 {hours}시간 → {target.Name}({target.UserId})`)

	-- 차단은 다음 접속 때 로드 시점에서도 확인되지만, 지금 있으면 바로 내보낸다.
	task.defer(function()
		if target.Parent == Players then
			target:Kick("출입이 금지되었다.")
		end
	end)
end

local function cmdInfo(admin: Player, arguments: { string })
	local target = requireTarget(admin, arguments)
	if target == nil then
		return
	end

	local data = DataService.getData(target)
	if data == nil then
		reply(admin, "그 사람 데이터가 아직 열리지 않았다.")
		return
	end

	reply(
		admin,
		`{target.Name} — +{data.weapon.level} · 골드 {Format.comma(data.gold)}`
			.. ` · 파편 {Format.comma(data.shards)} · 방지권 {data.protectTickets}`
			.. ` · 시도 {data.stats.enhanceTries} · 파괴 {data.stats.destroyed}`
			.. ` · 최고 +{data.stats.highestLevel} · 레이팅 {data.stats.rating}`
			.. ` · 스키마 v{data.schemaVersion}`
	)
	record(admin, `정보 조회 → {target.Name}({target.UserId})`)
end

local function cmdMaintenance(admin: Player, arguments: { string })
	local mode = arguments[2]
	if mode ~= "켜기" and mode ~= "끄기" and mode ~= "on" and mode ~= "off" then
		reply(admin, "/관리 점검 켜기 | 끄기")
		return
	end

	local enabled = mode == "켜기" or mode == "on"

	task.spawn(function()
		local saved = LiveOpsService.setMaintenance(enabled)
		reply(admin, `점검 모드 {if enabled then "켜짐" else "꺼짐"}{if saved then "" else " (저장 실패, 이 서버에만 적용)"}`)
	end)

	record(admin, `점검 {tostring(enabled)}`)
end

local function cmdEvent(admin: Player, arguments: { string })
	local buff = tonumber(arguments[2])
	local minutes = tonumber(arguments[3])

	if buff == nil or minutes == nil or buff <= 0 or minutes <= 0 then
		reply(admin, "/관리 이벤트 <성공확률+%p> <지속분>")
		return
	end

	local event = {
		id = `admin_{os.time()}`,
		nameKey = "event.boost",
		successBuff = math.clamp(buff, 1, 50),
		endsAt = os.time() + math.floor(minutes * 60),
	}

	task.spawn(function()
		local saved = LiveOpsService.setEvent(event)
		reply(
			admin,
			`이벤트 시작: 성공 +{event.successBuff}%p, {minutes}분{if saved then "" else " (저장 실패)"}`
		)
	end)

	record(admin, `이벤트 +{buff}%p / {minutes}분`)
end

local function cmdEventOff(admin: Player, _arguments: { string })
	task.spawn(function()
		LiveOpsService.setEvent(nil)
		reply(admin, "이벤트를 껐다.")
	end)
	record(admin, "이벤트 종료")
end

local function cmdAnomalies(admin: Player, _arguments: { string })
	local entries = AnalyticsService.getAnomalyLog()

	if #entries == 0 then
		reply(admin, "이상 기록이 없다.")
		return
	end

	for index = math.max(1, #entries - 9), #entries do
		reply(admin, entries[index])
	end
end

local function cmdAudit(admin: Player, _arguments: { string })
	if #auditLog == 0 then
		reply(admin, "관리자 기록이 없다.")
		return
	end

	for index = math.max(1, #auditLog - 9), #auditLog do
		reply(admin, auditLog[index])
	end
end

local HANDLERS: { [string]: Handler } = {
	["골드"] = cmdGold,
	["gold"] = cmdGold,
	["레벨"] = cmdLevel,
	["level"] = cmdLevel,
	["방지권"] = cmdTickets,
	["tickets"] = cmdTickets,
	["차단"] = cmdBan,
	["ban"] = cmdBan,
	["정보"] = cmdInfo,
	["info"] = cmdInfo,
	["점검"] = cmdMaintenance,
	["maintenance"] = cmdMaintenance,
	["이벤트"] = cmdEvent,
	["event"] = cmdEvent,
	["이벤트끄기"] = cmdEventOff,
	["eventoff"] = cmdEventOff,
	["이상기록"] = cmdAnomalies,
	["anomalies"] = cmdAnomalies,
	["기록"] = cmdAudit,
	["audit"] = cmdAudit,
}

local HELP = "/관리 골드|레벨|방지권|차단|정보 <닉네임> <값> · 점검 켜기|끄기 · 이벤트 <%p> <분> · 이벤트끄기 · 이상기록 · 기록"

--------------------------------------------------------------------------------

local function onAdminCommand(player: Player, arguments: { string })
	if not GameConfig.isAdmin(player.UserId) then
		-- 관리자가 아니면 명령이 있다는 사실조차 알리지 않는다.
		warn(`[Admin] 권한 없는 시도: {player.Name}({player.UserId})`)
		return
	end

	local subcommand = arguments[1]
	if subcommand == nil or subcommand == "도움말" or subcommand == "help" then
		reply(player, HELP)
		return
	end

	local handler = HANDLERS[string.lower(subcommand)] or HANDLERS[subcommand]
	if handler == nil then
		reply(player, HELP)
		return
	end

	local ok, err = xpcall(handler, debug.traceback, player, arguments)
	if not ok then
		warn(`[Admin] 명령 처리 오류:\n{err}`)
		reply(player, "명령 처리 중 문제가 생겼다.")
	end
end

function AdminService.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	feedRemote = remotesFolder:WaitForChild(Remotes.Events.FeedMessage) :: RemoteEvent
end

function AdminService.Start()
	if #GameConfig.ADMIN_USER_IDS == 0 then
		warn(
			"[Admin] 관리자 UserId 가 비어 있어 관리자 명령을 등록하지 않았습니다. "
				.. "src/shared/Config/Game.luau 의 ADMIN_USER_IDS 를 채워 주세요."
		)
		return
	end

	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[Admin] 레거시 채팅이라 관리자 명령을 등록하지 않았습니다.")
		return
	end

	local ok, err = pcall(function()
		local existing = TextChatService:FindFirstChild(COMMAND_NAME)
		local command = if existing and existing:IsA("TextChatCommand")
			then existing
			else Instance.new("TextChatCommand")

		command.Name = COMMAND_NAME
		command.PrimaryAlias = "/관리"
		command.SecondaryAlias = "/admin"
		command.AutocompleteVisible = false -- 일반 플레이어에게 노출하지 않는다
		command.Enabled = true
		command.Parent = TextChatService

		command.Triggered:Connect(function(textSource: TextSource, message: string)
			local player = Players:GetPlayerByUserId(textSource.UserId)
			if player == nil then
				return
			end

			local words = string.split(message, " ")
			local arguments: { string } = {}
			for index = 2, #words do
				if words[index] ~= "" then
					table.insert(arguments, words[index])
				end
			end

			onAdminCommand(player, arguments)
		end)
	end)

	if not ok then
		warn(`[Admin] 명령 등록 실패: {err}`)
		return
	end

	print(`[Admin] 관리자 {#GameConfig.ADMIN_USER_IDS}명, 명령 등록 완료`)
end

function AdminService.getAuditLog(): { string }
	return table.clone(auditLog)
end

return AdminService
