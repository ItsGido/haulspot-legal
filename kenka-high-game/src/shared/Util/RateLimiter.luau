--!strict
-- Per-key token bucket. Used by the server to drop remote spam.
--   local limiter = RateLimiter.new(12, 1)  -- 12 requests per 1 second
--   if not limiter:Allow(player) then return end

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable({} :: {
	_rate: number,
	_per: number,
	_buckets: { [any]: { Tokens: number, Updated: number } },
}, RateLimiter))

function RateLimiter.new(rate: number, per: number): RateLimiter
	return setmetatable({ _rate = rate, _per = per, _buckets = {} }, RateLimiter)
end

function RateLimiter.Allow(self: RateLimiter, key: any): boolean
	local now = os.clock()
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { Tokens = self._rate, Updated = now }
		self._buckets[key] = bucket
	end
	bucket.Tokens = math.min(self._rate, bucket.Tokens + (now - bucket.Updated) * (self._rate / self._per))
	bucket.Updated = now
	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end
	return false
end

function RateLimiter.Remove(self: RateLimiter, key: any)
	self._buckets[key] = nil
end

return RateLimiter
