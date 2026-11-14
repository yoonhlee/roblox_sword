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
	pityPoints: number, -- 방지권 확률형 상품의 천장 포인트 (꽝 1점, 3점이면 방지권 1개 후 0)
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

--------------------------------------------------------------------------------
-- 추격 생존 경주 (통합 기획서 4절)
--------------------------------------------------------------------------------

-- 경주에 함께 나간 사람 한 명 (다른 참가자에게 보여 주는 정보)
export type RaceEntrant = {
	userId: number,
	name: string,
	level: number, -- 출발할 때의 착용 검 레벨
}

-- 최종 순위표의 한 줄
export type RaceRankingRow = {
	rank: number,
	userId: number,
	name: string,
	level: number,
	distance: number, -- 서버가 인정한 거리(칸, 내림)
}

--[[
	서버가 RaceUpdate 이벤트로 보내는 알림. kind 로 구분한다.
	여기 있는 거리·보상·순위는 전부 서버가 계산한 값이다. 클라이언트는 표시만 한다.

	  queue      대기열 상태. queued=false 면 대기열에서 빠졌다는 뜻
	  lineup     출발선에 섰다. countdown 초 뒤에 출발
	  start      출발
	  eliminated 누군가(나 포함) 탈락했다
	  result     내 결과 (탈락한 순간 보상이 이미 지급됐다)
	  finished   모두 탈락해 판이 끝났다. returnIn 초 뒤 로비로 돌아간다
	  lobby      로비로 돌아왔다
]]
export type RaceUpdate = {
	kind: string,
	raceId: number?,

	-- queue
	queued: boolean?,
	count: number?, -- 대기 인원
	secondsLeft: number?, -- 출발 신호까지 남은 시간(초)

	-- lineup
	countdown: number?,
	originX: number?, -- 코스 출발선의 위치 (화면 표시용)
	originZ: number?,
	level: number?,
	speed: number?,
	maxDistance: number?,
	entrants: { RaceEntrant }?,

	-- eliminated / result
	userId: number?,
	rank: number?,
	distance: number?,
	reward: number?,
	bonus: number?, -- 1~3위 보너스 (미정 D6, 지금은 항상 0)
	racerCount: number?,

	-- finished
	ranking: { RaceRankingRow }?,
	returnIn: number?,
}

-- 서버가 TreadmillUpdate 이벤트로 보내는 트레드밀 상태
export type TreadmillUpdate = {
	onPad: boolean,
	progress: number, -- 이번 지급까지 채운 시간(초)
	interval: number, -- 몇 초마다
	gold: number, -- 몇 골드
	paid: number, -- 방금 지급된 골드 (없으면 0)
}

--------------------------------------------------------------------------------
-- 상점 (통합 기획서 7절)
--------------------------------------------------------------------------------

-- 뽑기 결과 한 줄. percent 는 화면에 보여 주는 값이며 한 목록의 합이 정확히 100 이다.
export type ShopOutcome = {
	tickets: number, -- 0 이면 꽝
	percent: number,
}

-- 상점에 보여 줄 항목 (클라이언트는 상품 ID 를 알 필요가 없다)
export type ShopItem = {
	key: string,
	kind: string, -- "fixed" | "random"
	ticketAmount: number, -- fixed 일 때 받는 방지권 수
	outcomes: { ShopOutcome }, -- random 일 때 모든 결과와 확률
}

export type ShopShardDraw = {
	cost: number, -- 1회에 드는 파편
	outcomes: { ShopOutcome },
}

--[[
	상점 화면에 필요한 것 전부. 아직 등록되지 않았거나 내용이 비어 있는 상품은 들어 있지 않다.
	유료 확률형이 제한된 유저(PolicyService)에게는 확률형 상품이 들어 있지 않다.
	천장 포인트의 현재 값은 복제받은 PlayerData.pityPoints 를 쓴다.
]]
export type ShopState = {
	items: { ShopItem },
	pityPerMiss: number,
	pityThreshold: number,
	pityTickets: number,
	shardDraw: ShopShardDraw?, -- 확률이 아직 없으면 nil
}

export type ShardDrawSuccess = {
	ok: true,
	tickets: number, -- 이번에 얻은 방지권 (0 이면 꽝)
	shards: number, -- 남은 파편
}

export type ShardDrawResponse = ShardDrawSuccess | Failure

return Types
