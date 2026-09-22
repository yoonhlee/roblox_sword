--!strict
--[[
	Weapons — 무기 종류 데이터. 전부 오리지널 명칭이며, 표시 문자열은
	LocalizationTable 키로만 참조한다(코드에 표시용 한국어를 박지 않는다).

	assetId 는 Studio 에서 만든 모델의 키. 모델 연결 전에는 빈 문자열로 두고
	클라이언트는 기본 외형으로 대체한다.
]]

export type WeaponInfo = {
	id: string,
	nameKey: string, -- LocalizationTable 키
	rarity: "common" | "rare" | "epic" | "legend",
	assetId: string, -- ReplicatedStorage 내 모델 이름 (비어 있으면 기본 외형)
	unlockLevel: number, -- 이 무기를 쓰려면 필요한 최고 강화 기록
}

local Weapons = {}

Weapons.DEFAULT_ID = "ironBlade"

Weapons.List = {
	ironBlade = {
		id = "ironBlade",
		nameKey = "weapon.ironBlade.name",
		rarity = "common",
		assetId = "",
		unlockLevel = 0,
	},
	emberEdge = {
		id = "emberEdge",
		nameKey = "weapon.emberEdge.name",
		rarity = "rare",
		assetId = "",
		unlockLevel = 5,
	},
	tideFang = {
		id = "tideFang",
		nameKey = "weapon.tideFang.name",
		rarity = "rare",
		assetId = "",
		unlockLevel = 8,
	},
	stormNeedle = {
		id = "stormNeedle",
		nameKey = "weapon.stormNeedle.name",
		rarity = "epic",
		assetId = "",
		unlockLevel = 12,
	},
	dawnbreaker = {
		id = "dawnbreaker",
		nameKey = "weapon.dawnbreaker.name",
		rarity = "legend",
		assetId = "",
		unlockLevel = 16,
	},
} :: { [string]: WeaponInfo }

-- 도감이 기록하는 레벨 구간
Weapons.CODEX_MILESTONES = { 5, 10, 15, 20 }

function Weapons.get(id: string): WeaponInfo?
	return Weapons.List[id]
end

return Weapons
