-- a structure used to track connections between vertex groups.
-- adjacent groups may have potentially many edges that cross over and connect them.
-- this structure effectively maintains refcounted mappings of which groups connect to others,
-- and which pairs of vertexes form the edges spanning those boundaries.
-- it also provides a successor function which may be used to traverse this web as a higher-level graph;
-- this may be plugged into a higher level vertex space to get a full connectivity graph.

-- invariants:
-- group handles are considered opaque, they can be table references, ints or whatever.
-- a group handle is considered distinct from another as long as they do not compare equal.
-- however, mixing handle values which may alias inside a table is undefined behaviour.
-- the successor function, per requirements for a successor from the search algorithm,
-- will never deliver a group N as a successor vertex when N itself is passed as input.

--[[
internally, the data structure stores "big edges" (referred to as "ropes" below)
from one group to another, and the vertex-pair edges which form it
(as well as keeping track of the count).
the following look-up abilities are required:
+ which edges does this vertex form a part of?
+ which ropes contain any of those edges?
+ which ropes are associated with a given group?

vertexmap = {
	-- references to vertices that form edges with this one.
	[hash1] = {
		-- imagine this is a set type so we don't have to go searching the array.
		-- inside each entry, the hashes are always stored with the "lesser" value first,
		-- as determined by the less-than operator.
		{ hash1, hash2 },
		{ hash1, hash3},
	},
	[hash2] = {
		-- this is a reference to the same table as above...
		edge1,
		...
	},
	[hash3] = ...,
	...
}
ropemap = {
	[edge1] = [rope1],	-- direct table ref. as opposed to the below hashing
	...
}
ropes = {
	-- indexed by appending the two group IDs.
	["group1!!group2"] = {
		group1 = ...
		group2 = ...,
		count = 1,
	},
	...
}
]]

local get_other_vertex = function(edge, hash)
	for i = 1, 2, 1 do
		local otherhash = edge[i]
		if otherhash ~= hash then return otherhash end
	end
end

--  remove a given edge from the set of edges associated with a given vertex.
-- if afterwards the vertex has no edges associated with it,
-- clean up the set also.
local unlink_edge_for_vertex(self, hash, edge)
	local edgeset = self.vertexmap[hash]
	edgeset:remove(edge)
	-- FIXME: warn if the above does something unexpected?
	if edgeset:size() == 0 then
		self.vertexmap[hash] = nil
	end
end

-- remove a vertex and any edges stored for it.
local remove_vertex = function(self, hash)
	local removed_edges = {}
	-- get the other vertex associated with each of the edges this vertex is part of.
	-- update the tracking entries for those other vertices to remove their link to those edges
	for edge in self.vertexmap.iterator() do
		table.insert(removed_edges, edge)
		local otherhash = get_other_vertex(edge, hash)
		-- make sure the other vertex does not have an edge pointing back to this one.
		unlink_edge_for_vertex(self, otherhash, edge)
	end
	-- then simply drop the edges set for this vertex to remove them all at once.
	self.vertexmap[hash] = nil

	return removed_edges
end

-- canonical hasher to determine if a group pair already exists as a rope.
-- takes the form "a!!b", where a is always the group that is less than (from "<") the other.
local hash_rope = function(a, b)
	local x, y
	if a < b then
		x, y = a, b
	else
		x, y = b, a
	end
	return tostring(a).."!!"..tostring(b)
end



-- svertices and sgroups are indexed by the associated hash.
-- this updates the internal structures to reflect the current set of successor edges.
-- removal of a vertex can be achieved by passing empty tables for svertices and sgroups.
local update = function(self, overtex, ohash, ogroup, svertices, sgroups)
	-- look up and remove the existing edges associated with the origin vertex.
	-- for each, take one from the count of the rope it belongs to,
	-- and make a note of each rope encountered.
	-- if at the end (after re-adding) a rope's refcount has decreased to zero,
	-- delete it.
	local ropes_to_check = {}
	local removed_edges = remove_vertex(self, ohash)
	for _, edge in removed_edges do
		local rope = ropemap[edge]
		rope:countdown()
		ropes_to_check[rope] = true
	end
	-- defer refcount checking until later...
	-- adding links back in may raise them again.

	-- now add links back for the specified successors.
	-- here we have to check if a given group pair already exists as a rope.
	for shash, svertex in pairs(svertices) do
		local sgroup = sgroups[hash]
		
	end
end

