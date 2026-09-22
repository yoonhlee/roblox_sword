--!strict
--[[
	EffectsController — 강화 결과 연출.

	모든 연출은 서버 응답을 받은 뒤 UIController 가 호출해서 시작한다.
	외부 에셋 없이 UI 요소의 움직임만으로 만든다(나중에 파티클/사운드를 얹기 쉬움).

	- 성공: 글자가 커지며 밝게 번쩍 + 위로 솟는 느낌
	- 유지: 짧은 좌우 흔들림
	- 파괴: 붉은 화면 번쩍 + 조각이 흩어지는 연출 + 화면 흔들림
	- 보호: 푸른 방패 펄스
]]

local TweenService = game:GetService("TweenService")

local EffectsController = {}
EffectsController.Name = "EffectsController"

local centerFrame: Frame? = nil
local levelLabel: TextLabel? = nil
local flash: Frame? = nil

local BASE_TEXT_SIZE = 72

-- UIController 가 자기 UI 요소를 넘겨 준다.
function EffectsController.bind(targetGui: ScreenGui, center: Frame, label: TextLabel)
	centerFrame = center
	levelLabel = label
	BASE_TEXT_SIZE = label.TextSize

	local overlay = Instance.new("Frame")
	overlay.Name = "Flash"
	overlay.BackgroundColor3 = Color3.new(1, 1, 1)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 50
	overlay.Active = false
	overlay.Parent = targetGui
	flash = overlay
end

local function flashScreen(color: Color3, strength: number)
	local overlay = flash
	if overlay == nil then
		return
	end

	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = 1 - strength
	TweenService:Create(
		overlay,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
end

local function shake(intensity: number, duration: number)
	local frame = centerFrame
	if frame == nil then
		return
	end

	local origin = frame.Position
	local steps = math.max(2, math.floor(duration / 0.04))

	task.spawn(function()
		for step = 1, steps do
			local decay = 1 - step / steps
			local offsetX = (math.random() - 0.5) * 2 * intensity * decay
			local offsetY = (math.random() - 0.5) * 2 * intensity * decay
			frame.Position = origin + UDim2.fromOffset(offsetX, offsetY)
			task.wait(0.04)
		end
		frame.Position = origin
	end)
end

local function pulseLabel(targetSize: number, color: Color3)
	local label = levelLabel
	if label == nil then
		return
	end

	local originalColor = label.TextColor3
	label.TextSize = targetSize
	label.TextColor3 = color

	TweenService:Create(
		label,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextSize = BASE_TEXT_SIZE, TextColor3 = originalColor }
	):Play()
end

-- 파괴될 때 조각이 흩어지는 연출
local function burst(count: number, color: Color3)
	local frame = centerFrame
	if frame == nil then
		return
	end

	for _ = 1, count do
		local piece = Instance.new("Frame")
		piece.BackgroundColor3 = color
		piece.BorderSizePixel = 0
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(0.5, 0.5)
		piece.Size = UDim2.fromOffset(math.random(4, 10), math.random(4, 10))
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 20
		piece.Parent = frame

		local angle = math.random() * math.pi * 2
		local distance = math.random(60, 180)

		local tween = TweenService:Create(
			piece,
			TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{
				Position = UDim2.new(
					0.5,
					math.cos(angle) * distance,
					0.5,
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

--[[
	결과에 맞는 연출을 재생한다.
	outcome: "success" | "keep" | "destroy" | "protected"
]]
function EffectsController.play(outcome: string)
	if outcome == "success" then
		pulseLabel(BASE_TEXT_SIZE * 1.4, Color3.fromRGB(255, 240, 200))
		flashScreen(Color3.fromRGB(255, 220, 150), 0.25)
	elseif outcome == "keep" then
		shake(6, 0.2)
	elseif outcome == "destroy" then
		pulseLabel(BASE_TEXT_SIZE * 0.7, Color3.fromRGB(255, 120, 108))
		flashScreen(Color3.fromRGB(255, 80, 70), 0.4)
		burst(14, Color3.fromRGB(200, 190, 180))
		shake(14, 0.45)
	elseif outcome == "protected" then
		pulseLabel(BASE_TEXT_SIZE * 1.15, Color3.fromRGB(150, 215, 255))
		flashScreen(Color3.fromRGB(120, 190, 255), 0.25)
	end
end

-- 최대 레벨 도달 시의 특수 연출
function EffectsController.playMaxLevel()
	pulseLabel(BASE_TEXT_SIZE * 1.6, Color3.fromRGB(255, 255, 255))
	flashScreen(Color3.fromRGB(255, 240, 200), 0.5)
	burst(24, Color3.fromRGB(255, 215, 140))
end

function EffectsController.Init() end

function EffectsController.Start() end

return EffectsController
