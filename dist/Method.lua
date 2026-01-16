-- Memoize caches inputs on functions and reuses the output instead of recomputing the function's result.
-- Memoize Method enables developers to memoize methods within a class rather than pure Roblox functions.
local Memoize = require(script.Parent)

--[[
	@function memoizeMethod
	@within Memoize
	Provides a decorator for methods within the class to memoize them.

	```lua
	local Class = {}
	Class.__index = Class

	function Class.new()
		return setmetatable({ index = 0 }, Class)
	end

	function Class:add(n: number)
		self.index += n
		return self.index
	end
	memoizeMethod()(Class, "add")

	function Class:subtract(n: number)
		self.index -= n
		return self.index
	end
	memoizeMethod()(Class, "subtract")

	return Class
	```
]]
local function memoizeMethod(options)
	options = options or {}

	-- Per-class storage
	local instanceMap = setmetatable({}, { __mode = "k" })

	return function(classTable, methodName)
		local original = classTable[methodName]
		if type(original) ~= "function" then
			error(("The decorated value '%s' must be a function"):format(methodName))
		end

		-- Replace method with a getter-like wrapper
		classTable[methodName] = function(self, ...)
			-- Lazily memoize per-instance
			local memoizedForInstance = instanceMap[self]
			if not memoizedForInstance then
				memoizedForInstance = Memoize.memoize(function(...)
					return original(self, ...)
				end, options)

				instanceMap[self] = memoizedForInstance
			end

			return memoizedForInstance(...)
		end
	end
end

return memoizeMethod
