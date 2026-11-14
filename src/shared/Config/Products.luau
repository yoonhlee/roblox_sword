--!strict
--[[
	Products — 방지권 상품과 방지권 뽑기 설정 (통합 기획서 3-4절, 7절).

	[개발자 입력 필요] Roblox 크리에이터 대시보드에서 "개발자 상품"을 만든 뒤 productId 를 채운다.
	[미정 D12] 묶음 개수, 확률형 결과·확률, 파편 뽑기 확률은 아직 정해지지 않았다. 그래서 비워 두었다.
	**ID 나 내용이 비어 있는 상품은 상점에 보이지 않고 살 수도 없다** (isSellable / isDrawReady).

	지킬 것 (통합 기획서 6·7절):
	- 유료 상품은 방지권뿐이다. 골드·파편을 주거나 골드 획득량을 늘리는 상품은 만들지 않는다.
	  (Robux 로 살 수 있는 화폐로 하는 강화는 로블록스 정책상 유료 확률형 아이템이 된다.)
	- 유료 확률형은 "방지권 확률형" 1종만 승인됐다. 다른 확률형 상품은 추가하지 않는다.
	- 가격은 대시보드에서 정한다. 정할 때 **확률형 3회 가격 > 확정 1개 가격** 이어야 한다
	  (아니면 꽝만 3번 나와도 확정 1개보다 싸게 방지권을 얻는다).
	- 확률을 채우면 상점이 모든 결과를 %(합계 100%)로 보여 준다. 실제 추첨은 weight 그대로 한다.

	결과 목록(outcomes) 쓰는 법: { tickets = 방지권 개수, weight = 비중 }
	  tickets = 0 인 줄이 "꽝"이다. weight 는 합이 100 일 필요가 없다(비율만 맞으면 된다).
	  예) { { tickets = 3, weight = 10 }, { tickets = 1, weight = 30 }, { tickets = 0, weight = 60 } }
]]

local Products = {}

export type TicketOutcome = {
	tickets: number, -- 받는 방지권 수. 0 이면 꽝
	weight: number, -- 뽑힐 비중 (0 보다 커야 한다)
}

export type DeveloperProduct = {
	key: string,
	productId: number, -- 0 이면 아직 등록하지 않은 상품
	kind: "fixed" | "random",
	ticketAmount: number, -- fixed: 주는 방지권 수. random 은 0
	outcomes: { TicketOutcome }, -- random: 결과 목록. fixed 는 빈 표
}

Products.DeveloperProducts = {
	-- [확정] 확정 1개: 방지권 1개. 1개당 가격이 가장 비싼 상품.
	ticketSingle = {
		key = "ticketSingle",
		productId = 0,
		kind = "fixed",
		ticketAmount = 1,
		outcomes = {},
	},

	-- 확정 묶음: 방지권 여러 개. [미정 D12] 개수가 정해지면 ticketAmount 를 채운다.
	ticketBundle = {
		key = "ticketBundle",
		productId = 0,
		kind = "fixed",
		ticketAmount = 0,
		outcomes = {},
	},

	-- 확률형: 방지권 여러 개 중 확률. [미정 D12] 결과와 확률이 정해지면 outcomes 를 채운다.
	ticketRandom = {
		key = "ticketRandom",
		productId = 0,
		kind = "random",
		ticketAmount = 0,
		outcomes = {},
	},
} :: { [string]: DeveloperProduct }

-- 상점에 보여 주는 순서
Products.ORDER = { "ticketSingle", "ticketBundle", "ticketRandom" }

--[[
	[확정] 천장 포인트 (통합 기획서 7절).
	확률형에서 꽝이 나오면 +PITY_PER_MISS 점, PITY_THRESHOLD 점이 되면 그 자리에서
	방지권 PITY_TICKETS 개를 주고 0 점으로 돌아간다. 확률형 꽝에서만 생기고 다른 용도는 없다.
]]
Products.PITY_PER_MISS = 1
Products.PITY_THRESHOLD = 3
Products.PITY_TICKETS = 1

--[[
	파편 뽑기 (통합 기획서 3-4절). Robux 가 닿지 않는 무과금 경로다.
	[확정] 파편 50개 = 뽑기 1회.
	[미정 D12] 뽑기 확률. 정해지면 outcomes 를 채운다. 비어 있는 동안은 상점에 보이지 않는다.
	천장 포인트는 여기서는 쌓이지 않는다(유료 확률형 꽝에서만 생긴다).
]]
Products.SHARD_DRAW = {
	cost = 50,
	outcomes = {} :: { TicketOutcome },
}

-- purchaseHistory 가 무한히 커지지 않도록 유지할 최근 기록 수
Products.PURCHASE_HISTORY_LIMIT = 200

-- 결과 목록이 뽑기에 쓸 수 있게 채워져 있는지
function Products.isDrawReady(outcomes: { TicketOutcome }): boolean
	if #outcomes == 0 then
		return false
	end

	for _, outcome in outcomes do
		local tickets = outcome.tickets
		local weight = outcome.weight

		if type(tickets) ~= "number" or tickets < 0 or tickets ~= math.floor(tickets) then
			return false
		end
		if type(weight) ~= "number" or weight ~= weight or weight <= 0 or weight == math.huge then
			return false
		end
	end

	return true
end

-- 팔 수 있는 상품인지 (ID 가 있고 내용이 채워져 있다)
function Products.isSellable(product: DeveloperProduct): boolean
	if product.productId == 0 then
		return false
	end

	if product.kind == "fixed" then
		return product.ticketAmount > 0 and product.ticketAmount == math.floor(product.ticketAmount)
	end

	return Products.isDrawReady(product.outcomes)
end

-- productId → 상품 정의 역인덱스 (ProcessReceipt 에서 사용)
function Products.byProductId(productId: number): DeveloperProduct?
	for _, product in Products.DeveloperProducts do
		if product.productId ~= 0 and product.productId == productId then
			return product
		end
	end
	return nil
end

--[[
	설정이 스스로 일관된지 검사한다. 문제가 있으면 사유 문자열, 없으면 nil.
	"아직 비어 있는 것"은 문제가 아니다(미정이라 비워 둔 것). 채웠는데 틀린 것만 잡는다.
]]
function Products.validate(): string?
	local seenIds: { [number]: string } = {}

	for key, product in Products.DeveloperProducts do
		if product.key ~= key then
			return `{key} 의 key 값이 "{product.key}" 입니다`
		end
		if table.find(Products.ORDER, key) == nil then
			return `{key} 가 ORDER 에 없습니다`
		end

		if product.productId ~= 0 then
			local other = seenIds[product.productId]
			if other ~= nil then
				return `{key} 와 {other} 의 productId 가 같습니다`
			end
			seenIds[product.productId] = key
		end

		if product.kind == "fixed" then
			if #product.outcomes > 0 then
				return `{key} 는 확정형인데 결과 목록이 있습니다`
			end
			if
				product.ticketAmount < 0
				or product.ticketAmount ~= math.floor(product.ticketAmount)
			then
				return `{key} 의 ticketAmount 가 잘못되었습니다`
			end
		elseif product.kind == "random" then
			if #product.outcomes > 0 and not Products.isDrawReady(product.outcomes) then
				return `{key} 의 결과 목록이 잘못되었습니다`
			end
		else
			return `{key} 의 kind 가 잘못되었습니다`
		end
	end

	for _, key in Products.ORDER do
		if Products.DeveloperProducts[key] == nil then
			return `ORDER 에 없는 상품이 있습니다: {key}`
		end
	end

	local shard = Products.SHARD_DRAW
	if shard.cost <= 0 or shard.cost ~= math.floor(shard.cost) then
		return "SHARD_DRAW.cost 가 잘못되었습니다"
	end
	if #shard.outcomes > 0 and not Products.isDrawReady(shard.outcomes) then
		return "SHARD_DRAW 의 결과 목록이 잘못되었습니다"
	end

	if Products.PITY_THRESHOLD < 1 or Products.PITY_TICKETS < 1 or Products.PITY_PER_MISS < 1 then
		return "천장 포인트 설정이 잘못되었습니다"
	end

	return nil
end

return Products
