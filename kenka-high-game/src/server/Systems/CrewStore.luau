--!strict
-- DataStore wrapper for crew records and the crew name index (used only by CrewService).
--   CrewStore.Init({ storeName, ... })
--   CrewStore.Update(storeName, key, transform) -> ok, newValue?   (UpdateAsync with 3 retries and backoff)
--   CrewStore.Get(storeName, key) -> ok, value?
--
-- transform(old) returns the new value, or nil to cancel the write (UpdateAsync semantics). It may be called
-- more than once, so it must reset any outer state it sets.
--
-- When DataStores are unavailable (Studio without API access), it switches to an in-memory store for the
-- rest of the session and warns once. Crews then live only as long as this server.

local DataStoreService = game:GetService("DataStoreService")

local CrewStore = {}

local RETRIES = 3
local BACKOFF_BASE = 1 -- seconds; waits 1, 2, 4

local stores: { [string]: DataStore } = {}
local memory: { [string]: { [string]: any } } = {}
local memoryMode = false

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function useMemory(reason: string)
	if memoryMode then
		return
	end
	memoryMode = true
	warn("[CrewService] Crew DataStores are unavailable (" .. reason .. "). Crews are kept in memory for this session only.")
end

local function isAccessError(message: string): boolean
	return message:find("StudioAccessToApisNotAllowed") ~= nil
		or message:find("API Services") ~= nil
		or message:find("publish this place") ~= nil
		or message:find("API access") ~= nil
end

local function bucket(storeName: string): { [string]: any }
	local existing = memory[storeName]
	if existing then
		return existing
	end
	local created = {}
	memory[storeName] = created
	return created
end

function CrewStore.Init(storeNames: { string })
	for _, name in storeNames do
		bucket(name)
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(name)
		end)
		if ok then
			stores[name] = result
		else
			useMemory(tostring(result))
		end
	end
end

function CrewStore.IsMemory(): boolean
	return memoryMode
end

function CrewStore.Update(storeName: string, key: string, transform: (old: any) -> any): (boolean, any)
	local store = stores[storeName]
	if memoryMode or not store then
		local data = bucket(storeName)
		local result = transform(deepCopy(data[key]))
		if result == nil then
			return true, nil
		end
		data[key] = deepCopy(result)
		return true, deepCopy(result)
	end
	local lastError = ""
	for attempt = 1, RETRIES do
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(key, function(old: any)
				return transform(old)
			end)
		end)
		if ok then
			return true, result
		end
		lastError = tostring(result)
		if isAccessError(lastError) then
			useMemory(lastError)
			return CrewStore.Update(storeName, key, transform)
		end
		if attempt < RETRIES then
			task.wait(BACKOFF_BASE * 2 ^ (attempt - 1))
		end
	end
	warn(string.format("[CrewService] UpdateAsync %s/%s failed: %s", storeName, key, lastError))
	return false, nil
end

function CrewStore.Get(storeName: string, key: string): (boolean, any)
	local store = stores[storeName]
	if memoryMode or not store then
		return true, deepCopy(bucket(storeName)[key])
	end
	local lastError = ""
	for attempt = 1, RETRIES do
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(key)
		end)
		if ok then
			return true, result
		end
		lastError = tostring(result)
		if isAccessError(lastError) then
			useMemory(lastError)
			return CrewStore.Get(storeName, key)
		end
		if attempt < RETRIES then
			task.wait(BACKOFF_BASE * 2 ^ (attempt - 1))
		end
	end
	warn(string.format("[CrewService] GetAsync %s/%s failed: %s", storeName, key, lastError))
	return false, nil
end

return CrewStore
