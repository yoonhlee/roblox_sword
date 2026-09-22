--!strict
--[[
	EnhanceLogic — 강화 결과 계산의 순수 함수.

	원칙:
	- Roblox API, 전역 상태, 다른 모듈에 대한 require 가 전혀 없다.
	  (그래서 Studio 밖에서 그대로 테스트할 수 있다)
	- 난수는 서버가 만든 Random 객체에서 뽑아 숫자로 넘겨받는다.
	  이 모듈은 난수를 직접 만들지 않는다 → 테스트에서 모든 분기를 재현할 수 있다.
	- 확률표도 인자로 받는다. 밸런스 데이터는 Config/EnhanceTable 에만 있다.
]]

local EnhanceLogic = {}

export type Odds = {
	success: number, -- 퍼센트
	keep: number,
	destroy: number,
	cost: number,
}

export type Outcome = "success" | "keep" | "destroy" | "protected"

export type ResolveParams = {
	level: number, -- 현재 강화 레벨 (호출 전에 level < maxLevel 임을 보장할 것)
	maxLevel: number,
	odds: Odds, -- 버프까지 반영된 최종 확률
	roll: number, -- [0, 100) 구간의 난수
	useProtect: boolean, -- 플레이어가 파괴 방지권 사용을 켜 두었는지
	protectTickets: number, -- 보유 방지권 수
	shardExponent: number,
}

export type ResolveResult = {
	outcome: Outcome,
	newLevel: number,
	shardsGained: number,
	ticketsUsed: number,
}

--[[
	확률 버프 이벤트를 적용한다.
	성공 확률에 +bonus %p 를 더하고 그만큼 유지 확률에서만 뺀다.
	파괴 확률은 절대 건드리지 않는다. 유지가 모자라면 더할 수 있는 만큼만 더한다.
]]
function EnhanceLogic.applyBuff(base: Odds, bonus: number): Odds
	local add = math.clamp(bonus, 0, base.keep)

	return {
		success = base.success + add,
		keep = base.keep - add,
		destroy = base.destroy,
		cost = base.cost,
	}
end

--[[
	난수 하나를 결과로 바꾼다.
	roll 은 [0, 100) 이어야 한다. 구간은 [성공)[유지)[파괴) 순서로 붙어 있다.
]]
function EnhanceLogic.roll(odds: Odds, roll: number): "success" | "keep" | "destroy"
	if roll < odds.success then
		return "success"
	elseif roll < odds.success + odds.keep then
		return "keep"
	end
	return "destroy"
end

-- 파괴 시 지급되는 파편 수 = floor(현재레벨 ^ exponent)
function EnhanceLogic.shardsFor(level: number, exponent: number): number
	if level <= 0 then
		return 0
	end
	return math.floor(level ^ exponent)
end

--[[
	강화 1회의 최종 결과.

	파괴 방지권은 "파괴가 실제로 나왔을 때"만 소모된다.
	파괴 확률이 0인 구간에서는 파괴가 나올 수 없으므로 방지권도 소모되지 않는다.
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

	-- 파괴가 나왔다. 방지권이 있고 사용 설정이 켜져 있으면 유지로 바꾼다.
	if params.useProtect and params.protectTickets > 0 then
		return {
			outcome = "protected",
			newLevel = params.level,
			shardsGained = 0,
			ticketsUsed = 1,
		}
	end

	return {
		outcome = "destroy",
		newLevel = 0,
		shardsGained = EnhanceLogic.shardsFor(params.level, params.shardExponent),
		ticketsUsed = 0,
	}
end

-- 파편으로 방지권을 몇 개까지 바꿀 수 있는지
function EnhanceLogic.ticketsAffordable(shards: number, shardsPerTicket: number): number
	if shardsPerTicket <= 0 then
		return 0
	end
	return math.floor(shards / shardsPerTicket)
end

return EnhanceLogic
