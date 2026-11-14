--!strict
--[[
	ShopService — 방지권 상품(Robux)과 파편 뽑기 (통합 기획서 3-4절, 7절).

	상품 세 가지 (Config/Products):
	  확정 1개 / 확정 묶음 / 확률형(꽝이면 천장 포인트 +1, 3점이면 방지권 1개 후 0점)
	그리고 Robux 가 닿지 않는 파편 뽑기(파편 50개 = 1회, 천장 포인트 없음).

	설계 원칙:
	- 유료 상품은 방지권뿐이다. 골드·파편을 주거나 골드 획득량을 늘리는 상품은 만들지 않는다.
	- ID 나 내용이 비어 있는 상품은 목록에 넣지 않고 구매 요청도 받지 않는다
	  (개수·확률·가격은 미정 D12, 상품 ID 는 개발자 입력 대기).

	로블록스 유료 확률형 정책 (통합 기획서 7절, creator-docs paid-random-items.md 로 확인):
	  1) 사기 전에 모든 결과와 확률을 %로, 합계 정확히 100% 로 보여 준다
	     → GetShopItems 가 결과별 %를 함께 보낸다(Pure/SwordLogic.exactPercents, 합이 정확히 100).
	  2) 확률을 바꾸는 장치(방지권, 천장)는 숫자로 설명하고 적용 중이면 표시를 바꾼다
	     → 방지권은 강화 화면이, 천장은 상점 화면이 처리한다.
	  3) PolicyService 의 ArePaidRandomItemsRestricted 가 참인 유저에게는 확률형을 숨긴다
	     → 목록에서 빼고, 구매창도 띄우지 않고, 혹시 결제가 들어와도 뽑지 않는다.
	     확인에 실패하면 제한된 것으로 본다(안전한 쪽).
	  4) 결제가 재시도돼도 다시 뽑지 않는다
	     → 뽑기 결과·천장 포인트 변경·PurchaseId 기록을 yield 없는 한 번의 변경으로 처리한다.
	       같은 PurchaseId 가 다시 오면 기록을 보고 건너뛴다.

	ProcessReceipt 구현은 ProfileStore 공식 문서의 "PurchaseId 캐싱" 방식을 따른다.
	핵심은 "지급했다"가 아니라 "지급한 사실이 DataStore 에 저장됐다"를 확인한 뒤에야
	PurchaseGranted 를 돌려준다는 것이다. 그래야 지급 직후 서버가 죽어도
	플레이어가 산 것을 잃지 않는다.

	  1) 프로필이 아직 안 열렸으면 NotProcessedYet (다음에 다시 물어본다)
	  2) purchaseHistory 에 PurchaseId 가 있으면 이미 지급한 것 → 중복 지급 안 함
	  3) 지급과 기록을 같은 프로필 업데이트 안에서 처리
	  4) LastSavedData 에 그 PurchaseId 가 보일 때까지 기다린 뒤 PurchaseGranted

	ProcessReceipt 콜백은 서버 전체에 딱 하나만 설정할 수 있다. 여기서만 설정한다.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Locale = require(Shared:WaitForChild("Locale"))

local ConfigFolder = Shared:WaitForChild("Config")
local Products = require(ConfigFolder:WaitForChild("Products"))

local Pure = Shared:WaitForChild("Pure")
local DrawLogic = require(Pure:WaitForChild("DrawLogic"))
local SwordLogic = require(Pure:WaitForChild("SwordLogic"))

local services = script.Parent
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local AnalyticsService = require(services:WaitForChild("AnalyticsService"))
local LiveOpsService = require(services:WaitForChild("LiveOpsService"))
local RateLimiter = require(services:WaitForChild("RateLimiter"))

local ShopService = {}
ShopService.Name = "ShopService"

-- 서버 난수. 뽑기 결과는 서버에서만 정한다.
local rng = Random.new()

-- 플레이어당 초당 3회, 동시 처리 1건 (파편 뽑기)
local limiter = RateLimiter.new({ maxRequests = 3, windowSeconds = 1 })

-- 표시 확률의 소수 자릿수
local PERCENT_DECIMALS = 2

-- 유료 확률형 제한 여부(PolicyService). true = 제한됨. 확인에 성공한 값만 넣는다.
local restrictedCache: { [Player]: boolean } = {}

local feedRemote: RemoteEvent? = nil

local function fail(reason: string): Types.Failure
	return { ok = false, reason = reason }
end

-- 그 플레이어의 채팅·피드에 한 줄 띄운다.
local function notify(player: Player, text: string)
	if feedRemote and player.Parent == Players then
		feedRemote:FireClient(player, { kind = "system", text = text })
	end
end

--------------------------------------------------------------------------------
-- 유료 확률형 제한 확인
--------------------------------------------------------------------------------

--[[
	이 플레이어가 유료 확률형 아이템을 쓸 수 없는지. **yield 한다**(웹 요청).
	확인에 실패하면 true(제한됨)를 돌려주고 캐시하지 않는다 → 다음에 다시 확인한다.
]]
local function isRandomRestricted(player: Player): boolean
	local cached = restrictedCache[player]
	if cached ~= nil then
		return cached
	end

	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)

	if not ok or type(info) ~= "table" then
		warn(`[ShopService] 정책 정보를 받지 못했습니다 ({player.UserId}): {info}`)
		return true
	end

	-- 값이 명확히 false 일 때만 허용한다.
	local restricted = info.ArePaidRandomItemsRestricted ~= false

	if player.Parent == Players then
		restrictedCache[player] = restricted
	end
	return restricted
end

--------------------------------------------------------------------------------
-- 개발자 상품 지급
--------------------------------------------------------------------------------

--[[
	상품 하나를 지급한다. **yield 하지 않는다.**
	확률형은 여기서 한 번만 뽑는다. 이 함수가 끝나면 호출자가 곧바로 같은 흐름에서
	PurchaseId 를 기록하므로, 같은 결제가 다시 와도 다시 뽑히지 않는다.
]]
local function grantProduct(
	player: Player,
	data: Types.PlayerData,
	product: Products.DeveloperProduct
)
	local language = data.settings.language
	local reason = `purchase_{product.key}`

	if product.kind == "fixed" then
		EconomyService.addTickets(player, data, product.ticketAmount, reason)
		notify(player, Locale.get(language, "shop.granted", product.ticketAmount))
		return
	end

	local result = DrawLogic.resolvePaid(
		product.outcomes,
		rng:NextNumber(),
		data.pityPoints,
		Products.PITY_PER_MISS,
		Products.PITY_THRESHOLD,
		Products.PITY_TICKETS
	)
	if result == nil then
		error("확률형 상품의 결과 목록이 비어 있습니다", 0)
	end

	-- 여기서부터 실제 변경.
	data.pityPoints = result.pityAfter
	if result.totalTickets > 0 then
		EconomyService.addTickets(player, data, result.totalTickets, reason)
	end

	if not result.isMiss then
		notify(player, Locale.get(language, "shop.randomWin", result.rolledTickets))
	elseif result.pityTickets > 0 then
		notify(player, Locale.get(language, "shop.randomPity", result.pityTickets))
	else
		notify(
			player,
			Locale.get(language, "shop.randomMiss", result.pityAfter, Products.PITY_THRESHOLD)
		)
	end

	AnalyticsService.logFunnel(player, "ticket_random", {
		tickets = result.rolledTickets,
		pityTickets = result.pityTickets,
		pityAfter = result.pityAfter,
	})
end

local function historyContains(history: { string }, purchaseId: string): boolean
	return table.find(history, purchaseId) ~= nil
end

--[[
	지급 → 저장 확인까지 기다린다.
	이 함수는 yield 한다. ProcessReceipt 는 결과를 돌려줄 때까지 기다려 주므로 괜찮다.
]]
local function grantAndConfirm(
	player: Player,
	profile: any,
	purchaseId: string,
	product: Products.DeveloperProduct
): Enum.ProductPurchaseDecision
	if not profile:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local data = profile.Data :: Types.PlayerData

	-- 아직 지급하지 않았다면 지급과 기록을 함께 처리한다. (이 구간에는 yield 가 없다)
	if not historyContains(data.purchaseHistory, purchaseId) then
		local ok, err = pcall(grantProduct, player, data, product)
		if not ok then
			warn(`[ShopService] 지급 실패 ({product.key}): {err}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- 기록이 무한히 커지지 않도록 오래된 것부터 버린다.
		while #data.purchaseHistory >= Products.PURCHASE_HISTORY_LIMIT do
			table.remove(data.purchaseHistory, 1)
		end
		table.insert(data.purchaseHistory, purchaseId)

		DataService.replicate(player)
		AnalyticsService.logFunnel(player, "purchase_granted", { product = product.key })
	end

	-- 저장이 확인될 때까지 기다린다.
	local function isSaved(): boolean
		local saved = profile.LastSavedData
		if saved == nil or saved.purchaseHistory == nil then
			return false
		end
		return historyContains(saved.purchaseHistory, purchaseId)
	end

	if isSaved() then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	while profile:IsActive() do
		local before = profile.LastSavedData
		profile:Save()

		if profile.LastSavedData == before then
			profile.OnAfterSave:Wait()
		end

		if isSaved() then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		if profile:IsActive() then
			task.wait(10)
		end
	end

	-- 저장을 확인하지 못했다. 다음에 다시 물어보게 둔다.
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local product = Products.byProductId(receipt.ProductId)
	if product == nil then
		warn(`[ShopService] 모르는 상품 ID: {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not Products.isSellable(product) then
		warn(
			`[ShopService] 내용이 비어 있는 상품의 결제가 들어왔습니다: {product.key}`
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	--[[
		유료 확률형이 제한된 유저의 결제는 뽑지 않고 "아직 처리 안 됨"으로 둔다.
		상점은 이런 유저에게 확률형을 보여 주지도, 구매창을 띄우지도 않으므로 게임 안의 정상
		경로로는 여기 올 수 없다. (조작한 클라이언트가 직접 구매창을 띄웠거나, 상품을 게임 소개
		페이지의 Store 탭에 노출한 경우에만 생긴다 → 확률형은 Store 탭에 올리지 말 것.)

		[결정 필요] 공식 문서상 처리 안 된 결제는 자동으로 환불되지 않고, 접속할 때마다 다시
		들어온다. 이런 결제에 무엇을 줄지(예: 확정 개수로 바꿔 지급)는 기획에 없어서 정하지 않았다.
		정해지면 여기서 지급하면 되고, 그때까지 쌓인 결제도 다음 접속 때 함께 처리된다.
	]]
	if product.kind == "random" and isRandomRestricted(player) then
		warn(
			`[ShopService] 확률형이 제한된 유저의 결제를 처리하지 않습니다 ({player.UserId})`
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 프로필이 열릴 때까지 기다린다(방금 접속한 직후일 수 있다).
	local profile = DataService.getProfile(player)
	while profile == nil and player.Parent == Players do
		task.wait()
		profile = DataService.getProfile(player)
	end

	if profile == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return grantAndConfirm(player, profile, tostring(receipt.PurchaseId), product)
end

--------------------------------------------------------------------------------
-- 상점 목록
--------------------------------------------------------------------------------

-- 결과 목록을 "결과 + 표시 확률" 로 바꾼다. 표시 확률의 합은 정확히 100 이다.
local function describeOutcomes(outcomes: { Products.TicketOutcome }): { Types.ShopOutcome }
	local percents = SwordLogic.exactPercents(DrawLogic.weights(outcomes), PERCENT_DECIMALS)

	local described: { Types.ShopOutcome } = {}
	for index, outcome in outcomes do
		described[index] = { tickets = outcome.tickets, percent = percents[index] }
	end
	return described
end

-- yield 할 수 있다(확률형 제한 확인).
local function handleGetShopItems(player: Player): Types.ShopState
	local items: { Types.ShopItem } = {}

	for _, key in Products.ORDER do
		local product = Products.DeveloperProducts[key]
		if product == nil or not Products.isSellable(product) then
			continue -- ID 나 내용을 넣지 않은 상품은 노출하지 않는다
		end

		if product.kind == "random" then
			if isRandomRestricted(player) then
				continue -- 유료 확률형이 제한된 유저에게는 확정형만 보여 준다
			end
			table.insert(items, {
				key = key,
				kind = "random",
				ticketAmount = 0,
				outcomes = describeOutcomes(product.outcomes),
			})
		else
			table.insert(items, {
				key = key,
				kind = "fixed",
				ticketAmount = product.ticketAmount,
				outcomes = {},
			})
		end
	end

	local shardDraw: Types.ShopShardDraw? = nil
	local shardConfig = Products.SHARD_DRAW
	if Products.isDrawReady(shardConfig.outcomes) then
		shardDraw = {
			cost = shardConfig.cost,
			outcomes = describeOutcomes(shardConfig.outcomes),
		}
	end

	return {
		items = items,
		pityPerMiss = Products.PITY_PER_MISS,
		pityThreshold = Products.PITY_THRESHOLD,
		pityTickets = Products.PITY_TICKETS,
		shardDraw = shardDraw,
	}
end

local function handlePromptPurchase(player: Player, key: any): Types.SimpleResponse
	if type(key) ~= "string" then
		return fail("invalid_argument")
	end

	local product = Products.DeveloperProducts[key]
	if product == nil or not Products.isSellable(product) then
		return fail("not_available")
	end

	if product.kind == "random" and isRandomRestricted(player) then
		return fail("not_available")
	end

	MarketplaceService:PromptProductPurchase(player, product.productId)
	return { ok = true }
end

--------------------------------------------------------------------------------
-- 파편 뽑기 (Robux 가 닿지 않는다)
--------------------------------------------------------------------------------

-- 파편 50개로 방지권 뽑기 1회. yield 하지 않는다.
local function processShardDraw(player: Player): Types.ShardDrawResponse
	if LiveOpsService.isMaintenance() then
		return fail("maintenance")
	end

	local config = Products.SHARD_DRAW
	if not Products.isDrawReady(config.outcomes) then
		return fail("not_available") -- 확률이 아직 정해지지 않았다 (미정 D12)
	end

	local data = DataService.getActiveData(player)
	if data == nil then
		return fail("not_ready")
	end

	if data.shards < config.cost then
		return fail("not_enough_shards")
	end

	local result = DrawLogic.resolveFree(config.outcomes, rng:NextNumber())
	if result == nil then
		return fail("not_available")
	end

	-- 여기서부터 실제 변경.
	EconomyService.spendShards(player, data, config.cost, "shard_draw")
	if result.tickets > 0 then
		EconomyService.addTickets(player, data, result.tickets, "shard_draw")
	end

	AnalyticsService.logFunnel(player, "shard_draw", { tickets = result.tickets })

	return {
		ok = true,
		tickets = result.tickets,
		shards = data.shards,
	}
end

local function handleShardDraw(player: Player): Types.ShardDrawResponse
	if not limiter:consume(player.UserId) then
		return fail("too_fast")
	end
	if not limiter:tryLock(player.UserId) then
		return fail("busy")
	end

	local ok, response = xpcall(processShardDraw, debug.traceback, player)

	limiter:unlock(player.UserId)

	if not ok then
		warn(`[ShopService] 파편 뽑기 처리 중 오류 ({player.UserId}):\n{response}`)
		return fail("unknown")
	end

	if response.ok then
		DataService.replicate(player)
	end

	return response
end

--------------------------------------------------------------------------------

function ShopService.Init()
	-- 상품 설정이 잘못된 채로 서버가 뜨는 일이 없도록 시작할 때 검사한다.
	local problem = Products.validate()
	if problem ~= nil then
		error(`[ShopService] 상품 설정이 잘못되었습니다: {problem}`, 0)
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)

	local itemsRemote = remotesFolder:WaitForChild(Remotes.Functions.GetShopItems) :: RemoteFunction
	itemsRemote.OnServerInvoke = handleGetShopItems

	local promptRemote =
		remotesFolder:WaitForChild(Remotes.Functions.PromptPurchase) :: RemoteFunction
	promptRemote.OnServerInvoke = handlePromptPurchase

	local shardRemote = remotesFolder:WaitForChild(Remotes.Functions.ShardDraw) :: RemoteFunction
	shardRemote.OnServerInvoke = handleShardDraw

	feedRemote = remotesFolder:WaitForChild(Remotes.Events.FeedMessage) :: RemoteEvent
end

function ShopService.Start()
	-- 콜백은 서버 전체에 딱 한 번만 설정한다.
	MarketplaceService.ProcessReceipt = processReceipt

	Players.PlayerRemoving:Connect(function(player)
		restrictedCache[player] = nil
		limiter:clear(player.UserId)
	end)
end

return ShopService
