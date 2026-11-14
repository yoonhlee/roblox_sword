--!strict
--[[
	DataMigration — 저장된 플레이어 데이터를 현재 스키마로 올리는 순수 함수.

	Roblox API 와 require 가 없어서 Studio 밖에서 테스트할 수 있다.
	필요한 상수는 options 로 받는다.

	규칙: 기존 데이터를 절대 버리지 않는다. 형태가 바뀐 값은 "옮기기"만 하고,
	기획에서 빠진 필드(배틀·업적 기록, 옛 weapon)는 그대로 둔다.

	ProfileStore 의 Reconcile() 이 먼저 돌아서 템플릿의 새 키는 이미 채워져 있다고
	보지만, 순서에 기대지 않도록 여기서도 없는 값은 채운다.
]]

local DataMigration = {}

export type Options = {
	schemaVersion: number, -- 코드가 아는 최신 버전
	purchaseHistoryLimit: number,
	defaultWeaponId: string,
	maxLevel: number,
	isKnownWeapon: (id: string) -> boolean,
}

local function toLevel(value: any, maxLevel: number): number
	local number = tonumber(value) or 0
	if number ~= number then -- NaN
		number = 0
	end
	return math.clamp(math.floor(number), 0, maxLevel)
end

--[[
	데이터가 게임이 기대하는 최소 조건을 만족하게 고친다. 여러 번 불러도 결과가 같다.
	  - 검이 하나도 없으면 기본 검을 준다
	  - 검마다 레벨·최고 레벨이 올바른 범위의 정수다
	  - 착용 검은 반드시 가진 검이다
	  - 소지 상한은 가진 검 수보다 작지 않다
]]
function DataMigration.repair(data: any, options: Options)
	if type(data.swords) ~= "table" then
		data.swords = {}
	end

	local count = 0
	for id, sword in data.swords do
		if type(id) ~= "string" or type(sword) ~= "table" then
			continue
		end

		sword.id = id
		sword.level = toLevel(sword.level, options.maxLevel)
		sword.bestLevel = math.max(toLevel(sword.bestLevel, options.maxLevel), sword.level)
		if sword.customName ~= nil and type(sword.customName) ~= "string" then
			sword.customName = nil
		end
		count += 1
	end

	if count == 0 then
		data.swords[options.defaultWeaponId] = {
			id = options.defaultWeaponId,
			level = 0,
			bestLevel = 0,
		}
		count = 1
	end

	if type(data.equippedId) ~= "string" or data.swords[data.equippedId] == nil then
		if data.swords[options.defaultWeaponId] ~= nil then
			data.equippedId = options.defaultWeaponId
		else
			-- 기본 검이 없는 드문 경우: 이름순으로 첫 검
			local ids: { string } = {}
			for id in data.swords do
				table.insert(ids, id)
			end
			table.sort(ids)
			data.equippedId = ids[1]
		end
	end

	local capacity = tonumber(data.swordCapacity) or 0
	data.swordCapacity = math.max(math.floor(capacity), count)

	local pity = tonumber(data.pityPoints) or 0
	data.pityPoints = math.max(0, math.floor(pity))
end

--[[
	저장된 데이터를 현재 스키마로 올린다. data 를 직접 고치고 그대로 돌려준다.
	두 번째 반환값은 "코드보다 새 버전으로 저장된 데이터"일 때 true 다(건드리지 않는다).
]]
function DataMigration.migrate(data: any, options: Options): (any, boolean)
	if data.schemaVersion == nil then
		data.schemaVersion = 1
	end

	if data.schemaVersion > options.schemaVersion then
		-- 더 새로운 버전으로 저장된 데이터. 덮어쓰면 손실이 나므로 건드리지 않는다.
		return data, true
	end

	-- v1 → v2: purchaseHistory 를 딕셔너리에서 배열로 옮긴다.
	-- (배열이어야 오래된 기록부터 버려 크기를 일정하게 유지할 수 있다)
	if data.schemaVersion == 1 then
		local history = data.purchaseHistory
		local migrated: { string } = {}

		if type(history) == "table" then
			for key, value in history do
				if type(key) == "string" and value == true then
					table.insert(migrated, key)
				elseif type(value) == "string" then
					table.insert(migrated, value) -- 이미 배열인 경우
				end
			end
		end

		while #migrated > options.purchaseHistoryLimit do
			table.remove(migrated, 1)
		end

		data.purchaseHistory = migrated
		data.schemaVersion = 2
	end

	-- v2 → v3: 업적 판정에 쓰던 통계를 추가했다. (업적은 지금 쓰지 않지만 필드는 남긴다)
	if data.schemaVersion == 2 then
		if type(data.stats) ~= "table" then
			data.stats = {}
		end
		data.stats.keepStreak = data.stats.keepStreak or 0
		data.stats.bestKeepStreak = data.stats.bestKeepStreak or 0
		data.stats.ticketsUsed = data.stats.ticketsUsed or 0
		data.schemaVersion = 3
	end

	-- v3 → v4: 무기 하나(weapon) → 검 여러 개(swords).
	-- 기존 weapon 을 첫 번째 검으로 옮기고 그 검을 착용한다. weapon 필드는 지우지 않는다.
	if data.schemaVersion == 3 then
		local old = data.weapon
		local swords: { [string]: any } = {}

		if type(old) == "table" then
			local id = options.defaultWeaponId
			if type(old.id) == "string" and options.isKnownWeapon(old.id) then
				id = old.id
			end

			local level = toLevel(old.level, options.maxLevel)
			-- v3 까지는 무기가 하나뿐이었으므로 "역대 최고 레벨"이 곧 이 검의 최고 레벨이다.
			local highest = if type(data.stats) == "table" then data.stats.highestLevel else 0

			swords[id] = {
				id = id,
				level = level,
				bestLevel = math.max(level, toLevel(highest, options.maxLevel)),
				customName = if type(old.customName) == "string" then old.customName else nil,
			}
			data.equippedId = id
		end

		data.swords = swords
		data.swordCapacity = 1
		data.pityPoints = 0
		data.schemaVersion = 4
	end

	DataMigration.repair(data, options)

	return data, false
end

return DataMigration
