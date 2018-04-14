_mod = {}
local modname = minetest.get_current_modname()
_mod.modname = modname
local modpath = minetest.get_modpath(modname).."/"
_mod.modpath = modpath

local basename = "com.github.thetaepsilon.minetest.libmt_node_network"
_mod.base = basename
dofile(modpath.."main.lua")


local export = dofile(modpath.."export.lua")
modns.register(basename, export)

_mod = nil
