--!strict
--[[
	EconomyService — 재화 증감의 단일 창구.

	골드/파편/방지권이 바뀌는 곳은 전부 여기를 거친다. 그래야
	(1) 모든 증감이 빠짐없이 기록되고 (2) 음수·소수 같은 잘못된 값이 저장되지 않는다.

	골드를 늘리는 유료 혜택(배수, 골드 팩)은 없다. 골드는 Robux 로 직접도 간접적으로도
	얻을 수 없어야 한다(통합 기획서 6절). 그래서 addGold 에는 배수 인자가 없다.

	모든 함수는 yield 하지 않는다. 호출자는 DataService.getActiveData() 로 받은
	데이터를 그대로 넘기고, 한 요청의 모든 변경을 끝낸 뒤 마지막에
	DataService.replicate(player) 를 한 번만 호출한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))

local ConfigFolder = Shared:WaitForChild("Config")
local EconomyConfig = require(ConfigFolder:WaitForChild("EconomyConfig"))

local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local EconomyService = {}
EconomyService.Name = "EconomyService"

-- 접속 중인 사람의 날짜 변경을 확인하는 주기
local DAILY_CHECK_INTERVAL_SECONDS = 60

-- 재화는 항상 0 이상의 정수로 유지한다.
local function sanitize(value: number): number
	if value ~= value then -- NaN
		return 0
	end
	return math.max(0, math.floor(value))
end

function EconomyService.canAfford(data: Types.PlayerData, cost: number): boolean
	return data.gold >= cost
end

-- 골드를 지급한다. 반환값은 실제로 지급된 양이다.
function EconomyService.addGold(
	player: Player,
	data: Types.PlayerData,
	amount: number,
	reason: string
): number
	local granted = sanitize(amount)
	if granted == 0 then
		return 0
	end

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
	UTC 기준으로 날짜가 바뀌었으면 출석 날짜와 연속 일수를 갱신한다.
	새 날이면 true 를 반환한다(출석 보상 지급 판단에 쓴다).

	daily.battlesToday / daily.opponentsToday 는 폐지된 1:1 배틀의 기록이다.
	저장된 값을 지우지 않으려고 여기서 더 이상 건드리지 않는다.
]]
function EconomyService.rolloverDaily(data: Types.PlayerData, nowSeconds: number?): boolean
	local today = math.floor((nowSeconds or os.time()) / 86400)

	if data.daily.lastLoginDay == today then
		return false
	end

	local isConsecutive = data.daily.lastLoginDay == today - 1
	data.daily.streak = if isConsecutive then data.daily.streak + 1 else 1
	data.daily.lastLoginDay = today

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

	return EconomyService.addGold(player, data, amount, "daily_login")
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
				EconomyService.addGold(player, data, EconomyConfig.PLAYTIME_REWARD_GOLD, "playtime")
				DataService.replicate(player)
			end
		end
	end)

	--[[
		접속한 채로 날짜가 바뀐 사람의 출석 날짜·연속 일수를 갱신한다.
		(배틀 서비스에 있던 주기 확인을 동작 그대로 옮겨 왔다.)
		이 경로에서는 출석 골드를 주지 않는다. 예전부터의 동작이며,
		출석 보상을 다시 정할 때(통합 기획서 6절) 함께 정한다.
	]]
	task.spawn(function()
		while true do
			task.wait(DAILY_CHECK_INTERVAL_SECONDS)

			for player, data in DataService.getAllActive() do
				if EconomyService.rolloverDaily(data) then
					DataService.replicate(player)
				end
			end
		end
	end)
end

return EconomyService
