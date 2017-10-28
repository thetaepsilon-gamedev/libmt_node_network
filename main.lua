local dir = _mod.modpath
_mod.util = {}
_mod.new = {}
_mod.modules = {}

dofile(_mod.modpath.."external-dependencies.lua")

local bfmap_deps = {
	new = {
		queue = _mod.new.queue,
	},
	increment_counter = _mod.util.increment_counter,
}
local bfmap_factory = dofile(dir.."bfmap.lua")
local bfmap = bfmap_factory(bfmap_deps)
_mod.modules.bfmap = bfmap

local networkspace_deps = {
}
local networkspace_factory = dofile(dir.."networkspace.lua")
_mod.modules.networkspace = networkspace_factory(networkspace_deps)
