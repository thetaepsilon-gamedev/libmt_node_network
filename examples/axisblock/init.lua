-- demonstrate the voxelgraph rotation helper,
-- by applying it to a set of vectors in a "T" pattern around a node,
-- then treating the keys of the neighbour set as nodes to set.

local require = mtrequire

local basetex = "axisblock_base.png"
local b = basetex
local toptex = "axisblock_top.png"
local t = basetex.."^"..toptex
local tiles = { t,b,b }

--[[
-- "T" pattern points in these directions when param2 = 0:
{
	{x=0,y=0,z=-1},	-- south
	{x=-1,y=0,z=0},	-- west
	{x=1,y=0,z=0},	-- east
}
]]
local basedirs = {
	[{name="default:dirt_with_grass"}] = {x=0,y=0,z=-1},
	[{name="default:ice"}] = {x=-1,y=0,z=0},
	[{name="default:sandstone"}] = {x=1,y=0,z=0},
}

local neighbourset_rotate =
	require("com.github.thetaepsilon.minetest.libmt_node_network.voxelgraph.facedir_rotation")
local rotator = neighbourset_rotate.create_neighbour_fn(function() return basedirs end)

local rightclick_handler = function(bpos, node, clicker, itemstack, pointed_thing)
	local rotated = rotator(node)
	for k, v in pairs(rotated) do
		local pos = vector.add(bpos, v)
		minetest.set_node(pos, k)
	end
end

local desc = {
	description = "Axis indicator block",
	tiles = tiles,
	paramtype2 = "facedir",
	groups = { oddly_breakable_by_hand=3 },
	--on_rotate = rotation_handler,
	on_rightclick = rightclick_handler,
}
minetest.register_node("axisblock:axis", desc)

