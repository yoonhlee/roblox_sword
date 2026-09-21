--!strict
--[[
	EconomyService — 재화 증감의 단일 창구.

	골드/파편/방지권이 바뀌는 곳은 전부 여기를 거친다. 그래야
	(1) 모든 증감이 빠짐없이 기록되고 (2) 음수·소수 같은 잘못된 값이 저장되지 않는다.

	모든 함수는 yield 하지 않는다. 호출자는 DataService.getActiveData() 로 받은
	데이터를 그대로 넘기고, 한 요청의 모든 변경을 끝낸 뒤 마지막에
	DataService.replicate(player) 를 한 번만 호출한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))

local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))

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

function EconomyService.Init() end

function EconomyService.Start() end

return EconomyService
