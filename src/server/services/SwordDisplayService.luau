--!strict
--[[
	SwordDisplayService — 블록 3D 검을 보여 준다 (통합 기획서 8-2절).

	1) 손에 든 검: 모든 플레이어의 오른손에 착용 검을 붙인다. 레벨 색(쇠 달구는 색)과 등급 색이 보인다.
	   보기만 하는 장식이다(부딪힘·무게·능력 없음). 착용 검이나 레벨이 바뀌면 다시 붙인다.
	2) 이 서버 최고 검 진열대: 지금 서버에 있는 사람 중 가장 높은 착용 검을 진열대에 세우고,
	   받침에 주인 이름·검·레벨 속성을 단다(명패 글자와 회전은 기기가 한다). 저장하지 않는다.

	검 모양은 shared/SwordModel(Config/SwordShapes) 이 만든다. 1초마다 바뀐 것만 확인한다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SwordModel = require(Shared:WaitForChild("SwordModel"))
local World = require(Shared:WaitForChild("Config"):WaitForChild("World"))
local SwordLogic = require(Shared:WaitForChild("Pure"):WaitForChild("SwordLogic"))

local services = script.Parent
local DataService = require(services:WaitForChild("DataService"))
local WorldService = require(services:WaitForChild("WorldService"))

local SwordDisplayService = {}
SwordDisplayService.Name = "SwordDisplayService"

local CHECK_SECONDS = 1
local HAND_SCALE = 0.62 -- 캐릭터 키(약 5칸)에 맞춘 크기

-- 플레이어마다 지금 손에 붙인 검의 "검id:레벨"
local handSignature: { [Player]: string } = {}
local showcaseSignature = ""
local showcaseModel: Model? = nil

local function handOf(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		return hand
	end
	return nil
end

local function attachToHand(player: Player, swordId: string, level: number)
	local character = player.Character
	if character == nil then
		return
	end
	local hand = handOf(character)
	if hand == nil then
		return
	end

	local old = character:FindFirstChild(SwordModel.MODEL_NAME)
	if old then
		old:Destroy()
	end

	-- 손 아래쪽에서 쥐고, 칼날이 앞(-Z)을 향하게
	local grip = hand.CFrame
		* CFrame.new(0, -hand.Size.Y / 2, -0.15)
		* CFrame.Angles(math.rad(-90), 0, 0)
	local model = SwordModel.build(swordId, level, {
		cframe = grip,
		scale = HAND_SCALE,
		anchored = false,
		effects = true,
	})

	local handle = model.PrimaryPart
	if handle == nil then
		model:Destroy()
		return
	end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = handle
	weld.Parent = handle

	model.Parent = character
	handSignature[player] = `{swordId}:{level}`
end

local function updateHands()
	for player, data in DataService.getAllActive() do
		local sword = SwordLogic.equipped(data.swords, data.equippedId)
		local character = player.Character
		if sword == nil or character == nil then
			continue
		end

		local signature = `{sword.id}:{sword.level}`
		local attached = character:FindFirstChild(SwordModel.MODEL_NAME) ~= nil
		if handSignature[player] ~= signature or not attached then
			local ok, err = pcall(attachToHand, player, sword.id, sword.level)
			if not ok then
				warn(
					`[SwordDisplayService] 손에 검을 붙이지 못했습니다 ({player.UserId}): {err}`
				)
			end
		end
	end
end

local function updateShowcase()
	local base = WorldService.getShowcaseBase()
	if base == nil then
		return
	end

	-- 지금 서버에서 가장 높은 착용 검 (같으면 이름순)
	local bestPlayer: Player? = nil
	local bestId, bestLevel = "", -1
	for player, data in DataService.getAllActive() do
		local sword = SwordLogic.equipped(data.swords, data.equippedId)
		if sword == nil then
			continue
		end
		local better = sword.level > bestLevel
			or (sword.level == bestLevel and bestPlayer ~= nil and player.Name < bestPlayer.Name)
		if better then
			bestPlayer, bestId, bestLevel = player, sword.id, sword.level
		end
	end

	local owner = bestPlayer
	local signature = if owner then `{owner.UserId}:{bestId}:{bestLevel}` else ""
	if signature == showcaseSignature then
		return
	end
	showcaseSignature = signature

	local old = showcaseModel
	if old then
		old:Destroy()
		showcaseModel = nil
	end

	if owner == nil then
		base:SetAttribute(World.ATTR.ownerName, "")
		base:SetAttribute(World.ATTR.swordId, "")
		base:SetAttribute(World.ATTR.swordLevel, 0)
		return
	end

	-- 유리 상자 가운데에 세운다 (회전·떠오르기는 기기가 한다)
	local top = base.Position.Y + base.Size.Y / 2
	local model = SwordModel.build(bestId, bestLevel, {
		cframe = CFrame.new(base.Position.X, top + 1.3, base.Position.Z),
		scale = 0.85,
		anchored = true,
		effects = true,
	})
	model.Name = "ShowcaseSword"
	model.Parent = base.Parent
	showcaseModel = model

	base:SetAttribute(World.ATTR.ownerName, owner.DisplayName)
	base:SetAttribute(World.ATTR.swordId, bestId)
	base:SetAttribute(World.ATTR.swordLevel, bestLevel)
end

function SwordDisplayService.Start()
	Players.PlayerRemoving:Connect(function(player)
		handSignature[player] = nil
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(updateHands)
			if not ok then
				warn(`[SwordDisplayService] 손에 든 검 갱신 오류: {err}`)
			end
			local okShowcase, errShowcase = pcall(updateShowcase)
			if not okShowcase then
				warn(`[SwordDisplayService] 진열대 갱신 오류: {errShowcase}`)
			end
			task.wait(CHECK_SECONDS)
		end
	end)
end

return SwordDisplayService
