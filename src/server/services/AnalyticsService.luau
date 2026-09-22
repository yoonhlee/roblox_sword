--!strict
--[[
	AnalyticsService — 경제 이벤트(골드 source/sink)와 퍼널 이벤트를 기록한다.

	지금은 서버 로그(print)로만 남긴다. 중요한 건 "모든 재화 증감이 반드시
	이 모듈을 거친다"는 구조이고, 실제 전송 대상은 나중에 한 곳만 바꾸면 된다.

	[확인 필요 / Phase 4 이후] Roblox 내장 AnalyticsService 의
	LogEconomyEvent 시그니처를 공식 문서에서 확인한 뒤 sendToRoblox() 안에서 연결할 것.
	문서를 확인하기 전에는 추측해서 호출하지 않는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("EconomyConfig"))

local AnalyticsService = {}
AnalyticsService.Name = "AnalyticsService"

export type Currency = "gold" | "shards" | "tickets"

-- 이상 탐지용 누적 기록: userId → { windowStart, gained }
type AnomalyRecord = { windowStart: number, gained: number }
local anomalyByUser: { [number]: AnomalyRecord } = {}

-- 관리자 확인용으로 서버 메모리에 남겨 두는 최근 이상 기록
local anomalyLog: { string } = {}
local MAX_ANOMALY_LOG = 100

local function sendToRoblox(_eventName: string, _payload: { [string]: any })
	-- [확인 필요] 공식 문서 확인 후 Roblox AnalyticsService 호출을 여기에 추가한다.
end

--[[
	재화 증감 기록. amount 가 양수면 획득(source), 음수면 소비(sink).
	reason 은 "enhance_cost", "enhance_destroy_shards", "daily_login" 같은 고정 문자열.
]]
function AnalyticsService.logCurrency(
	player: Player,
	currency: Currency,
	amount: number,
	reason: string,
	balanceAfter: number
)
	if amount == 0 then
		return
	end

	local direction = if amount > 0 then "source" else "sink"
	print(
		`[Economy] {player.UserId} {currency} {direction} {amount} ({reason}) → {balanceAfter}`
	)

	sendToRoblox("currency", {
		userId = player.UserId,
		currency = currency,
		amount = amount,
		reason = reason,
		balanceAfter = balanceAfter,
	})

	if currency == "gold" and amount > 0 then
		AnalyticsService.trackGoldGain(player, amount)
	end
end

-- 튜토리얼/퍼널 단계 기록
function AnalyticsService.logFunnel(player: Player, step: string, detail: { [string]: any }?)
	print(`[Funnel] {player.UserId} {step}`)
	sendToRoblox("funnel", { userId = player.UserId, step = step, detail = detail })
end

-- 강화 결과 분포 기록 (실제 확률이 설계대로 나오는지 라이브에서 확인하기 위함)
function AnalyticsService.logEnhance(player: Player, level: number, outcome: string, cost: number)
	print(`[Enhance] {player.UserId} +{level} → {outcome} (비용 {cost})`)
	sendToRoblox("enhance", {
		userId = player.UserId,
		level = level,
		outcome = outcome,
		cost = cost,
	})
end

--[[
	짧은 시간에 골드가 비정상적으로 늘면 기록해 둔다.
	치트/버그 탐지용이며, 자동으로 제재하지는 않는다(오탐 위험).
]]
function AnalyticsService.trackGoldGain(player: Player, amount: number)
	local now = os.time()
	local record = anomalyByUser[player.UserId]

	if not record or now - record.windowStart > EconomyConfig.ANOMALY_WINDOW_SECONDS then
		record = { windowStart = now, gained = 0 }
		anomalyByUser[player.UserId] = record
	end

	record.gained += amount

	if record.gained >= EconomyConfig.ANOMALY_GOLD_DELTA then
		local message = string.format(
			"[Anomaly] %d 가 %d초 안에 골드 %d 획득",
			player.UserId,
			EconomyConfig.ANOMALY_WINDOW_SECONDS,
			record.gained
		)
		warn(message)
		table.insert(anomalyLog, message)
		if #anomalyLog > MAX_ANOMALY_LOG then
			table.remove(anomalyLog, 1)
		end

		-- 같은 창에서 반복 경고가 쏟아지지 않도록 초기화
		record.windowStart = now
		record.gained = 0
	end
end

-- AdminService 가 조회한다.
function AnalyticsService.getAnomalyLog(): { string }
	return table.clone(anomalyLog)
end

function AnalyticsService.clearPlayer(userId: number)
	anomalyByUser[userId] = nil
end

function AnalyticsService.Init() end

function AnalyticsService.Start()
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		AnalyticsService.clearPlayer(player.UserId)
	end)
end

return AnalyticsService
