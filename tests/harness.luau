--!strict
--[[
	harness — 의존성 없는 초소형 테스트 러너.
	Lune 과 순수 Luau 어느 쪽에서도 돌아가도록 표준 라이브러리만 쓴다.

	사용법:
		local t = require("./harness")
		t.describe("EnhanceTable", function()
			t.it("확률 합이 100", function()
				t.expectEqual(sum, 100)
			end)
		end)
]]

local Harness = {}

local passed = 0
local failed = 0
local failures: { string } = {}
local suite = ""

function Harness.describe(name: string, body: () -> ())
	suite = name
	body()
	suite = ""
end

function Harness.it(name: string, body: () -> ())
	local label = if suite ~= "" then `{suite} > {name}` else name
	local ok, err = pcall(body)

	if ok then
		passed += 1
		print(`  PASS  {label}`)
	else
		failed += 1
		table.insert(failures, `{label}\n        {tostring(err)}`)
		print(`  FAIL  {label}`)
		print(`        {tostring(err)}`)
	end
end

function Harness.expect(condition: boolean, message: string?)
	if not condition then
		error(message or "조건이 참이 아닙니다", 2)
	end
end

function Harness.expectEqual(actual: any, expected: any, message: string?)
	if actual ~= expected then
		local detail = `기대값 {tostring(expected)}, 실제값 {tostring(actual)}`
		error(if message then `{message} — {detail}` else detail, 2)
	end
end

function Harness.expectNear(actual: number, expected: number, tolerance: number?, message: string?)
	local eps = tolerance or 1e-9
	if math.abs(actual - expected) > eps then
		local detail = `기대값 {expected} ± {eps}, 실제값 {actual}`
		error(if message then `{message} — {detail}` else detail, 2)
	end
end

function Harness.expectNil(value: any, message: string?)
	if value ~= nil then
		error(message or `nil 이어야 하는데 {tostring(value)} 입니다`, 2)
	end
end

-- 전체 결과를 출력한다. 실패가 있으면 error 로 끝내 프로세스 종료 코드를 0 이 아니게 만든다.
function Harness.finish()
	print("")
	print(`총 {passed + failed}개 중 {passed}개 통과, {failed}개 실패`)

	if failed > 0 then
		print("")
		for _, failure in failures do
			print(`  - {failure}`)
		end
		error(`테스트 {failed}개 실패`, 0)
	end
end

return Harness
