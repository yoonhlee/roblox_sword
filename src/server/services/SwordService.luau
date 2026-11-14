--!strict
--[[
	SwordService — 검 보관함: 착용 검 바꾸기, 소지 상한 구매 + 새 검 뽑기 (통합 기획서 5절).

	- 착용 검은 가진 검 중에서만 고를 수 있다.
	- 소지 상한은 골드로 1칸씩 산다. 1칸을 사면 그 자리에서 새 검을 1번 뽑는다.
	    가격 = SLOT_PRICE_MULTIPLIER × (SLOT_PRICE_LEVEL 강의 강화 비용, 가진 검 수 할증 포함)
	- 이미 가진 검은 뽑히지 않는다. 뽑힌 검은 0강에서 시작한다.
	- 확률표는 클라이언트가 같은 Pure/SwordLogic 으로 그린다(복제된 데이터 기준).

	골드로만 한다. 여기에 Robux 가 닿는 상품을 만들면 유료 확률형 아이템이 되므로 만들지 않는다.
	클라이언트가 보내는 값은 "착용할 검 id" 하나뿐이다. 가격·확률·결과는 전부 서버가 정한다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ConfigFolder = Shared:WaitForChild("Config")
local Weapons = require(ConfigFolder:WaitForChild("Weapons"))

local SwordLogic = require(Shared:WaitForChild("Pure"):WaitForChild("SwordLogic"))

local services = script.Parent
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local AnalyticsService = require(services:WaitForChild("AnalyticsService"))
local LiveOpsService = require(services:WaitForChild("LiveOpsService"))
local EnhanceService = require(services:WaitForChild("EnhanceService"))
local RateLimiter = require(services:WaitForChild("RateLimiter"))

local SwordService = {}
SwordService.Name = "SwordService"

local rng = Random.new()

-- 플레이어당 초당 3회, 동시 처리 1건
local limiter = RateLimiter.new({ maxRequests = 3, windowSeconds = 1 })

local RARITY_OF = Weapons.rarityMap()

local function fail(reason: string): Types.Failure
	return { ok = false, reason = reason }
end

-- 지금 가진 검 수 기준 소지 상한 1칸 가격
local function slotPriceFor(data: Types.PlayerData): number
	local count = SwordLogic.count(data.swords)
	return SwordLogic.slotPrice(
		EnhanceService.costFor(Weapons.SLOT_PRICE_LEVEL, count),
		Weapons.SLOT_PRICE_MULTIPLIER
	)
end

local function processEquip(player: Player, swordId: string): Types.EquipResponse
	local data = DataService.getActiveData(player)
	if data == nil then
		return fail("not_ready")
	end

	if data.swords[swordId] == nil then
		return fail("not_owned")
	end

	data.equippedId = swordId

	return {
		ok = true,
		swordId = swordId,
		odds = EnhanceService.getDisplayOdds(data),
	}
end

-- 소지 상한 1칸 구매 + 뽑기 1회. yield 하지 않는다.
local function processDraw(player: Player): Types.DrawResponse
	if LiveOpsService.isMaintenance() then
		return fail("maintenance")
	end

	local data = DataService.getActiveData(player)
	if data == nil then
		return fail("not_ready")
	end

	local drawTable =
		SwordLogic.buildDrawTable(Weapons.Order, RARITY_OF, Weapons.DRAW_WEIGHTS, data.swords)
	if #drawTable.entries == 0 then
		return fail("no_more_swords")
	end

	local price = slotPriceFor(data)
	if not EconomyService.canAfford(data, price) then
		return fail("not_enough_gold")
	end

	local swordId = SwordLogic.pick(drawTable, rng:NextNumber())
	if swordId == nil then
		return fail("no_more_swords")
	end

	-- 여기서부터 실제 변경.
	EconomyService.spendGold(player, data, price, "sword_slot")

	data.swordCapacity = math.max(data.swordCapacity, SwordLogic.count(data.swords)) + 1
	data.swords[swordId] = { id = swordId, level = 0, bestLevel = 0 }

	AnalyticsService.logFunnel(player, "sword_drawn", { sword = swordId, price = price })

	return {
		ok = true,
		swordId = swordId,
		pricePaid = price,
		gold = data.gold,
		odds = EnhanceService.getDisplayOdds(data),
	}
end

-- 레이트 리밋·락·오류 처리를 씌운 공통 입구
local function guarded(player: Player, handler: (...any) -> any, ...: any): any
	if not limiter:consume(player.UserId) then
		return fail("too_fast")
	end
	if not limiter:tryLock(player.UserId) then
		return fail("busy")
	end

	local ok, response = xpcall(handler, debug.traceback, player, ...)

	limiter:unlock(player.UserId)

	if not ok then
		warn(`[SwordService] 처리 중 오류 ({player.UserId}):\n{response}`)
		return fail("unknown")
	end

	if response.ok then
		DataService.replicate(player)
	end

	return response
end

local function handleEquip(player: Player, swordId: any): Types.EquipResponse
	if type(swordId) ~= "string" or Weapons.get(swordId) == nil then
		return fail("invalid_argument")
	end
	return guarded(player, processEquip, swordId)
end

local function handleDraw(player: Player): Types.DrawResponse
	return guarded(player, processDraw)
end

function SwordService.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)

	local equipRemote = remotesFolder:WaitForChild(Remotes.Functions.EquipSword) :: RemoteFunction
	equipRemote.OnServerInvoke = handleEquip

	local drawRemote = remotesFolder:WaitForChild(Remotes.Functions.BuySwordSlot) :: RemoteFunction
	drawRemote.OnServerInvoke = handleDraw
end

function SwordService.Start()
	Players.PlayerRemoving:Connect(function(player)
		limiter:clear(player.UserId)
	end)
end

return SwordService
