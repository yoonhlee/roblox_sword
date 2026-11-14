--!strict
--[[
	EnhanceLogic — 강화 결과 계산의 순수 함수.

	원칙:
	- Roblox API, 전역 상태, 다른 모듈에 대한 require 가 전혀 없다.
	  (그래서 Studio 밖에서 그대로 테스트할 수 있다)
	- 난수는 서버가 만든 Random 객체에서 뽑아 숫자로 넘겨받는다.
	  이 모듈은 난수를 직접 만들지 않는다 → 테스트에서 모든 분기를 재현할 수 있다.
	- 확률표와 비용 상수도 인자로 받는다. 밸런스 데이터는 Config/EnhanceTable 에만 있다.

	결과 네 가지:
	  success    레벨 +1
	  keep       그대로
	  fail       2구간에서만. 안전 레벨(10강)로 돌아가고 파편을 받는다
	  protected  실패가 나왔지만 방지권이 막았다. 그대로, 방지권 1개 소모
]]

local EnhanceLogic = {}

export type Odds = {
	success: number, -- 퍼센트
	keep: number,
	fail: number,
}

export type Outcome = "success" | "keep" | "fail" | "protected"

export type ResolveParams = {
	level: number, -- 현재 강화 레벨 (호출 전에 level < maxLevel 임을 보장할 것)
	maxLevel: number,
	safeLevel: number, -- 실패했을 때 돌아가는 레벨
	odds: Odds, -- 버프까지 반영된 최종 확률 (방지권 표시용 변환은 넣지 않는다)
	roll: number, -- [0, 100) 구간의 난수
	useProtect: boolean, -- 플레이어가 방지권 사용을 켜 두었는지
	protectTickets: number, -- 보유 방지권 수
	shardsOnFail: number, -- 실패했을 때 줄 파편 수
}

export type ResolveResult = {
	outcome: Outcome,
	newLevel: number,
	shardsGained: number,
	ticketsUsed: number,
}

--[[
	레벨 level 에서 level+1 로 강화하는 1회 비용 (정수 골드, 소수는 반올림).
	    base × (1 + 2^level) × swordCount^exponent
	검이 1개면 정확히 base × (1 + 2^level) 이다.
]]
function EnhanceLogic.cost(
	level: number,
	swordCount: number,
	base: number,
	exponent: number
): number
	local count = math.max(1, swordCount)
	return math.floor(base * (1 + 2 ^ level) * count ^ exponent + 0.5)
end

--[[
	확률 버프 이벤트를 적용한다.
	성공 확률에 +bonus %p 를 더하고 그만큼 유지 확률에서만 뺀다.
	실패 확률은 절대 건드리지 않는다. 유지가 모자라면 더할 수 있는 만큼만 더한다.
]]
function EnhanceLogic.applyBuff(base: Odds, bonus: number): Odds
	local add = math.clamp(bonus, 0, base.keep)

	return {
		success = base.success + add,
		keep = base.keep - add,
		fail = base.fail,
	}
end

--[[
	방지권이 켜져 있을 때 화면에 보여 줄 확률.
	실패가 유지로 바뀌므로 실패 0, 유지 = 유지 + 실패 가 된다.
	(실제 판정은 resolve 가 한다. 이 함수는 같은 결과를 숫자로 보여 주기 위한 것이다.)
]]
function EnhanceLogic.applyProtect(odds: Odds): Odds
	return {
		success = odds.success,
		keep = odds.keep + odds.fail,
		fail = 0,
	}
end

--[[
	난수 하나를 결과로 바꾼다.
	roll 은 [0, 100) 이어야 한다. 구간은 [성공)[유지)[실패) 순서로 붙어 있다.
]]
function EnhanceLogic.roll(odds: Odds, roll: number): "success" | "keep" | "fail"
	if roll < odds.success then
		return "success"
	elseif roll < odds.success + odds.keep then
		return "keep"
	end
	return "fail"
end

-- 실패 시 지급되는 파편 수 = floor(실패한 레벨 ^ exponent)
function EnhanceLogic.shardsFor(level: number, exponent: number): number
	if level <= 0 then
		return 0
	end
	return math.floor(level ^ exponent)
end

--[[
	강화 1회의 최종 결과.

	방지권은 "실패가 실제로 나왔을 때"만 소모된다.
	실패 확률이 0인 1구간에서는 실패가 나올 수 없으므로 방지권도 소모되지 않는다.
]]
function EnhanceLogic.resolve(params: ResolveParams): ResolveResult
	local raw = EnhanceLogic.roll(params.odds, params.roll)

	if raw == "success" then
		return {
			outcome = "success",
			newLevel = math.min(params.level + 1, params.maxLevel),
			shardsGained = 0,
			ticketsUsed = 0,
		}
	elseif raw == "keep" then
		return {
			outcome = "keep",
			newLevel = params.level,
			shardsGained = 0,
			ticketsUsed = 0,
		}
	end

	-- 실패가 나왔다. 방지권이 있고 사용 설정이 켜져 있으면 유지로 바꾼다.
	if params.useProtect and params.protectTickets > 0 then
		return {
			outcome = "protected",
			newLevel = params.level,
			shardsGained = 0,
			ticketsUsed = 1,
		}
	end

	return {
		outcome = "fail",
		-- 안전 레벨 아래에서 실패가 나오는 표는 없지만, 그래도 레벨이 오르는 일은 없게 한다.
		newLevel = math.min(params.level, params.safeLevel),
		shardsGained = math.max(0, math.floor(params.shardsOnFail)),
		ticketsUsed = 0,
	}
end

return EnhanceLogic
