--!strict
--[[
	RateLimiter — 플레이어별 요청 속도 제한과 동시 요청 락.

	생명주기(Init/Start)가 없는 유틸 모듈이라 부트스트랩 순서 목록에 넣지 않는다.
	Roblox API 를 쓰지 않고 시계 함수를 주입받으므로 Studio 밖에서도 테스트된다.

	사용 예:
		local limiter = RateLimiter.new({ maxRequests = 3, windowSeconds = 1 })

		if not limiter:consume(userId) then
			return { ok = false, reason = "too_fast" }
		end
		if not limiter:tryLock(userId) then
			return { ok = false, reason = "busy" }
		end
		-- ... 처리 ...
		limiter:unlock(userId)
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type Config = {
	maxRequests: number, -- 창(window) 당 허용 요청 수
	windowSeconds: number,
	clock: (() -> number)?, -- 테스트용 주입. 기본은 os.clock
}

type Self = {
	maxRequests: number,
	windowSeconds: number,
	clock: () -> number,
	history: { [number]: { number } },
	locks: { [number]: true },
}

export type Limiter = typeof(setmetatable({} :: Self, RateLimiter))

function RateLimiter.new(config: Config): Limiter
	assert(config.maxRequests > 0, "maxRequests 는 1 이상이어야 합니다")
	assert(config.windowSeconds > 0, "windowSeconds 는 0 보다 커야 합니다")

	return setmetatable({
		maxRequests = config.maxRequests,
		windowSeconds = config.windowSeconds,
		clock = config.clock or os.clock,
		history = {},
		locks = {},
	} :: Self, RateLimiter)
end

--[[
	요청 1건을 기록하고 허용 여부를 반환한다.
	허용되지 않으면 아무것도 기록하지 않는다(거절된 요청이 다음 요청을 더 막지 않도록).
]]
function RateLimiter.consume(self: Limiter, userId: number): boolean
	local now = self.clock()
	local stamps = self.history[userId]

	if not stamps then
		stamps = {}
		self.history[userId] = stamps
	end

	-- 창 밖으로 나간 기록을 앞에서부터 버린다.
	local cutoff = now - self.windowSeconds
	while #stamps > 0 and stamps[1] <= cutoff do
		table.remove(stamps, 1)
	end

	if #stamps >= self.maxRequests then
		return false
	end

	table.insert(stamps, now)
	return true
end

-- 처리 중인 요청이 있으면 false. 성공하면 반드시 unlock 을 호출해야 한다.
function RateLimiter.tryLock(self: Limiter, userId: number): boolean
	if self.locks[userId] then
		return false
	end
	self.locks[userId] = true
	return true
end

function RateLimiter.unlock(self: Limiter, userId: number)
	self.locks[userId] = nil
end

function RateLimiter.isLocked(self: Limiter, userId: number): boolean
	return self.locks[userId] == true
end

-- 플레이어가 나갈 때 기록을 정리한다(메모리 누수 방지).
function RateLimiter.clear(self: Limiter, userId: number)
	self.history[userId] = nil
	self.locks[userId] = nil
end

return RateLimiter
