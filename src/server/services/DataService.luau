--!strict
--[[
	DataService — 플레이어 데이터의 단일 진입점.

	ProfileStore 로 세션 락이 걸린 프로필을 열고, 다른 서비스는 전부
	이 모듈을 통해서만 데이터를 읽고 쓴다.

	중요한 규칙:
	- 로드에 실패하면 기본값으로 덮어쓰지 않고 Kick 한다. (데이터 유실 방지)
	- Studio 는 _DEV 스토어, 라이브는 _PROD 스토어를 쓴다. 절대 섞지 않는다.
	- 서버 종료 시 저장 대기는 ProfileStore 가 내부 game:BindToClose 에서
	  모든 활성 프로필의 저장이 끝날 때까지 기다린다. 여기서 따로 BindToClose 를
	  걸면 같은 일을 두 번 하게 되므로 걸지 않는다.
	- getActiveData() 로 받은 테이블은 "yield 하지 않고" 즉시 수정해야 한다.
	  (task.wait, WaitForChild 등을 끼우면 그 사이 세션이 끝날 수 있다)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Locale = require(Shared:WaitForChild("Locale"))

local ConfigFolder = Shared:WaitForChild("Config")
local GameConfig = require(ConfigFolder:WaitForChild("Game"))
local EconomyConfig = require(ConfigFolder:WaitForChild("EconomyConfig"))
local Weapons = require(ConfigFolder:WaitForChild("Weapons"))

local DataService = {}
DataService.Name = "DataService"

-- ProfileStore 는 require 로 가져오므로 정적 타입이 붙지 않는다.
type Profile = any

local profiles: { [Player]: Profile } = {}
local loadedListeners: { (player: Player, data: Types.PlayerData) -> () } = {}
local unloadingListeners: { (player: Player, data: Types.PlayerData) -> () } = {}

local playerStore: any = nil
local dataChangedRemote: RemoteEvent? = nil

--[[
	ProfileStore 모듈을 가져온다.
	설치가 안 되어 있으면 무엇을 해야 하는지 알려 주고 멈춘다
	(WaitForChild 로 조용히 영원히 기다리면 원인을 찾기 어렵다).
]]
local function requireProfileStore(): any
	local packages = ServerStorage:FindFirstChild("ServerPackages")
	local module = packages and packages:FindFirstChild("ProfileStore")

	if not module or not module:IsA("ModuleScript") then
		error(
			"[DataService] ProfileStore 모듈을 찾을 수 없습니다.\n"
				.. "저장소 루트에서 `wally install` 을 실행한 뒤 Rojo 로 다시 동기화해 주세요.\n"
				.. "(ServerStorage/ServerPackages/ProfileStore 위치에 있어야 합니다)",
			0
		)
	end

	return require(module)
end

-- 새 플레이어의 기본 데이터. ProfileStore 가 이 표를 깊은 복사해서 쓴다.
local function buildTemplate(): Types.PlayerData
	return {
		schemaVersion = Types.SCHEMA_VERSION,
		gold = EconomyConfig.STARTING_GOLD,
		shards = EconomyConfig.STARTING_SHARDS,
		weapon = {
			id = Weapons.DEFAULT_ID,
			level = 0,
		},
		protectTickets = EconomyConfig.STARTING_PROTECT_TICKETS,
		stats = {
			enhanceTries = 0,
			enhanceSuccess = 0,
			destroyed = 0,
			highestLevel = 0,
			battleWins = 0,
			battleLosses = 0,
			rating = 1000,
		},
		codex = {},
		achievements = {},
		daily = {
			lastLoginDay = 0,
			streak = 0,
			battlesToday = 0,
			opponentsToday = {},
		},
		purchaseHistory = {},
		settings = {
			sfx = true,
			language = GameConfig.DEFAULT_LANGUAGE,
		},
	}
end

--[[
	저장된 데이터를 현재 스키마로 올린다.
	Reconcile() 이 "빠진 키 채우기"를 담당하고, 여기서는 "형태가 바뀐 값"을 옮긴다.
	기존 데이터를 절대 버리지 않는다.
]]
local function migrate(data: Types.PlayerData): Types.PlayerData
	if data.schemaVersion == nil then
		data.schemaVersion = 1
	end

	-- 스키마 버전을 올릴 때마다 아래에 단계를 하나씩 추가한다.
	-- 예시)
	-- if data.schemaVersion == 1 then
	--     data.newField = 계산값
	--     data.schemaVersion = 2
	-- end

	if data.schemaVersion > Types.SCHEMA_VERSION then
		-- 더 새로운 버전으로 저장된 데이터. 덮어쓰면 손실이 나므로 건드리지 않는다.
		warn(
			`[DataService] 저장된 스키마 버전({data.schemaVersion})이 코드 버전({Types.SCHEMA_VERSION})보다 높습니다`
		)
	end

	return data
end

local function fire(listeners: { (Player, Types.PlayerData) -> () }, player: Player, data: Types.PlayerData)
	for _, listener in listeners do
		local ok, err = xpcall(listener, debug.traceback, player, data)
		if not ok then
			warn(`[DataService] 리스너 오류:\n{err}`)
		end
	end
end

--[[
	클라이언트에 현재 데이터를 보낸다.
	RemoteEvent 로 보내는 순간 테이블이 복사되므로 서버 테이블이 노출되지는 않는다.
]]
function DataService.replicate(player: Player)
	local profile = profiles[player]
	if not profile or not dataChangedRemote then
		return
	end
	dataChangedRemote:FireClient(player, profile.Data)
end

-- 세션이 살아 있을 때만 데이터를 준다. 반환값은 yield 없이 즉시 수정할 것.
function DataService.getActiveData(player: Player): Types.PlayerData?
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return nil
	end
	return profile.Data
end

-- 읽기 전용 용도(세션이 끝나가는 중일 수도 있음)
function DataService.getData(player: Player): Types.PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService.isReady(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile:IsActive()
end

function DataService.getProfile(player: Player): Profile
	return profiles[player]
end

-- 구매 등 중요한 변경 직후 즉시 저장하고 싶을 때만 쓴다(DataStore 호출 1회).
function DataService.saveNow(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile:Save()
	end
end

function DataService.onLoaded(listener: (player: Player, data: Types.PlayerData) -> ())
	table.insert(loadedListeners, listener)

	-- 이미 로드된 플레이어에게도 바로 알려 준다(서비스 등록 순서에 의존하지 않도록).
	for player, profile in profiles do
		task.spawn(listener, player, profile.Data)
	end
end

function DataService.onUnloading(listener: (player: Player, data: Types.PlayerData) -> ())
	table.insert(unloadingListeners, listener)
end

function DataService.getAllActive(): { [Player]: Types.PlayerData }
	local result: { [Player]: Types.PlayerData } = {}
	for player, profile in profiles do
		if profile:IsActive() then
			result[player] = profile.Data
		end
	end
	return result
end

local function onPlayerAdded(player: Player)
	local profile = playerStore:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- 다른 서버가 동시에 같은 프로필 세션을 잡으려 한 드문 경우.
		player:Kick(Locale.get(nil, "error.load_fail"))
		return
	end

	profile:AddUserId(player.UserId) -- GDPR: 데이터 삭제 요청 대응
	profile:Reconcile() -- 템플릿에 새로 생긴 키 채우기
	migrate(profile.Data)

	profile.OnSessionEnd:Connect(function()
		local data = profiles[player] and profiles[player].Data
		profiles[player] = nil
		if data then
			fire(unloadingListeners, player, data)
		end
		player:Kick(Locale.get(nil, "error.session_end"))
	end)

	if player.Parent ~= Players then
		-- 로드되는 사이에 나갔다.
		profile:EndSession()
		return
	end

	local data = profile.Data :: Types.PlayerData

	-- 차단 확인은 로드 직후에 한다.
	if data.bannedUntil ~= nil and data.bannedUntil > os.time() then
		profile:EndSession()
		player:Kick(Locale.get(data.settings and data.settings.language, "error.banned"))
		return
	end

	profiles[player] = profile

	fire(loadedListeners, player, data)
	DataService.replicate(player)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end

	fire(unloadingListeners, player, profile.Data)
	profile:EndSession()
	profiles[player] = nil
end

function DataService.Init()
	local ProfileStore = requireProfileStore()

	local storeName = if RunService:IsStudio()
		then GameConfig.DATASTORE_DEV
		else GameConfig.DATASTORE_PROD

	playerStore = ProfileStore.New(storeName, buildTemplate())

	ProfileStore.OnError:Connect(function(message: string, storeName_: string, profileKey: string)
		warn(`[DataService] DataStore 오류 (store={storeName_}, key={profileKey}): {message}`)
	end)

	ProfileStore.OnCriticalToggle:Connect(function(isCritical: boolean)
		if isCritical then
			warn("[DataService] DataStore 가 불안정한 상태입니다")
		else
			print("[DataService] DataStore 가 정상으로 돌아왔습니다")
		end
	end)

	local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	dataChangedRemote = remotesFolder:WaitForChild(Remotes.Events.DataChanged) :: RemoteEvent

	print(`[DataService] 스토어 "{storeName}" 사용`)
end

function DataService.Start()
	-- 이 스크립트보다 먼저 들어온 플레이어도 처리한다.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return DataService
