--!strict
--[[
	TreadmillService — 로비 트레드밀 수입 (통합 기획서 6절).

	발판 위에 있으면 단계별로 정해진 시간마다 골드를 받는다(1단계: 20초당 100골드).
	- 무료만 있다. Robux 가 닿는 트레드밀은 만들지 않는다(골드를 간접적으로 파는 것이 된다).
	- 자리 비움 제한을 두지 않는다. 가만히 서 있어도 받는다.
	- "발판 위에 있는지"는 서버가 본 캐릭터 위치로 판단한다. 클라이언트가 보내는 값은 없다.
	- 발판에서 내려오면 채우던 시간은 멈춘 채 남는다. 다시 올라오면 이어서 채운다(접속 중에만).
	- 점검 모드에서는 시간이 가지 않는다(다른 골드 변동과 같이 멈춘다).

	[미정 D18] 2단계 이상은 아직 없다. EconomyConfig.TREADMILL_TIERS 와 Config/World 의
	TREADMILL_PADS 에 추가하면 이 서비스는 그대로 동작한다. 해금 조건이 생기면 padUnder 에서 확인한다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TreadmillLogic = require(Shared:WaitForChild("Pure"):WaitForChild("TreadmillLogic"))

local services = script.Parent
local DataService = require(services:WaitForChild("DataService"))
local EconomyService = require(services:WaitForChild("EconomyService"))
local LiveOpsService = require(services:WaitForChild("LiveOpsService"))
local WorldService = require(services:WaitForChild("WorldService"))

local TreadmillService = {}
TreadmillService.Name = "TreadmillService"

-- 발판 위에 있는지 확인하는 주기(초)
local TICK_SECONDS = 1

-- 이번 지급까지 채운 시간(초). 접속 중에만 유지한다.
local progress: { [Player]: number } = {}
local wasOnPad: { [Player]: boolean } = {}

local updateRemote: RemoteEvent? = nil

local function send(player: Player, payload: Types.TreadmillUpdate)
	if updateRemote then
		updateRemote:FireClient(player, payload)
	end
end

-- 플레이어가 올라가 있는 발판. 없으면 nil.
local function padUnder(player: Player): WorldService.TreadmillPad?
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end

	local position = root.Position
	for _, pad in WorldService.getTreadmillPads() do
		if TreadmillLogic.isOnPad(position.X, position.Y, position.Z, pad.bounds) then
			return pad
		end
	end
	return nil
end

local function step(dt: number)
	if LiveOpsService.isMaintenance() then
		return
	end

	for player, data in DataService.getAllActive() do
		local pad = padUnder(player)

		if pad == nil then
			if wasOnPad[player] then
				wasOnPad[player] = nil
				send(player, {
					onPad = false,
					progress = progress[player] or 0,
					interval = 0,
					gold = 0,
					paid = 0,
				})
			end
			continue
		end

		local tier = pad.tier
		local rest, payouts =
			TreadmillLogic.advance(progress[player] or 0, dt, tier.intervalSeconds)
		progress[player] = rest
		wasOnPad[player] = true

		local paid = 0
		if payouts > 0 then
			paid = EconomyService.addGold(player, data, payouts * tier.gold, "treadmill")
			DataService.replicate(player)
		end

		send(player, {
			onPad = true,
			progress = rest,
			interval = tier.intervalSeconds,
			gold = tier.gold,
			paid = paid,
		})
	end
end

function TreadmillService.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	updateRemote = remotesFolder:WaitForChild(Remotes.Events.TreadmillUpdate) :: RemoteEvent
end

function TreadmillService.Start()
	Players.PlayerRemoving:Connect(function(player)
		progress[player] = nil
		wasOnPad[player] = nil
	end)

	task.spawn(function()
		local last = os.clock()

		while true do
			task.wait(TICK_SECONDS)

			local now = os.clock()
			local ok, err = xpcall(step, debug.traceback, now - last)
			last = now

			if not ok then
				warn(`[TreadmillService] 처리 중 오류:\n{err}`)
			end
		end
	end)
end

return TreadmillService
