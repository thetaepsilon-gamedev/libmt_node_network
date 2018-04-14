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
* The nodes which should be looked at around the origin node (the neighbour candidate set)
* whether those nodes are allowed to connect back on that side (the direction check)

The structures below allow determining this.
The successor function's vertex structure looks like the following:
vertex = {
	grid = gridimpl,	-- *
	position = { x, y, z },
}
The hashes produced by this successor are a contatenation of tostring() on the grid object,
followed by a string representation of the XYZ coordinates.
In order to prevent address re-use problems if a grid object happens to vanish mid-search,
a given successor instance maintains references to all seen grids while it is still alive. 

The successor queries the vertex's grid for the node at the vertex position, 
then looks up the node name in it's internal data structures.
The candidate neighbours are retrieved either from a presets table
or by dynamically calling a function registered in a callbacks table
(which can e.g. examine metadata).
In either case, the result is a list-like table,
which holds relative vectors of nodes to check, e.g. {x=0,y=1,z=0} for the node above.

Then, the successor code asks the grid object for the resulting grid and position on that grid*,
then calls that grid with that position to retrieve node data.
The directionality data for that node is again looked up by preset table or callback.
If the direction is allowed, then that node's position is added to the successor set.

* The intent here is to be as general as possible,
and not lock out tricks that break under the assumption of a singleton euclidian grid.
Passing the grid a direction instead of calculating offsets directly allows "portals",
where a graph of nodes can span otherwise logically disconnected areas.
Likewise, differing target grids allows the code to cross boundaries to something other than the MT world;
for example, the sought after but ever postponed Voxel Area Entities,
which would be freely rotateable and would not relate directly to "global" co-ordinates.
This means that in general any callback functions MUST NOT use any minetest.* functions with world side effects,
such as trying to spawn an entity assuming the coordinates map to the global grid.
]]

--[[
-- @INTERFACE linkedgrid
grid = {
	get = function(self, pos),
		-- must return a table with at least a "name" member, like minetest.get_node().
	getmeta = function(self, pos),
		-- called to retrieve a meta ref to pass to the callback if one needs to be called.
		-- returns a metadata ref as in worldcache.lua;
		-- only required to support the get/set_* operations and flush() to commit.
	neighbour = function(self, pos, direction),
		-- direction is an offset vector from pos.
		-- must return the following:
		-- * actual result position
		-- * target grid (which may not be the same as the grid on which the method was invoked)
}
]]





