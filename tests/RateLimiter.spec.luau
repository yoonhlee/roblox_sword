--!strict
local t = require("./harness")
local RateLimiter = require("../src/server/services/RateLimiter")

-- 시계를 직접 굴려 시간에 의존하지 않는 테스트를 만든다.
local function makeClock()
	local now = 0
	return function(): number
		return now
	end, function(delta: number)
			now += delta
		end
end

t.describe("RateLimiter.consume", function()
	t.it("창 안에서는 상한까지만 허용한다", function()
		local clock = makeClock()
		local limiter = RateLimiter.new({ maxRequests = 3, windowSeconds = 1, clock = clock })

		t.expectEqual(limiter:consume(1), true)
		t.expectEqual(limiter:consume(1), true)
		t.expectEqual(limiter:consume(1), true)
		t.expectEqual(limiter:consume(1), false)
	end)

	t.it("창이 지나면 다시 허용한다", function()
		local clock, advance = makeClock()
		local limiter = RateLimiter.new({ maxRequests = 3, windowSeconds = 1, clock = clock })

		for _ = 1, 3 do
			limiter:consume(1)
		end
		t.expectEqual(limiter:consume(1), false)

		advance(1.01)
		t.expectEqual(limiter:consume(1), true)
	end)

	t.it("거절된 요청은 기록되지 않는다", function()
		local clock, advance = makeClock()
		local limiter = RateLimiter.new({ maxRequests = 2, windowSeconds = 1, clock = clock })

		limiter:consume(1)
		limiter:consume(1)
		for _ = 1, 100 do
			limiter:consume(1) -- 전부 거절
		end

		advance(1.01)
		t.expectEqual(limiter:consume(1), true, "거절된 요청이 다음 창까지 영향을 주면 안 된다")
	end)

	t.it("플레이어끼리 서로 영향을 주지 않는다", function()
		local clock = makeClock()
		local limiter = RateLimiter.new({ maxRequests = 1, windowSeconds = 1, clock = clock })

		t.expectEqual(limiter:consume(1), true)
		t.expectEqual(limiter:consume(1), false)
		t.expectEqual(limiter:consume(2), true)
	end)
end)

t.describe("RateLimiter 동시 요청 락", function()
	t.it("처리 중에는 두 번째 요청을 막는다", function()
		local clock = makeClock()
		local limiter = RateLimiter.new({ maxRequests = 99, windowSeconds = 1, clock = clock })

		t.expectEqual(limiter:tryLock(1), true)
		t.expectEqual(limiter:tryLock(1), false)
		t.expectEqual(limiter:isLocked(1), true)

		limiter:unlock(1)
		t.expectEqual(limiter:isLocked(1), false)
		t.expectEqual(limiter:tryLock(1), true)
	end)

	t.it("락은 플레이어별로 독립이다", function()
		local clock = makeClock()
		local limiter = RateLimiter.new({ maxRequests = 99, windowSeconds = 1, clock = clock })

		t.expectEqual(limiter:tryLock(1), true)
		t.expectEqual(limiter:tryLock(2), true)
	end)

	t.it("clear 는 기록과 락을 모두 지운다", function()
		local clock = makeClock()
		local limiter = RateLimiter.new({ maxRequests = 1, windowSeconds = 1, clock = clock })

		limiter:consume(1)
		limiter:tryLock(1)
		limiter:clear(1)

		t.expectEqual(limiter:consume(1), true)
		t.expectEqual(limiter:tryLock(1), true)
	end)
end)
