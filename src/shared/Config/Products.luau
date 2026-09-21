--!strict
--[[
	Products — 게임패스 / 개발자 상품 ID.

	[개발자 입력 필요] Roblox 크리에이터 대시보드에서 상품을 만든 뒤 여기 ID 를 채운다.
	ID 가 0 이면 해당 상품은 UI 에 노출되지 않는다(ShopService 가 걸러 냄).

	정책 주의: Robux 로 "확률 결과 자체"를 파는 상품(유료 강화권 뽑기 등)은 만들지 않는다.
	그런 상품이 필요해지면 로블록스의 유료 랜덤 아이템 규정(구매 전 확률 공개)과
	국내 확률형 아이템 표시 규정을 먼저 확인하고 개발자 승인을 받을 것.
]]

local Products = {}

-- 게임패스: 편의/꾸미기 위주
Products.GamePasses = {
	goldBoost = 0, -- 골드 획득 +20%
	extraSkinSlots = 0, -- 무기 외형 슬롯 확장
	vipTag = 0, -- VIP 채팅 태그
}

-- 개발자 상품: 재화/소모품
-- goldAmount / ticketAmount 는 지급량이며 서버에서만 사용한다.
export type DeveloperProduct = {
	key: string,
	productId: number,
	goldAmount: number,
	ticketAmount: number,
}

Products.DeveloperProducts = {
	goldSmall = { key = "goldSmall", productId = 0, goldAmount = 5000, ticketAmount = 0 },
	goldMedium = { key = "goldMedium", productId = 0, goldAmount = 30000, ticketAmount = 0 },
	goldLarge = { key = "goldLarge", productId = 0, goldAmount = 100000, ticketAmount = 0 },
	ticketPack = { key = "ticketPack", productId = 0, goldAmount = 0, ticketAmount = 5 },
} :: { [string]: DeveloperProduct }

-- purchaseHistory 가 무한히 커지지 않도록 유지할 최근 기록 수
Products.PURCHASE_HISTORY_LIMIT = 200

-- productId → 상품 정의 역인덱스 (ProcessReceipt 에서 사용)
function Products.byProductId(productId: number): DeveloperProduct?
	for _, product in Products.DeveloperProducts do
		if product.productId ~= 0 and product.productId == productId then
			return product
		end
	end
	return nil
end

return Products
