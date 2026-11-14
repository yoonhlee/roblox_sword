--!strict
--[[
	simulate_economy — 확률표와 비용 공식으로 강화 구조를 분석한다 (통합 기획서 3절 기준).

	실행:  lune run tools/simulate_economy

	규칙: 1구간(0~9강)은 실패 없음. 2구간(10~19강)은 실패하면 10강으로 돌아간다.
	그래서 기댓값이 닫힌 식으로 정확히 풀린다.
	    레벨 L → L+1 에 드는 기대 시도   E_L = (1 + r_L × D_L) / p_L
	    D_L = 10강에서 L강까지 다시 올라오는 기대 시도 (1구간에서는 0)
	비용·실패 횟수도 같은 식에 "한 번 시도할 때 쌓이는 양"만 바꿔 넣으면 된다.

	골드 수입(경주·트레드밀)은 아직 코드에 없어서 "도달 시간"은 계산하지 않는다.
]]

local EnhanceTable = require("../src/shared/Config/EnhanceTable")
local EnhanceLogic = require("../src/shared/Pure/EnhanceLogic")
local Format = require("../src/shared/Pure/Format")

local MAX = EnhanceTable.MAX_LEVEL
local SAFE = EnhanceTable.SAFE_LEVEL

type Weight = (level: number) -> number

--[[
	0강에서 각 레벨에 처음 닿을 때까지 쌓이는 값의 기댓값을 레벨별로 돌려준다.
	weight(L) = 레벨 L 에서 한 번 시도할 때 쌓이는 양.
	protect = true 면 방지권을 항상 쓴다고 본다(실패가 유지로 바뀐다).
]]
local function expectedTotals(weight: Weight, protect: boolean): { [number]: number }
	local totals: { [number]: number } = { [0] = 0 }
	local total = 0
	local fromSafe = 0 -- 10강에서 현재 레벨까지 다시 오는 데 쌓이는 양

	for level = 0, MAX - 1 do
		local odds = EnhanceTable.Odds[level]
		local p = odds.success / 100
		local r = if protect then 0 else odds.fail / 100
		local step = (weight(level) + r * fromSafe) / p

		total += step
		if level >= SAFE then
			fromSafe += step
		end
		totals[level + 1] = total
	end

	return totals
end

local function costOf(swordCount: number): Weight
	return function(level: number): number
		return EnhanceLogic.cost(
			level,
			swordCount,
			EnhanceTable.COST_BASE,
			EnhanceTable.SWORD_COUNT_EXPONENT
		)
	end
end

local function one(_level: number): number
	return 1
end

local function failChance(level: number): number
	return EnhanceTable.Odds[level].fail / 100
end

local function padLeft(text: string, width: number): string
	if #text >= width then
		return text
	end
	return string.rep(" ", width - #text) .. text
end

local function row(cells: { string })
	local parts: { string } = {}
	for index, cell in cells do
		table.insert(parts, padLeft(cell, if index == 1 then 5 else 18))
	end
	print(table.concat(parts))
end

print("")
print(
	"=== 강화의 대장간 · 강화 시뮬레이션 (0강에서 처음 도달할 때까지, 정확 계산) ==="
)
print("")
print("[1] 방지권 없이, 검 1개")
row({ "목표", "기대 골드", "기대 시도", "기대 실패" })

local gold = expectedTotals(costOf(1), false)
local tries = expectedTotals(one, false)
local fails = expectedTotals(failChance, false)

for target = 1, MAX do
	row({
		Format.level(target),
		Format.comma(gold[target]),
		Format.comma(tries[target]),
		Format.comma(fails[target]),
	})
end

print("")
print(
	"[2] 방지권을 항상 쓸 때, 검 1개 (실패가 유지로 바뀐다. 방지권은 골드로 살 수 없다)"
)
row({ "목표", "기대 골드", "기대 시도", "방지권 소모" })

local protectedGold = expectedTotals(costOf(1), true)
local protectedTries = expectedTotals(one, true)
local tickets = expectedTotals(failChance, true)

for _, target in { 11, 13, 15, 17, 18, 19, MAX } do
	row({
		Format.level(target),
		Format.comma(protectedGold[target]),
		Format.comma(protectedTries[target]),
		Format.comma(tickets[target]),
	})
end

print("")
print("[3] 검 수에 따른 0강 → 20강 기대 골드 (방지권 없이, 할증 n^1.1)")
row({ "검 수", "기대 골드", "검 1개 대비" })

for _, swordCount in { 1, 2, 5, 10, 20 } do
	local total = expectedTotals(costOf(swordCount), false)[MAX]
	row({
		tostring(swordCount),
		Format.comma(total),
		string.format("%.2f배", total / gold[MAX]),
	})
end

print("")
