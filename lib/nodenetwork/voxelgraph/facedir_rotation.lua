--[[
Helpers for the neighbour set object (see the appropriate file)
which take a base set of vectors,
specified with respect to a node when it's facedir param2 == 0,
and rotates them dependent on a node's actual param2.
This will make the yielded directions consistent with texture/model rotation.
]]
local facedir =
	mtrequire("com.github.thetaepsilon.minetest.libmthelpers.facedir")
local lookup = facedir.get_rotation_function

local i = {}
local rotate_vector_set = function(baseset, param2)
	local result = {}
	local rotate = lookup(param2)
	for k, v in pairs(baseset) do
		result[k] = rotate(v)
	end
	return result
end
i.rotate_vector_set = rotate_vector_set

local create_neighbour_fn = function(basefunc)
	return function(node)
		local param2 = node.param2
		local baseset = basefunc(node)
		return rotate_vector_set(baseset, param2)
	end
end
i.create_neighbour_fn = create_neighbour_fn

return i

