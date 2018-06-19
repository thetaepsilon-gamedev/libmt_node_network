local memgrid_ro =
	mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.grid.memgrid_ro")
local linkedgrid = 
	mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.grid.linkedgrid")
local oob = linkedgrid.constants.out_of_bounds()
local eq = mtrequire("ds2.minetest.vectorextras.equality")
local m_add = mtrequire("ds2.minetest.vectorextras.add")
local vadd = m_add.wrapped

-- set up the grid.
-- pretend block data is just strings for display/debug purposes
local i = "."
local S = "+"
local identity = function(...) return ... end
-- bear in mind that due to the order of lines in the source,
-- this particular case is a coordinate system with +Y going down.
local data = {
	i, i, i, i, i,
	i, i, S, i, i,
	i, S, S, S, i,
	i, i, S, i, i,
	i, i, i, i, i,
}
local grid = memgrid_ro({
	translator = identity,
	srcarray = data,
	basepos = {x=0,y=0,z=0},
	size = {x=5, y=5, z=1}
})



-- test cases.

-- grid is rooted at 0,0,0 so that coordinate should work.
local position = function(pos, v)
	assert(grid.get(pos) == v)
end
position({x=0,y=0,z=0}, i)
-- likewise the far corner should work.
position({x=4,y=4,z=0}, i)
-- center position
position({x=2,y=2,z=0}, S)
-- along the edge
position({x=1,y=0,z=0}, i)
position({x=2,y=0,z=0}, i)
-- the plus part
position({x=3,y=2,z=0}, S)
position({x=1,y=2,z=0}, S)
position({x=2,y=1,z=0}, S)
position({x=2,y=3,z=0}, S)

-- now test just outside those boundaries,
-- we should get the out-of-bounds sentinel
local outofbounds = function(pos) position(pos, oob) end
outofbounds({x=-1,y=0,z=0})
outofbounds({x=0,y=-1,z=0})
outofbounds({x=5,y=0,z=0})
outofbounds({x=0,y=5,z=0})

-- as we specified a Z-size of one,
--anything in a higher or lower Z plane should also be OOB
outofbounds({x=0,y=0,z=1})
outofbounds({x=0,y=0,z=2})
outofbounds({x=0,y=0,z=-1})
outofbounds({x=0,y=0,z=-2})



-- now test the functionality of grid.neighbour().
-- as this is just a regular euclidian grid,
-- we expect that x+1 of a position will be that of adding +1 to the position's X etc.;
-- and that neighbour movements crossing the boundary will result in oob also.
local origin = {x=0,y=0,z=0}
local euclid_offset = function(base, offset)
	local expected = vadd(base, offset)
	local r = grid.neighbour(base, offset)
	assert(type(r) == "table")
	assert(r ~= oob)
	assert(r.grid == grid)
	assert(eq(r.pos, expected))
	assert(eq(r.direction, offset))
end

euclid_offset(origin, {x=1,y=0,z=0})
euclid_offset(origin, {x=0,y=1,z=0})
euclid_offset({x=4,y=4,z=0}, {x=-1,y=0,z=0})
euclid_offset({x=4,y=4,z=0}, {x=0,y=-1,z=0})
euclid_offset({x=2,y=2,z=0}, {x=-1,y=0,z=0})

-- check oob crossings
local offset_oob = function(base, offset)
	local r = grid.neighbour(base, offset)
	assert(r == oob)
end
offset_oob(origin, {x=-1,y=0,z=0})
offset_oob(origin, {x=0,y=-1,z=0})
offset_oob(origin, {x=0,y=0,z=-1})
offset_oob({x=2,y=3,z=0}, {x=0,y=0,z=2})

