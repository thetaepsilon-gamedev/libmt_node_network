--[[
In order to track connected groups of nodes in the world,
here we map the abstract graph concept to individual voxels and their neighbours.
We need some kind of filtering as every voxel has six neighbours naturally,
but we may not be interested in all of them if they're e.g. not a cable or other connecting node.
Additionally, they may be the right node but may have direction constraints;
for example, a node that can only connect with other nodes on the top or bottom,
even if the other touching nodes could connect on their sides.
Furthermore, that set of allowed connections may vary dependent on node data.

Therefore, in order to determine the valid neighbours of a given node, we need to determine:
* The nodes which should be looked at around the origin node (the neighbour candidate set);
* Whether those nodes are valid neighbours based on their node data (filtering step); and
* whether those nodes are allowed to connect *back* in the reverse direction (the direction check)

The structures below allow determining this.
The successor function's vertex structure looks like the following:
vertex = {
	grid = gridimpl,	-- *
	pos = { x, y, z },
}
In order to prevent address re-use problems if a grid object happens to vanish mid-search,
a given successor instance maintains references to all seen grids while it is still alive
(hence why it has to be created each time).

The successor queries the vertex's grid for the node at the vertex position, 
then looks up the node name in it's internal data structures.
The candidate neighbours are retrieved either from a presets table
or by dynamically calling a function registered in a callbacks table
(which can e.g. examine metadata),
resulting in a list of offset vectors.

Then, the successor code asks the grid object for the resulting grid and position on that grid*,
then calls that grid with that position to retrieve node data.
At this point, the source node has the opportunity to filter each of these candidates,
based upon the node data for the candidate;
this allows e.g. filtering the initial vectors based on the node's group.

The directionality data for each candidate that passes the above is again looked up by preset table or callback.
This is in reverse, from the target back to the source
and just asks "is this node in this direction allowed to connect?", with a boolean outcome.
If this check passes, then that target position and grid are added to the successor set.
Repeat for all initial neighbour candidates, and that list is returned
(in appropriate hashset form for the search algorithm).



* The intent here is to be as general as possible,
and not lock out tricks that break under the assumption of a singleton euclidian grid.
Passing the grid a direction instead of calculating offsets directly allows "portals",
where a graph of nodes can span otherwise logically disconnected areas.
Likewise, differing target grids allows the code to cross boundaries to something other than the MT world;
for example, the sought after but ever postponed Voxel Area Entities,
which would be freely rotateable and would not relate directly to "global" co-ordinates.

This means that in general any callback functions MUST NOT use any minetest.* functions with world side effects,
such as trying to spawn an entity assuming the coordinates map to the global grid.
Generally speaking, where possible the callbacks must avoid making *any* visible side effects,
as changing things mid-search may cause strange results from the search algorithm.
]]



--[[
-- @INTERFACE linkedgrid
grid = {
	get = function(self, pos, keys),
		-- where pos is the regular XYZ vector.
		-- must return a table with at least "name", "param1", and "param2" values.
		-- it may assume that pos contains integer coordinates.
		-- keys is an opaque object which specifies which aspects of a node require loading.
		-- the grid and used callbacks must at least agree on the meaning of this object.
		-- this is to support e.g. providing metadata access, or *other data*
		-- which are currently unknown (e.g. grids that possess a means to get temperature).
		-- please note: if providing a metadata ref,
		-- *accessors are allowed to assume it can't change*.
		-- in other words, make it read only!
	neighbour = function(self, pos, direction),
		-- direction is an offset vector from pos.
		-- must return the following:
		-- * vertex table in the above format,
			containing position and target grid.
			note the grid object is not required to be the same as the invoked one.
		-- * effective direction vector going *into* the node
			(e.g. to allow "portal rotations").

}
]]
local check = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.check")
local methods = { "get", "neighbour" }
local checkgrid = check.mk_interface_check(methods, "checkgrid()")



-- coordinates should be kept to whole nodes where possible.
-- among other things, fractional coordinates cause hashing issues,
-- especially if an already visited position ends up with a different hash due to round errors.
local checkdim = function(t, k)
	if (t[k] % 1.0) ~= 0 then
		error("coordinate dimension "..k.." not node aligned")
	end
end
local checkcoord = function(pos)
	checkdim(pos, "x")
	checkdim(pos, "y")
	checkdim(pos, "z")
	return pos
end



local i = {}

local tableutils = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.tableutils")
local shallowcopy = tableutils.shallowcopy
local mk_voxel_hasher = function(initial_set)
	local seen_set = shallowcopy(initial_set)

	local hasher = function(vertex)
		local pos = checkcoord(vertex.pos)
		local grid = vertex.grid
		seen_set[grid] = true
		local p = "P="..pos.x..","..pos.y..","..pos.z
		return "G="..tostring(grid)..","..p
	end

	return hasher
end
i.mk_voxel_hasher = mk_voxel_hasher

local get_at_position = function(vertex)
	return vertex.grid:get(vertex.pos)
end



return i

