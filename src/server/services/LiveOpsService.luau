--!strict
--[[
	LiveOpsService — 확률 버프 이벤트, 공지, 점검 모드.

	Phase 7 에서 원격 설정(DataStore/MemoryStore)을 주기적으로 읽어 오도록 채운다.
	지금은 "이벤트 없음 / 점검 아님"을 돌려주는 기본 구현이며,
	다른 서비스는 이미 이 함수들을 통해서만 상태를 묻는다.
	→ 나중에 내부 구현만 바꾸면 되고 호출부는 손대지 않는다.
]]

local LiveOpsService = {}
LiveOpsService.Name = "LiveOpsService"

export type ActiveEvent = {
	id: string,
	nameKey: string, -- 표시용 로컬라이즈 키
	successBuff: number, -- 성공 확률에 더할 %p
	endsAt: number, -- UTC 종료 시각
}

local activeEvent: ActiveEvent? = nil
local maintenance = false

-- 성공 확률에 더해질 %p. 이벤트가 없으면 0.
function LiveOpsService.getSuccessBuff(): number
	if activeEvent == nil then
		return 0
	end
	if os.time() >= activeEvent.endsAt then
		activeEvent = nil
		return 0
	end
	return activeEvent.successBuff
end

function LiveOpsService.getActiveEvent(): ActiveEvent?
	if activeEvent ~= nil and os.time() >= activeEvent.endsAt then
		activeEvent = nil
	end
	return activeEvent
end

function LiveOpsService.isMaintenance(): boolean
	return maintenance
end

-- AdminService 가 호출한다.
function LiveOpsService.setMaintenance(enabled: boolean)
	maintenance = enabled
	warn(`[LiveOps] 점검 모드 {if enabled then "켜짐" else "꺼짐"}`)
end

function LiveOpsService.setEvent(event: ActiveEvent?)
	activeEvent = event
end

function LiveOpsService.Init() end

function LiveOpsService.Start() end

return LiveOpsService
