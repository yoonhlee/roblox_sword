--!strict
--[[
	EffectsController — 강화 결과 연출 (통합 기획서 8-1절 결정 3).

	서버 응답을 받은 뒤 UIController 가 playReveal 을 부른다. 순서:
	  1) 망치질: 강화하기 "전" 레벨이 높을수록 길고 횟수가 많다
	     (0~9강 0.5초·1번, 10~14강 1초·2번, 15강 이상 2초·3번 — Config/VisualConfig.Reveal)
	     15강 이상은 망치질하는 동안 화면이 점점 어두워진다.
	  2) 결과 공개: onReveal 을 불러 화면 숫자를 바꾸고, 결과별 연출
	     성공 = 주황 번쩍 + 레벨 숫자가 튀어 오름 + 불티 / 유지 = 흔들림 /
	     실패 = 붉게 번쩍 + 조각 + "+10" / 방지 = 하늘색 고리가 퍼짐 / 20강 = 크게 하얗게
	  3) onDone
	망치질 도중 화면을 누르면(skip) 바로 결과로 넘어간다.
	외부 에셋 없이 UI 요소의 움직임만으로 만든다. 소리는 SoundController 의 자리만 부른다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VisualConfig = require(Shared:WaitForChild("Config"):WaitForChild("VisualConfig"))
local VisualLogic = require(Shared:WaitForChild("Pure"):WaitForChild("VisualLogic"))

local client = script.Parent.Parent
local ui = client:WaitForChild("ui")
local Theme = require(ui:WaitForChild("Theme"))
local Components = require(ui:WaitForChild("Components"))
local ScreenManager = require(ui:WaitForChild("ScreenManager"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local EffectsController = {}
EffectsController.Name = "EffectsController"

local C = Theme.color

local stage: Frame? = nil
local labelScale: UIScale? = nil
local flash: Frame? = nil
local dimmer: Frame? = nil

local playing = false
local skipped = false

-- UIController 가 자기 화면 요소를 넘겨 준다.
function EffectsController.bind(stageFrame: Frame, label: TextLabel)
	stage = stageFrame

	local scale = label:FindFirstChildOfClass("UIScale")
	if scale == nil then
		local created = Instance.new("UIScale")
		created.Parent = label
		scale = created
	end
	labelScale = scale
end

local function flashScreen(color: Color3, strength: number, duration: number?)
	local overlay = flash
	if overlay == nil then
		return
	end
	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = 1 - strength
	TweenService:Create(
		overlay,
		TweenInfo.new(duration or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
end

local function setDim(amount: number, duration: number)
	local overlay = dimmer
	if overlay == nil then
		return
	end
	TweenService:Create(overlay, TweenInfo.new(duration, Enum.EasingStyle.Sine), {
		BackgroundTransparency = 1 - amount,
	}):Play()
end

local function punchLabel(peak: number, duration: number)
	local scale = labelScale
	if scale == nil then
		return
	end
	scale.Scale = peak
	TweenService
		:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		})
		:Play()
end

local function shake(intensity: number, duration: number)
	local frame = stage
	if frame == nil then
		return
	end

	local origin = frame.Position
	local steps = math.max(2, math.floor(duration / 0.04))

	task.spawn(function()
		for step = 1, steps do
			local decay = 1 - step / steps
			frame.Position = origin
				+ UDim2.fromOffset(
					(math.random() - 0.5) * 2 * intensity * decay,
					(math.random() - 0.5) * 2 * intensity * decay
				)
			task.wait(0.04)
		end
		frame.Position = origin
	end)
end

-- 무대 가운데(또는 아래)에서 작은 조각들이 튀어 나간다 (불티·쇳조각)
local function burst(count: number, color: Color3, fromBottom: boolean?, spread: number?)
	local frame = stage
	if frame == nil then
		return
	end

	local originY = if fromBottom then 0.8 else 0.5
	for _ = 1, count do
		local piece = Instance.new("Frame")
		piece.BackgroundColor3 = color
		piece.BorderSizePixel = 0
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(0.5, originY)
		local size = math.random(4, 9)
		piece.Size = UDim2.fromOffset(size, size)
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 20
		piece.Parent = frame

		local angle = if fromBottom
			then -math.pi / 2 + (math.random() - 0.5) * math.pi * 0.9
			else math.random() * math.pi * 2
		local distance = math.random(50, spread or 170)

		local tween = TweenService:Create(
			piece,
			TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{
				Position = UDim2.new(
					0.5,
					math.cos(angle) * distance,
					originY,
					math.sin(angle) * distance
				),
				BackgroundTransparency = 1,
				Rotation = piece.Rotation + math.random(-180, 180),
			}
		)
		tween.Completed:Connect(function()
			piece:Destroy()
		end)
		tween:Play()
	end
end

-- 방지권: 하늘색 고리가 퍼진다
local function ring(color: Color3)
	local frame = stage
	if frame == nil then
		return
	end

	local circle = Instance.new("Frame")
	circle.BackgroundTransparency = 1
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.55)
	circle.Size = UDim2.fromOffset(40, 40)
	circle.ZIndex = 19
	circle.Parent = frame
	Components.round(circle)
	local stroke = Components.stroke(circle, color, 6)

	local tween = TweenService:Create(
		circle,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = UDim2.fromOffset(260, 260),
		}
	)
	TweenService:Create(stroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
	tween.Completed:Connect(function()
		circle:Destroy()
	end)
	tween:Play()
end

-- 망치질 한 번
local function strike(level: number)
	SoundController.play("hammer")
	punchLabel(0.88, 0.18)
	flashScreen(Theme.heatColor(level), 0.12, 0.15)
	burst(6, C.gold, true, 110)
end

local function playResult(outcome: string, newLevel: number, isMax: boolean)
	local frame = stage

	if isMax then
		SoundController.play("max")
		punchLabel(1.6, 0.6)
		flashScreen(C.white, 0.6, 0.8)
		burst(30, C.gold, false, 220)
		if frame then
			Components.floatText(frame, "+20", C.white, UDim2.fromScale(0.5, 0.4), Theme.text.big)
		end
		return
	end

	SoundController.play(outcome)

	if outcome == "success" then
		punchLabel(1.35, 0.4)
		flashScreen(Theme.heatColor(newLevel), 0.28)
		burst(16, Theme.heatColor(newLevel), false, 170)
	elseif outcome == "keep" then
		shake(6, 0.22)
	elseif outcome == "fail" then
		punchLabel(0.7, 0.45)
		flashScreen(C.fail, 0.42)
		burst(14, Color3.fromRGB(200, 190, 180), false, 180)
		shake(14, 0.45)
		if frame then
			Components.floatText(
				frame,
				`+{newLevel}`,
				C.fail,
				UDim2.fromScale(0.5, 0.45),
				Theme.text.big
			)
		end
	elseif outcome == "protected" then
		punchLabel(1.15, 0.35)
		flashScreen(C.protect, 0.25)
		ring(C.protect)
	end
end

--[[
	강화 결과 연출 전체.
	startLevel: 강화하기 전 레벨 (망치질 길이 결정)
	onReveal: 결과를 화면에 반영할 때 부른다 (레벨 숫자 바꾸기, 피드 한 줄)
	onDone:   연출이 끝났을 때
]]
function EffectsController.playReveal(
	startLevel: number,
	outcome: string,
	newLevel: number,
	isMax: boolean,
	onReveal: () -> (),
	onDone: () -> ()
)
	local step = VisualLogic.reveal(startLevel, VisualConfig.Reveal)
	playing = true
	skipped = false

	task.spawn(function()
		local interval = step.seconds / step.strikes
		local darkens = step.strikes >= 3

		if darkens then
			setDim(0.45, step.seconds)
		end

		for index = 1, step.strikes do
			if skipped then
				break
			end
			strike(startLevel)

			-- 다음 망치질까지 조금씩 쉬며 건너뛰기를 확인한다
			local waited = 0
			local target = if index == step.strikes then interval * 0.6 else interval
			while waited < target and not skipped do
				waited += task.wait(0.03)
			end
		end

		if darkens then
			setDim(0, 0.15)
		end

		local ok, err = pcall(onReveal)
		if not ok then
			warn(`[EffectsController] 결과 반영 오류: {err}`)
		end
		playResult(outcome, newLevel, isMax)

		playing = false
		task.wait(0.25)
		onDone()
	end)
end

-- 망치질 도중에 누르면 바로 결과로
function EffectsController.skip()
	if playing then
		skipped = true
	end
end

function EffectsController.isPlaying(): boolean
	return playing
end

function EffectsController.Init()
	local overlay = ScreenManager.createOverlay("ForgeFlash", 20)

	local flashFrame = Instance.new("Frame")
	flashFrame.Name = "Flash"
	flashFrame.BackgroundColor3 = C.white
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.Active = false
	flashFrame.Parent = overlay
	flash = flashFrame

	-- 15강 이상 망치질 때 "주변이" 어두워지도록 대장간 패널(5)보다 아래 층에 둔다.
	local dimOverlay = ScreenManager.createOverlay("ForgeRevealDim", 3)
	local dimFrame = Instance.new("Frame")
	dimFrame.Name = "Dim"
	dimFrame.BackgroundColor3 = C.black
	dimFrame.BackgroundTransparency = 1
	dimFrame.BorderSizePixel = 0
	dimFrame.Size = UDim2.fromScale(1, 1)
	dimFrame.Active = false
	dimFrame.Parent = dimOverlay
	dimmer = dimFrame
end

function EffectsController.Start() end

return EffectsController
