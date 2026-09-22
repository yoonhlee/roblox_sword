--!strict
--[[
	simulate_economy — 확률표와 경제 설정을 읽어 강화 비용 구조를 분석한다.

	실행:  lune run tools/simulate_economy

	두 가지 방법을 함께 쓴다.

	1) 정확 계산 (마르코프 연쇄)
	   강화는 "레벨 i 에서 성공하면 i+1, 유지면 i, 파괴면 0" 인 상태 전이다.
	   목표 레벨 T 에 처음 도달할 때까지의 기대 비용은 연립방정식으로 정확히 풀린다.
	       E_i = c_i + p_i·E_{i+1} + q_i·E_i + r_i·E_0   (E_T = 0)
	   각 E_i 를 E_0 의 일차식 A_i + B_i·E_0 로 두고 뒤에서부터 내려오면
	   E_0 = A_0 / (1 - B_0) 로 한 번에 구해진다.
	   → 시뮬레이션보다 빠르고 오차가 없다.

	2) 몬테카를로 (분포용)
	   중앙값과 90퍼센타일은 평균만으로는 알 수 없어서 실제로 굴려 본다.
	   상위 레벨은 기대 시행 횟수가 매우 커서 1인당 시도 상한을 둔다.
]]

local EnhanceTable = require("../src/shared/Config/EnhanceTable")
local EconomyConfig = require("../src/shared/Config/EconomyConfig")
local BattleConfig = require("../src/shared/Config/BattleConfig")
local EnhanceLogic = require("../src/shared/Pure/EnhanceLogic")
local Format = require("../src/shared/Pure/Format")

local MAX = EnhanceTable.MAX_LEVEL

-- 몬테카를로 설정
local PLAYER_COUNT = 20000
local ATTEMPT_CAP = 200000 -- 1인당 강화 시도 상한
local MC_TARGET = 15 -- 이 레벨까지 분포를 낸다

--------------------------------------------------------------------------------
-- 1) 정확 계산
--------------------------------------------------------------------------------

type Weight = (level: number) -> number

--[[
	레벨 0 에서 시작해 target 에 처음 도달할 때까지 쌓이는 값의 기댓값.
	weight(i) 가 "레벨 i 에서 한 번 시도할 때 쌓이는 양"이다.
	  - 비용을 넣으면 기대 소모 골드
	  - 1 을 넣으면 기대 시도 횟수
	  - 파괴 확률을 넣으면 기대 파괴 횟수
]]
local function expectedUntil(target: number, weight: Weight): number
	local a: { [number]: number } = { [target] = 0 }
	local b: { [number]: number } = { [target] = 0 }

	for level = target - 1, 0, -1 do
		local odds = EnhanceTable.Odds[level]
		local p = odds.success / 100
		local q = odds.keep / 100
		local r = odds.destroy / 100

		a[level] = (weight(level) + p * a[level + 1]) / (1 - q)
		b[level] = (p * b[level + 1] + r) / (1 - q)
	end

	return a[0] / (1 - b[0])
end

local function costWeight(level: number): number
	return EnhanceTable.Odds[level].cost
end

local function oneWeight(_level: number): number
	return 1
end

local function destroyWeight(level: number): number
	return EnhanceTable.Odds[level].destroy / 100
end

--[[
	"파괴 방지권을 항상 쓴다"고 가정했을 때의 기댓값.
	방지권이 파괴를 유지로 바꾸므로 파괴 확률이 유지 쪽으로 합쳐지고,
	레벨 0 으로 떨어지는 일이 없어져 식이 훨씬 단순해진다.
	   E = Σ (c_i / p_i)
	방지권 소모 기댓값도 같은 방식으로 Σ (r_i / p_i) 로 구한다.
]]
local function expectedProtected(target: number, weight: Weight): number
	local total = 0

	for level = 0, target - 1 do
		local odds = EnhanceTable.Odds[level]
		local p = odds.success / 100
		total += weight(level) / p
	end

	return total
end

local function ticketWeight(level: number): number
	return EnhanceTable.Odds[level].destroy / 100
end

-- 파괴로 얻는 파편의 기댓값 (파괴는 레벨 i 에서 일어나므로 i^1.5 파편)
local function shardWeight(level: number): number
	local chance = EnhanceTable.Odds[level].destroy / 100
	return chance * EnhanceLogic.shardsFor(level, EnhanceTable.SHARD_EXPONENT)
end

--------------------------------------------------------------------------------
-- 2) 몬테카를로
--------------------------------------------------------------------------------

local function makeRng(seed: number): () -> number
	local state = seed
	return function(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return (state / 4294967296) * 100
	end
end

local function percentile(sorted: { number }, fraction: number): number
	if #sorted == 0 then
		return 0
	end
	local index = math.clamp(math.ceil(#sorted * fraction), 1, #sorted)
	return sorted[index]
end

type Sample = {
	gold: { number },
	destroys: { number },
	reached: number,
}

local function runMonteCarlo(target: number): Sample
	local nextRoll = makeRng(20260921)
	local sample: Sample = { gold = {}, destroys = {}, reached = 0 }

	for _ = 1, PLAYER_COUNT do
		local level = 0
		local spent = 0
		local destroys = 0
		local attempts = 0

		while level < target and attempts < ATTEMPT_CAP do
			local odds = EnhanceTable.Odds[level]
			spent += odds.cost
			attempts += 1

			local outcome = EnhanceLogic.roll(odds, nextRoll())
			if outcome == "success" then
				level += 1
			elseif outcome == "destroy" then
				destroys += 1
				level = 0
			end
		end

		if level >= target then
			sample.reached += 1
			table.insert(sample.gold, spent)
			table.insert(sample.destroys, destroys)
		end
	end

	table.sort(sample.gold)
	table.sort(sample.destroys)
	return sample
end

--------------------------------------------------------------------------------
-- 3) 일일 수입 모델
--------------------------------------------------------------------------------

type Profile = {
	name: string,
	playMinutes: number,
	battlesPerDay: number,
	averageOpponentLevel: number,
}

local function dailyIncome(profile: Profile): number
	-- 출석: 연속 출석 표의 평균
	local loginTotal = 0
	for _, amount in EconomyConfig.DAILY_LOGIN_GOLD do
		loginTotal += amount
	end
	local login = loginTotal / #EconomyConfig.DAILY_LOGIN_GOLD

	-- 플레이 시간 보상
	local intervals =
		math.floor(profile.playMinutes * 60 / EconomyConfig.PLAYTIME_REWARD_INTERVAL_SECONDS)
	local playtime = intervals * EconomyConfig.PLAYTIME_REWARD_GOLD

	-- 배틀: 비슷한 레벨끼리 붙는다고 보면 승률 50%.
	-- 이기면 base × (1 + 0.1·상대레벨) × 역전배율(=2), 지면 참가 보상.
	local winReward = BattleConfig.BASE_REWARD
		* (1 + BattleConfig.LEVEL_BONUS_PER_LEVEL * profile.averageOpponentLevel)
		* math.min(1 / 0.5, BattleConfig.UPSET_MULTIPLIER_CAP)
	local perBattle = 0.5 * winReward + 0.5 * BattleConfig.LOSER_REWARD
	local battles = math.min(profile.battlesPerDay, BattleConfig.DAILY_BATTLE_REWARD_CAP)
		* perBattle

	return login + playtime + battles
end

--------------------------------------------------------------------------------
-- 출력
--------------------------------------------------------------------------------

local function line(text: string)
	print(text)
end

local function padRight(text: string, width: number): string
	if #text >= width then
		return text
	end
	return text .. string.rep(" ", width - #text)
end

local function padLeft(text: string, width: number): string
	if #text >= width then
		return text
	end
	return string.rep(" ", width - #text) .. text
end

line("")
line("=== 강화의 대장간 · 경제 시뮬레이션 ===")
line("")
line("[1] 레벨 0 에서 각 레벨에 처음 도달할 때까지 (정확 계산)")
line("")
line(
	padRight("목표", 6)
		.. padLeft("기대 골드", 16)
		.. padLeft("기대 시도", 14)
		.. padLeft("기대 파괴", 12)
		.. padLeft("기대 파편", 12)
)
line(string.rep("-", 60))

local expectedGold: { [number]: number } = {}

for target = 1, MAX do
	expectedGold[target] = expectedUntil(target, costWeight)

	line(
		padRight(Format.level(target), 6)
			.. padLeft(Format.comma(expectedGold[target]), 16)
			.. padLeft(Format.comma(expectedUntil(target, oneWeight)), 14)
			.. padLeft(Format.comma(expectedUntil(target, destroyWeight)), 12)
			.. padLeft(Format.comma(expectedUntil(target, shardWeight)), 12)
	)
end

line("")
line("[2] 파괴 방지권을 항상 쓸 때 (정확 계산)")
line("")
line("방지권을 켜 두면 파괴가 유지로 바뀌어 레벨 0 으로 떨어지지 않는다.")
line("대신 방지권을 소모하고, 파괴가 없으니 파편도 들어오지 않는다.")
line(`방지권을 골드로 사면 1개당 {Format.comma(EconomyConfig.PROTECT_TICKET_GOLD_PRICE)} 골드.`)
line("")
line(
	padRight("목표", 6)
		.. padLeft("강화 골드", 14)
		.. padLeft("방지권", 10)
		.. padLeft("방지권 골드", 14)
		.. padLeft("합계 골드", 14)
		.. padLeft("무방지 대비", 12)
)
line(string.rep("-", 72))

local protectedTotal: { [number]: number } = {}

for _, target in { 10, 15, 17, 18, 19, MAX } do
	local gold = expectedProtected(target, costWeight)
	local tickets = expectedProtected(target, ticketWeight)
	local ticketGold = tickets * EconomyConfig.PROTECT_TICKET_GOLD_PRICE
	protectedTotal[target] = gold + ticketGold

	local ratio = expectedGold[target] / protectedTotal[target]

	line(
		padRight(Format.level(target), 6)
			.. padLeft(Format.comma(gold), 14)
			.. padLeft(Format.comma(tickets), 10)
			.. padLeft(Format.comma(ticketGold), 14)
			.. padLeft(Format.comma(protectedTotal[target]), 14)
			.. padLeft(`{Format.comma(ratio)}배`, 12)
	)
end

line("")
line(`[3] 분포 (가상 플레이어 {Format.comma(PLAYER_COUNT)}명, 1인당 시도 상한 {Format.comma(ATTEMPT_CAP)})`)
line("")
line(
	padRight("목표", 6)
		.. padLeft("도달률", 10)
		.. padLeft("중앙값 골드", 16)
		.. padLeft("90% 골드", 16)
		.. padLeft("중앙 파괴", 12)
		.. padLeft("90% 파괴", 12)
)
line(string.rep("-", 72))

for _, target in { 5, 10, 12, MC_TARGET } do
	local sample = runMonteCarlo(target)
	local rate = sample.reached / PLAYER_COUNT

	line(
		padRight(Format.level(target), 6)
			.. padLeft(Format.percent(rate * 100, 1), 10)
			.. padLeft(Format.comma(percentile(sample.gold, 0.5)), 16)
			.. padLeft(Format.comma(percentile(sample.gold, 0.9)), 16)
			.. padLeft(Format.comma(percentile(sample.destroys, 0.5)), 12)
			.. padLeft(Format.comma(percentile(sample.destroys, 0.9)), 12)
	)
end

line("")
line("[4] 일일 수입 기준 도달 예상 일수")
line("")

local profiles: { Profile } = {
	{ name = "가벼운 유저 (30분/일, 10배틀)", playMinutes = 30, battlesPerDay = 10, averageOpponentLevel = 8 },
	{ name = "보통 유저 (1시간/일, 20배틀)", playMinutes = 60, battlesPerDay = 20, averageOpponentLevel = 10 },
	{ name = "헤비 유저 (3시간/일, 30배틀)", playMinutes = 180, battlesPerDay = 30, averageOpponentLevel = 12 },
}

for _, profile in profiles do
	local income = dailyIncome(profile)
	line(`{profile.name} — 하루 약 {Format.comma(income)} 골드`)

	for _, target in { 10, 15, MAX } do
		local bare = expectedGold[target] / income
		local guarded = if protectedTotal[target] then protectedTotal[target] / income else bare

		line(
			`    {Format.level(target)} 도달: 방지권 없이 약 {Format.comma(bare)} 일`
				.. ` / 방지권 쓰면 약 {Format.comma(guarded)} 일 ({Format.comma(guarded / 7)} 주)`
		)
	end
	line("")
end

line("주의: [4] 는 '기대 골드 ÷ 하루 수입' 이라 운에 따른 편차를 담지 못한다.")
line("      실제 체감은 [2] 의 중앙값·90퍼센타일과 함께 봐야 한다.")
line("")
