--!strict
--[[
	Types — 서버/클라이언트가 공유하는 데이터 타입 정의.
	여기 있는 타입은 저장 스키마(ProfileStore)와 리모트 페이로드의 계약이다.
	스키마를 바꾸면 SCHEMA_VERSION 을 올리고 Pure/DataMigration 에 단계를 추가할 것.

	"사용 안 함" 이라고 적힌 필드는 기획에서 빠진 기능(1:1 배틀, 업적)이나 옛 구조가
	쓰던 것이다. 저장된 데이터를 지우지 않기 위해 남겨 두고, 코드는 읽지도 쓰지도 않는다.
]]

local Types = {}

-- 현재 저장 스키마 버전. PlayerData.schemaVersion 의 기준값.
-- v4: 무기 하나(weapon) → 검 여러 개(swords, equippedId, swordCapacity), 천장 포인트 추가
Types.SCHEMA_VERSION = 4

-- 가진 검 하나의 상태
export type SwordState = {
	id: string, -- Config/Weapons 의 키 (swords 표의 키와 같다)
	level: number, -- 0 ~ EnhanceTable.MAX_LEVEL
	bestLevel: number, -- 이 검의 역대 최고 레벨 (10강으로 돌아가도 유지, 도감에 표시)
	customName: string?, -- 필터링을 통과한 이름만 저장
}

-- v3 까지 쓰던 "무기 하나" 구조
export type LegacyWeaponState = {
	id: string,
	level: number,
	customName: string?,
}

export type PlayerStats = {
	enhanceTries: number,
	enhanceSuccess: number,
	destroyed: number, -- 2구간 실패 횟수 (이름은 옛 "파괴" 시절 것을 그대로 쓴다)
	highestLevel: number, -- 모든 검을 통틀어 역대 최고 레벨 (랭킹)
	battleWins: number, -- 사용 안 함 (1:1 배틀 폐지)
	battleLosses: number, -- 사용 안 함 (1:1 배틀 폐지)
	rating: number, -- 사용 안 함 (1:1 배틀 폐지)
	keepStreak: number, -- 사용 안 함 (업적 삭제)
	bestKeepStreak: number, -- 사용 안 함 (업적 삭제)
	ticketsUsed: number, -- 사용 안 함 (업적 삭제)
}

export type DailyState = {
	lastLoginDay: number, -- UTC 기준 일자 (os.time() // 86400)
	streak: number,
	battlesToday: number, -- 사용 안 함 (1:1 배틀 폐지)
	opponentsToday: { [string]: number }, -- 사용 안 함 (1:1 배틀 폐지)
}

export type PlayerSettings = {
	sfx: boolean,
	language: string,
}

export type PlayerData = {
	schemaVersion: number,
	gold: number,
	shards: number, -- 2구간 실패 시 얻는 보조 재화
	swords: { [string]: SwordState }, -- 검 id → 상태. 같은 검을 두 개 가질 수 없다
	equippedId: string, -- 착용 중인 검의 id (반드시 swords 에 있다)
	swordCapacity: number, -- 소지 상한 (골드로 1칸씩 산다)
	pityPoints: number, -- 방지권 확률형 상품의 천장 포인트 (상품은 아직 없다)
	weapon: LegacyWeaponState?, -- 사용 안 함 (v3 까지의 무기. v4 에서 swords 로 옮겼다)
	protectTickets: number, -- 방지권
	stats: PlayerStats,
	codex: { [string]: boolean }, -- "검id:구간" 달성 여부 (구간 = 5, 10, 15, 20)
	achievements: { [string]: boolean }, -- 사용 안 함 (업적 삭제)
	daily: DailyState,
	-- ProcessReceipt 중복 지급 방지용 PurchaseId 목록.
	-- 배열인 이유: 오래된 것부터 버려서 크기를 일정하게 유지해야 하기 때문이다.
	-- (스키마 v1 에서는 { [id]: true } 딕셔너리였고 v2 에서 배열로 옮겼다)
	purchaseHistory: { string },
	settings: PlayerSettings,
	bannedUntil: number?,
}

-- 서버 함수의 공통 반환 형태. 실패는 에러 대신 ok=false 로 돌려준다.
export type Failure = {
	ok: false,
	reason: string,
}

export type Success = { ok: true }

-- 결과에 따로 실어 보낼 값이 없는 요청의 응답
export type SimpleResponse = Success | Failure

--[[
	강화 화면에 노출하는 확률 (착용 검 기준, 이벤트 버프 반영 후, 퍼센트 단위).
	방지권을 켰을 때의 표시(실패 0, 유지 + 실패)는 클라이언트가
	Pure/EnhanceLogic.applyProtect 로 바꿔서 보여 준다.
]]
export type DisplayOdds = {
	level: number,
	success: number,
	keep: number,
	fail: number,
	cost: number, -- 0 이면 최대 레벨
	eventName: string?, -- 적용 중인 확률 버프 이벤트 이름(로컬라이즈 키)
}

export type EnhanceOutcome = "success" | "keep" | "fail" | "protected"

export type EnhanceSuccess = {
	ok: true,
	result: EnhanceOutcome,
	newLevel: number,
	gold: number,
	shardsGained: number,
	odds: DisplayOdds, -- 새 레벨 기준 확률. 클라이언트가 다시 물어보지 않아도 되도록 같이 보낸다.
}

export type EnhanceResponse = EnhanceSuccess | Failure

export type RenameSuccess = {
	ok: true,
	name: string, -- 필터링을 통과한 이름 (표시할 때도 이 값을 쓴다)
}

export type RenameResponse = RenameSuccess | Failure

export type EquipSuccess = {
	ok: true,
	swordId: string,
	odds: DisplayOdds, -- 새로 착용한 검 기준 확률
}

export type EquipResponse = EquipSuccess | Failure

-- 소지 상한 1칸 구매 + 새 검 뽑기 1회의 결과
export type DrawSuccess = {
	ok: true,
	swordId: string, -- 뽑힌 검
	pricePaid: number,
	gold: number,
	odds: DisplayOdds, -- 검 수가 늘어 강화 비용이 바뀌므로 다시 보낸다
}

export type DrawResponse = DrawSuccess | Failure

export type LeaderboardEntry = {
	rank: number,
	userId: number,
	name: string,
	value: number,
}

-- 상점에 보여 줄 항목 (클라이언트는 상품 ID 를 알 필요가 없다)
export type ShopItem = {
	key: string,
	ticketAmount: number,
}

return Types
