--!strict
-- Thin wrapper around a DataStore with retries.
-- In Studio, when DataStores are unavailable (unpublished place, or
-- "Enable Studio Access to API Services" off), falls back to an in-memory
-- store so the game stays playable. Data then does not persist between runs.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

export type Store = {
	isMemory: boolean,
	load: (self: Store, key: string) -> (boolean, any),
	save: (self: Store, key: string, value: any) -> boolean,
}

local DataStoreAdapter = {}

local function withRetries<T>(attempts: number, label: string, fn: () -> T): (boolean, T?)
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[DataStore] {label} failed (attempt {attempt}/{attempts}): {result}`)
		if attempt < attempts then
			task.wait(2 ^ (attempt - 1))
		end
	end
	return false, nil
end

local function memoryStore(): Store
	local values: { [string]: any } = {}
	return {
		isMemory = true,
		load = function(_, key)
			return true, values[key]
		end,
		save = function(_, key, value)
			values[key] = value
			return true
		end,
	}
end

function DataStoreAdapter.new(name: string, maxRetries: number): Store
	local ok, dataStore = pcall(DataStoreService.GetDataStore, DataStoreService, name)
	if ok and RunService:IsStudio() then
		-- Studio without API access fails on the first request, not on GetDataStore.
		ok = pcall(dataStore.GetAsync, dataStore, "__studio_probe")
	end

	if not ok then
		if RunService:IsStudio() then
			warn("[DataStore] Unavailable in Studio; using in-memory store (data will not persist).")
			return memoryStore()
		end
		error(`[DataStore] Could not open "{name}": {dataStore}`)
	end

	return {
		isMemory = false,
		load = function(_, key)
			local loaded, value = withRetries(maxRetries, `load {key}`, function()
				return dataStore:GetAsync(key)
			end)
			return loaded, value
		end,
		save = function(_, key, value)
			local saved = withRetries(maxRetries, `save {key}`, function()
				dataStore:SetAsync(key, value)
				return true
			end)
			return saved
		end,
	}
end

return DataStoreAdapter
