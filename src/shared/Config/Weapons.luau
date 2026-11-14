--!strict
--[[
	Weapons — 무기 종류 데이터. 전부 오리지널 명칭이며, 표시 문자열은
	Locale 키로만 참조한다(코드에 표시용 한국어를 박지 않는다).

	assetId 는 Studio 에서 만든 모델의 키. 모델 연결 전에는 빈 문자열로 두고
	클라이언트는 기본 외형으로 대체한다.

	[미정 D22] 기본 검(ironBlade)이 common 인 것만 확정이다. 나머지 4종의 등급은
	프로토타입 때 넣은 값이고, 검 20종 목록과 함께 다시 정한다.
]]

export type WeaponInfo = {
	id: string,
	nameKey: string, -- Locale 키
	rarity: "common" | "rare" | "epic" | "legend",
	assetId: string, -- ReplicatedStorage 내 모델 이름 (비어 있으면 기본 외형)
}

local Weapons = {}

Weapons.DEFAULT_ID = "ironBlade"

Weapons.List = {
	ironBlade = {
		id = "ironBlade",
		nameKey = "weapon.ironBlade.name",
		rarity = "common",
		assetId = "",
	},
	emberEdge = {
		id = "emberEdge",
		nameKey = "weapon.emberEdge.name",
		rarity = "rare",
		assetId = "",
	},
	tideFang = {
		id = "tideFang",
		nameKey = "weapon.tideFang.name",
		rarity = "rare",
		assetId = "",
	},
	stormNeedle = {
		id = "stormNeedle",
		nameKey = "weapon.stormNeedle.name",
		rarity = "epic",
		assetId = "",
	},
	dawnbreaker = {
		id = "dawnbreaker",
		nameKey = "weapon.dawnbreaker.name",
		rarity = "legend",
		assetId = "",
	},
} :: { [string]: WeaponInfo }

--[[
	보여 주는 순서(보관함, 도감, 뽑기 확률표). 검을 추가하면 여기에도 넣는다.
	[미정 D22] 기본 20종 중 지금은 5종만 있다. 나머지 15종은 List 와 Order 에 추가만 하면 된다.
]]
Weapons.Order = { "ironBlade", "emberEdge", "tideFang", "stormNeedle", "dawnbreaker" }

Weapons.RARITY_ORDER = { "common", "rare", "epic", "legend" }

-- 새 검 뽑기에서 검 1개당 가중치 (통합 기획서 5-2절). 이미 가진 검은 뽑기에서 빠진다.
Weapons.DRAW_WEIGHTS = {
	common = 10,
	rare = 5,
	epic = 2,
	legend = 0.5,
} :: { [string]: number }

-- 소지 상한 1칸 가격 = SLOT_PRICE_MULTIPLIER × (SLOT_PRICE_LEVEL 강의 강화 비용, 검 수 할증 포함)
Weapons.SLOT_PRICE_LEVEL = 15
Weapons.SLOT_PRICE_MULTIPLIER = 150

--[[
	도감이 기록하는 레벨 구간. 검마다 이 레벨을 처음 달성하면 기록한다.
	[미정 D16] 기념으로 주는 영구 업그레이드의 종류·크기·상한은 아직 정해지지 않았다.
	지금은 달성 기록만 남긴다(codex["검id:구간"]). 수치가 정해지면 그 기록을 읽어 효과를 준다.
]]
Weapons.CODEX_MILESTONES = { 5, 10, 15, 20 }

-- 검 id → 등급 (SwordLogic.buildDrawTable 에 넘기는 모양)
function Weapons.rarityMap(): { [string]: string }
	local map: { [string]: string } = {}
	for id, info in Weapons.List do
		map[id] = info.rarity
	end
	return map
end

function Weapons.get(id: string): WeaponInfo?
	return Weapons.List[id]
end

return Weapons
