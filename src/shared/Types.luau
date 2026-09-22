--!strict
--[[
	Types — 서버/클라이언트가 공유하는 데이터 타입 정의.
	여기 있는 타입은 저장 스키마(ProfileStore)와 리모트 페이로드의 계약이다.
	스키마를 바꾸면 SCHEMA_VERSION 을 올리고 DataService 에 마이그레이션을 추가할 것.
]]

local Types = {}

-- 현재 저장 스키마 버전. PlayerData.schemaVersion 의 기준값.
Types.SCHEMA_VERSION = 3

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
	-- v3 에서 추가된 업적용 통계
	keepStreak: number, -- 현재 연속 "유지" 횟수
	bestKeepStreak: number, -- 최고 연속 "유지" 횟수
	ticketsUsed: number, -- 지금까지 사용한 파괴 방지권 수
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

-- 같은 서버에서 도전할 수 있는 상대 (공개해도 되는 정보만)
export type BattleTarget = {
	userId: number,
	name: string,
	level: number,
	rating: number,
}

export type BattleInvitePayload = {
	challengerUserId: number,
	challengerName: string,
	challengerLevel: number,
	expiresAt: number, -- os.time() 기준
}

-- 배틀이 끝난 뒤 양쪽 클라이언트에 보내는 연출용 정보
export type BattleResultPayload = {
	won: boolean,
	goldGained: number,
	ratingBefore: number,
	ratingAfter: number,
	opponentName: string,
	opponentLevel: number,
	myLevel: number,
	winProbability: number,
	rewardCapped: boolean,
}

export type Success = { ok: true }

export type RenameSuccess = {
	ok: true,
	name: string, -- 필터링을 통과한 이름 (표시할 때도 이 값을 쓴다)
}

export type RenameResponse = RenameSuccess | Failure

export type TicketPurchaseSuccess = {
	ok: true,
	tickets: number,
}

export type TicketPurchaseResponse = TicketPurchaseSuccess | Failure

-- 상점에 보여 줄 항목 (클라이언트는 ID 를 알 필요가 없다)
-- 도감/업적 화면에 보낼 정보
export type CodexEntry = {
	weaponId: string,
	milestone: number,
	unlocked: boolean,
}

export type AchievementEntry = {
	id: string,
	unlocked: boolean,
	gold: number,
}

export type LeaderboardEntry = {
	rank: number,
	userId: number,
	name: string,
	value: number,
}

export type ShopItem = {
	key: string,
	kind: "gamepass" | "product",
	owned: boolean,
	goldAmount: number,
	ticketAmount: number,
}

export type BattleResponse = Success | Failure

return Types
