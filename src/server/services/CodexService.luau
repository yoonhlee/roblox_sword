--!strict
--[[
	CodexService — 도감과 업적.

	(Roblox 내장 CollectionService 와 이름이 겹치지 않도록 Codex 로 이름을 잡았다.)

	- 도감: 무기 종류 × 레벨 구간(5/10/15/20) 달성 기록. 칸마다 골드 보상.
	- 업적: Config/Achievements 의 판정 함수를 전부 돌려 새로 달성된 것만 보상.

	업적 판정은 순수 함수라 데이터만 보면 되므로, 강화·배틀 직후는 물론
	접속 시점에도 한 번 돌린다. 예전 버전에서 조건을 이미 만족했던 사람도
	접속하면 자연스럽게 보상을 받게 된다(뒤늦게 추가된 업적 대응).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Locale = require(Shared:WaitForChild("Locale"))

local ConfigFolder = Shared:WaitForChild("Config")
local Weapons = require(ConfigFolder:WaitForChild("Weapons"))
local Achievements = require(ConfigFolder:WaitForChild("Achievements"))
local EconomyConfig = require(ConfigFolder:WaitForChild("EconomyConfig"))

local services = script.Parent
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local AnalyticsService = require(services:WaitForChild("AnalyticsService"))

local CodexService = {}
CodexService.Name = "CodexService"

local feedRemote: RemoteEvent? = nil

local function notify(player: Player, data: Types.PlayerData, key: string, ...: any)
	if feedRemote == nil then
		return
	end

	feedRemote:FireClient(player, {
		kind = "system",
		text = Locale.get(data.settings.language, key, ...),
	})
end

--[[
	무기가 어떤 레벨에 도달했을 때 도감을 채운다.
	새로 채워진 칸마다 골드를 준다. yield 하지 않는다.
	반환값은 이번에 새로 채운 칸 수.
]]
function CodexService.recordWeaponLevel(
	player: Player,
	data: Types.PlayerData,
	level: number
): number
	local unlocked = 0

	for _, milestone in Weapons.CODEX_MILESTONES do
		if level < milestone then
			continue
		end

		local key = `{data.weapon.id}:{milestone}`
		if data.codex[key] then
			continue
		end

		data.codex[key] = true
		unlocked += 1

		EconomyService.addGold(player, data, EconomyConfig.CODEX_ENTRY_GOLD, "codex_entry", true)
		notify(player, data, "codex.unlocked", milestone)
		AnalyticsService.logFunnel(player, "codex_unlocked", { key = key })
	end

	return unlocked
end

--[[
	업적을 전부 확인하고 새로 달성된 것에 보상을 준다. yield 하지 않는다.
	반환값은 이번에 새로 달성한 업적 수.
]]
function CodexService.evaluate(player: Player, data: Types.PlayerData): number
	local granted = 0

	for _, achievement in Achievements.List do
		if data.achievements[achievement.id] then
			continue
		end

		local ok, reached = pcall(achievement.check, data :: any)
		if not ok then
			warn(`[CodexService] 업적 판정 오류 ({achievement.id}): {reached}`)
			continue
		end

		if reached ~= true then
			continue
		end

		data.achievements[achievement.id] = true
		granted += 1

		EconomyService.addGold(player, data, achievement.gold, `achv_{achievement.id}`, true)
		notify(player, data, "achv.unlocked", Locale.get(data.settings.language, `achv.{achievement.id}.name`))
		AnalyticsService.logFunnel(player, "achievement_unlocked", { id = achievement.id })
	end

	return granted
end

local function handleGetCodex(player: Player): {
	entries: { Types.CodexEntry },
	achievements: { Types.AchievementEntry },
} | Types.Failure
	local data = DataService.getData(player)
	if data == nil then
		return { ok = false, reason = "not_ready" }
	end

	local entries: { Types.CodexEntry } = {}
	for _, weapon in Weapons.List do
		for _, milestone in Weapons.CODEX_MILESTONES do
			table.insert(entries, {
				weaponId = weapon.id,
				milestone = milestone,
				unlocked = data.codex[`{weapon.id}:{milestone}`] == true,
			})
		end
	end

	local achievements: { Types.AchievementEntry } = {}
	for _, achievement in Achievements.List do
		table.insert(achievements, {
			id = achievement.id,
			unlocked = data.achievements[achievement.id] == true,
			gold = achievement.gold,
		})
	end

	return { entries = entries, achievements = achievements }
end

function CodexService.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)

	local codexRemote = remotesFolder:WaitForChild(Remotes.Functions.GetCodex) :: RemoteFunction
	codexRemote.OnServerInvoke = handleGetCodex

	feedRemote = remotesFolder:WaitForChild(Remotes.Events.FeedMessage) :: RemoteEvent
end

function CodexService.Start()
	-- 접속 시 한 번 평가한다. 나중에 추가된 업적도 여기서 소급 지급된다.
	DataService.onLoaded(function(player, data)
		if CodexService.evaluate(player, data) > 0 then
			DataService.replicate(player)
		end
	end)
end

return CodexService
