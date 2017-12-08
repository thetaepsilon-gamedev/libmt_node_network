--[[
Similar to vertex spaces, but written with different assumptions in mind.
Instead of whole graphs where adding link between them indiscriminately merges them,
vertexes belong to groups which may be subsets of a full interconnected graph.

The successor function understood by the search algorithm remains,
but it is possible that connections between vertices span between groups.
As usual, successor returns a table mapping from hashes to values for each vertex.

That said, there are still some rules involved.
In a given group space, there is a 1:1 mapping to/from a given tracked vertex and it's group at all times.
Groups have a limit on their size (call it "L") -
Adding a vertex with connections to a group's vertices will add that vertex to the group only if it fits,
otherwise a new group forms.
Like the vertex space, a complete split between two parts of a group causes the group to split apart,
however the "still connected" search does not propogate past group boundaries.
So, if the only "bridge" between two disconnected halves of a group is via another group's nodes,
the split will still occur.

The point of this grouping is to place limits on how far into the graph a connectivity search will proceed.
Combined with a regular vertex space (or maybe even another group space),
The connections between neighbouring groups can be tracked to form a higher-level connectivity graph.
When a group is modifed, the search will only proceed at most L vertices,
*then* the higher-level graph is modified.
In most cases, unless a group splits apart, the higher-level graph doesn't need modifying,
yielding amortised O(1) performance.
]]

--[[
self = {
	ropegraph = {},	-- see ropegraph.lua
	maptogroup = {},	-- actually guardedmap from libmthelpers datastructs.
		-- keys in here are hashes and the values are the group tables.
		-- groups are passed around by value,
		-- so callers can already use this to obtain refs to other groups using the ropegraph.
		-- this guarded map has no remove callback.
		-- group tables are guarded maps also;
		-- their remove operation warns if there is an attempt to remove a non-existant vertex.
	grouplimit = 20,
		-- size limit on groups
		-- flood search operations are guaranteed to not run past this many found vertices.
	successor = function,
		-- successor function as described by bfmap for this kind of graph.
	testvertex = function,
		-- testvertex also as understood by bfmap.
}
]]
local guardedmap = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.datastructs.guardedmap")
local bfmap = mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.bfmap")
local ropegraph = mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.ropegraph")
local tableutils = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.tableutils")
local checkers = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.check")
local shallowcopy = tableutils.shallowcopy



local whichgroup = function(self, vhash) return self.maptogroup:get(vhash) end



-- clear out the given vertex by hash from any internal data tables.
-- returns the group that the hash used to belong to, if any.
-- note this does NOT update the ropegraph, see update() for that.
local clearvertex = function(self, vhash)
	local group = self.maptogroup:remove(vhash)
	return group
end



-- entire-group discard operation:
-- removes mappings for every vertex in the group from the maptogroup table,
-- then updates the ropegraph for each vertex with a nil set to clear all vertices.
-- TODO: callback invocations for group destruction?
local unmap_group = function(self, group)
	local m = self.maptogroup
	local r = self.ropegraph
	local empty = {}
	for vhash, vertex in group:iterator() do
		m:remove(vhash)
		-- ropegraph guaranteed to completely forget the vertex if nil sets passed
		r:update(vertex, vhash, group, empty, empty)
	end
end



-- successor function for the repair operation that looks for any vertices either untracked,
-- or the same group as a given group.
-- a lower successor function is passed which is then wrapped,
-- and each returned vertex is looked up in the vertex-to-group mapping.
-- those entries which either match the expected group are returned.
-- optionally, any vertices missing a group (i.e. they're not tracked yet for whatever reason)
-- are saved in an orphan table.
-- groupless vertices do not participate in or affect the search while running,
-- per the rules for the successor set out by bfmap.
local mk_repair_successor = function(groupmap, expectedgroup, lowersuccessor, orphanset)
	return function(vertex, vhash)
		local results = {}
		local successors = lowersuccessor(vertex, vhash)
		
		for shash, successor in pairs(successors) do
			local group = groupmap:get(shash)
			if group == expectedgroup then
				results[shash] = successor
			else
				if group == nil and orphanset then orphanset[shash] = successor end
			end
		end

		return results
	end
end
local mk_repair_successor_auto = function(self, expectedgroup, orphanset)
	return mk_repair_successor(self.maptogroup, expectedgroup, self.successor, orphanset)
end

-- visitor for the repair operation:
-- clear out found vertices from a provided set.
-- used below in the repair operation to clear away reachable vertices;
-- any that remain are not reachable by the search.
local mk_repair_visitor = function(clearset, foundset)
	return function(vertex, vhash)
		foundset[vhash] = vertex
		clearset[vhash] = nil
	end
end

-- onfinished callback for repair operation.
-- groups should never be allowed to grow beyond the group limit anyway,
-- therefore a search with that size as it's limit should be able to reach them all,
-- with no frontiers left in the search queue.
-- if any *are* found (in other words, the search ended due to a limit),
-- raise a warning.
local mk_repair_onfinished = function(self)
	local parent = self
	return function(remainder_iterator)
		local count = 0
		for hash, vertex in remainder_iterator do
			count = count + 1
		end
		if count > 0 then
			parent:warning({n="repair.unreached_search_frontiers", args={count=count}})
		end
	end
end



-- run searches from a set of vertexes until they are all discovered.
-- if an isolated vertex is found while starting a search from another isolated vertex,
-- it is removed before the search picks the next vertex.
-- the found vertices get added to a new group;
-- then the next vertex is picked out (if any) and the process repeats.
-- each isolated set of vertices becomes a new group.
local recover_vertices = function(self, clearset)
	local discover_successor = self:mk_repair_successor(nil, nil)
	local testvertex = self.testvertex
	local opts = { vertexlimit=self.grouplimit }

	while true do
		local hash, vertex = next(clearset)
		if not hash then break end

		local foundset = {}
		local discover_visitor = mk_repair_visitor(clearset, foundset)
		local callbacks = { testvertex=testvertex, visitor=discover_visitor }
		-- we rely on the search algorithm testing the vertex for validity for us.
		-- therefore if the foundset is empty, don't bother creating a new group,
		-- and just forget about the invalid vertex.
		local search = bfmap.new(vertex, hash, discover_successor, callbacks, opts)
		while search.advance() do end
		if next(foundset) == nil then
			clearset[hash] = nil
		else
			self:newgroupbatch(foundset)
		end
	end
end



-- when a vertex already in a group gets modified,
-- we need to determine if the vertices are all still connected together.
-- pick an arbitary vertex in the group and run a breadth-first flood search,
-- marking each vertex found in the group's current set.
-- if at the end any vertices remain, those have become disconnected and become a new group.
-- repeat the search procedure until either all those vertices have been found,
-- or they have been determined to not exist any more.
-- after calling this function, group may no longer be valid;
-- if this function returns true, then that is the case.
local repair = function(self, group)
	-- can't do anything if group contains no elements.
	local ihash, ivertex = group:next()
	if not ihash then
		self:warning({n="undefined.repair_on_empty_group", args={group=group}})
		return false
	end

	local clearset = group:copyentries()
	local foundset = {}
	local orphanset = {}
	local oncomplete = self:mk_repair_onfinished()
	local successor = self:mk_repair_successor(group, orphanset)
	local visitor = mk_repair_visitor(clearset, foundset)
	local callbacks = {
		visitor = visitor,
		testvertex = self.testvertex,
		finished = oncomplete,
	}
	local opts = {vertexlimit = self.grouplimit}
	-- run the search up to the group size limit.
	-- as the search can only traverse vertices in this group,
	-- if the graph remains intact this should be able to flood to all of them.
	-- any that become unreachable after the search spawn new searches,
	-- to determine the graph subsets for the newly split groups.
	local search = bfmap.new(ivertex, ihash, self.successor, callbacks, opts)
	while search.advance() do end

	-- if there are any unreachable groups, the group has split, so discard the old group.
	-- searches will then spread out across previously untracked vertices too.
	-- FIXME: validity test should be ran here!
	if next(clearset) == nil then return false end
	self:unmap_group(group)
	self:newgroupbatch(foundset)

	-- for the remaining vertices that got isolated, keep spawning searches until they are all covered.
	self:recover_vertices(clearset)

	-- let the caller know that the group was deleted
	return true
end



-- adds an untracked but "alive" vertex.
-- attempts to find a group to add it to by looking at it's successors,
-- or creates a new one if all the neighbour groups are at the limit.
local add_new = function(self, vertex, vhash)
	local successors = self.successor(vertex, vhash)

	-- we want to see if any groups touching this vertex has room left.
	-- if so, add the vertex to that group directly.
	-- otherwise, create a new group for it.
	-- (currently unhandled: deal with untracked adjacent vertices)
	local foundgroup = nil
	local touchingvertices = {}
	local touchinggroups = {}
	for shash, successor in pairs(successors) do
		local sgroup = self:whichgroup(shash)
		-- argh, why does lua not have continue for loops!?
		if sgroup then
			local canfit = (sgroup:size() < self.grouplimit)
			if not foundgroup and canfit then
				self:addtogroup(sgroup, shash, successor)
				foundgroup = sgroup
			else
				touchingvertices[shash] = successor
				touchinggroups[shash] = sgroup
			end
		else
			self:warning({n="unhandled.untracked_successor", args={shash=shash}})
		end
	end
	-- if none of the successors were groups with room left,
	-- then create a new one and add the vertex to it.
	-- the touching groups will all have been recorded above.
	foundgroup = foundgroup or newgroupwith(self, vertex, vhash)

	-- update the list of groups that this vertex touches.
	self.ropegraph:update(vertex, vhash, foundgroup, touchingvertices, touchinggroups)

	return true
end



-- update an existing tracked vertex, which may be alive or have become "dead"
-- (that is, testvertex() returns false for it).
local update_existing = function(self, vertex, vhash, vgroup, isalive)
	-- updating a vertex may mean the successors it connects to has changed.
	-- to check that the group is still intact, we run a search (see repair() above).
	-- however, first we must locate a still-valid vertex to start from,
	-- else the successor may exhibit undefined behaviour.
	-- in addition, remove the vertex if it is dead.

	if not isalive then
		-- if dead, clear the vertex from the group.
		clearvertex(self, vhash, vgroup)
	end

	-- then let the repair operation locate a valid vertex to search from.
	-- repair() above returns false if the group was empty
	-- (which it may do if the triggering vertex was the last member of the group).
	-- in that event, take any steps to completely de-register the group and de-allocate it.
	-- FIXME WIP
	-- TODO: what about ropegraph updates here?

	return true
end



-- updates a vertex's internal tracking information.
-- this can be used when a vertex's edges have been modified,
-- e.g. due to an MT node being rotated by the screwdriver or some other node-local change.
-- also handles removal; can be called with a "just deleted" vertex,
-- and the testvertex operation is used to detect this.
-- things to consider here:
--	* changes in edges that cross group boundaries are handled by the rope graph.
--	* changes in edges to vertices in the same group may cause the group to fragment;
--		see repair() above.
--	* TODO changes in edges to untracked successor vertices are currently ignored.
local update = function(self, vertex, vhash)
	-- determine if the vertex under question is currently tracked.
	local group = self:whichgroup(vhash)
	local tracked = (group ~= nil)
	-- check also if the vertex reference is still valid.
	local isalive = self.testvertex(vertex, vhash)

--[[
	Cases to handle here:
	* untracked and dead (isalive == false): ignore it, invalid vertices are not part of the graph.
	* untracked and alive: vertex is new, try to insert it into a group. no group repair operation needed.
	* already tracked (dead or alive):
		existing connectivity info may have changed, so run the repair operation.
]]
	if tracked then
		return update_existing(self, vertex, vhash, group, isalive)
	else	-- if untracked
		if alive then
			return add_new(self, vertex, vhash)
		else
			return false
		end
	end
end



-- internal warning function.
-- for now, just call the debugger
local warning = function(self, ev)
	return self.debugger(ev)
end



-- external interface follows
local i = {}

local new_rg = ropegraph.new

-- callback table checking
local callback_signatures = {
}
local dname = "groupspace.new() "
local defaults = {}
local checkc = checkers.mk_interface_defaulter(dname.."callbacks table invalid:", callback_signatures, defaults)
-- use interface checking for optional callbacks as well
local opts_signatures = {
	"debugger",
}
local checko = checkers.mk_interface_defaulter(dname.."passed optionals invalid:", opts_signatures, defaults)



local prototype = {
	update = update,
	whichgroup = whichgroup,
	warning = warning,
}

-- WIP, nowhere near complete!
local construct = function(impl, opts)
	opts = checko(opts)
	local debugger = opts.debugger

	local self = shallowcopy(prototype)
	self.debugger = debugger
	self.callbacks = checkc(opts.callbacks)
	self.ropegraph = new_rg()

	return self
end
i.new = construct

return i
