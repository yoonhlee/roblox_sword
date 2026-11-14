--!strict
--[[
	ClientState — 서버가 보내 준 내 데이터의 로컬 사본.

	클라이언트는 이 값을 "표시"에만 쓴다. 여기 있는 숫자를 고쳐도 게임에는
	아무 영향이 없다(서버가 진짜 값을 들고 있다).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Locale = require(Shared:WaitForChild("Locale"))

local ClientState = {}

local data: Types.PlayerData? = nil
local odds: Types.DisplayOdds? = nil
local liveOps: { maintenance: boolean, notice: string, event: any } = {
	maintenance = false,
	notice = "",
	event = nil,
}
-- "방지권 사용" 스위치. 강화 요청에 실어 보내고, 화면의 확률 표시도 이 값에 따라 바뀐다.
local useProtect = false
-- 경주 화면이 떠 있는 동안(출발선 ~ 로비 복귀)은 대장간 화면을 숨긴다.
local inRace = false
-- 대장간 화면(무기·강화 버튼)을 펴 둘지. 접으면 로비를 돌아다니기 편하다.
local forgeOpen = true
local listeners: { () -> () } = {}

local function notify()
	for _, listener in listeners do
		local ok, err = pcall(listener)
		if not ok then
			warn(`[ClientState] 리스너 오류: {err}`)
		end
	end
end

function ClientState.setData(newData: Types.PlayerData)
	data = newData
	notify()
end

function ClientState.setOdds(newOdds: Types.DisplayOdds)
	odds = newOdds
	notify()
end

function ClientState.getData(): Types.PlayerData?
	return data
end

function ClientState.getOdds(): Types.DisplayOdds?
	return odds
end

-- 착용 중인 검 (데이터가 아직 없으면 nil)
function ClientState.getEquipped(): Types.SwordState?
	if data == nil or type(data.swords) ~= "table" then
		return nil
	end
	return data.swords[data.equippedId]
end

-- 가진 검 수 (데이터가 아직 없으면 1)
function ClientState.getSwordCount(): number
	if data == nil or type(data.swords) ~= "table" then
		return 1
	end

	local count = 0
	for _ in data.swords do
		count += 1
	end
	return math.max(1, count)
end

function ClientState.getUseProtect(): boolean
	return useProtect
end

function ClientState.setUseProtect(value: boolean)
	useProtect = value
	notify()
end

-- 방지권이 실제로 효과를 내는 상태인지 (스위치가 켜져 있고 방지권이 1개 이상)
function ClientState.isProtectActive(): boolean
	return useProtect and data ~= nil and data.protectTickets > 0
end

function ClientState.isInRace(): boolean
	return inRace
end

function ClientState.setInRace(value: boolean)
	if inRace ~= value then
		inRace = value
		notify()
	end
end

function ClientState.isForgeOpen(): boolean
	return forgeOpen
end

function ClientState.setForgeOpen(value: boolean)
	if forgeOpen ~= value then
		forgeOpen = value
		notify()
	end
end

function ClientState.getLanguage(): string
	if data and data.settings and data.settings.language then
		return data.settings.language
	end
	return Locale.DEFAULT_LANGUAGE
end

function ClientState.setLiveOps(config: any)
	liveOps = {
		maintenance = config.maintenance == true,
		notice = if type(config.notice) == "string" then config.notice else "",
		event = config.event,
	}
	notify()
end

function ClientState.getLiveOps()
	return liveOps
end

function ClientState.onChanged(listener: () -> ())
	table.insert(listeners, listener)
end

return ClientState
