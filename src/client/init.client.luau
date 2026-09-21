--!strict
--[[
	클라이언트 부트스트랩.
	controllers 폴더의 모듈을 정해진 순서대로 require → Init() → Start() 한다.

	클라이언트는 "요청"과 "표시"만 한다.
	확률 계산, 골드 증감, 레벨 변경, 배틀 결과는 전부 서버가 결정한다.
	서버 응답을 받기 전에는 어떤 결과 연출도 시작하지 않는다.
]]

type Controller = {
	Name: string?,
	Init: (() -> ())?,
	Start: (() -> ())?,
}

local CONTROLLER_ORDER = {
	"SoundController",
	"EffectsController",
	"FeedController",
	"OddsTableController",
	"BattleController",
	"ShopController",
	"CollectionController",
	"UIController",
}

local controllersFolder = script:WaitForChild("controllers")

local function loadController(name: string): Controller
	local module = controllersFolder:WaitForChild(name)
	assert(module:IsA("ModuleScript"), `[Client] 컨트롤러 모듈이 아닙니다: {name}`)
	return require(module) :: Controller
end

local function runStage(stage: "Init" | "Start", controllers: { Controller })
	for _, controller in controllers do
		local fn = if stage == "Init" then controller.Init else controller.Start
		if not fn then
			continue
		end

		local ok, err = xpcall(fn, debug.traceback)
		if not ok then
			warn(`[Client] {controller.Name or "?"}.{stage} 실패:\n{err}`)
		end
	end
end

local controllers: { Controller } = {}
for _, name in CONTROLLER_ORDER do
	local controller = loadController(name)
	controller.Name = controller.Name or name
	table.insert(controllers, controller)
end

runStage("Init", controllers)
runStage("Start", controllers)
