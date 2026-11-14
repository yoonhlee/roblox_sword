--!strict
--[[
	EnhanceTable — 강화 확률/비용 데이터 (통합 기획서 3절).
	밸런스 수치는 전부 여기에 두고, 로직(Pure/EnhanceLogic)은 이 데이터를 읽기만 한다.

	Odds[L] = 레벨 L 에서 L+1 로 올리는 1회 시도의 확률(퍼센트).
	  - 1구간 (L = 0~9): 실패 없음. 성공 아니면 유지.
	  - 2구간 (L = 10~19): 실패하면 SAFE_LEVEL(10강)로 돌아간다.
	표의 값이 정본이다. 만든 공식(기획서 3-1)은 테스트가 표와 맞는지 확인한다.

	비용은 표가 아니라 공식이다: COST_BASE × (1 + 2^L) × (가진 검 수)^SWORD_COUNT_EXPONENT
	계산은 Pure/EnhanceLogic.cost 가 한다.
]]

export type LevelOdds = {
	success: number,
	keep: number,
	fail: number,
}

local EnhanceTable = {}

EnhanceTable.MAX_LEVEL = 20

-- 2구간이 시작되는 레벨이자, 2구간에서 실패했을 때 돌아가는 레벨
EnhanceTable.SAFE_LEVEL = 10

EnhanceTable.COST_BASE = 100
EnhanceTable.SWORD_COUNT_EXPONENT = 1.1

-- [미정 D12] 2구간 실패 시 주는 파편 양은 아직 정해지지 않았다.
-- 임시로 프로토타입 공식 floor(실패한 레벨 ^ SHARD_EXPONENT) 을 그대로 쓴다.
EnhanceTable.SHARD_EXPONENT = 1.5

EnhanceTable.Odds = {
	[0] = { success = 100, keep = 0, fail = 0 },
	[1] = { success = 97, keep = 3, fail = 0 },
	[2] = { success = 94, keep = 6, fail = 0 },
	[3] = { success = 89, keep = 11, fail = 0 },
	[4] = { success = 84, keep = 16, fail = 0 },
	[5] = { success = 76, keep = 24, fail = 0 },
	[6] = { success = 66, keep = 34, fail = 0 },
	[7] = { success = 53, keep = 47, fail = 0 },
	[8] = { success = 37, keep = 63, fail = 0 },
	[9] = { success = 15, keep = 85, fail = 0 },
	[10] = { success = 66, keep = 29, fail = 5 },
	[11] = { success = 53, keep = 40, fail = 7 },
	[12] = { success = 43, keep = 49, fail = 8 },
	[13] = { success = 35, keep = 55, fail = 10 },
	[14] = { success = 27, keep = 61, fail = 12 },
	[15] = { success = 21, keep = 66, fail = 13 },
	[16] = { success = 16, keep = 69, fail = 15 },
	[17] = { success = 11, keep = 72, fail = 17 },
	[18] = { success = 6, keep = 76, fail = 18 },
	[19] = { success = 2, keep = 78, fail = 20 },
} :: { [number]: LevelOdds }

-- 서버 채팅 전체 공지를 띄우는 최소 레벨
EnhanceTable.BROADCAST_MIN_LEVEL = 15

--[[
	확률표가 스스로 일관된지 검사한다.
	서버 시작 시점(EnhanceService.Init)과 테스트 양쪽에서 호출한다.
	실패 사유 문자열을 반환하고, 문제가 없으면 nil 을 반환한다.
]]
function EnhanceTable.validate(): string?
	for level = 0, EnhanceTable.MAX_LEVEL - 1 do
		local odds = EnhanceTable.Odds[level]
		if not odds then
			return `Odds[{level}] 항목이 없습니다`
		end

		local sum = odds.success + odds.keep + odds.fail
		if sum ~= 100 then
			return `Odds[{level}] 의 성공+유지+실패 합이 {sum} 입니다 (100 이어야 함)`
		end

		for key, value in { success = odds.success, keep = odds.keep, fail = odds.fail } do
			if value < 0 or value ~= math.floor(value) then
				return `Odds[{level}].{key} 값이 잘못되었습니다: {value}`
			end
		end

		if level < EnhanceTable.SAFE_LEVEL and odds.fail ~= 0 then
			return `Odds[{level}] 는 1구간인데 실패 확률이 있습니다`
		end
	end

	if EnhanceTable.Odds[EnhanceTable.MAX_LEVEL] ~= nil then
		return `최대 레벨({EnhanceTable.MAX_LEVEL})에는 강화 확률이 있으면 안 됩니다`
	end

	return nil
end

return EnhanceTable
