local dir = _mod.modpath
_mod.util = {}
_mod.new = {}
_mod.modules = {}

-- I might make this use libmtlog at some point.
local modname = _mod.modname
local logger = function(event, data)
	local result = "# ["..modname.."] "..tostring(event)
	for k, v in pairs(data) do
		result = result.." "..tostring(k).."="..tostring(v)
	end
	print(result)
end
_mod.logger = logger

dofile(_mod.modpath.."external-dependencies.lua")

-- misc internal helpers
dofile(dir.."util.lua")

local bfmap_deps = {
	new = {
		queue = _mod.new.queue,
	},
	increment_counter = _mod.util.increment_counter,
}
local bfmap_factory = dofile(dir.."bfmap.lua")
local bfmap = bfmap_factory(bfmap_deps)
_mod.modules.bfmap = bfmap

_mod.modules.vertexspace = dofile(dir.."vertexspace.lua")

local networkspace_deps = {
	logger = logger
}
local networkspace_factory = dofile(dir.."networkspace_register.lua")
_mod.modules.networkspace = networkspace_factory(networkspace_deps)
