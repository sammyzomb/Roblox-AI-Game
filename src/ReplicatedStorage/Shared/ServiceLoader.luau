--!strict
-- Loads every ModuleScript in a folder and runs the service lifecycle:
--   1. require all modules and build a registry keyed by module name
--   2. call :Init(registry) on each, in order (sync; an error aborts boot)
--   3. call :Start() on each, in order, each in its own thread
--
-- Order: lower `Priority` first (default 0), then module name.
-- Services get each other from the registry in Init instead of requiring
-- each other directly, which avoids circular requires.

export type Registry = { [string]: any }

local ServiceLoader = {}

function ServiceLoader.boot(folder: Instance, label: string): Registry
	local registry: Registry = {}
	local ordered = {}

	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local module = (require :: any)(child)
			registry[child.Name] = module
			table.insert(ordered, { name = child.Name, module = module })
		end
	end

	table.sort(ordered, function(a, b)
		local pa, pb = a.module.Priority or 0, b.module.Priority or 0
		if pa ~= pb then
			return pa < pb
		end
		return a.name < b.name
	end)

	table.freeze(registry)

	for _, entry in ordered do
		if entry.module.Init then
			entry.module:Init(registry)
		end
	end

	for _, entry in ordered do
		if entry.module.Start then
			task.spawn(entry.module.Start, entry.module)
		end
	end

	print(`[{label}] booted {#ordered} module(s)`)
	return registry
end

return ServiceLoader
