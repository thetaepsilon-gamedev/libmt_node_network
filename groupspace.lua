--[[
Similar to vertex spaces, but written with different assumptions in mind.
Instead of whole graphs where adding link between them indiscriminately merges them,
vertexes belong to groups which may be subsets of a full interconnected graph.
The successor function understood by the search algorithm and vertex space remains,
but it is possible that connections between vertices span between groups.

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



local update = function(self, vertex)
	-- firstly remove any existing information about this vertex
	-- this should clear existing group mappings etc...
	local vhash = self.hasher(vertex)
	self:clearvertex(vhash)

	-- ..so that here we can add the vertex as if new.
	local successors = successor(vertex)
	successors = toset(successors)

	-- we want to see if any groups touching this vertex has room left.
	-- if so, add the vertex to that group directly.
	-- otherwise, or if already added to a group,
	-- make a note of the found group being adjacent to the added one.
	-- (currently unhandled: deal with untracked adjacent vertices)
	local foundgroup = nil
	local touchingvertices = {}
	local touchinggroups = {}
	for successor in successors:iterator() do
		local shash = self.hasher(successor)
		local group = self:getgroup(shash)
		-- argh, why does lua not have continue for loops!?
		if group then
			local canfit = (group:size() < self.grouplimit)
			if not foundgroup and canfit then
				self:addtogroup(group, hash)
				foundgroup = group
			else
				touchingvertices[shash] = successor
				touchinggroups[shash] = group
			end
		else
			self:warning("unhandled.untracked_successor")
		end
	end
	-- if none of the successors were groups with room left,
	-- then create a new one and add the vertex to it.
	-- the touching groups will all have been recorded above.
	foundgroup = self:newgroupwith(vhash)

	-- update the list of groups that this vertex touches.
	self.ropegraph:update(vertex, vhash, foundgroup, touchingvertices, touchinggroups)
end
