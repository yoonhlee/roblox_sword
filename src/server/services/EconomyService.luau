--!strict
--[[
	EconomyService — 재화 증감의 단일 창구.

	골드/파편/방지권이 바뀌는 곳은 전부 여기를 거친다. 그래야
	(1) 모든 증감이 빠짐없이 기록되고 (2) 음수·소수 같은 잘못된 값이 저장되지 않는다.

	모든 함수는 yield 하지 않는다. 호출자는 DataService.getActiveData() 로 받은
	데이터를 그대로 넘기고, 한 요청의 모든 변경을 끝낸 뒤 마지막에
	DataService.replicate(player) 를 한 번만 호출한다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ConfigFolder = Shared:WaitForChild("Config")
local EconomyConfig = require(ConfigFolder:WaitForChild("EconomyConfig"))
local EnhanceTable = require(ConfigFolder:WaitForChild("EnhanceTable"))

local EnhanceLogic = require(Shared:WaitForChild("Pure"):WaitForChild("EnhanceLogic"))

local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local EconomyService = {}
EconomyService.Name = "EconomyService"

-- 재화는 항상 0 이상의 정수로 유지한다.
local function sanitize(value: number): number
	if value ~= value then -- NaN
		return 0
	end
	return math.max(0, math.floor(value))
end

--[[
	플레이어가 "벌어들이는" 골드에 곱해지는 배수.
	게임패스(골드 획득 +20%)가 붙으면 ShopService 가 이 값을 채운다.
	구매로 지급하는 골드에는 적용하지 않는다.
]]
local goldMultiplierProvider: ((player: Player) -> number)? = nil

function EconomyService.setGoldMultiplierProvider(provider: (player: Player) -> number)
	goldMultiplierProvider = provider
end

function EconomyService.getGoldMultiplier(player: Player): number
	if goldMultiplierProvider == nil then
		return 1
	end

	local ok, multiplier = pcall(goldMultiplierProvider, player)
	if not ok or type(multiplier) ~= "number" or multiplier <= 0 then
		return 1
	end
	return multiplier
end

function EconomyService.canAfford(data: Types.PlayerData, cost: number): boolean
	return data.gold >= cost
end

--[[
	골드를 지급한다. applyMultiplier 가 true 면 게임패스 배수를 적용한다
	(플레이 보상에는 true, Robux 구매 지급에는 false).
	반환값은 실제로 지급된 양이다.
]]
function EconomyService.addGold(
	player: Player,
	data: Types.PlayerData,
	amount: number,
	reason: string,
	applyMultiplier: boolean?
): number
	if amount <= 0 then
		return 0
	end

	local granted = amount
	if applyMultiplier then
		granted = math.floor(amount * EconomyService.getGoldMultiplier(player))
	end
	granted = sanitize(granted)

	data.gold = sanitize(data.gold + granted)
	AnalyticsService.logCurrency(player, "gold", granted, reason, data.gold)
	return granted
end

-- 골드를 차감한다. 잔액이 모자라면 아무것도 바꾸지 않고 false 를 반환한다.
function EconomyService.spendGold(
	player: Player,
	data: Types.PlayerData,
	amount: number,
	reason: string
): boolean
	local cost = sanitize(amount)
	if cost == 0 then
		return true
	end
	if data.gold < cost then
		return false
	end

	data.gold = sanitize(data.gold - cost)
	AnalyticsService.logCurrency(player, "gold", -cost, reason, data.gold)
	return true
end

function EconomyService.addShards(
	player: Player,
	data: Types.PlayerData,
	amount: number,
	reason: string
): number
	local granted = sanitize(amount)
	if granted == 0 then
		return 0
	end

	data.shards = sanitize(data.shards + granted)
	AnalyticsService.logCurrency(player, "shards", granted, reason, data.shards)
	return granted
end

function EconomyService.spendShards(
	player: Player,
	data: Types.PlayerData,
	amount: number,
	reason: string
): boolean
	local cost = sanitize(amount)
	if data.shards < cost then
		return false
	end

	data.shards = sanitize(data.shards - cost)
	AnalyticsService.logCurrency(player, "shards", -cost, reason, data.shards)
	return true
end

function EconomyService.addTickets(
	player: Player,
	data: Types.PlayerData,
	amount: number,
	reason: string
): number
	local granted = sanitize(amount)
	if granted == 0 then
		return 0
	end

	data.protectTickets = sanitize(data.protectTickets + granted)
	AnalyticsService.logCurrency(player, "tickets", granted, reason, data.protectTickets)
	return granted
end

function EconomyService.spendTickets(
	player: Player,
	data: Types.PlayerData,
	amount: number,
	reason: string
): boolean
	local cost = sanitize(amount)
	if data.protectTickets < cost then
		return false
	end

	data.protectTickets = sanitize(data.protectTickets - cost)
	AnalyticsService.logCurrency(player, "tickets", -cost, reason, data.protectTickets)
	return true
end

--[[
	UTC 기준으로 날짜가 바뀌었으면 하루짜리 기록을 초기화한다.
	배틀 횟수와 오늘 상대 목록이 여기서 비워진다.
	새 날이면 true 를 반환한다(출석 보상 지급 판단에 쓴다).
]]
function EconomyService.rolloverDaily(data: Types.PlayerData, nowSeconds: number?): boolean
	local today = math.floor((nowSeconds or os.time()) / 86400)

	if data.daily.lastLoginDay == today then
		return false
	end

	local isConsecutive = data.daily.lastLoginDay == today - 1
	data.daily.streak = if isConsecutive then data.daily.streak + 1 else 1
	data.daily.lastLoginDay = today
	data.daily.battlesToday = 0
	data.daily.opponentsToday = {}

	return true
end

--[[
	출석 보상. 연속 일수에 따라 금액이 커지고, 표 끝을 넘으면 마지막 값을 계속 준다.
	rolloverDaily 가 true 를 돌려준 직후에만 호출한다.
]]
function EconomyService.grantDailyLogin(player: Player, data: Types.PlayerData): number
	local rewards = EconomyConfig.DAILY_LOGIN_GOLD
	local index = math.clamp(data.daily.streak, 1, #rewards)
	local amount = rewards[index]

	return EconomyService.addGold(player, data, amount, "daily_login", true)
end

--[[
	파편 또는 골드로 파괴 방지권을 산다.
	method: "shards" | "gold"
]]
function EconomyService.buyProtectTickets(
	player: Player,
	method: string,
	count: number
): Types.TicketPurchaseResponse
	if method ~= "shards" and method ~= "gold" then
		return { ok = false, reason = "invalid_argument" }
	end
	if type(count) ~= "number" or count ~= math.floor(count) or count < 1 or count > 100 then
		return { ok = false, reason = "invalid_argument" }
	end

	local data = DataService.getActiveData(player)
	if data == nil then
		return { ok = false, reason = "not_ready" }
	end

	if method == "shards" then
		local price = EnhanceTable.SHARDS_PER_TICKET * count
		if not EconomyService.spendShards(player, data, price, "ticket_exchange") then
			return { ok = false, reason = "not_enough_shards" }
		end
	else
		local price = EconomyConfig.PROTECT_TICKET_GOLD_PRICE * count
		if not EconomyService.spendGold(player, data, price, "ticket_purchase") then
			return { ok = false, reason = "not_enough_gold" }
		end
	end

	EconomyService.addTickets(player, data, count, `ticket_{method}`)
	DataService.replicate(player)

	return { ok = true, tickets = data.protectTickets }
end

-- 파편으로 지금 살 수 있는 방지권 수 (UI 표시용)
function EconomyService.affordableTickets(data: Types.PlayerData): number
	return EnhanceLogic.ticketsAffordable(data.shards, EnhanceTable.SHARDS_PER_TICKET)
end

function EconomyService.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)

	local ticketRemote =
		remotesFolder:WaitForChild(Remotes.Functions.BuyProtectTicket) :: RemoteFunction
	ticketRemote.OnServerInvoke = function(player: Player, method: any, count: any)
		return EconomyService.buyProtectTickets(player, tostring(method), tonumber(count) or 0)
	end
end

function EconomyService.Start()
	-- 접속 시 출석 확인
	DataService.onLoaded(function(player, data)
		if EconomyService.rolloverDaily(data) then
			EconomyService.grantDailyLogin(player, data)
			DataService.replicate(player)
			AnalyticsService.logFunnel(player, "daily_login", { streak = data.daily.streak })
		end
	end)

	-- 플레이 시간 보상
	task.spawn(function()
		while true do
			task.wait(EconomyConfig.PLAYTIME_REWARD_INTERVAL_SECONDS)

			for player, data in DataService.getAllActive() do
				EconomyService.addGold(
					player,
					data,
					EconomyConfig.PLAYTIME_REWARD_GOLD,
					"playtime",
					true
				)
				DataService.replicate(player)
			end
		end
	end)
end

return EconomyService
