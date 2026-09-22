--!strict
--[[
	LiveOpsService — 확률 버프 이벤트, 공지, 점검 모드.

	설정은 DataStore 키 하나에 통째로 들어 있고, 모든 서버가 주기적으로 읽는다.
	게임을 다시 올리지 않고도 이벤트를 켜고 끌 수 있다.

	저장 형태:
	    {
	      maintenance = false,
	      notice = "" ,                       -- 비어 있으면 공지 없음
	      event = {                           -- nil 이면 진행 중인 이벤트 없음
	        id = "weekend1",
	        nameKey = "event.weekend",        -- Locale 키 또는 그냥 문구
	        successBuff = 5,                  -- 성공 확률에 더할 %p
	        endsAt = 1790000000,              -- UTC 종료 시각
	      },
	    }

	읽기 실패는 조용히 넘어가고 직전 설정을 유지한다.
	통신이 잠깐 끊겼다고 이벤트가 꺼지거나 점검이 걸리면 안 되기 때문이다.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("Game"))

local LiveOpsService = {}
LiveOpsService.Name = "LiveOpsService"

local POLL_SECONDS = 60
local CONFIG_KEY = "config"

export type ActiveEvent = {
	id: string,
	nameKey: string,
	successBuff: number,
	endsAt: number,
}

export type LiveConfig = {
	maintenance: boolean,
	notice: string,
	event: ActiveEvent?,
}

local current: LiveConfig = {
	maintenance = false,
	notice = "",
	event = nil,
}

local store: DataStore? = nil
local changedRemote: RemoteEvent? = nil

local function storeName(): string
	local base = if RunService:IsStudio() then GameConfig.DATASTORE_DEV else GameConfig.DATASTORE_PROD
	return `{base}_LiveOps`
end

-- 저장된 값이 우리가 기대하는 모양인지 확인한다. 이상하면 무시한다.
local function sanitize(raw: any): LiveConfig?
	if type(raw) ~= "table" then
		return nil
	end

	local event: ActiveEvent? = nil
	local rawEvent = raw.event

	if type(rawEvent) == "table" then
		local buff = tonumber(rawEvent.successBuff) or 0
		local endsAt = tonumber(rawEvent.endsAt) or 0

		if endsAt > os.time() and buff > 0 then
			event = {
				id = tostring(rawEvent.id or "event"),
				nameKey = tostring(rawEvent.nameKey or "event.default"),
				successBuff = math.clamp(buff, 0, 100),
				endsAt = endsAt,
			}
		end
	end

	return {
		maintenance = raw.maintenance == true,
		notice = if type(raw.notice) == "string" then raw.notice else "",
		event = event,
	}
end

local function broadcast()
	if changedRemote == nil then
		return
	end

	changedRemote:FireAllClients({
		maintenance = current.maintenance,
		notice = current.notice,
		event = current.event,
	})
end

local function apply(config: LiveConfig)
	local changed = config.maintenance ~= current.maintenance
		or config.notice ~= current.notice
		or (config.event ~= nil) ~= (current.event ~= nil)
		or (config.event ~= nil and current.event ~= nil and config.event.id ~= current.event.id)

	current = config

	if changed then
		broadcast()
		print(
			`[LiveOps] 설정 갱신 — 점검 {current.maintenance}, `
				.. `이벤트 {if current.event then current.event.id else "없음"}`
		)
	end
end

local function poll()
	if store == nil then
		return
	end

	local ok, raw = pcall(function()
		return (store :: DataStore):GetAsync(CONFIG_KEY)
	end)

	if not ok then
		warn(`[LiveOps] 설정을 읽지 못했습니다: {raw}`)
		return -- 직전 설정을 그대로 유지한다
	end

	local sanitized = sanitize(raw)
	if sanitized ~= nil then
		apply(sanitized)
	end
end

--------------------------------------------------------------------------------
-- 다른 서비스가 쓰는 조회 함수
--------------------------------------------------------------------------------

function LiveOpsService.getSuccessBuff(): number
	local event = LiveOpsService.getActiveEvent()
	return if event then event.successBuff else 0
end

function LiveOpsService.getActiveEvent(): ActiveEvent?
	local event = current.event
	if event ~= nil and os.time() >= event.endsAt then
		current.event = nil
		broadcast()
		return nil
	end
	return event
end

function LiveOpsService.isMaintenance(): boolean
	return current.maintenance
end

function LiveOpsService.getNotice(): string
	return current.notice
end

function LiveOpsService.getConfig(): LiveConfig
	return current
end

--------------------------------------------------------------------------------
-- AdminService 가 쓰는 변경 함수 (즉시 적용 + DataStore 저장)
--------------------------------------------------------------------------------

-- 이 함수는 yield 한다. 성공 여부를 반환한다.
function LiveOpsService.save(config: LiveConfig): boolean
	apply(config)

	if store == nil then
		return false
	end

	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(CONFIG_KEY, {
			maintenance = config.maintenance,
			notice = config.notice,
			event = config.event,
		})
	end)

	if not ok then
		warn(`[LiveOps] 설정 저장 실패: {err}`)
	end

	return ok
end

function LiveOpsService.setMaintenance(enabled: boolean): boolean
	local config = LiveOpsService.getConfig()
	return LiveOpsService.save({
		maintenance = enabled,
		notice = config.notice,
		event = config.event,
	})
end

function LiveOpsService.setNotice(notice: string): boolean
	local config = LiveOpsService.getConfig()
	return LiveOpsService.save({
		maintenance = config.maintenance,
		notice = notice,
		event = config.event,
	})
end

function LiveOpsService.setEvent(event: ActiveEvent?): boolean
	local config = LiveOpsService.getConfig()
	return LiveOpsService.save({
		maintenance = config.maintenance,
		notice = config.notice,
		event = event,
	})
end

--------------------------------------------------------------------------------

function LiveOpsService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(storeName())
	end)

	if ok then
		store = result
	else
		warn(`[LiveOps] 설정 저장소를 열지 못했습니다: {result}`)
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	changedRemote = remotesFolder:WaitForChild(Remotes.Events.LiveOpsChanged) :: RemoteEvent
end

function LiveOpsService.Start()
	task.spawn(function()
		while true do
			poll()
			task.wait(POLL_SECONDS)
		end
	end)
end

return LiveOpsService
