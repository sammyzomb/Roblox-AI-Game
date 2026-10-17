--!strict
-- Fixed-window request limiter keyed by anything (usually a UserId).
-- Pure module: the caller passes the current time, so it is unit testable.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Window = { start: number, count: number }

export type RateLimiter = typeof(setmetatable(
	{} :: { _max: number, _window: number, _windows: { [any]: Window } },
	RateLimiter
))

function RateLimiter.new(maxRequests: number, windowSeconds: number): RateLimiter
	return setmetatable({ _max = maxRequests, _window = windowSeconds, _windows = {} }, RateLimiter)
end

-- Returns true if the request is within budget and counts it.
function RateLimiter.allow(self: RateLimiter, key: any, now: number): boolean
	local window = self._windows[key]
	if not window or now - window.start >= self._window then
		self._windows[key] = { start = now, count = 1 }
		return true
	end
	if window.count >= self._max then
		return false
	end
	window.count += 1
	return true
end

-- Forget a key (call when the player leaves).
function RateLimiter.clear(self: RateLimiter, key: any)
	self._windows[key] = nil
end

return RateLimiter
