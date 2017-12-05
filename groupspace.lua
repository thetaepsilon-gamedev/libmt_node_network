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
}
]]
local guardedmap = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.datastructs.guardedmap")
local bfmap = mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.bfmap")
local tableutils = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.tableutils")
local shallowcopy = tableutils.shallowcopy



local whichgroup = function(self, vhash) return self.maptogroup:get(vhash) end



-- clear out the given vertex by hash from any internal data tables.
-- returns the group that the hash used to belong to, if any.
-- note this does NOT update the ropegraph, see update() for that.
local clearvertex = function(self, vhash)
	local group = self.maptogroup:remove(vhash)
	return group
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

-- visitor for the repair operation:
-- clear out found vertices from a provided set.
-- used below in the repair operation to clear away reachable vertices;
-- any that remain are not reachable by the search.
local mk_repair_visitor = function(clearset)
	return function(vertex, vhash)
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

-- when a vertex already in a group gets modified,
-- we need to determine if the vertices are all still connected together.
-- pick an arbitary vertex in the group and run a breadth-first flood search,
-- marking each vertex found in the group's current set.
-- if at the end any vertices remain, those have become disconnected and become a new group.
-- repeat the search procedure until either all those vertices have been found,
-- or they have been determined to not exist any more.
local repair = function(self, group)
	-- can't do anything if group contains no elements.
	local ihash, ivertex = group:next()
	if not ihash then
		self:warning({n="undefined.repair_on_empty_group", args={group=group}})
		return false
	end

	local clearset = group:copyentries()
	local orphanset = {}
	local oncomplete = self:mk_repair_onfinished()
	local successor = mk_repair_successor(self.maptogroup, group, self.successor, orphanset)
	local visitor = mk_repair_visitor(clearset)
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
end



local update = function(self, vertex, vhash)
	-- firstly remove any existing information about this vertex
	-- this should clear existing group mappings etc...
	local oldgroup = clearvertex(self, vhash)

	-- ..so that here we can add the vertex as if new.
	local successors = self.successor(vertex, vhash)

	-- we want to see if any groups touching this vertex has room left.
	-- if so, add the vertex to that group directly.
	-- otherwise, or if already added to a group,
	-- make a note of the found group being adjacent to the added one.
	-- (currently unhandled: deal with untracked adjacent vertices)
	local foundgroup = nil
	local touchingvertices = {}
	local touchinggroups = {}
	for shash, successor in pairs(successors) do
		local group = self:getgroup(shash)
		-- argh, why does lua not have continue for loops!?
		if group then
			local canfit = (group:size() < self.grouplimit)
			if not foundgroup and canfit then
				self:addtogroup(group, shash, successor)
				foundgroup = group
			else
				touchingvertices[shash] = successor
				touchinggroups[shash] = group
			end
		else
			self:warning({n="unhandled.untracked_successor", args={shash=shash}})
		end
	end
	-- if none of the successors were groups with room left,
	-- then create a new one and add the vertex to it.
	-- the touching groups will all have been recorded above.
	foundgroup = self:newgroupwith(vertex, vhash)

	-- update the list of groups that this vertex touches.
	self.ropegraph:update(vertex, vhash, foundgroup, touchingvertices, touchinggroups)
end
