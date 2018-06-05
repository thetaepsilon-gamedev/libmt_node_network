--[[
The breadth-first mapping algorithm (see bfmap.lua)
operates on an abstract graph (think dots joined by lines).
We can map this concept to minetest's world
by treating nodes as the "dots" (vertexes)
and connections between suitable adjacent nodes as the lines (edges).
If we provide the algorithm with a way of traversing from one node to the next
(the successor function), the algorithm will flood search all nodes connected to a starting point.

The code below deals with setting this up for a given type of "network" of nodes.
Node data is obtained by a "grid" object*,
and functions should be passed which answer certain queries about encountered nodes.
These functions are provided by the caller to
describe which nodes should be considered part of the network;
nodes which pass all the stages described below are considered neighbours,
whereas those which don't are ignored.

When the successor is called with a starting position,
the query functions are invoked in this order:
+ Neighbour set stage:
	"Which nodes around this one might be a valid neighbour?"
	This is passed just the node's data** (as returned by the grid object)
	as it's single argument,
	and must return a table where the values are MT XYZ offset vectors
	(e.g. {x=0,y=1,z=0} to specify the node immediately above).
	Return {} for no neighbours; nil is treated as an internal error.
	The keys must be unique but may themselves be tables which may carry extra data,
	which will be passed to...
+ Inbound filter stage:
	"Can this node be connected to?"
	This function is passed a table like the following:
	{
		node = { /* nodedata */ },
			-- node data for candidate, same as for source
		extra = ...,
			-- key data of this neighbour as described above
		direction = {...},
			-- *reverse* connection direction, going back out to the origin
			-- (e.g. for the above example the vector would point *down*)
	}
	The keys used in the neighbour set can therefore be used to communicate with the inbound filter.
	It must return a boolean predicate value, indicating if this node is a valid neighbour.

If an offset is a) present in the neighbour set and b) given the ok by the inbound filter,
then it is returned as a successor of this node (and added to the ongoing search).
In this manner, you can teach the search algorithm about exactly which nodes to "connect" to.

For instance (assuming the grid populates the "name" field):
neighbourset = function(node)
	if (node.name == "default:stone") then
		-- horizontal plus "+" pattern: +-X, +-Z
		return { {x=1,y=0,z=0}, {x=-1,y=0,z=0}, {x=0,y=0,z=1}, {x=0,y=0,z=-1}}
	end
	-- explicitly return empty set, nil is treated as an internal error.
	return {}
end
inbound_filter = function(node)
	if node.name == "default:stone" or "default:cobble" then return true end
	return false
end
This defines a network which propogates horizontally
(but not across diagonals) along adjacent stone blocks,
and will also include cobblestone but they are considered a "dead end"
(that is, they will not provide any neighbours to continue the search from them).
More advanced networks could do things like inspect node metadata
(however the grid object would have to provide this data).



* See @INTERFACE linkedgrid below.
The intent here is to be as general as possible,
and not lock out tricks that break under the assumption of a singleton euclidian grid.
Singletons are bad enough practice as-is,
and if e.g. VAEs or other "dimensions" to the MT world get added at some point in the future,
most code using the singletone get/set_node api will fail to work with this.
Additionally, the chosen grid object(s) can correlate extra data with world positions if desired,
relieving the query functions of this burden.

**
This means that in general any callback functions
MUST NOT use any minetest.* functions with world side effects,
such as trying to spawn an entity assuming the coordinates map to the global grid.
Generally speaking, where possible the callbacks must avoid making *any* visible side effects,
as changing things mid-search may cause strange results from the search algorithm.
(In other words: bfmap may assume the graph isn't modified in-flight,
so doing so may cause undefined behaviour - anything could happen!)
]]



--[[
-- @INTERFACE linkedgrid
grid = {
	get = function(self, pos),
		-- where pos is the regular XYZ vector.
		-- returns a table, but no constraints are placed on it's contents;
		-- grids and query functions used together must pre-arrange needed data.
		-- it may assume that pos contains integer coordinates.
		-- please note: if providing a minetest metadata ref,
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
	id = {},
		-- a unique, empty table (it should literally be {} in source code)
		-- which serves to uniquely identify a grid.
		-- this object is used to determine the hash of a grid/position pair
		-- (and therefore if a given vertex has already been visited).
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

--[[
Two positions in separate grids are considered distinct entities.
In order to check whether a given grid/position pair is equal to another,
we create a hash string that includes them both,
utilising the fact that tostring(table) will utilise it's address.

However, it is possible (though unlikely) that an address could potentially wind up re-used,
if another grid is created in the heap in the same space as another one which got garbage collected.
To avoid this problem, a given instance of the successor retains references to seen grids.
This way, the grids remain live as long as the successor does,
ensuring that addresses from tostring of a table will not collide.
]]
local tableutils = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.tableutils")
local shallowcopy = tableutils.shallowcopy
local mk_voxel_hasher = function(initial_set)
	local seen_set = shallowcopy(initial_set)

	local hasher = function(vertex)
		local pos = checkcoord(vertex.pos)
		local id = vertex.grid.id
		assert(id ~= nil)
		seen_set[id] = true
		local p = "pos="..pos.x..","..pos.y..","..pos.z
		return "gid="..tostring(id)..","..p
	end

	return hasher
end
i.mk_voxel_hasher = mk_voxel_hasher

local get_at_position = function(vertex)
	return vertex.grid:get(vertex.pos)
end



return i

