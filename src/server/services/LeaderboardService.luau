--!strict
--[[
	LeaderboardService — 전체 순위 (최고 강화 레벨 / 배틀 레이팅).

	OrderedDataStore 는 호출 예산이 빠듯해서 아무 때나 쓰면 안 된다.
	그래서 쓰기는 두 경우로 제한한다.
	  - 플레이어가 나갈 때 (그 사람 것 1건)
	  - 5분 주기로 접속 중인 사람들 (값이 바뀐 사람만)

	쓰기 전에는 항상 DataStoreService:GetRequestBudgetForRequestType 으로
	남은 예산을 확인하고, 모자라면 이번 차례를 건너뛴다.
	순위표가 조금 늦게 갱신되는 건 괜찮지만, 예산이 바닥나면
	데이터 저장까지 영향을 받기 때문이다.

	읽기는 60초 동안 캐시해서 같은 서버의 여러 사람이 눌러도 한 번만 조회한다.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("Game"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local LeaderboardService = {}
LeaderboardService.Name = "LeaderboardService"

local TOP_COUNT = 50
local WRITE_INTERVAL_SECONDS = 300
local CACHE_SECONDS = 60
local MIN_BUDGET = 10 -- 이만큼은 남겨 둔다

type BoardKind = "level" | "rating"

local stores: { [string]: OrderedDataStore } = {}

-- 마지막으로 써 넣은 값. 바뀌지 않았으면 다시 쓰지 않는다.
local lastWritten: { [string]: { [number]: number } } = {
	level = {},
	rating = {},
}

type Cache = {
	entries: { Types.LeaderboardEntry },
	fetchedAt: number,
}

local caches: { [string]: Cache } = {}
local nameCache: { [number]: string } = {}

local function hasBudget(requestType: Enum.DataStoreRequestType): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(requestType)
	end)
	return ok and budget > MIN_BUDGET
end

local function valueFor(kind: BoardKind, data: Types.PlayerData): number
	if kind == "level" then
		return data.stats.highestLevel
	end
	return data.stats.rating
end

--[[
	한 사람의 점수를 올린다. yield 한다.
	실패해도 게임 진행에는 영향이 없으므로 경고만 남긴다.
]]
local function writeEntry(kind: BoardKind, userId: number, value: number)
	local store = stores[kind]
	if store == nil then
		return
	end

	if lastWritten[kind][userId] == value then
		return -- 바뀐 게 없다
	end

	if not hasBudget(Enum.DataStoreRequestType.SetIncrementSortedAsync) then
		return -- 예산이 모자라면 다음 차례에
	end

	local ok, err = pcall(function()
		store:SetAsync(tostring(userId), value)
	end)

	if ok then
		lastWritten[kind][userId] = value
	else
		warn(`[LeaderboardService] {kind} 순위 기록 실패 ({userId}): {err}`)
	end
end

local function displayName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end

	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)

	local resolved = if ok and type(name) == "string" then name else `#{userId}`
	nameCache[userId] = resolved
	return resolved
end

-- 상위 목록을 읽는다. yield 한다.
local function fetchTop(kind: BoardKind): { Types.LeaderboardEntry }
	local cache = caches[kind]
	if cache and os.clock() - cache.fetchedAt < CACHE_SECONDS then
		return cache.entries
	end

	local store = stores[kind]
	if store == nil then
		return {}
	end

	if not hasBudget(Enum.DataStoreRequestType.GetSortedAsync) then
		return if cache then cache.entries else {}
	end

	local ok, result = pcall(function()
		local pages = store:GetSortedAsync(false, TOP_COUNT) -- 내림차순
		return pages:GetCurrentPage()
	end)

	if not ok then
		warn(`[LeaderboardService] {kind} 순위 조회 실패: {result}`)
		return if cache then cache.entries else {}
	end

	local entries: { Types.LeaderboardEntry } = {}
	for rank, row in result :: { { key: string, value: number } } do
		local userId = tonumber(row.key) or 0
		table.insert(entries, {
			rank = rank,
			userId = userId,
			name = displayName(userId),
			value = row.value,
		})
	end

	caches[kind] = { entries = entries, fetchedAt = os.clock() }
	return entries
end

local function handleGetLeaderboard(_player: Player, kind: any): { Types.LeaderboardEntry }
	if kind ~= "level" and kind ~= "rating" then
		return {}
	end
	return fetchTop(kind)
end

function LeaderboardService.Init()
	local ok, err = pcall(function()
		stores.level = DataStoreService:GetOrderedDataStore(GameConfig.ORDERED_STORE_LEVEL)
		stores.rating = DataStoreService:GetOrderedDataStore(GameConfig.ORDERED_STORE_RATING)
	end)

	if not ok then
		warn(`[LeaderboardService] 순위 저장소를 열지 못했습니다: {err}`)
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	local boardRemote =
		remotesFolder:WaitForChild(Remotes.Functions.GetLeaderboard) :: RemoteFunction
	boardRemote.OnServerInvoke = handleGetLeaderboard
end

function LeaderboardService.Start()
	-- 나갈 때 그 사람 점수만 기록
	DataService.onUnloading(function(player, data)
		task.spawn(function()
			writeEntry("level", player.UserId, valueFor("level", data))
			writeEntry("rating", player.UserId, valueFor("rating", data))
		end)
	end)

	-- 5분 주기로 접속 중인 사람들 기록
	task.spawn(function()
		while true do
			task.wait(WRITE_INTERVAL_SECONDS)

			for player, data in DataService.getAllActive() do
				writeEntry("level", player.UserId, valueFor("level", data))
				writeEntry("rating", player.UserId, valueFor("rating", data))
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastWritten.level[player.UserId] = nil
		lastWritten.rating[player.UserId] = nil
	end)
end

return LeaderboardService
