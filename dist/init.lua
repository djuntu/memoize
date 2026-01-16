-- Memoize caches inputs on functions and reuses the output instead of recomputing the function's result.

-- Roblox equivalent of Date.now()
local function now()
	return os.clock() * 1000
end

local MAX_TIMEOUT_VALUE = 2_147_483_647

-- Stores metadata for memoized functions
local cacheStore: { [() -> any]: any } = {}
local cacheKeyStore: { [() -> any]: (any) -> any } = {}
local cacheTimerStore: { [() -> any]: { any } } = {}

export type CacheItem<Value> = {
	data: Value,
	maxAge: number,
}

export type CacheLike<Key, Value> = {
	has: (self: any, key: Key) -> boolean,
	get: (self: any, key: Key) -> CacheItem<Value>?,
	set: (self: any, key: Key, value: CacheItem<Value>) -> (),
	delete: (self: any, key: Key) -> (),
	clear: (self: any) -> ()?,
}

export type Options<Fn, CacheKey> = {
	maxAge: number | ((...any) -> number)?,
	cacheKey: ((args: { any }) -> CacheKey)?,
	cache: CacheLike<CacheKey, any>?,
}

--[[
	@function getValidCacheItem
	@within Memoize
	Gets the cached result based on the given input and returns it if it exists
	and has not expired.

	@private
	@param cache: CacheLike<K, V>
	@param key: any
	@returns CacheItem<V>?
]]
local function getValidCacheItem(cache, key)
	local item = cache:get(key)
	if not item then
		return nil
	end

	if item.maxAge <= now() then
		cache:delete(key)
		return nil
	end

	return item
end

--[[
	@function defaultCache
	@within Memoize
	Creates a standard CacheLike for a function to store its computed inputs.

	@private
	@returns CacheLike
]]
local function defaultCache()
	local store = {}
	local cache = {}

	function cache:has(key)
		return store[key] ~= nil
	end

	function cache:get(key)
		return store[key]
	end

	function cache:set(key, value)
		store[key] = value
	end

	function cache:delete(key)
		store[key] = nil
	end

	function cache:clear()
		for k in pairs(store) do
			store[k] = nil
		end
	end

	return cache
end

--[[
	@function memoize
	@within Memoize
	Memoizes a given function so that any previous inputs are not recomputed and instead
	cached and taken.

	::: @note :::
	Memoize provides a separate function for Memoizing methods instead of functions,
	which is required via */Method.
	::: @note :::

	@public
	@param fn: non-void, non-nullary Function : (...any) -> any
	@param options: Options
	@returns (...any) -> any
]]
local function memoize(fn: (...any) -> any, options: Options<any, any>?): (...any) -> any
	options = options or {}

	-- Retrieve the cache for the Memoization.
	local cache = options.cache or defaultCache()
	local cacheKey = options.cacheKey or function(args)
		return args[1]
	end

	-- Decide the max age.
	local maxAge = options.maxAge
	if maxAge == 0 then
		-- If maxAge is zero inputs will never be cached and hence not memoized.
		return fn
	end

	local memoized
	memoized = function(...)
		local args = table.pack(...)
		local key = cacheKey(args)

		-- Get the cached item if possible and return it or compute and cache with given args.
		local cached = getValidCacheItem(cache, key)
		if cached then
			return cached.data
		end

		local result = fn(...)

		local computedMaxAge
		if typeof(maxAge) == "function" then
			computedMaxAge = maxAge(...)
		else
			computedMaxAge = maxAge
		end

		if computedMaxAge ~= nil and computedMaxAge ~= math.huge then
			if computedMaxAge <= 0 then
				return result
			end
			if computedMaxAge > MAX_TIMEOUT_VALUE then
				error("maxAge cannot exceed " .. MAX_TIMEOUT_VALUE)
			end
		end

		local expires = (computedMaxAge == nil or computedMaxAge == math.huge) and math.huge or (now() + computedMaxAge)

		cache:set(key, {
			data = result,
			maxAge = expires,
		})

		-- We set a timer for the computed value to expire if able. Nil and math.huge both represent non-expiring values.
		-- The timer is set as a promise that cached values will expire in given time rather than based on recalling of the
		-- memoized function.
		if computedMaxAge ~= nil and computedMaxAge ~= math.huge then
			local timer = task.delay(computedMaxAge / 1000, function()
				cache:delete(key)
			end)

			local timers = cacheTimerStore[memoized]
			if not timers then
				timers = {}
				cacheTimerStore[memoized] = timers
			end
			table.insert(timers, timer)
		end

		return result
	end

	cacheStore[memoized] = cache
	cacheKeyStore[memoized] = cacheKey

	return memoized
end

--[[
	@function memoizeClear
	@within Memoize
	Clears any memoized additions from a function to return it to a normal Native function.

	@public
	@param fn: Function(Memoized)
	@returns void
]]
local function memoizeClear(fn)
	local cache = cacheStore[fn]
	if not cache then
		error("Cannot clear a function that was not memoized")
	end

	if not cache.clear then
		error("Cache does not support clear()")
	end

	cache:clear()
	if cacheTimerStore[fn] and next(cacheTimerStore[fn]) then
		for index: number, timer: thread in pairs(cacheTimerStore[fn]) do
			cacheTimerStore[fn][index] = nil
			task.cancel(timer)
		end
	end
end

--[[
	@function memoizeIsCached
	@within Memoize
	Checks if a given value is a member of the function's memoized cache.

	@param fn: Function(Memoized)
	@param args: tuple<any>
	@returns boolean
]]
local function memoizeIsCached(fn, ...)
	local cacheKey = cacheKeyStore[fn]
	if not cacheKey then
		return false
	end

	local cache = cacheStore[fn]
	if not cache then
		return false
	end

	local key = cacheKey(table.pack(...))
	local item = getValidCacheItem(cache, key)
	return item ~= nil
end

return {
	memoize = memoize,
	memoizeClear = memoizeClear,
	memoizeIsCached = memoizeIsCached,
}
