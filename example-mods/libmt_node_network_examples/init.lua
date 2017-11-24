_mod = {}
local modname = minetest.get_current_modname()
_mod.modname = modname
local modpath = minetest.get_modpath(modname).."/"
_mod.modpath = modpath

dofile(modpath.."main.lua")

local export = dofile(modpath.."export.lua")
node_network_examples = export
modns.register("com.github.thetaepsilon.minetest.libmt_node_network.examples", export)

_mod = nil
