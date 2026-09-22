--!strict
--[[
	서버 부트스트랩.
	services 폴더의 모듈을 정해진 순서대로 require → Init() → Start() 한다.

	- Init(): 상태 준비, 리모트 핸들러 등록. 다른 서비스를 호출하지 않는다.
	- Start(): 다른 서비스가 모두 Init 된 뒤에 실행되는 실제 동작 시작점.

	Init 단계에서 에러가 나면 게임이 정상 동작할 수 없으므로 크게 실패시킨다
	(데이터가 준비되지 않은 채로 플레이어를 받으면 안 된다).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

type Service = {
	Name: string?,
	Init: (() -> ())?,
	Start: (() -> ())?,
}

-- 의존 순서대로 나열한다. 여기 없는 모듈은 생명주기 없는 유틸로 간주하고 건너뛴다.
local SERVICE_ORDER = {
	"DataService",
	"AnalyticsService",
	"LiveOpsService",
	"EconomyService",
	"EnhanceService",
	"ChatCommandService",
	"BattleService",
	"ShopService",
	"CodexService",
	"LeaderboardService",
	"AdminService",
}

local servicesFolder = script:WaitForChild("services")

local function loadService(name: string): Service
	local module = servicesFolder:FindFirstChild(name)
	assert(
		module and module:IsA("ModuleScript"),
		`[Bootstrap] 서비스 모듈을 찾을 수 없습니다: {name}`
	)
	return require(module) :: Service
end

local function runStage(stage: "Init" | "Start", services: { Service })
	for _, service in services do
		local fn = if stage == "Init" then service.Init else service.Start
		if not fn then
			continue
		end

		local ok, err = xpcall(fn, debug.traceback)
		if not ok then
			warn(`[Bootstrap] {service.Name or "?"}.{stage} 실패:\n{err}`)
			if stage == "Init" then
				error(`[Bootstrap] {service.Name or "?"}.Init 실패로 서버 시작을 중단합니다`, 0)
			end
		end
	end
end

-- 리모트는 서비스가 핸들러를 붙이기 전에 미리 만들어 둔다.
Remotes.Build()

local services: { Service } = {}
for _, name in SERVICE_ORDER do
	local service = loadService(name)
	service.Name = service.Name or name
	table.insert(services, service)
end

runStage("Init", services)
runStage("Start", services)

print(`[Bootstrap] 서비스 {#services}개 시작 완료`)
