--!strict
--[[
	EnhanceTable — 강화 확률/비용/판매가 데이터.
	밸런스 수치는 전부 여기에 두고, 로직(Pure/EnhanceLogic)은 이 데이터를 읽기만 한다.

	Odds[n] = 레벨 n 에서 n+1 로 올리는 1회 시도의 확률(퍼센트)과 비용(골드).
	SellValue[n] = 레벨 n 무기의 판매가(골드).
]]

export type LevelOdds = {
	success: number,
	keep: number,
	destroy: number,
	cost: number,
}

local EnhanceTable = {}

EnhanceTable.MAX_LEVEL = 20

-- 파괴 시 지급 파편 = floor(현재레벨 ^ SHARD_EXPONENT)
EnhanceTable.SHARD_EXPONENT = 1.5
-- 방지권 1개 교환에 필요한 파편 수
EnhanceTable.SHARDS_PER_TICKET = 50

EnhanceTable.Odds = {
	[0] = { success = 100, keep = 0, destroy = 0, cost = 10 },
	[1] = { success = 95, keep = 5, destroy = 0, cost = 20 },
	[2] = { success = 90, keep = 10, destroy = 0, cost = 40 },
	[3] = { success = 85, keep = 15, destroy = 0, cost = 70 },
	[4] = { success = 80, keep = 20, destroy = 0, cost = 110 },
	[5] = { success = 70, keep = 30, destroy = 0, cost = 160 },
	[6] = { success = 65, keep = 35, destroy = 0, cost = 230 },
	[7] = { success = 60, keep = 40, destroy = 0, cost = 320 },
	[8] = { success = 55, keep = 45, destroy = 0, cost = 440 },
	[9] = { success = 50, keep = 50, destroy = 0, cost = 600 },
	[10] = { success = 45, keep = 50, destroy = 5, cost = 800 },
	[11] = { success = 40, keep = 52, destroy = 8, cost = 1050 },
	[12] = { success = 35, keep = 55, destroy = 10, cost = 1350 },
	[13] = { success = 30, keep = 58, destroy = 12, cost = 1700 },
	[14] = { success = 25, keep = 60, destroy = 15, cost = 2100 },
	[15] = { success = 20, keep = 62, destroy = 18, cost = 2600 },
	[16] = { success = 15, keep = 65, destroy = 20, cost = 3200 },
	[17] = { success = 10, keep = 68, destroy = 22, cost = 4000 },
	[18] = { success = 7, keep = 70, destroy = 23, cost = 5000 },
	[19] = { success = 5, keep = 70, destroy = 25, cost = 6500 },
} :: { [number]: LevelOdds }

EnhanceTable.SellValue = {
	[0] = 0,
	[1] = 5,
	[2] = 15,
	[3] = 30,
	[4] = 55,
	[5] = 90,
	[6] = 140,
	[7] = 210,
	[8] = 300,
	[9] = 430,
	[10] = 620,
	[11] = 880,
	[12] = 1250,
	[13] = 1750,
	[14] = 2500,
	[15] = 3500,
	[16] = 5000,
	[17] = 7000,
	[18] = 10000,
	[19] = 15000,
	[20] = 25000,
} :: { [number]: number }

-- 서버 채팅 전체 공지를 띄우는 최소 레벨
EnhanceTable.BROADCAST_MIN_LEVEL = 15

--[[
	확률표가 스스로 일관된지 검사한다.
	서버 시작 시점(EnhanceService.Init)과 Lune 테스트 양쪽에서 호출한다.
	실패 사유 문자열을 반환하고, 문제가 없으면 nil 을 반환한다.
]]
function EnhanceTable.validate(): string?
	for level = 0, EnhanceTable.MAX_LEVEL - 1 do
		local odds = EnhanceTable.Odds[level]
		if not odds then
			return `Odds[{level}] 항목이 없습니다`
		end

		local sum = odds.success + odds.keep + odds.destroy
		if sum ~= 100 then
			return `Odds[{level}] 의 성공+유지+파괴 합이 {sum} 입니다 (100 이어야 함)`
		end

		for key, value in { success = odds.success, keep = odds.keep, destroy = odds.destroy } do
			if value < 0 or value ~= math.floor(value) then
				return `Odds[{level}].{key} 값이 잘못되었습니다: {value}`
			end
		end

		if odds.cost <= 0 or odds.cost ~= math.floor(odds.cost) then
			return `Odds[{level}].cost 값이 잘못되었습니다: {odds.cost}`
		end
	end

	if EnhanceTable.Odds[EnhanceTable.MAX_LEVEL] ~= nil then
		return `최대 레벨({EnhanceTable.MAX_LEVEL})에는 강화 확률이 있으면 안 됩니다`
	end

	for level = 0, EnhanceTable.MAX_LEVEL do
		local sell = EnhanceTable.SellValue[level]
		if sell == nil then
			return `SellValue[{level}] 항목이 없습니다`
		end
		if sell < 0 or sell ~= math.floor(sell) then
			return `SellValue[{level}] 값이 잘못되었습니다: {sell}`
		end
	end

	return nil
end

return EnhanceTable
