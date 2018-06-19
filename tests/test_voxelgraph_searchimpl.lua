local eq = mtrequire("ds2.minetest.vectorextras.equality")
-- enable these for print debug statements when they're uncommented...
--local coords = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.coords")
--local fmt = coords.format



--[[
-- An example of the query functions that could be used in a voxelgraph successor
-- (assuming the grid object populates the name field):
--]]
local neighbourset = function(node)
	--print(node.name)
	if (node.name == "default:stone") then
		-- plus "+" pattern: +-X, +-Y
		return { {x=1,y=0,z=0}, {x=-1,y=0,z=0}, {x=0,y=1,z=0}, {x=0,y=-1,z=0}}
	end
	-- explicitly return empty set, nil is treated as an internal error.
	return {}
end
local inbound_filter = function(data)
	local n = data.node.name
	--print(n)
	local accept = (n == "default:stone") or (n == "default:cobble")
	--print(accept)
	return accept
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
	".................",
	"......S...S...C..",
	".S.C.SSS.SCS.CSC.",
	"......S...S...C..",
	".................",
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
	--print(k, v)
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
local psuccessors = function(pos)
	return successor({grid=grid, pos=pos}, nil)
end
-- first up is the lone stone and cobble blocks ("S" and "C").
-- both of these ought to return the empty set,
-- as neither of them have any stone-y nodes around them.
--print(grid.get({x=0,y=2,z=0}).name)
empty(psuccessors({x=1,y=2,z=0}))
empty(psuccessors({x=3,y=2,z=0}))

-- next, the S and C plus shape formations.
-- in the latter case, we expect the cobble to end up as a dead end;
-- i.e. it will not propogate to the surrounding stone.
local expect_vector_set = function(expected, actual)
	for i, ex in ipairs(expected) do
		-- test each successor in the actual set in turn.
		-- if a match isn't found, raise an error.
		-- otherwise clear it from the actual set (note destructive!).
		local k
		local empty = true
		for hash, vertex in pairs(actual) do
			empty = false
			assert(vertex.grid == grid)
			local pos = vertex.pos
			--print(fmt(pos))
			if eq(pos, ex) then
				k = hash
			end
		end
		assert(not empty, "actual set was empty!?")
		if k == nil then
			local f = fmt(ex)
			error("expected element "..i.." not present in set: "..f)
		end
		actual[k] = nil
	end
end

local plus = {{x=5,y=2,z=0}, {x=7,y=2,z=0}, {x=6,y=1,z=0}, {x=6,y=3,z=0}}
expect_vector_set(plus, successor({grid=grid, pos={x=6,y=2,z=0}}, nil))
empty(psuccessors({x=10,y=2,z=0}))

-- finally we have the plus shape on the far right.
-- the stone in the middle should include it's surrounding cobblestone,
-- but those cobble themselves are dead ends.
local plus = {{x=13,y=2,z=0}, {x=15,y=2,z=0}, {x=14,y=1,z=0}, {x=14,y=3,z=0}}
expect_vector_set(plus, successor({grid=grid, pos={x=14,y=2,z=0}}, nil))
empty(psuccessors({x=13,y=2,z=0}))
empty(psuccessors({x=15,y=2,z=0}))
empty(psuccessors({x=14,y=1,z=0}))
empty(psuccessors({x=14,y=3,z=0}))

