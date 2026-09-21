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
	SellWeapon = "SellWeapon", -- 무기 판매 → 골드 지급
	BuyProtectTicket = "BuyProtectTicket", -- 파편 → 방지권 교환
	RenameWeapon = "RenameWeapon", -- 무기 이름 변경(필터링 후 저장)
	GetOdds = "GetOdds", -- 현재 레벨 기준 최종 확률표 조회
	ChallengeBattle = "ChallengeBattle", -- 배틀 도전 신청
	RespondBattle = "RespondBattle", -- 도전 수락/거절
	SetSetting = "SetSetting", -- 사운드/언어 설정 변경
}

-- RemoteEvent: 서버가 밀어 주는 것 (클라이언트→서버 방향은 원칙적으로 쓰지 않음)
Remotes.Events = {
	DataChanged = "DataChanged", -- 프로필 변경분 복제
	BattleInvite = "BattleInvite", -- 도전 도착 알림
	BattleResolved = "BattleResolved", -- 배틀 결과 연출용
	FeedMessage = "FeedMessage", -- 결과 피드 한 줄
	LiveOpsChanged = "LiveOpsChanged", -- 이벤트/점검 상태 변경
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
