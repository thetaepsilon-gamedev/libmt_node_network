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

--[[
local addvertex = function(self, vertex)
	-- same group optimisation: if all successors reside in the same existing group,
	-- add it to that group if it'll fit, else create a new one.
	
end
]]