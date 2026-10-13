--!strict
-- Token bucket: `rate` requests per second on average, bursts of up to `burst`.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: { rate: number, burst: number, tokens: number, last: number },
	RateLimiter
))

function RateLimiter.new(rate: number, burst: number, now: number): RateLimiter
	return setmetatable({ rate = rate, burst = burst, tokens = burst, last = now }, RateLimiter)
end

function RateLimiter.allow(self: RateLimiter, now: number): boolean
	local elapsed = math.max(0, now - self.last)
	self.last = now
	self.tokens = math.min(self.burst, self.tokens + elapsed * self.rate)
	if self.tokens >= 1 then
		self.tokens -= 1
		return true
	end
	return false
end

return RateLimiter
