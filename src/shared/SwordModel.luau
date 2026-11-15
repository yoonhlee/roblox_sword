--!strict
--[[
	SwordModel — 블록으로 3D 검을 짓는다 (통합 기획서 8-2절).

	모양은 Config/SwordShapes(숫자 데이터), 색은 Config/Palette 에서 온다.
	  칼날 바탕 = 강철색 금속 / 테두리 = 레벨 색(쇠 달구는 색, 5강부터 네온으로 빛남) /
	  가드·손잡이 끝 = 등급 색 / 속심·장식 = 검마다 정한 색(네온)
	  레벨이 높을수록 칼날 주위 빛이 커지고, 15강부터 불티, 20강은 하얀 불꽃.
	서버(손에 든 검, 진열대)와 클라이언트(대장간 화면 미리보기)가 같은 함수를 쓴다.
	보기만 하는 장식이라 부딪히지도, 무게도, 클릭 판정도 없다.
]]

local Config = script.Parent:WaitForChild("Config")
local Palette = require(Config:WaitForChild("Palette"))
local SwordShapes = require(Config:WaitForChild("SwordShapes"))
local Weapons = require(Config:WaitForChild("Weapons"))
local VisualLogic = require(script.Parent:WaitForChild("Pure"):WaitForChild("VisualLogic"))

local SwordModel = {}

SwordModel.MODEL_NAME = "ForgeSword"
SwordModel.HANDLE_NAME = "Handle"

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local SHAPE_TYPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Wedge = Enum.PartType.Wedge,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

export type Options = {
	cframe: CFrame, -- 손잡이 가운데가 놓일 자리 (칼날은 이 CFrame 의 +Y 쪽)
	scale: number?, -- 크기 배율 (손에 들 때는 작게)
	anchored: boolean?, -- true 면 고정(진열대·미리보기), false 면 손잡이에 용접(손에 들 때)
	effects: boolean?, -- 빛·불티·불꽃을 붙일지 (미리보기 화면에서는 빛이 안 보이므로 끈다)
}

--[[
	검 모델을 만든다. 부모는 정하지 않는다(호출한 쪽이 붙인다).
	PrimaryPart 는 손잡이(Handle).
]]
function SwordModel.build(swordId: string, level: number, options: Options): Model
	local shape = SwordShapes.get(swordId)
	local info = Weapons.get(swordId)
	local rarityColor =
		rgb(Palette.RARITY[if info then info.rarity else "common"] or Palette.RARITY.common)
	local tier = VisualLogic.heatTier(level, Palette.HEAT_TIERS)
	local heatColor = rgb(tier.rgb)
	local accentColor = if shape.accent then rgb(shape.accent) else heatColor
	local scale = options.scale or 1
	local anchored = options.anchored == true

	local model = Instance.new("Model")
	model.Name = SwordModel.MODEL_NAME
	model:SetAttribute("SwordId", swordId)
	model:SetAttribute("SwordLevel", level)

	local handle: BasePart? = nil
	local glowPart: BasePart? = nil

	for index, spec in shape.parts do
		local part = Instance.new("Part")
		part.Name = if spec.role == "grip" and handle == nil
			then SwordModel.HANDLE_NAME
			else `{spec.role}{index}`
		part.Shape = SHAPE_TYPES[spec.shape] or Enum.PartType.Block
		part.Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3]) * scale
		part.Anchored = anchored
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth

		local role = spec.role
		if role == "blade" then
			part.Color = rgb(Palette.WORLD.steel)
			part.Material = Enum.Material.Metal
			if glowPart == nil then
				glowPart = part
			end
		elseif role == "edge" then
			part.Color = heatColor
			part.Material = if tier.glow > 0 then Enum.Material.Neon else Enum.Material.Metal
		elseif role == "core" or role == "accent" then
			part.Color = accentColor
			part.Material = Enum.Material.Neon
		elseif role == "guard" or role == "pommel" then
			part.Color = rarityColor
			part.Material = Enum.Material.Metal
		else -- grip
			part.Color = rgb(Palette.WORLD.wood)
			part.Material = Enum.Material.Wood
		end

		local rot = spec.rot or { 0, 0, 0 }
		part.CFrame = options.cframe
			* CFrame.new(spec.pos[1] * scale, spec.pos[2] * scale, spec.pos[3] * scale)
			* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
		part.Parent = model

		if part.Name == SwordModel.HANDLE_NAME then
			handle = part
		end
	end

	local primary = handle or model:FindFirstChildWhichIsA("BasePart")
	model.PrimaryPart = primary

	-- 손에 들 때: 모든 조각을 손잡이에 붙인다
	if not anchored and primary then
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") and child ~= primary then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = child
				weld.Parent = child
			end
		end
	end

	-- 레벨이 높을수록 빛, 15강부터 불티, 20강은 하얀 불꽃
	local glow = glowPart
	if options.effects ~= false and glow and tier.glow > 0 then
		local light = Instance.new("PointLight")
		light.Color = heatColor
		light.Range = (4 + 8 * tier.glow) * scale
		light.Brightness = 0.6 + 1.6 * tier.glow
		light.Parent = glow

		if tier.sparks then
			local sparks = Instance.new("ParticleEmitter")
			sparks.Name = "Sparks"
			sparks.Color = ColorSequence.new(heatColor)
			sparks.LightEmission = 1
			sparks.Rate = 6
			sparks.Lifetime = NumberRange.new(0.4, 0.8)
			sparks.Speed = NumberRange.new(1, 3)
			sparks.SpreadAngle = Vector2.new(60, 60)
			sparks.Size = NumberSequence.new(0.12 * scale, 0)
			sparks.Parent = glow
		end

		local whiteTier = Palette.HEAT_TIERS[#Palette.HEAT_TIERS]
		if level >= whiteTier.minLevel then
			local fire = Instance.new("Fire")
			fire.Color = Color3.new(1, 1, 1)
			fire.SecondaryColor = rgb(Palette.WORLD.gold)
			fire.Size = 2 * scale
			fire.Heat = 3
			fire.Parent = glow
		end
	end

	return model
end

-- 모양 길이 (미리보기 카메라 거리용)
function SwordModel.length(swordId: string): number
	return SwordShapes.length(SwordShapes.get(swordId))
end

return SwordModel
