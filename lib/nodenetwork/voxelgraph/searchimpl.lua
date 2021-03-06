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
			-- inbound connection direction, going *into* the node
			-- (e.g. above upwards vector going inwards is the bottom side)
	}
	The keys used in the neighbour set can therefore be used to communicate with the inbound filter.
	It must return a boolean predicate value, indicating if this node is a valid neighbour.

If an offset is a) present in the neighbour set and b) given the ok by the inbound filter,
then it is returned as a successor of this node (and added to the ongoing search).
In this manner, you can teach the search algorithm about exactly which nodes to "connect" to.
See the associated test script (tests/test_voxelgraph_searchimpl.lua) to see an example.



* See @INTERFACE linkedgrid described in lib/nodenetwork/grid/linkedgrid.lua.

**
This means that in general any callback functions
MUST NOT use any minetest.* functions with world side effects,
such as trying to spawn an entity assuming the coordinates map to the global grid.
Generally speaking, where possible the callbacks must avoid making *any* visible side effects,
as changing things mid-search may cause strange results from the search algorithm.
(In other words: bfmap may assume the graph isn't modified in-flight,
so doing so may cause undefined behaviour - anything could happen!)
]]



-- get the special out-of-bounds sentinel value.
local linkedgrid =
	mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.grid.linkedgrid")
local oob = linkedgrid.constants.out_of_bounds()

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
	local seen_set
	if initial_set ~= nil then
		seen_set = shallowcopy(initial_set)
	else
		seen_set = {}
	end

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



-- phase 2 helper:
-- handle getting grid data and invoking the inbound filter.
-- returns successor vertex if everything went ok and the filter said yes,
-- otherwise returns nil.
local aget = function(v) assert(v ~= nil) return v end
local filter_candidate_offset = function(bpos, currentgrid, extradata, offset, inbound_filter)
	-- asserts due to refactor...
	aget(bpos)
	aget(currentgrid)
	aget(extradata)
	aget(offset)
	aget(inbound_filter)

	local remoteloc = currentgrid.neighbour(bpos, offset)
	-- only process the location if it's not out of bounds.
	if remoteloc ~= oob then
		assert(remoteloc ~= nil)

		-- we have: newgrid, newpos, newdirection
		-- we need: newnode, extra, newdirection
		local newpos = aget(remoteloc.pos)
		local newgrid = aget(remoteloc.grid)
		local newdir = aget(remoteloc.direction)
		local newnode = newgrid.get(newpos)
		if newnode ~= oob then
			assert(newnode ~= nil)
			-- XXX: defensive copy of newnode?
			local accept = inbound_filter({
				node=newnode,
				extra=extradata,
				direction=newdir,
			})
			if accept then
				-- if it passed all that: add as successor
				local sv = {
					grid=newgrid,
					pos=newpos,
					data=newnode
				}
				return sv
			else
				-- rejected by filter, ignore it
				return nil
			end
		else
			-- node was oob for this offset: fell off the grid
			return nil
		end
	else
		-- remoteloc was oob for offset: fell off the grid
		return nil
	end
end





--[[
Internal graph vertex structure for voxel graphs:
{
	grid = { ... },	-- source grid
	pos = { ... },	-- position on that grid
}
]]
-- note that due to the hasher needing to retain state as described earlier,
-- an instance of it must be passed in.
local successor_inner = function(vertex, neighbourset, inbound_filter, hasher)
	local currentgrid = aget(vertex.grid)

	-- phase 1: get current node and get candidates around it
	-- node is cached in vertex data so just use that.
	local bpos = vertex.pos
	assert(bpos ~= nil)
	local node = currentgrid.get(bpos)
	assert(node ~= nil)
	-- did we get out of bounds for some reason?
	-- if so, just return the empty set.
	if (node == oob) then return {} end

	local candidates = neighbourset(node)
	-- XXX: customise failure mode?
	if candidates == nil then return {} end
	assert(type(candidates) == "table")

	-- phase 2:
	-- load candidate positions around this node,
	-- query inbound filter stage
	local successors = {}
	for extradata, offset in pairs(candidates) do
		local vertex =
			filter_candidate_offset(
				bpos,
				currentgrid,
				extradata,
				offset,
				inbound_filter)
		if vertex ~= nil then
			local hash = hasher(vertex)
			assert(hash ~= nil)
			assert(
				successors[hash] == nil,
				"hash collision!? bug or duplicate candidate!")
			successors[hash] = vertex
		end
	end

	return successors
end



-- public interface follows
local i = {}

local cf = check.mkfnexploder("create_successor()")
local create_successor = function(query_functions)
	-- why isn't there some kind of macro facility for this...
	local neighbourset =
		cf(query_functions.neighbourset, "query_functions.neighbourset")
	local inbound_filter =
		cf(query_functions.inbound_filter, "query_functions.inbound_filter")
	local hasher = mk_voxel_hasher(nil)

	return function(vertex, hash)
		return successor_inner(vertex, neighbourset, inbound_filter, hasher)
	end, hasher
end
i.create_successor = create_successor



return i

