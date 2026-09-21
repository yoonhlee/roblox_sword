--!strict
--[[
	Types — 서버/클라이언트가 공유하는 데이터 타입 정의.
	여기 있는 타입은 저장 스키마(ProfileStore)와 리모트 페이로드의 계약이다.
	스키마를 바꾸면 SCHEMA_VERSION 을 올리고 DataService 에 마이그레이션을 추가할 것.
]]

local Types = {}

-- 현재 저장 스키마 버전. PlayerData.schemaVersion 의 기준값.
Types.SCHEMA_VERSION = 1

export type WeaponState = {
	id: string, -- Config/Weapons 의 키
	level: number, -- 0 ~ EnhanceTable.MAX_LEVEL
	customName: string?, -- 필터링을 통과한 이름만 저장
}

export type PlayerStats = {
	enhanceTries: number,
	enhanceSuccess: number,
	destroyed: number,
	highestLevel: number,
	battleWins: number,
	battleLosses: number,
	rating: number, -- 배틀 레이팅, 시작 1000
}

export type DailyState = {
	lastLoginDay: number, -- UTC 기준 일자 (os.time() // 86400)
	streak: number,
	battlesToday: number,
	opponentsToday: { [string]: number }, -- userId(문자열) → 오늘 보상 지급 횟수
}

export type PlayerSettings = {
	sfx: boolean,
	language: string,
}

export type PlayerData = {
	schemaVersion: number,
	gold: number,
	shards: number, -- 파괴 시 얻는 보조 재화
	weapon: WeaponState,
	protectTickets: number, -- 파괴 방지권
	stats: PlayerStats,
	codex: { [string]: boolean }, -- "weaponId:level" 달성 여부
	achievements: { [string]: boolean },
	daily: DailyState,
	purchaseHistory: { [string]: boolean }, -- ProcessReceipt 중복 방지 (PurchaseId)
	settings: PlayerSettings,
	bannedUntil: number?,
}

-- 서버 함수의 공통 반환 형태. 실패는 에러 대신 ok=false 로 돌려준다.
export type Failure = {
	ok: false,
	reason: string,
}

-- 강화 화면에 노출하는 확률(버프 반영 후 최종값, 퍼센트 단위)
export type DisplayOdds = {
	level: number,
	success: number,
	keep: number,
	destroy: number,
	cost: number,
	eventName: string?, -- 적용 중인 확률 버프 이벤트 이름(로컬라이즈 키)
}

export type EnhanceOutcome = "success" | "keep" | "destroy" | "protected"

export type EnhanceSuccess = {
	ok: true,
	result: EnhanceOutcome,
	newLevel: number,
	gold: number,
	shardsGained: number,
	odds: DisplayOdds, -- 새 레벨 기준 확률. 클라이언트가 다시 물어보지 않아도 되도록 같이 보낸다.
}

export type EnhanceResponse = EnhanceSuccess | Failure

export type SellSuccess = {
	ok: true,
	goldGained: number,
	gold: number,
	odds: DisplayOdds,
}

export type SellResponse = SellSuccess | Failure

export type BattleOutcomeSide = "win" | "loss"

export type BattleResult = {
	ok: true,
	outcome: BattleOutcomeSide,
	goldGained: number,
	ratingBefore: number,
	ratingAfter: number,
	rewardCapped: boolean, -- 일일 보상 한도 초과로 보상이 0인 경우 true
}

export type BattleResponse = BattleResult | Failure

return Types
