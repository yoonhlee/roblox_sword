--!strict
--[[
	SwordLogic — 검 보관함과 새 검 뽑기의 순수 함수 (통합 기획서 5절).

	Roblox API 와 require 가 없다. 검 목록·등급·가중치는 전부 인자로 받는다.
	서버는 이 함수로 실제 뽑기를 하고, 클라이언트는 같은 함수로 확률표를 그린다.
	(같은 데이터 + 같은 함수라서 화면의 확률과 실제 확률이 어긋날 수 없다.)
]]

local SwordLogic = {}

export type SwordState = {
	id: string,
	level: number,
	bestLevel: number,
	customName: string?,
}

export type DrawEntry = {
	id: string,
	rarity: string,
	weight: number,
	percent: number, -- 화면에 보여 주는 값. 모든 항목의 합이 정확히 100
}

export type RarityShare = {
	rarity: string,
	percent: number,
}

export type DrawTable = {
	entries: { DrawEntry }, -- 아직 안 가진 검만, 주어진 순서대로
	rarities: { RarityShare }, -- 등급별 합계 (항목이 있는 등급만)
	totalWeight: number,
}

-- 확률을 소수 몇째 자리까지 보여 줄지
SwordLogic.PERCENT_DECIMALS = 2

function SwordLogic.count(swords: { [string]: any }): number
	local count = 0
	for _ in swords do
		count += 1
	end
	return count
end

-- 착용 중인 검. 데이터가 깨져 있으면 nil.
function SwordLogic.equipped(swords: { [string]: SwordState }, equippedId: string): SwordState?
	return swords[equippedId]
end

--[[
	소지 상한 1칸 가격 = multiplier × (기준 레벨의 강화 비용, 검 수 할증 포함).
	costAtBaseLevel 에는 EnhanceLogic.cost(15, 지금 가진 검 수, ...) 를 넘긴다.
]]
function SwordLogic.slotPrice(costAtBaseLevel: number, multiplier: number): number
	return math.floor(costAtBaseLevel * multiplier + 0.5)
end

--[[
	가중치를 "합이 정확히 100 인 퍼센트"로 바꾼다.
	그냥 반올림하면 합이 99.99 나 100.01 이 될 수 있어서, 내림한 뒤 남은 몫을
	소수 부분이 큰 순서대로 한 칸씩 나눠 준다.
]]
function SwordLogic.exactPercents(weights: { number }, decimals: number): { number }
	local total = 0
	for _, weight in weights do
		total += weight
	end

	local result: { number } = {}
	if total <= 0 then
		for index in weights do
			result[index] = 0
		end
		return result
	end

	local scale = 10 ^ decimals
	local units = 100 * scale -- 나눠 줄 전체 칸 수

	local floors: { number } = {}
	local order: { number } = {}
	local remainders: { number } = {}
	local used = 0

	for index, weight in weights do
		local exact = weight / total * units
		local whole = math.floor(exact + 1e-9)
		floors[index] = whole
		remainders[index] = exact - whole
		order[index] = index
		used += whole
	end

	table.sort(order, function(a, b)
		if remainders[a] ~= remainders[b] then
			return remainders[a] > remainders[b]
		end
		return a < b
	end)

	local left = math.floor(units - used + 0.5)
	for position = 1, left do
		local index = order[(position - 1) % #order + 1]
		floors[index] += 1
	end

	for index, whole in floors do
		result[index] = whole / scale
	end
	return result
end

--[[
	그 플레이어 기준 뽑기 표를 만든다. 이미 가진 검은 빠진다.
	order: 검 id 를 보여 줄 순서대로. rarityOf: 검 id → 등급. weights: 등급 → 가중치.
]]
function SwordLogic.buildDrawTable(
	order: { string },
	rarityOf: { [string]: string },
	weights: { [string]: number },
	owned: { [string]: any }
): DrawTable
	local entries: { DrawEntry } = {}
	local rawWeights: { number } = {}
	local totalWeight = 0

	for _, id in order do
		if owned[id] == nil then
			local rarity = rarityOf[id]
			local weight = weights[rarity] or 0
			if weight > 0 then
				table.insert(entries, { id = id, rarity = rarity, weight = weight, percent = 0 })
				table.insert(rawWeights, weight)
				totalWeight += weight
			end
		end
	end

	local percents = SwordLogic.exactPercents(rawWeights, SwordLogic.PERCENT_DECIMALS)
	local scale = 10 ^ SwordLogic.PERCENT_DECIMALS

	local rarities: { RarityShare } = {}
	local shareIndex: { [string]: number } = {}

	for index, entry in entries do
		entry.percent = percents[index]

		local position = shareIndex[entry.rarity]
		if position == nil then
			table.insert(rarities, { rarity = entry.rarity, percent = 0 })
			position = #rarities
			shareIndex[entry.rarity] = position
		end

		-- 소수 오차가 쌓이지 않게 정수 칸으로 더한 뒤 되돌린다.
		local share = rarities[position]
		share.percent = math.floor(share.percent * scale + entry.percent * scale + 0.5) / scale
	end

	return { entries = entries, rarities = rarities, totalWeight = totalWeight }
end

--[[
	뽑기 1회. unitRoll 은 [0, 1) 난수. 뽑을 검이 없으면 nil.
	실제 추첨은 반올림한 퍼센트가 아니라 원래 가중치로 한다.
]]
function SwordLogic.pick(drawTable: DrawTable, unitRoll: number): string?
	local entries = drawTable.entries
	if #entries == 0 or drawTable.totalWeight <= 0 then
		return nil
	end

	local target = math.clamp(unitRoll, 0, 1) * drawTable.totalWeight
	local running = 0

	for _, entry in entries do
		running += entry.weight
		if target < running then
			return entry.id
		end
	end

	return entries[#entries].id
end

return SwordLogic
