--!strict
--[[
	Remotes — 리모트 이름을 한 곳에서 관리한다.
	서버는 Build() 로 인스턴스를 만들고, 클라이언트는 Get() 으로 가져온다.
	문자열 리터럴을 코드 여기저기에 흩뿌리지 말 것.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

Remotes.FOLDER_NAME = "Remotes"

-- RemoteFunction: 클라이언트가 요청하고 결과를 기다리는 것
Remotes.Functions = {
	Enhance = "Enhance", -- 강화 1회 요청 → Types.EnhanceResponse
	RenameWeapon = "RenameWeapon", -- 착용 검 이름 변경(필터링 후 저장)
	EquipSword = "EquipSword", -- 착용 검 바꾸기 → Types.EquipResponse
	BuySwordSlot = "BuySwordSlot", -- 소지 상한 1칸 구매 + 새 검 뽑기 1회 → Types.DrawResponse
	GetState = "GetState", -- 접속 직후 현재 데이터 + 확률 조회 (복제 이벤트를 놓쳤을 때의 보정)
	GetOdds = "GetOdds", -- 착용 검 기준 최종 확률 조회
	GetLeaderboard = "GetLeaderboard", -- 랭킹 상위 목록
	GetShopItems = "GetShopItems", -- 상점 목록 조회 → Types.ShopState
	PromptPurchase = "PromptPurchase", -- 구매창 띄우기 요청
	ShardDraw = "ShardDraw", -- 파편으로 방지권 뽑기 1회 → Types.ShardDrawResponse
	SetSetting = "SetSetting", -- 사운드/언어 설정 변경
	JoinRace = "JoinRace", -- 경주 매칭 대기열에 들어가기
	LeaveRaceQueue = "LeaveRaceQueue", -- 매칭 대기 취소
	ReturnToLobby = "ReturnToLobby", -- 탈락 후 관전을 끝내고 로비로
}

-- RemoteEvent: 서버가 밀어 주는 것 (클라이언트→서버 방향은 원칙적으로 쓰지 않음)
Remotes.Events = {
	DataChanged = "DataChanged", -- 프로필 변경분 복제
	FeedMessage = "FeedMessage", -- 결과 피드 한 줄
	LiveOpsChanged = "LiveOpsChanged", -- 이벤트/점검 상태 변경
	RaceUpdate = "RaceUpdate", -- 경주 진행 알림 (Types.RaceUpdate)
	TreadmillUpdate = "TreadmillUpdate", -- 트레드밀 진행 상태 (Types.TreadmillUpdate)
}

-- 서버 전용: 리모트 폴더와 인스턴스를 생성한다.
function Remotes.Build(): Folder
	local existing = ReplicatedStorage:FindFirstChild(Remotes.FOLDER_NAME)
	if existing then
		return existing :: Folder
	end

	local folder = Instance.new("Folder")
	folder.Name = Remotes.FOLDER_NAME

	for _, name in Remotes.Functions do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
	end

	for _, name in Remotes.Events do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end

	folder.Parent = ReplicatedStorage
	return folder
end

-- 클라이언트 전용: 이름으로 리모트를 가져온다(없으면 대기).
function Remotes.Get(name: string): Instance
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME)
	return folder:WaitForChild(name)
end

return Remotes
