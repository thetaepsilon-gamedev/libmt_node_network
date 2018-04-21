local b = "default_stone.png"
local t = b .. "^neighbourblock_top_overlay.png"

local name = "neighbourblock:block"

local neighbourset =
	mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.voxelgraph.neighbourset")
local facerot =
	mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.voxelgraph.facedir_rotation")

-- with respect to the overlay texture
local basevecs = {
	{ x=0,y=0,z=1 },
	{ x=1,y=0,z=0 },
}
local hook = facerot.create_neighbour_fn(function() return basevecs end)

local lut = neighbourset.mk_neighbour_lut()
lut:add_custom_hook(name, hook)

local convert = {name="default:glass"}
local poke = function(bpos, node, clicker, itemstack, pointed_thing)
	-- NB: cheat and pass nil meta ref here, we know the function won't modify it.
	local neighbours = lut:query_neighbour_set(node, nil)
	if (neighbours) then
		for _, vec in ipairs(neighbours) do
			local pos = vector.add(bpos, vec)
			minetest.set_node(pos, convert)
		end
	end
end

minetest.register_node(name, {
	description = "Neighbour set test block",
	tiles = { t,b,b,b,b,b },
	paramtype2 = "facedir",
	groups = {
		oddly_breakable_by_hand = 3,
	},
	on_rightclick = poke,
})

