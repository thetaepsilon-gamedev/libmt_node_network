local libnetwork = modns.get("com.github.thetaepsilon.minetest.libmt_node_network")
local libexamples = modns.get("com.github.thetaepsilon.minetest.libmt_node_network.examples")
local woollist = {
	"wool:white",
        "wool:red",
        "wool:yellow",
        "wool:green",
        "wool:cyan",
        "wool:blue",
        "wool:magenta",
        "wool:orange",
        "wool:violet",
        "wool:brown",
        "wool:pink",
        "wool:dark_green",
        "wool:grey",
        "wool:dark_grey",
        "wool:black",
}
local opts = { forgetnode="default:obsidian" }
local grid = libnetwork.worldcache.mkmtgrid()
woolnet = libexamples.demonet.new("default:cobble", woollist, {}, "woolnet", opts, grid)
minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
	if newnode.name == "default:cobble" then
		woolnet.addvertex(pos)
	end
end)

local successor_gridless = woolnet.successor_gridless
local tester = woolnet.tester
minetest.register_on_dignode(function(pos, oldnode, digger)
	if tester(oldnode.name) then
		local neighbours = successor_gridless(grid, pos)
		woolnet.removevertex(pos, neighbours)
	end
end)
