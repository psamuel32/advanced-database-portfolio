-- MIT 8103 ADVANCED DATABASE SYSTEMS: PORTFOLIO 4
-- REDIS FIXED-WINDOW REQUEST RATE LIMITER (LUA SCRIPT)
-- AUTHOR: Praise Samuel (p.okoro4197@miva.edu.ng)
--
-- INVOCATION
--   redis-cli --eval 02_redis_rate_limiter.lua <key> , <limit> <window_seconds>
--   redis-cli --eval 02_redis_rate_limiter.lua ratelimit:102.89.23.11 , 100 60
--
-- KEYS[1] = counter key
-- ARGV[1] = maximum requests permitted per window
-- ARGV[2] = window length in seconds (defaults to 60 when omitted)
--
-- The script executes as a single atomic unit: Redis runs Lua on its single
-- command thread, so the read of the counter, the comparison and the increment
-- cannot interleave with another client's request.

local key = KEYS[1]
local limit = tonumber(ARGV[1])
local ttl = tonumber(ARGV[2]) or 60
local current = tonumber(redis.call('get', key) or "0")

if current + 1 > limit then
    -- Rate limit exceeded: Return 0 (HTTP 429 Too Many Requests)
    return 0
else
    -- Increment the counter atomically
    redis.call('incrby', key, 1)
    if current == 0 then
        -- Arm the window on the first request in it
        redis.call('expire', key, ttl)
    end
    -- Request approved: Return 1 (HTTP 200 OK)
    return 1
end
