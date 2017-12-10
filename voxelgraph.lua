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
The successor function is passed a structure:
vertex = {
	grid = gridimpl,	-- *
	position = { ... },	-- not assumed to be MT xyz vectors!
}
The successor queries the grid for the node at that position, 
then looks up the node name in it's internal data structures.
The candidate neighbours are retrieved either from a presets table
or by dynamically calling a function registered in a callbacks table
(which can e.g. examine metadata).
Then, the successor code asks the grid for the result position for each candidate direction,
as well as the target node's data and grid*.
The directionality data for that node is again looked up by preset table or callback.
If the direction is allowed, then that node's position is added to the successor set.

For both neighbour and directionality data,
it is assumed that the resulting set (whether found statically or dynamically generated)


The testvertex function works by seeing if any kind of neighbour data exists for the node name;
if not, it is assumed to not be one of the nodes that participates.
This can be used to detect when a node has been removed and should be forgotten by the graph tracking.

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
-- requirements of a "linkedgrid":
grid = {
	get = function(self, pos),
		-- must return a table with at least a "name" member.
	getmeta = function(self, pos),
		-- called to retrieve a meta ref to pass to the callback if one needs to be called.
		-- returns a metadata ref as in worldcache.lua;
		-- only required to support the get/set_* operations and flush() to commit.
	neighbour = function(self, pos, direction),
		-- direction is an offset vector (determined by neighbour data lookup).
		-- must return the following:
		-- * target node data
		-- * actual result position (which will be returned in the successor set)
		-- * an equality-comparable representation of the direction back to the origin vertex.
		--	this is used to index into the offsets tables below.
		-- * target grid (which may not be the same as the grid on which the method was invoked)
		--	target grid must obey the same constraints as this one,
		--	and use a coordinate system compatible with the direction/neighbour offset data.
	hashpos = function(pos),
		-- a pure function which must return an equality-comparable unique representation of a position.
}
]]

--[[
self = {
	neighbourdata = {
		"somenodename" = {
			dir1hash = dir1,
			...
		},
		...
	}
	-- table used to look up static list of nodes
	-- takes precedence over the below.
	-- "dirhash" is the representation of the reverse direction as per the grid description above.

	neighbourfn = {
		"anothernode" = function(nodedata, metaref)
			-- the function should examine the provided node data only.
	}

	-- if neighbourdata is present for the target node,
	-- that is indexed by the direction hash returned by the grid to see if any data is present.
	-- if so, the node is assumed to be allowed to connect back to this one.
	-- if not, a function is looked up in the below table and again called with that direction hash;
	-- the result for the direction check is then the outcome of that function.
	directionfn = {
		-- a test function expected to return true/false to indicate an allowed connection direction.
		"anothernode" = function(nodedata, metaref, direction),
		...
	}
}
]]

