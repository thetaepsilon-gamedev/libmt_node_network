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


local bfmap = mtrequire(_mod.base..".bfmap")
_mod.modules.bfmap = bfmap

_mod.modules.ropegraph = dofile(dir.."ropegraph.lua")
dofile(dir.."ropegraph_test.lua")
_mod.modules.groupspace = dofile(dir.."groupspace.lua")

_mod.modules.worldcache = dofile(dir.."worldcache.lua")
