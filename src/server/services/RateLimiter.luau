--!strict
--[[
	RateLimiter — 플레이어별 요청 속도 제한과 동시 요청 락.
	생명주기(Init/Start)가 없는 유틸 모듈이라 부트스트랩 순서 목록에 넣지 않는다.

	(구현 예정: Phase 1 — 초당 최대 N회 + 동시 처리 1건, 처리 중이면 거절)
]]

local RateLimiter = {}

return RateLimiter
