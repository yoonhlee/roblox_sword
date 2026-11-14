--!strict
--[[
	DrawLogic — 방지권 뽑기의 순수 함수 (통합 기획서 3-4절, 7절).

	두 가지 뽑기가 같은 함수를 쓴다.
	  - 확률형 상품 (Robux): 꽝이면 천장 포인트 +1, 다 차면 방지권을 주고 0 으로 → resolvePaid
	  - 파편 뽑기 (무과금): 천장 포인트 없음 → resolveFree

	Roblox API 와 require 가 없다. 결과 목록과 천장 규칙은 인자로 받는다(Config/Products).
	난수는 서버가 만든 [0, 1) 값을 넘겨받는다. 이 모듈은 난수를 만들지 않는다.

	화면에 보여 주는 %는 Pure/SwordLogic.exactPercents(DrawLogic.weights(결과 목록), 자릿수) 로 만든다
	(합이 정확히 100 이 된다). 실제 추첨은 반올림한 %가 아니라 원래 weight 로 한다.
]]

local DrawLogic = {}

export type Outcome = {
	tickets: number, -- 0 이면 꽝
	weight: number,
}

export type FreeResult = {
	index: number, -- 뽑힌 결과의 순번
	tickets: number,
}

export type PaidResult = {
	index: number,
	rolledTickets: number, -- 뽑기 자체로 나온 방지권 수 (꽝이면 0)
	isMiss: boolean,
	pityTickets: number, -- 천장 포인트가 차서 받은 방지권 수 (없으면 0)
	totalTickets: number, -- 실제로 지급할 방지권 수
	pityAfter: number, -- 처리 후 천장 포인트
}

-- 결과 목록의 비중만 뽑아낸다 (% 계산에 넘기는 모양).
function DrawLogic.weights(outcomes: { Outcome }): { number }
	local list: { number } = {}
	for index, outcome in outcomes do
		list[index] = math.max(0, outcome.weight)
	end
	return list
end

--[[
	뽑기 1회. unitRoll 은 [0, 1) 난수. 뽑을 것이 없으면 nil.
	구간은 목록 순서대로 붙어 있다.
]]
function DrawLogic.pick(outcomes: { Outcome }, unitRoll: number): number?
	local total = 0
	for _, outcome in outcomes do
		total += math.max(0, outcome.weight)
	end

	if #outcomes == 0 or total <= 0 then
		return nil
	end

	local target = math.clamp(unitRoll, 0, 1) * total
	local running = 0
	local last = 0

	for index, outcome in outcomes do
		local weight = math.max(0, outcome.weight)
		if weight > 0 then
			running += weight
			last = index
			if target < running then
				return index
			end
		end
	end

	return last
end

--[[
	꽝 한 번을 천장 포인트에 반영한다.
	반환: (처리 후 포인트, 이번에 받는 방지권 수)
	포인트가 threshold 에 닿으면 그 자리에서 방지권을 주고 0 으로 돌아간다.
]]
function DrawLogic.applyMiss(
	pityPoints: number,
	perMiss: number,
	threshold: number,
	pityTickets: number
): (number, number)
	local points = math.max(0, math.floor(pityPoints)) + perMiss

	if threshold > 0 and points >= threshold then
		return 0, pityTickets
	end
	return points, 0
end

-- 다음 꽝에서 천장이 차는 상태인지 (상점이 꽝 줄의 설명을 바꿔 보여 주는 데 쓴다)
function DrawLogic.isPityNext(pityPoints: number, perMiss: number, threshold: number): boolean
	return threshold > 0 and math.max(0, math.floor(pityPoints)) + perMiss >= threshold
end

-- 파편 뽑기 1회 (천장 포인트 없음)
function DrawLogic.resolveFree(outcomes: { Outcome }, unitRoll: number): FreeResult?
	local index = DrawLogic.pick(outcomes, unitRoll)
	if index == nil then
		return nil
	end

	return {
		index = index,
		tickets = math.max(0, math.floor(outcomes[index].tickets)),
	}
end

-- 확률형 상품 1회 (꽝이면 천장 포인트)
function DrawLogic.resolvePaid(
	outcomes: { Outcome },
	unitRoll: number,
	pityPoints: number,
	perMiss: number,
	threshold: number,
	pityTickets: number
): PaidResult?
	local index = DrawLogic.pick(outcomes, unitRoll)
	if index == nil then
		return nil
	end

	local rolled = math.max(0, math.floor(outcomes[index].tickets))
	local isMiss = rolled == 0

	local pityAfter = math.max(0, math.floor(pityPoints))
	local bonus = 0
	if isMiss then
		pityAfter, bonus = DrawLogic.applyMiss(pityPoints, perMiss, threshold, pityTickets)
	end

	return {
		index = index,
		rolledTickets = rolled,
		isMiss = isMiss,
		pityTickets = bonus,
		totalTickets = rolled + bonus,
		pityAfter = pityAfter,
	}
end

return DrawLogic
