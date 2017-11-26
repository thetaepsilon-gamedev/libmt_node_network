_mod.new = {}
_mod.util = {}
_mod.new = {}

local modhelpers_base = "com.github.thetaepsilon.minetest.libmthelpers."

local pos = modns.get(modhelpers_base.."playerpos")
_mod.util.center_on_node = pos.center_on_node

local tableutils = modns.get(modhelpers_base.."tableutils")
_mod.util.shallowcopy = tableutils.shallowcopy
_mod.util.search = tableutils.search

local coords = modns.get(modhelpers_base.."coords")
_mod.util.formatvec = coords.format
_mod.util.neighbour_offsets = coords.neighbour_offsets
_mod.util.adjacent_offsets = coords.adjacent_offsets

_mod.util.increment_counter = modns.get(modhelpers_base.."stats").increment_counter

local datastructs = modns.get(modhelpers_base.."datastructs")
_mod.new.queue = datastructs.new.queue

local nodenetwork = modns.get("com.github.thetaepsilon.minetest.libmt_node_network")
_mod.new.bfmap = nodenetwork.bfmap.new
_mod.util.node_hasher = nodenetwork.util.node_hasher
_mod.new.vertexspace = nodenetwork.vertexspace.new
_mod.new.worldcache = nodenetwork.worldcache.new
_mod.new.statsgrid = nodenetwork.worldcache.mkstatsgrid
