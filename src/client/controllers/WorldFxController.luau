--!strict
--[[
	WorldFxController — 불씨 광장과 쇳물 수로의 움직임·글자 (통합 기획서 8-2절, 시안 "움직임 목록").

	서버는 블록과 "상태 속성"만 만든다. 이 컨트롤러가 각 기기에서:
	  광장  모루 영감 망치질(2.4초) + 모루 불티 / 화덕 흔들림, 러닝머신 인원만큼 불이 커짐 / 횃불 흔들림 /
	        풀무 러닝머신: 벨트 흐름·풀무 펌프·관 속 불씨·지급 때 금화와 "+100" / 발판 위 안내판 /
	        쇳물 관문: 고리 12칸 숨쉬기·카운트다운·마지막 3초·출발 빛기둥, 전광판, 쇳물 폭포 /
	        표지판 글자 / 명예의 벽 / 최고 검 진열대 회전·명패 / 15강·20강 자랑 연출과 모루 영감 말풍선 /
	        "강화하기" 근접 버튼 / 내 캐릭터가 태어날 때 불티
	  코스  출발 화로 3·2·1 / 출발 쇠창살 내려감 / 쇳물 해일의 출렁이는 꼭대기·끓는 앞면·녹은 바닥
	  화면  대장간 화면의 3D 검 미리보기 (천천히 돈다)
	전부 보기만 하는 장식이다. 판정·보상과 관계없다. 카메라가 광장에서 멀면 광장 연출을 멈춘다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SwordModel = require(Shared:WaitForChild("SwordModel"))
local Format = require(Shared:WaitForChild("Pure"):WaitForChild("Format"))

local ConfigFolder = Shared:WaitForChild("Config")
local World = require(ConfigFolder:WaitForChild("World"))
local Palette = require(ConfigFolder:WaitForChild("Palette"))
local Weapons = require(ConfigFolder:WaitForChild("Weapons"))
local EconomyConfig = require(ConfigFolder:WaitForChild("EconomyConfig"))
local RaceConfig = require(ConfigFolder:WaitForChild("RaceConfig"))

local client = script.Parent.Parent
local ClientState = require(client:WaitForChild("ClientState"))
local ui = client:WaitForChild("ui")
local Theme = require(ui:WaitForChild("Theme"))
local ScreenManager = require(ui:WaitForChild("ScreenManager"))

local controllers = script.Parent
local UIController = require(controllers:WaitForChild("UIController"))

local WorldFxController = {}
WorldFxController.Name = "WorldFxController"

local A = World.ATTR
local LOBBY_RANGE = 220 -- 카메라가 광장 가운데에서 이보다 멀면 광장 연출을 멈춘다
local HAMMER_CYCLE = 2.4

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- 연출용 부품을 담는 이 기기 전용 폴더
local fxFolder = Instance.new("Folder")
fxFolder.Name = "ForgeLocalFx"

local lobby: Instance? = nil
local textRefreshers: { () -> () } = {} -- 언어가 바뀌면 다시 그릴 글자들

--------------------------------------------------------------------------------
-- 공용
--------------------------------------------------------------------------------

local function surfaceText(
	part: BasePart,
	face: Enum.NormalId,
	pixelsPerStud: number
): (SurfaceGui, Frame)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ForgeText"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Adornee = part
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	return gui, holder
end

local function textLabel(
	parent: Instance,
	text: string,
	color: Color3,
	font: Enum.Font,
	size: UDim2,
	position: UDim2?
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position or UDim2.new()
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	label.Parent = parent
	return label
end

-- 세계 위에 떠올랐다 사라지는 글자 ("+100")
local function floatWorldText(at: BasePart, text: string, color: Color3)
	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = at
	billboard.Size = UDim2.fromOffset(160, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local label = textLabel(billboard, text, color, Theme.font.display, UDim2.fromScale(1, 1))

	local tween = TweenService:Create(
		billboard,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			StudsOffset = Vector3.new(0, 7, 0),
		}
	)
	TweenService:Create(label, TweenInfo.new(1.2), { TextTransparency = 1 }):Play()
	tween.Completed:Connect(function()
		billboard:Destroy()
	end)
	tween:Play()
end

local function lobbyNearby(): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and camera.Focus.Position.Magnitude < LOBBY_RANGE
end

--------------------------------------------------------------------------------
-- 모루 영감 · 화덕 · 횃불
--------------------------------------------------------------------------------

type Forge = {
	arm: Model?,
	armBase: CFrame?,
	anvilSparks: ParticleEmitter?,
	anvilGlow: PointLight?,
	furnaceLight: PointLight?,
	furnaceFire: Fire?,
	chimneyTop: BasePart?,
	head: BasePart?,
	bubble: BillboardGui?,
	bubbleText: TextLabel?,
	flareUntil: number,
	lastStrikeCycle: number,
}

local forge: Forge = { flareUntil = 0, lastStrikeCycle = -1 }
local torches: { { light: PointLight, base: number } } = {}

local function setupForge(lobbyFolder: Instance)
	local forgeFolder = lobbyFolder:FindFirstChild("Forge")
	if forgeFolder == nil then
		return
	end

	local npc = forgeFolder:FindFirstChild("AnvilElder")
	local arm = if npc then npc:FindFirstChild("HammerArm") else nil
	if arm and arm:IsA("Model") then
		forge.arm = arm
		forge.armBase = arm:GetPivot()
	end
	local head = if npc then npc:FindFirstChild("Head") else nil
	if head and head:IsA("BasePart") then
		forge.head = head
		local bubble = Instance.new("BillboardGui")
		bubble.Adornee = head
		bubble.Size = UDim2.fromOffset(260, 70)
		bubble.StudsOffset = Vector3.new(0, 3.2, 0)
		bubble.MaxDistance = 140
		bubble.Enabled = false
		bubble.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = Theme.color.text
		frame.Size = UDim2.fromScale(1, 1)
		frame.Parent = bubble
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = frame
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -16, 1, -8)
		label.Position = UDim2.fromOffset(8, 4)
		label.Font = Theme.font.bodyBold
		label.TextScaled = true
		label.TextWrapped = true
		label.TextColor3 = Theme.color.ink
		label.Parent = frame
		forge.bubble = bubble
		forge.bubbleText = label
	end

	local anvilTop = forgeFolder:FindFirstChild("AnvilTop")
	if anvilTop then
		local emitter = anvilTop:FindFirstChild("Sparks")
		forge.anvilSparks = if emitter and emitter:IsA("ParticleEmitter") then emitter else nil
		local glow = anvilTop:FindFirstChild("AnvilGlow")
		forge.anvilGlow = if glow and glow:IsA("PointLight") then glow else nil

		-- "강화하기" 근접 버튼: 글자를 내 언어로, 누르면 대장간 화면
		local prompt = anvilTop:FindFirstChild("ForgePrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			local function refreshPrompt()
				local language = ClientState.getLanguage()
				prompt.ActionText = Locale.get(language, "world.prompt.forge")
				prompt.ObjectText = Locale.get(language, "world.prompt.object")
				prompt.Enabled = ScreenManager.getMode() == "lobby"
			end
			refreshPrompt()
			table.insert(textRefreshers, refreshPrompt)
			ScreenManager.onStateChanged(refreshPrompt)
			prompt.Triggered:Connect(function()
				ScreenManager.setForgeOpen(true)
			end)
		end
	end

	local mouth = forgeFolder:FindFirstChild("FurnaceMouth")
	local furnaceLight = if mouth then mouth:FindFirstChild("FurnaceLight") else nil
	forge.furnaceLight = if furnaceLight and furnaceLight:IsA("PointLight")
		then furnaceLight
		else nil
	local flame = forgeFolder:FindFirstChild("FurnaceFlame")
	local furnaceFire = if flame then flame:FindFirstChild("FurnaceFire") else nil
	forge.furnaceFire = if furnaceFire and furnaceFire:IsA("Fire") then furnaceFire else nil
	local chimneyTop = forgeFolder:FindFirstChild("ChimneyTop")
	forge.chimneyTop = if chimneyTop and chimneyTop:IsA("BasePart") then chimneyTop else nil

	for _, descendant in lobbyFolder:GetDescendants() do
		if descendant:IsA("PointLight") and descendant.Name == "TorchLight" then
			table.insert(torches, { light = descendant, base = descendant.Brightness })
		end
	end
end

local function say(text: string, seconds: number)
	local bubble, label = forge.bubble, forge.bubbleText
	if bubble == nil or label == nil then
		return
	end
	label.Text = text
	bubble.Enabled = true
	local token = os.clock()
	bubble:SetAttribute("Token", token)
	task.delay(seconds, function()
		if bubble:GetAttribute("Token") == token then
			bubble.Enabled = false
		end
	end)
end

-- 망치질: 들어 올리고(0.6초) 빠르게 내려치고(0.12초) 쉰다
local function hammerAngle(t: number): number
	local rest, raised = 25, 110
	if t < 0.6 then
		local p = t / 0.6
		return rest + (raised - rest) * (1 - (1 - p) ^ 2)
	elseif t < 0.72 then
		local p = (t - 0.6) / 0.12
		return raised + (rest - raised) * p * p
	end
	return rest
end

local furnaceSize = 4
local lastFlicker = 0

local function stepForge(now: number, dt: number)
	local arm, base = forge.arm, forge.armBase
	if arm and base then
		local cycle = math.floor(now / HAMMER_CYCLE)
		local t = now - cycle * HAMMER_CYCLE
		arm:PivotTo(base * CFrame.Angles(math.rad(hammerAngle(t)), 0, 0))

		if t >= 0.72 and forge.lastStrikeCycle ~= cycle then
			forge.lastStrikeCycle = cycle
			if forge.anvilSparks then
				forge.anvilSparks:Emit(12)
			end
			local glow = forge.anvilGlow
			if glow then
				glow.Brightness = 2.5
				TweenService:Create(glow, TweenInfo.new(0.25), { Brightness = 0 }):Play()
			end
		end
	end

	-- 화덕: 러닝머신 위 인원만큼 커지고, 자랑 연출 중에는 크게 치솟는다
	local users = 0
	local lobbyFolder = lobby
	if lobbyFolder then
		users = tonumber(lobbyFolder:GetAttribute(A.treadmillUsers)) or 0
	end
	local target = 4 + math.min(4, users) * 1.5
	if now < forge.flareUntil then
		target *= 2
	end
	furnaceSize += (target - furnaceSize) * math.min(1, dt * 1.5)

	local fire = forge.furnaceFire
	if fire then
		fire.Size = furnaceSize
	end

	if now - lastFlicker > 0.12 then
		lastFlicker = now
		local light = forge.furnaceLight
		if light then
			light.Range = 16 + furnaceSize * 1.6
			light.Brightness = (1.8 + furnaceSize * 0.08) * (0.85 + math.random() * 0.3)
		end
		for _, torch in torches do
			torch.light.Brightness = torch.base * (0.8 + math.random() * 0.4)
		end
	end
end

-- 20강: 굴뚝에서 흰·금 불기둥 5초
local function chimneyPillar()
	local top = forge.chimneyTop
	if top == nil then
		return
	end
	local pillar = Instance.new("Part")
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = Color3.fromRGB(255, 244, 200)
	pillar.Shape = Enum.PartType.Cylinder
	local height = 60
	local base = top.Position + Vector3.new(0, 0.5, 0)
	local function frameFor(h: number): CFrame
		return CFrame.new(base + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end
	pillar.Size = Vector3.new(0.1, 3, 3)
	pillar.CFrame = frameFor(0.1)
	pillar.Parent = fxFolder

	local up = TweenService:Create(
		pillar,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(height, 3, 3),
			CFrame = frameFor(height),
		}
	)
	up:Play()
	task.delay(5.5, function()
		local fade = TweenService:Create(pillar, TweenInfo.new(1), { Transparency = 1 })
		fade.Completed:Connect(function()
			pillar:Destroy()
		end)
		fade:Play()
	end)
end

-- 서버 공지(15강 이상 성공)를 받으면 광장 연출
local function onBroadcast(payload: any)
	local level = tonumber(payload.level) or 0
	local language = ClientState.getLanguage()
	local name = tostring(payload.playerName)
	local weapon = Locale.get(language, tostring(payload.weaponKey))

	forge.flareUntil = os.clock() + 2.3
	if level >= 20 then
		say(Locale.get(language, "npc.shout.max", name, weapon), 4)
		chimneyPillar()
	else
		say(Locale.get(language, "npc.shout.high", name, weapon, level), 3)
	end
end

--------------------------------------------------------------------------------
-- 풀무 러닝머신
--------------------------------------------------------------------------------

type Treadmill = {
	index: number,
	pad: BasePart,
	stripes: { BasePart },
	stripeBase: { CFrame },
	bellows: { { part: BasePart, size: Vector3, cframe: CFrame, layer: number } },
	lamp: BasePart?,
	coins: ParticleEmitter?,
	lastPaid: number,
	phase: number,
	nextEmber: number,
}

local treadmills: { Treadmill } = {}
local beltLength = World.TREADMILL_PAD.sizeZ - 2

local function setupTreadmills(lobbyFolder: Instance)
	local folder = lobbyFolder:FindFirstChild(World.TREADMILL_FOLDER)
	if folder == nil then
		return
	end

	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local pad = model:FindFirstChild("Pad")
		if pad == nil or not pad:IsA("BasePart") then
			continue
		end

		local entry: Treadmill = {
			index = tonumber(model:GetAttribute("PadIndex")) or 0,
			pad = pad,
			stripes = {},
			stripeBase = {},
			bellows = {},
			lamp = nil,
			coins = nil,
			lastPaid = tonumber(pad:GetAttribute(A.paidAt)) or 0,
			phase = 0,
			nextEmber = 0,
		}
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") then
				if child.Name == "BeltStripe" then
					table.insert(entry.stripes, child)
				elseif child.Name == "BellowsLayer" then
					table.insert(entry.bellows, {
						part = child,
						size = child.Size,
						cframe = child.CFrame,
						layer = tonumber(child:GetAttribute("Layer")) or 1,
					})
				elseif child.Name == "Lamp" then
					entry.lamp = child
					local coins = child:FindFirstChild("Coins")
					entry.coins = if coins and coins:IsA("ParticleEmitter") then coins else nil
				end
			end
		end
		table.sort(entry.stripes, function(a, b)
			return (tonumber(a:GetAttribute("Index")) or 0)
				< (tonumber(b:GetAttribute("Index")) or 0)
		end)
		for index, stripe in entry.stripes do
			entry.stripeBase[index] = stripe.CFrame
		end

		-- 발판 위 안내판 (내 언어로)
		local tierId = pad:GetAttribute(World.TREADMILL_TIER_ATTRIBUTE)
		local tier = if type(tierId) == "string" then EconomyConfig.treadmillTier(tierId) else nil
		if tier then
			local billboard = Instance.new("BillboardGui")
			billboard.Adornee = pad
			billboard.Size = UDim2.fromOffset(220, 56)
			billboard.StudsOffset = Vector3.new(0, 8, 0)
			billboard.MaxDistance = 120
			billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
			local frame = Instance.new("Frame")
			frame.BackgroundColor3 = Theme.color.bg
			frame.BackgroundTransparency = 0.25
			frame.Size = UDim2.fromScale(1, 1)
			frame.Parent = billboard
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 10)
			corner.Parent = frame
			local label = textLabel(
				frame,
				"",
				Theme.color.gold,
				Theme.font.bodyBold,
				UDim2.new(1, -12, 1, -8),
				UDim2.fromOffset(6, 4)
			)
			local function refresh()
				label.Text = Locale.get(
					ClientState.getLanguage(),
					"ui.treadmill.label",
					tier.intervalSeconds,
					Format.comma(tier.gold)
				)
			end
			refresh()
			table.insert(textRefreshers, refresh)
		end

		table.insert(treadmills, entry)
	end
end

-- 관을 따라 화덕으로 굴러가는 불씨 구슬
local function sendEmber(index: number)
	local path = World.pipePath(index)
	if #path < 2 then
		return
	end
	local y = World.PIPE.height + 0.4
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.7, 0.7, 0.7)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Material = Enum.Material.Neon
	ball.Color = rgb(Palette.WORLD.moltenHot)
	ball.Position = Vector3.new(path[1][1], y, path[1][2])
	ball.Parent = fxFolder

	task.spawn(function()
		for step = 2, #path do
			local target = Vector3.new(path[step][1], y, path[step][2])
			local distance = (target - ball.Position).Magnitude
			local tween = TweenService:Create(
				ball,
				TweenInfo.new(distance / 16, Enum.EasingStyle.Linear),
				{ Position = target }
			)
			tween:Play()
			tween.Completed:Wait()
		end
		ball:Destroy()
	end)
end

local function stepTreadmills(now: number, dt: number)
	local server = serverNow()
	for _, entry in treadmills do
		local occupied = entry.pad:GetAttribute(A.occupied) == true

		if occupied then
			-- 벨트 줄무늬가 뒤로(-Z) 흐른다: 0.45초에 한 칸
			entry.phase = (entry.phase + dt / 0.45) % #entry.stripes
			local spacing = beltLength / math.max(1, #entry.stripes)
			for index, stripe in entry.stripes do
				local base = entry.stripeBase[index]
				local offset = -((entry.phase * spacing) % beltLength)
				local localZ = (base.Position.Z - entry.pad.Position.Z) + offset
				if localZ < -beltLength / 2 then
					localZ += beltLength
				end
				stripe.CFrame =
					CFrame.new(base.Position.X, base.Position.Y, entry.pad.Position.Z + localZ)
			end

			-- 풀무: 0.9초 주기로 접혔다 펴진다
			local squeeze = 0.55 + 0.45 * (0.5 + 0.5 * math.cos(now / 0.9 * math.pi * 2))
			for _, layer in entry.bellows do
				local height = layer.size.Y * squeeze
				local baseY = layer.cframe.Position.Y
					- layer.size.Y / 2
					- (layer.layer - 1) * layer.size.Y
				layer.part.Size = Vector3.new(layer.size.X, height, layer.size.Z)
				layer.part.CFrame = CFrame.new(
					layer.cframe.Position.X,
					baseY + (layer.layer - 0.5) * height,
					layer.cframe.Position.Z
				)
			end

			if now >= entry.nextEmber then
				entry.nextEmber = now + 1.6
				sendEmber(entry.index)
			end

			local lamp = entry.lamp
			if lamp then
				lamp.Transparency = 0.15 + 0.15 * math.sin(now * 4)
			end
		else
			local lamp = entry.lamp
			if lamp then
				lamp.Transparency = 0.6
			end
		end

		-- 지급 순간: 계기판 번쩍 + 금화 + "+100" (주변 모두에게 보인다)
		local paidAt = tonumber(entry.pad:GetAttribute(A.paidAt)) or 0
		if paidAt > entry.lastPaid then
			entry.lastPaid = paidAt
			if server - paidAt < 3 then
				local lamp = entry.lamp
				if lamp then
					lamp.Transparency = 0
					if entry.coins then
						entry.coins:Emit(10)
					end
				end
				local tierId = entry.pad:GetAttribute(World.TREADMILL_TIER_ATTRIBUTE)
				local tier = if type(tierId) == "string"
					then EconomyConfig.treadmillTier(tierId)
					else nil
				floatWorldText(
					entry.pad,
					"+" .. Format.comma(if tier then tier.gold else 0),
					Theme.color.gold
				)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- 쇳물 관문
--------------------------------------------------------------------------------

type Gate = {
	model: Model,
	segments: { BasePart },
	runes: { BasePart },
	falls: { BasePart },
	boardLabel: TextLabel?,
	ringCenter: Vector3,
	lastLaunch: number,
}

local gate: Gate? = nil

local function setupGate(lobbyFolder: Instance)
	local model = lobbyFolder:FindFirstChild("Gate")
	if model == nil or not model:IsA("Model") then
		return
	end

	local entry: Gate = {
		model = model,
		segments = {},
		runes = {},
		falls = {},
		boardLabel = nil,
		ringCenter = Vector3.new(World.GATE.ringX, 0.3, World.GATE.ringZ),
		lastLaunch = tonumber(model:GetAttribute(A.launchAt)) or 0,
	}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name == "RingSegment" then
				table.insert(entry.segments, child)
			elseif child.Name == "Rune" then
				table.insert(entry.runes, child)
			elseif string.sub(child.Name, 1, 10) == "MoltenFall" then
				table.insert(entry.falls, child)
			elseif child.Name == "Board" then
				local _, holder = surfaceText(child, Enum.NormalId.Front, 30)
				local background = Instance.new("Frame")
				background.BackgroundColor3 = Theme.color.bg
				background.BackgroundTransparency = 0.1
				background.Size = UDim2.fromScale(1, 1)
				background.Parent = holder
				entry.boardLabel = textLabel(
					holder,
					"",
					Theme.color.gold,
					Theme.font.display,
					UDim2.new(1, -20, 1, -16),
					UDim2.fromOffset(10, 8)
				)
			end
		end
	end
	table.sort(entry.segments, function(a, b)
		return (tonumber(a:GetAttribute("Index")) or 0) < (tonumber(b:GetAttribute("Index")) or 0)
	end)
	gate = entry
end

local function launchPillar(center: Vector3)
	local pillar = Instance.new("Part")
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = rgb(Palette.WORLD.moltenHot)
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(0.2, World.GATE.ringRadius * 2, World.GATE.ringRadius * 2)
	pillar.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Transparency = 0.3
	pillar.Parent = fxFolder

	local height = 30
	local up = TweenService:Create(
		pillar,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(height, World.GATE.ringRadius * 2, World.GATE.ringRadius * 2),
			CFrame = CFrame.new(center + Vector3.new(0, height / 2, 0))
				* CFrame.Angles(0, 0, math.rad(90)),
		}
	)
	up.Completed:Connect(function()
		local fade = TweenService:Create(pillar, TweenInfo.new(0.4), { Transparency = 1 })
		fade.Completed:Connect(function()
			pillar:Destroy()
		end)
		fade:Play()
	end)
	up:Play()
end

local function stepGate(now: number)
	local entry = gate
	if entry == nil then
		return
	end
	local language = ClientState.getLanguage()
	local count = tonumber(entry.model:GetAttribute(A.queueCount)) or 0
	local departAt = tonumber(entry.model:GetAttribute(A.departAt)) or 0
	local remaining = math.max(0, departAt - serverNow())
	local window = RaceConfig.MATCH_WINDOW_SECONDS
	local molten = rgb(Palette.WORLD.molten)
	local hot = rgb(Palette.WORLD.moltenHot)

	if count > 0 and departAt > 0 then
		-- 대기 중: 남은 시간만큼 고리가 켜져 있고 한 칸씩 꺼진다
		local lit = math.ceil(remaining / window * #entry.segments)
		local finalSeconds = remaining <= RaceConfig.LINEUP_SECONDS
		for index, segment in entry.segments do
			local on = index <= lit
			segment.Transparency = if on then 0.05 else 0.85
			segment.Color = if finalSeconds then Color3.new(1, 0.92, 0.75) else hot
		end
		for _, rune in entry.runes do
			rune.Transparency = if finalSeconds then 0 else 0.15
		end
		if entry.boardLabel then
			entry.boardLabel.Text = Locale.get(
				language,
				"world.board.queue",
				math.ceil(remaining),
				count,
				RaceConfig.MATCH_FULL_COUNT
			)
		end
	else
		-- 대기 없음: 천천히 숨 쉰다 (2.6초)
		local breathe = 0.5 + 0.5 * math.sin(now / 2.6 * math.pi * 2)
		for _, segment in entry.segments do
			segment.Transparency = 0.35 + 0.45 * breathe
			segment.Color = molten
		end
		for _, rune in entry.runes do
			rune.Transparency = 0.2 + 0.5 * breathe
		end
		if entry.boardLabel then
			entry.boardLabel.Text = Locale.get(language, "world.board.idle")
		end
	end

	-- 쇳물 폭포: 줄마다 다른 박자로 밝기가 바뀐다
	for index, fall in entry.falls do
		fall.Transparency = 0.1 + 0.35 * (0.5 + 0.5 * math.sin(now * (1.6 + index * 0.4) + index))
	end

	local launchAt = tonumber(entry.model:GetAttribute(A.launchAt)) or 0
	if launchAt > entry.lastLaunch then
		entry.lastLaunch = launchAt
		if serverNow() - launchAt < 3 then
			launchPillar(entry.ringCenter)
		end
	end
end

--------------------------------------------------------------------------------
-- 표지판 · 명예의 벽 · 진열대
--------------------------------------------------------------------------------

local function setupSigns(lobbyFolder: Instance)
	for _, child in lobbyFolder:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute(A.signKey) then
			local key = tostring(child:GetAttribute(A.signKey))
			local _, holder = surfaceText(child, Enum.NormalId.Front, 30)
			local label = textLabel(
				holder,
				"",
				Theme.color.gold,
				Theme.font.display,
				UDim2.new(1, -16, 1, -12),
				UDim2.fromOffset(8, 6)
			)
			local function refresh()
				label.Text = Locale.get(ClientState.getLanguage(), key)
			end
			refresh()
			table.insert(textRefreshers, refresh)
		end
	end
end

local honorRows: { TextLabel } = {}
local honorTitle: TextLabel? = nil
local boardRemote: RemoteFunction? = nil

local function refreshHonor()
	local title = honorTitle
	local remote = boardRemote
	if title == nil or remote == nil then
		return
	end
	local language = ClientState.getLanguage()
	title.Text = Locale.get(language, "world.honor.title")

	local ok, entries = pcall(function()
		return remote:InvokeServer("level")
	end)
	local list = if ok and type(entries) == "table" then entries else {}

	for index, row in honorRows do
		local entry = list[index]
		if entry then
			row.Text = `{entry.rank}. {entry.name}   +{entry.value}`
			row.TextColor3 = Theme.heatColor(tonumber(entry.value) or 0)
		elseif index == 1 then
			row.Text = Locale.get(language, "world.honor.empty")
			row.TextColor3 = Theme.color.muted
		else
			row.Text = ""
		end
	end
end

local function setupHonor(lobbyFolder: Instance)
	local honor = lobbyFolder:FindFirstChild("Honor")
	local board = if honor then honor:FindFirstChild("HonorBoard") else nil
	if board == nil or not board:IsA("BasePart") then
		return
	end
	local _, holder = surfaceText(board, Enum.NormalId.Left, 24)
	honorTitle = textLabel(
		holder,
		"",
		Theme.color.gold,
		Theme.font.display,
		UDim2.new(1, -20, 0.14, 0),
		UDim2.new(0, 10, 0.02, 0)
	)
	for index = 1, 10 do
		local row = textLabel(
			holder,
			"",
			Theme.color.text,
			Theme.font.bodyBold,
			UDim2.new(1, -40, 0.07, 0),
			UDim2.new(0, 20, 0.18 + (index - 1) * 0.08, 0)
		)
		row.TextXAlignment = Enum.TextXAlignment.Left
		honorRows[index] = row
	end
	table.insert(textRefreshers, function()
		task.spawn(refreshHonor)
	end)

	task.spawn(function()
		while true do
			refreshHonor()
			task.wait(60)
		end
	end)
end

type Showcase = {
	base: BasePart,
	folder: Instance,
	plaque: TextLabel?,
	sword: Model?,
	pivot: CFrame?,
	lastLevel: number,
}
local showcase: Showcase? = nil

local function refreshShowcaseText()
	local entry = showcase
	if entry == nil or entry.plaque == nil then
		return
	end
	local language = ClientState.getLanguage()
	local owner = tostring(entry.base:GetAttribute(A.ownerName) or "")
	local swordId = tostring(entry.base:GetAttribute(A.swordId) or "")
	local level = tonumber(entry.base:GetAttribute(A.swordLevel)) or 0
	local info = Weapons.get(swordId)
	local plaque = entry.plaque :: TextLabel
	if owner == "" or info == nil then
		plaque.Text = Locale.get(language, "world.showcase.empty")
	else
		plaque.Text = Locale.get(language, "world.showcase.title")
			.. "\n"
			.. Locale.get(
				language,
				"world.showcase.line",
				owner,
				Locale.get(language, info.nameKey),
				level
			)
	end
	plaque.TextColor3 = Theme.heatColor(level)
end

local function setupShowcase(lobbyFolder: Instance)
	local folder = lobbyFolder:FindFirstChild("Showcase")
	local base = if folder then folder:FindFirstChild("ShowcaseBase") else nil
	local plaquePart = if folder then folder:FindFirstChild("ShowcasePlaque") else nil
	if folder == nil or base == nil or not base:IsA("BasePart") then
		return
	end

	local entry: Showcase = {
		base = base,
		folder = folder,
		plaque = nil,
		sword = nil,
		pivot = nil,
		lastLevel = tonumber(base:GetAttribute(A.swordLevel)) or 0,
	}
	if plaquePart and plaquePart:IsA("BasePart") then
		local _, holder = surfaceText(plaquePart, Enum.NormalId.Left, 40)
		local label = textLabel(
			holder,
			"",
			Theme.color.gold,
			Theme.font.bodyBold,
			UDim2.new(1, -8, 1, -6),
			UDim2.fromOffset(4, 3)
		)
		label.TextWrapped = true
		entry.plaque = label
	end
	showcase = entry

	local function track(child: Instance)
		if child:IsA("Model") and child.Name == "ShowcaseSword" then
			entry.sword = child
			entry.pivot = child:GetPivot()
		end
	end
	for _, child in folder:GetChildren() do
		track(child)
	end
	folder.ChildAdded:Connect(track)

	base:GetAttributeChangedSignal(A.swordLevel):Connect(function()
		local level = tonumber(base:GetAttribute(A.swordLevel)) or 0
		if level > entry.lastLevel and level > 0 then
			say(Locale.get(ClientState.getLanguage(), "npc.shout.record"), 3)
		end
		entry.lastLevel = level
		refreshShowcaseText()
	end)
	base:GetAttributeChangedSignal(A.ownerName):Connect(refreshShowcaseText)
	refreshShowcaseText()
	table.insert(textRefreshers, refreshShowcaseText)
end

local function stepShowcase(now: number)
	local entry = showcase
	if entry == nil then
		return
	end
	local sword, pivot = entry.sword, entry.pivot
	if sword and pivot and sword.Parent ~= nil then
		sword:PivotTo(
			pivot
				* CFrame.new(0, 0.3 * math.sin(now / 3 * math.pi * 2), 0)
				* CFrame.Angles(0, now / 8 * math.pi * 2, 0)
		)
	end
end

--------------------------------------------------------------------------------
-- 코스: 출발 화로 · 쇠창살 · 쇳물 해일 장식
--------------------------------------------------------------------------------

type Course = {
	id: number,
	folder: Instance?,
	chaser: BasePart?,
	crests: { BasePart },
	front: BasePart?,
	trail: BasePart?,
	goAt: number,
	started: boolean,
}

local course: Course? = nil

local function localPart(color: Color3, size: Vector3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.Shape = shape or Enum.PartType.Block
	part.Parent = fxFolder
	return part
end

local function clearCourse()
	local current = course
	if current == nil then
		return
	end
	for _, crest in current.crests do
		crest:Destroy()
	end
	if current.front then
		current.front:Destroy()
	end
	if current.trail then
		current.trail:Destroy()
	end
	course = nil
end

local function findCourseFolder(id: number): Instance?
	local races = Workspace:FindFirstChild(World.RACES_FOLDER)
	return if races then races:FindFirstChild(`{World.RACE_FOLDER_PREFIX}{id}`) else nil
end

local function onRaceUpdate(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind == "lineup" then
		clearCourse()
		local crests: { BasePart } = {}
		for _ = 1, 5 do
			table.insert(
				crests,
				localPart(rgb(Palette.WORLD.moltenHot), Vector3.new(9, 9, 9), Enum.PartType.Ball)
			)
		end
		course = {
			id = tonumber(payload.raceId) or 0,
			folder = nil,
			chaser = nil,
			crests = crests,
			front = localPart(Color3.fromRGB(255, 224, 112), Vector3.new(1, 1, 1)),
			trail = localPart(rgb(Palette.WORLD.molten), Vector3.new(1, 0.2, 1)),
			goAt = os.clock() + (tonumber(payload.countdown) or 0),
			started = false,
		}
	elseif payload.kind == "start" then
		local current = course
		if current and current.folder then
			current.started = true
			for _, child in current.folder:GetChildren() do
				if child:IsA("BasePart") and child.Name == "StartBar" then
					TweenService:Create(
						child,
						TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{
							CFrame = child.CFrame - Vector3.new(0, 9, 0),
						}
					):Play()
				end
			end
		end
	elseif payload.kind == "lobby" then
		clearCourse()
	end
end

local function stepCourse(now: number)
	local current = course
	if current == nil then
		return
	end

	if current.folder == nil or current.folder.Parent == nil then
		current.folder = findCourseFolder(current.id)
		local folder = current.folder
		if folder then
			local chaser = folder:FindFirstChild(World.CHASER_NAME)
			current.chaser = if chaser and chaser:IsA("BasePart") then chaser else nil
		end
	end
	local folder = current.folder
	if folder == nil then
		return
	end

	-- 출발 화로: 남은 3·2·1초에 하나씩 켜진다
	if not current.started then
		local left = current.goAt - now
		for index = 1, 3 do
			local bowl = folder:FindFirstChild(`StartBrazier{index}`)
			local flame = if bowl then bowl:FindFirstChild("CountFire") else nil
			if flame and flame:IsA("Fire") then
				local shouldBurn = left <= (4 - index)
				if flame.Enabled ~= shouldBurn then
					flame.Enabled = shouldBurn
				end
			end
		end
	end

	-- 쇳물 해일 장식: 출렁이는 꼭대기, 끓는 앞면, 지나간 자리의 녹은 바닥
	local chaser = current.chaser
	if chaser and chaser.Parent ~= nil then
		local size = chaser.Size
		local front = chaser.Position.Z + size.Z / 2
		local topY = chaser.Position.Y + size.Y / 2
		local floorY = chaser.Position.Y - size.Y / 2
		for index, crest in current.crests do
			local x = chaser.Position.X - size.X / 2 + (index - 0.5) * size.X / #current.crests
			local bob = math.sin(now * (2 * math.pi / (1.1 + index * 0.1)) + index) * 2
			crest.Position = Vector3.new(x, topY + bob, chaser.Position.Z)
		end
		local hot = current.front
		if hot then
			hot.Size = Vector3.new(size.X, size.Y, 1)
			hot.CFrame = CFrame.new(chaser.Position.X, chaser.Position.Y, front + 0.5)
			hot.Transparency = 0.25 + 0.2 * math.sin(now * 9)
		end
		local trail = current.trail
		if trail then
			local startZ = front - 200
			local length = math.max(1, front - startZ)
			trail.Size = Vector3.new(size.X - 4, 0.2, length)
			trail.CFrame = CFrame.new(chaser.Position.X, floorY + 0.15, startZ + length / 2)
		end
	end
end

--------------------------------------------------------------------------------
-- 대장간 화면의 3D 검 미리보기
--------------------------------------------------------------------------------

local previewFrame: ViewportFrame? = nil
local previewModel: Model? = nil
local previewSignature = ""
local previewLength = 4

local function setupPreview()
	local slot = UIController.getPreviewSlot()
	local frame = Instance.new("ViewportFrame")
	frame.Name = "SwordPreview"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 0.82)
	frame.Ambient = Color3.fromRGB(150, 130, 130)
	frame.LightColor = Color3.fromRGB(255, 220, 190)
	frame.LightDirection = Vector3.new(-1, -1, -1)
	frame.Parent = slot

	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = frame
	frame.CurrentCamera = camera
	previewFrame = frame
end

local function refreshPreview()
	local frame = previewFrame
	if frame == nil then
		return
	end
	local sword = ClientState.getEquipped()
	if sword == nil then
		return
	end
	local level = UIController.getDisplayLevel()
	local signature = `{sword.id}:{level}`
	if signature == previewSignature then
		return
	end
	previewSignature = signature

	local old = previewModel
	if old then
		old:Destroy()
	end
	local model = SwordModel.build(
		sword.id,
		level,
		{ cframe = CFrame.new(), anchored = true, effects = false }
	)
	model.Parent = frame
	previewModel = model
	previewLength = SwordModel.length(sword.id)

	local camera = frame.CurrentCamera
	if camera then
		local center = Vector3.new(0, previewLength * 0.42, 0)
		camera.CFrame = CFrame.lookAt(center + Vector3.new(0, 0, previewLength * 2.1), center)
	end
end

local function stepPreview(now: number)
	local model = previewModel
	if model == nil or ScreenManager.getMode() ~= "forge" then
		return
	end
	-- 비스듬히 세워 천천히 돈다
	local center = CFrame.new(0, previewLength * 0.42, 0)
	model:PivotTo(
		center
			* CFrame.Angles(0, now * 0.8, math.rad(-28))
			* CFrame.new(0, -previewLength * 0.42, 0)
	)
end

--------------------------------------------------------------------------------
-- 내 캐릭터가 태어날 때 불티
--------------------------------------------------------------------------------

local function spawnSparkle(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(rgb(Palette.WORLD.ember))
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.6)
	emitter.Speed = NumberRange.new(8, 12)
	emitter.SpreadAngle = Vector2.new(180, 10)
	emitter.Size = NumberSequence.new(0.25, 0)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Parent = root
	emitter:Emit(30)
	task.delay(1.5, function()
		emitter:Destroy()
	end)
end

--------------------------------------------------------------------------------

local lastLanguage = ""

function WorldFxController.Init()
	fxFolder.Parent = Workspace
	setupPreview()

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	boardRemote = remotesFolder:WaitForChild(Remotes.Functions.GetLeaderboard) :: RemoteFunction

	local worldEvent = remotesFolder:WaitForChild(Remotes.Events.WorldEvent) :: RemoteEvent
	worldEvent.OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and payload.kind == "openForge" then
			ScreenManager.setForgeOpen(true)
		end
	end)

	local feedRemote = remotesFolder:WaitForChild(Remotes.Events.FeedMessage) :: RemoteEvent
	feedRemote.OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and payload.kind == "broadcast" then
			onBroadcast(payload)
		end
	end)

	local raceRemote = remotesFolder:WaitForChild(Remotes.Events.RaceUpdate) :: RemoteEvent
	raceRemote.OnClientEvent:Connect(onRaceUpdate)

	ClientState.onChanged(function()
		refreshPreview()
		local language = ClientState.getLanguage()
		if language ~= lastLanguage then
			lastLanguage = language
			for _, refresh in textRefreshers do
				pcall(refresh)
			end
		end
	end)

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function(character)
		task.spawn(spawnSparkle, character)
	end)
end

function WorldFxController.Start()
	task.spawn(function()
		local found = Workspace:WaitForChild(World.LOBBY_FOLDER, 60)
		if found == nil then
			warn("[WorldFxController] 로비를 찾지 못했습니다")
			return
		end
		lobby = found
		-- 서버가 다 지은 뒤 복제되도록 잠깐 기다린다
		task.wait(1)
		setupForge(found)
		setupTreadmills(found)
		setupGate(found)
		setupSigns(found)
		setupHonor(found)
		setupShowcase(found)
	end)

	local last = os.clock()
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = math.min(0.1, now - last)
		last = now

		local ok, err = pcall(function()
			if lobby and lobbyNearby() then
				stepForge(now, dt)
				stepTreadmills(now, dt)
				stepGate(now)
				stepShowcase(now)
			end
			stepCourse(now)
			stepPreview(now)
		end)
		if not ok then
			warn(`[WorldFxController] 연출 오류: {err}`)
		end
	end)

	-- 연출 중 바뀐 레벨을 미리보기에 반영 (공개 시점에 맞춰)
	task.spawn(function()
		while true do
			task.wait(0.25)
			refreshPreview()
		end
	end)
end

return WorldFxController
