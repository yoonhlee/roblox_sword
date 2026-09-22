--!strict
--[[
	Game — 게임 정체성과 운영에 필요한 전역 상수.
]]

local Game = {}

Game.NAME = "강화의 대장간" -- 표시용 이름은 LocalizationTable 의 "game.title" 을 우선 사용
Game.ID = "ForgeFever" -- 코드/스토어 키에 쓰는 내부 식별자

-- DataStore 이름. Studio 플레이테스트와 라이브 데이터를 절대 섞지 않는다.
Game.DATASTORE_DEV = "ForgeFever_DEV"
Game.DATASTORE_PROD = "ForgeFever_PROD"

-- 랭킹용 OrderedDataStore
Game.ORDERED_STORE_LEVEL = "ForgeFever_Level_v1"
Game.ORDERED_STORE_RATING = "ForgeFever_Rating_v1"

-- 관리자 UserId 목록. [개발자 입력 필요] 본인 UserId 를 넣을 것.
Game.ADMIN_USER_IDS = {} :: { number }

-- 결과 피드를 말하는 오리지널 NPC (대사는 LocalizationTable 의 "npc.*" 키)
Game.NPC_NAME_KEY = "npc.anvilElder.name" -- 모루 영감

Game.DEFAULT_LANGUAGE = "ko"
Game.SUPPORTED_LANGUAGES = { "ko", "en" }

function Game.isAdmin(userId: number): boolean
	for _, id in Game.ADMIN_USER_IDS do
		if id == userId then
			return true
		end
	end
	return false
end

return Game
