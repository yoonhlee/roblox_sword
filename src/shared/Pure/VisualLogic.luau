--!strict
--[[
	VisualLogic — 레벨 색·연출 길이를 고르는 순수 함수 (통합 기획서 8-1절).
	Roblox API 와 require 가 없다. 색표·시간표는 인자로 받는다(Config/Palette, Config/VisualConfig).
]]

local VisualLogic = {}

export type HeatTier = {
	minLevel: number,
	rgb: { number },
	glow: number,
	sparks: boolean,
	nameKey: string,
}

export type RevealStep = {
	minLevel: number,
	seconds: number,
	strikes: number,
}

-- minLevel 오름차순 표에서 level 에 해당하는 마지막 줄의 번호. 표가 비어 있으면 0.
local function stepIndex(list: { any }, level: number): number
	local found = 0
	for index, entry in list do
		if level >= entry.minLevel then
			found = index
		end
	end
	if found == 0 and #list > 0 then
		return 1
	end
	return found
end

-- 레벨의 달구는 색 단계
function VisualLogic.heatTier(level: number, tiers: { HeatTier }): HeatTier
	return tiers[stepIndex(tiers, level)]
end

-- 강화 결과 연출 단계 (강화하기 "전" 레벨 기준: 높은 곳에서 두드릴수록 긴장감이 길다)
function VisualLogic.reveal(level: number, steps: { RevealStep }): RevealStep
	return steps[stepIndex(steps, level)]
end

--[[
	화면 배율. 기준 크기에 맞춰 줄이거나 키우되 [minScale, maxScale] 안에서.
	가로·세로 중 더 빡빡한 쪽에 맞춘다.
]]
function VisualLogic.scaleFor(
	width: number,
	height: number,
	referenceWidth: number,
	referenceHeight: number,
	minScale: number,
	maxScale: number
): number
	local scale = math.min(width / referenceWidth, height / referenceHeight)
	return math.clamp(scale, minScale, maxScale)
end

return VisualLogic
