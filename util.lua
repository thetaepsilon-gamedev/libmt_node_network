local centerpos = _mod.util.center_on_node
local node_hasher = function(vertex) return minetest.hash_node_position(centerpos(vertex)) end
_mod.util.node_hasher = node_hasher
