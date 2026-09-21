--!strict
--[[
	EnhanceLogic — 강화 결과 계산의 순수 함수. (Phase 1 에서 구현)

	설계 원칙:
	- Roblox API 와 전역 상태를 쓰지 않는다. 확률표와 난수값을 인자로 받는다.
	- 난수는 서버가 만든 Random 객체에서 뽑아 이 모듈에 숫자로 넘긴다.
	  → 테스트에서 고정 시드/고정 값으로 모든 분기를 재현할 수 있다.
]]

local EnhanceLogic = {}

return EnhanceLogic
