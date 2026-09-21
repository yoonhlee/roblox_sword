--!strict
--[[
	ShopService — 게임패스와 개발자 상품.

	설계 원칙 (지시서 7절):
	- Robux 로 "확률 결과 자체"를 파는 상품은 만들지 않는다.
	  게임패스는 편의/꾸미기, 개발자 상품은 골드 팩과 방지권 묶음까지만.
	- 확률표는 상품 여부와 관계없이 강화 화면에서 항상 볼 수 있다.

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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ConfigFolder = Shared:WaitForChild("Config")
local Products = require(ConfigFolder:WaitForChild("Products"))
local EconomyConfig = require(ConfigFolder:WaitForChild("EconomyConfig"))

local services = script.Parent
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local AnalyticsService = require(services:WaitForChild("AnalyticsService"))

local ShopService = {}
ShopService.Name = "ShopService"

-- userId → { gamePassKey → 보유 여부 }
local ownership: { [number]: { [string]: boolean } } = {}

local function fail(reason: string): Types.Failure
	return { ok = false, reason = reason }
end

local function ownsPass(player: Player, key: string): boolean
	local owned = ownership[player.UserId]
	return owned ~= nil and owned[key] == true
end

--[[
	게임패스 보유 여부를 조회한다. 이 함수는 yield 한다(웹 요청).
	실패하면 "보유하지 않음"으로 두지 않고 이전 값을 유지한다
	(일시적인 통신 실패로 혜택이 사라지면 안 되므로).
]]
local function refreshOwnership(player: Player)
	local owned = ownership[player.UserId]
	if owned == nil then
		owned = {}
		ownership[player.UserId] = owned
	end

	for key, gamePassId in Products.GamePasses do
		if gamePassId == 0 then
			continue -- 아직 ID 를 넣지 않은 상품
		end

		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
		end)

		if ok then
			owned[key] = result
		else
			warn(`[ShopService] 게임패스 조회 실패 ({key}): {result}`)
		end
	end
end

--------------------------------------------------------------------------------
-- 개발자 상품 지급
--------------------------------------------------------------------------------

-- 상품 하나를 지급한다. yield 하지 않는다.
local function grantProduct(player: Player, data: Types.PlayerData, product: Products.DeveloperProduct)
	if product.goldAmount > 0 then
		-- Robux 로 산 골드에는 게임패스 배수를 적용하지 않는다.
		EconomyService.addGold(player, data, product.goldAmount, `purchase_{product.key}`, false)
	end
	if product.ticketAmount > 0 then
		EconomyService.addTickets(player, data, product.ticketAmount, `purchase_{product.key}`)
	end
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

	-- 아직 지급하지 않았다면 지급과 기록을 함께 처리한다.
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
-- 리모트
--------------------------------------------------------------------------------

local function handleGetShopItems(player: Player): { Types.ShopItem }
	local items: { Types.ShopItem } = {}

	for key, gamePassId in Products.GamePasses do
		if gamePassId == 0 then
			continue -- ID 를 넣지 않은 상품은 노출하지 않는다
		end

		table.insert(items, {
			key = key,
			kind = "gamepass",
			owned = ownsPass(player, key),
			goldAmount = 0,
			ticketAmount = 0,
		})
	end

	for key, product in Products.DeveloperProducts do
		if product.productId == 0 then
			continue
		end

		table.insert(items, {
			key = key,
			kind = "product",
			owned = false,
			goldAmount = product.goldAmount,
			ticketAmount = product.ticketAmount,
		})
	end

	table.sort(items, function(a, b)
		if a.kind ~= b.kind then
			return a.kind == "gamepass"
		end
		return a.key < b.key
	end)

	return items
end

local function handlePromptPurchase(player: Player, kind: any, key: any): Types.BattleResponse
	if type(kind) ~= "string" or type(key) ~= "string" then
		return fail("invalid_argument")
	end

	if kind == "gamepass" then
		local gamePassId = Products.GamePasses[key]
		if gamePassId == nil or gamePassId == 0 then
			return fail("not_available")
		end

		MarketplaceService:PromptGamePassPurchase(player, gamePassId)
		return { ok = true }
	elseif kind == "product" then
		local product = Products.DeveloperProducts[key]
		if product == nil or product.productId == 0 then
			return fail("not_available")
		end

		MarketplaceService:PromptProductPurchase(player, product.productId)
		return { ok = true }
	end

	return fail("invalid_argument")
end

--------------------------------------------------------------------------------

function ShopService.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)

	local itemsRemote = remotesFolder:WaitForChild(Remotes.Functions.GetShopItems) :: RemoteFunction
	itemsRemote.OnServerInvoke = handleGetShopItems

	local promptRemote =
		remotesFolder:WaitForChild(Remotes.Functions.PromptPurchase) :: RemoteFunction
	promptRemote.OnServerInvoke = handlePromptPurchase

	-- 골드 획득 배수를 경제 쪽에 연결한다.
	EconomyService.setGoldMultiplierProvider(function(player: Player): number
		if ownsPass(player, "goldBoost") then
			return EconomyConfig.GOLD_BOOST_MULTIPLIER
		end
		return 1
	end)
end

function ShopService.Start()
	-- 콜백은 서버 전체에 딱 한 번만 설정한다.
	MarketplaceService.ProcessReceipt = processReceipt

	DataService.onLoaded(function(player, _data)
		task.spawn(refreshOwnership, player)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			if not wasPurchased then
				return
			end

			for key, id in Products.GamePasses do
				if id == gamePassId then
					local owned = ownership[player.UserId]
					if owned == nil then
						owned = {}
						ownership[player.UserId] = owned
					end
					owned[key] = true

					AnalyticsService.logFunnel(player, "gamepass_purchased", { key = key })
					break
				end
			end
		end
	)

	Players.PlayerRemoving:Connect(function(player)
		ownership[player.UserId] = nil
	end)
end

return ShopService
