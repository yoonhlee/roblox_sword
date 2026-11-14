--!strict
--[[
	TreadmillLogic — 로비 트레드밀의 순수 함수 (통합 기획서 6절).
	Roblox API 와 require 가 없다.
]]

local TreadmillLogic = {}

-- 발판 하나의 자리. 좌표는 발판 중심, topY 는 발판 윗면의 높이.
export type Pad = {
	x: number,
	z: number,
	sizeX: number,
	sizeZ: number,
	topY: number,
	reach: number, -- 윗면에서 이 높이까지 "올라가 있다"로 본다
}

--[[
	발판 위에 있던 시간을 더한다.
	반환: (남은 진행 시간, 이번에 지급할 횟수)
	interval 초를 채울 때마다 1회 지급이다. 한 번에 여러 번 채웠으면 그만큼 준다.
]]
function TreadmillLogic.advance(progress: number, dt: number, interval: number): (number, number)
	if interval <= 0 then
		return 0, 0
	end

	local total = math.max(0, progress) + math.max(0, dt)
	local payouts = math.floor(total / interval + 1e-9)
	local rest = math.max(0, total - payouts * interval)

	return rest, payouts
end

-- 위치 (px, py, pz) 가 발판 위인지. py 는 캐릭터 중심의 높이.
function TreadmillLogic.isOnPad(px: number, py: number, pz: number, pad: Pad): boolean
	if math.abs(px - pad.x) > pad.sizeX / 2 then
		return false
	end
	if math.abs(pz - pad.z) > pad.sizeZ / 2 then
		return false
	end
	return py >= pad.topY and py <= pad.topY + pad.reach
end

return TreadmillLogic
