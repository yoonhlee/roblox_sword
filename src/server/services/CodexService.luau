--!strict
--[[
	CodexService — 도감 기록 (통합 기획서 5-5절).

	(Roblox 내장 CollectionService 와 이름이 겹치지 않도록 Codex 로 이름을 잡았다.)

	- 검 1종 = 1칸. 칸에는 그 검의 역대 최고 레벨(sword.bestLevel)을 보여 준다.
	- 검마다 5·10·15·20강을 처음 달성하면 codex["검id:구간"] 에 기록한다.
	- [미정 D16] 기념으로 주는 영구 업그레이드는 아직 없다. 기록만 남긴다.
	  수치가 정해지면 이 기록을 읽어서 효과를 주면 된다(예전에 달성한 것도 그대로 인정된다).

	도감 화면은 클라이언트가 복제받은 데이터(swords, codex)로 직접 그린다. 리모트는 없다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Locale = require(Shared:WaitForChild("Locale"))

local ConfigFolder = Shared:WaitForChild("Config")
local Weapons = require(ConfigFolder:WaitForChild("Weapons"))

local services = script.Parent
local AnalyticsService = require(services:WaitForChild("AnalyticsService"))

local CodexService = {}
CodexService.Name = "CodexService"

local feedRemote: RemoteEvent? = nil

--[[
	검의 레벨이 올랐을 때 최고 레벨과 구간 기록을 갱신한다. yield 하지 않는다.
	반환값은 이번에 새로 달성한 구간 수.
]]
function CodexService.recordSwordLevel(
	player: Player,
	data: Types.PlayerData,
	sword: Types.SwordState
): number
	if sword.level > sword.bestLevel then
		sword.bestLevel = sword.level
	end

	local unlocked = 0

	for _, milestone in Weapons.CODEX_MILESTONES do
		if sword.bestLevel < milestone then
			continue
		end

		local key = `{sword.id}:{milestone}`
		if data.codex[key] then
			continue
		end

		data.codex[key] = true
		unlocked += 1

		if feedRemote then
			local language = data.settings.language
			local info = Weapons.get(sword.id)
			local name = if info then Locale.get(language, info.nameKey) else sword.id

			feedRemote:FireClient(player, {
				kind = "system",
				text = Locale.get(language, "codex.unlocked", name, milestone),
			})
		end

		AnalyticsService.logFunnel(player, "codex_unlocked", { key = key })
	end

	return unlocked
end

function CodexService.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	feedRemote = remotesFolder:WaitForChild(Remotes.Events.FeedMessage) :: RemoteEvent
end

return CodexService
