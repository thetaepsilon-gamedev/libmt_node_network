local modules = {}

dofile(_mod.modpath.."external-dependencies.lua")

modules.node_virus = dofile(_mod.modpath.."node-virus.lua")
modules.demo_network = dofile(_mod.modpath.."demo-network.lua")

_mod.modules = modules
