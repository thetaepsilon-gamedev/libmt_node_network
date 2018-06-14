--[[
-- An example of the query functions that could be used in a voxelgraph successor
-- (assuming the grid object populates the name field):
--]]
local neighbourset = function(node)
	if (node.name == "default:stone") then
		-- horizontal plus "+" pattern: +-X, +-Z
		return { {x=1,y=0,z=0}, {x=-1,y=0,z=0}, {x=0,y=0,z=1}, {x=0,y=0,z=-1}}
	end
	-- explicitly return empty set, nil is treated as an internal error.
	return {}
end
local inbound_filter = function(data)
	if data.node.name == "default:stone" or "default:cobble" then return true end
	return false
end

--[[
This defines a network which propogates horizontally
(but not across diagonals) along adjacent stone blocks,
and will also include cobblestone but they are considered a "dead end"
(that is, they will not provide any neighbours to continue the search from them).
More advanced networks could do things like inspect node metadata
(however the grid object would have to provide this data).
]]
local searchimpl =
	mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.voxelgraph.searchimpl")

-- create a memgrid for testing;
-- nodes are set as strings here but we use memgrid's translator to create the proper table.
local memgrid =
	mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.grid.memgrid_ro")

local a = "air"
local S = "default:stone"
local C = "default:cobble"

-- hey look, it's nethack!
local src = {
	".............",
	"......S...S..",
	".S.C.SSS.SCS.",
	"......S...S..",
	".............",
}
local map = {
	["."] = "air",
	["S"] = "default:stone",
	["C"] = "default:cobble",
}
local mapf_ = function(map)
	assert(type(map) == "table")
	return function(k)
		local v = map[k]
		assert(v ~= nil)
		return v
	end
end

-- hmm, maybe something like this is in order:
-- local a, b, ... = modns.from("longpath"):import(compa, compb, ...)
local p = "com.github.thetaepsilon.minetest.libmthelpers.functional."
local char_iterator = mtrequire(p.."string").char_iterator
local generator_ = mtrequire(p.."fmap").generator_
local shallowcopy =
	mtrequire("com.github.thetaepsilon.minetest.libmthelpers.tableutils").shallowcopy
local create_memgrid_from_nethack = function(src, mapf, gridopts)
	-- there has to be at least one line for this to make sense.
	-- we set the width of the grid based on the first line.
	assert(src[1] ~= nil)
	local width = #src[1]
	assert(width > 0)
	local t = {}
	local insertpos = 0

	-- allow translation from a character in the nethack notation
	-- to something more sane, like say node name strings.
	local fmap = generator_(mapf)

	local n
	for i, line in ipairs(src) do
		n = i
		-- all the lines must be the same for a 2D grid.
		assert(#line == width)

		-- convert to the linear layout expected by memgrid.
		for v in fmap(char_iterator(line)) do
			insertpos = insertpos + 1
			t[insertpos] = v
		end
	end

	-- once that's done, overlay the opts with the source array and size,
	-- as we know those from having worked them out here.
	local opts = shallowcopy(gridopts)
	opts.srcarray = t
	opts.size = {x=width,y=n,z=1}
	return memgrid(opts)
end




-- use a translator to wrap the name string in the source array to node.name
local trans = function(v) return {name=v} end
local grid =
	create_memgrid_from_nethack(
		src,
		mapf_(map),
		{
			translator = trans,
			basepos = {x=0,y=0,z=0}
		}
	)

-- utility functions for testing what comes out of the successor
local table_is_empty = function(t)
	local k, v = next(t)
	return k == nil
end
local empty = function(t)
	assert(type(t) == "table")
	assert(table_is_empty(t))
end

-- initialise the successor (see these functions near the top)
local queryf = {
	neighbourset = neighbourset,
	inbound_filter = inbound_filter,
}
local successor = searchimpl.create_successor(queryf)

-- now, poke positions on the grid and see what we get back for successors.
-- we kind of cheat here as this successor doesn't use the hash it gets,
-- as all the information it needs is present in the passed vertex object.
local fetch_position_successors = function(pos)
	
end


