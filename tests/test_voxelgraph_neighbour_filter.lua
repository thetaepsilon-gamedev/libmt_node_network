--[[
These tests for the voxelgraph.neighbourfilter module
show some examples of what is expected to happen within the voxelgraph code.
As the structure currently more or less passes through libmthelpers.datastructs.handler_lut,
you should look there for more thorough testing of the data structure.
]]
local testing =
	mtrequire("com.github.thetaepsilon.minetest.libmthelpers.testing")
local neighbourfilter =
	mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.voxelgraph.neighbourfilter")

local stone_handler = function(data)
	-- let's say we want stone blocks to connect to nearby grass,
	-- *or* cobblestone *if* certain extradata was set for that particular neighbour.
	-- yes, I'm aware it's actually dirt_with_grass... just roll with the example.
	local n = data.dest.name
	-- NB: beware of what and/or actually do.. can cause problems!
	return (n == "default:grass" or (data.extradata.crackly == true and n == "default:cobble"))
end

local mknode = function(n) return { name = n } end
local src = mknode("default:stone")

local get_dep = function()
	local q, r = neighbourfilter.mk_filter_lut({})
	r("default:stone", stone_handler)
	return { query=q, register=r }
end


local grass = mknode("default:grass")
local cobble = mknode("default:cobble")

testing.test_harness_with_deps({
	get_dep = get_dep, 
	testvecs = {
		function(dep)
			-- grass should always work.
			local data = {
				src = src,
				dest = grass,
				extradata = {}
			}
			local r, e = dep.query(data)
			assert(r == true)
		end,
		function(dep)
			-- cobblestone should NOT work without crackly set.
			local data = {
				src = src,
				dest = cobble,
				extradata = {}
			}
			local r, e = dep.query(data)
			assert(r == false)
		end,
		function(dep)
			-- cobblestone should work if we set crackly.
			local data = {
				src = src,
				dest = cobble,
				extradata = { crackly = true }
			}
			local r, e = dep.query(data)
			assert(r == true)
		end,
	}
})

