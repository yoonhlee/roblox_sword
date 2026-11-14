--!strict
--[[
	Products — 개발자 상품(Robux 로 사는 것) ID.

	[개발자 입력 필요] Roblox 크리에이터 대시보드에서 상품을 만든 뒤 여기 ID 를 채운다.
	ID 가 0 이면 해당 상품은 UI 에 노출되지 않는다(ShopService 가 걸러 냄).

	지킬 것 (통합 기획서 6·7절):
	- 유료 상품은 방지권뿐이다. 골드 팩·게임패스는 없다.
	- 골드나 파편을 주는 상품, 골드 획득량을 늘리는 상품은 만들지 않는다.
	  (Robux 로 살 수 있는 화폐로 하는 강화는 로블록스 정책상 유료 확률형 아이템이 된다.)
	  그래서 상품 정의에는 방지권 개수(ticketAmount)만 있다.
	- 유료 확률형은 "방지권 확률형" 1종만 승인됐고, 아직 구현하지 않았다.
]]

local Products = {}

-- ticketAmount 는 지급량이며 서버에서만 사용한다.
export type DeveloperProduct = {
	key: string,
	productId: number,
	ticketAmount: number,
}

Products.DeveloperProducts = {
	-- [미정 D12] 방지권 상품의 종류·개수·가격은 아직 정해지지 않았다.
	-- 아래 5개 묶음은 프로토타입 때 넣은 임시값이다. ID 가 0 이라 상점에 보이지 않는다.
	ticketPack = { key = "ticketPack", productId = 0, ticketAmount = 5 },
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
