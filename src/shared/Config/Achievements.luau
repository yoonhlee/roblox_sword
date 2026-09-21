--!strict
--[[
	Achievements — 업적 정의.

	각 업적은 PlayerData 만 보고 달성 여부를 판단하는 순수 함수(check)를 가진다.
	서버가 강화/배틀 직후에 전부 한 번씩 돌려 보고, 새로 달성된 것만 보상을 준다.

	표시 문자열은 Locale 의 "achv.<id>.name" / "achv.<id>.desc" 키를 쓴다.
]]

export type PlayerDataLike = {
	gold: number,
	shards: number,
	protectTickets: number,
	weapon: { level: number },
	stats: {
		enhanceTries: number,
		enhanceSuccess: number,
		destroyed: number,
		highestLevel: number,
		battleWins: number,
		battleLosses: number,
		rating: number,
		bestKeepStreak: number,
		ticketsUsed: number,
	},
	codex: { [string]: boolean },
	daily: { streak: number },
}

export type Achievement = {
	id: string,
	gold: number,
	check: (data: PlayerDataLike) -> boolean,
}

local function countCodex(data: PlayerDataLike): number
	local count = 0
	for _, unlocked in data.codex do
		if unlocked then
			count += 1
		end
	end
	return count
end

local Achievements = {}

Achievements.List = {
	{
		id = "firstSwing",
		gold = 100,
		check = function(data)
			return data.stats.enhanceTries >= 1
		end,
	},
	{
		id = "firstBreak",
		gold = 200,
		check = function(data)
			return data.stats.destroyed >= 1
		end,
	},
	{
		id = "reach5",
		gold = 300,
		check = function(data)
			return data.stats.highestLevel >= 5
		end,
	},
	{
		id = "reach10",
		gold = 800,
		check = function(data)
			return data.stats.highestLevel >= 10
		end,
	},
	{
		id = "reach15",
		gold = 3000,
		check = function(data)
			return data.stats.highestLevel >= 15
		end,
	},
	{
		id = "reach20",
		gold = 20000,
		check = function(data)
			return data.stats.highestLevel >= 20
		end,
	},
	{
		id = "tries100",
		gold = 400,
		check = function(data)
			return data.stats.enhanceTries >= 100
		end,
	},
	{
		id = "tries1000",
		gold = 2500,
		check = function(data)
			return data.stats.enhanceTries >= 1000
		end,
	},
	{
		id = "break10",
		gold = 600,
		check = function(data)
			return data.stats.destroyed >= 10
		end,
	},
	{
		id = "break50",
		gold = 3000,
		check = function(data)
			return data.stats.destroyed >= 50
		end,
	},
	{
		id = "keepStreak10",
		gold = 1200,
		check = function(data)
			return data.stats.bestKeepStreak >= 10
		end,
	},
	{
		-- 방지권을 한 번도 쓰지 않고 15강에 도달
		id = "pureFifteen",
		gold = 5000,
		check = function(data)
			return data.stats.highestLevel >= 15 and data.stats.ticketsUsed == 0
		end,
	},
	{
		id = "firstBattle",
		gold = 100,
		check = function(data)
			return data.stats.battleWins + data.stats.battleLosses >= 1
		end,
	},
	{
		id = "win10",
		gold = 500,
		check = function(data)
			return data.stats.battleWins >= 10
		end,
	},
	{
		id = "win100",
		gold = 4000,
		check = function(data)
			return data.stats.battleWins >= 100
		end,
	},
	{
		id = "rating1200",
		gold = 2000,
		check = function(data)
			return data.stats.rating >= 1200
		end,
	},
	{
		id = "streak7",
		gold = 1500,
		check = function(data)
			return data.daily.streak >= 7
		end,
	},
	{
		id = "hoard100k",
		gold = 2000,
		check = function(data)
			return data.gold >= 100000
		end,
	},
	{
		id = "shards1000",
		gold = 1000,
		check = function(data)
			return data.shards >= 1000
		end,
	},
	{
		id = "codex10",
		gold = 1500,
		check = function(data)
			return countCodex(data) >= 10
		end,
	},
} :: { Achievement }

function Achievements.count(): number
	return #Achievements.List
end

return Achievements
