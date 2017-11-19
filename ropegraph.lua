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

-- I wish I could write "namespace" and datastructs::tableset::new_raw() sometimes...
local require = mtrequire	-- see modns - built-in require() is disabled for security
local ns_datastructs = require("com.github.thetaepsilon.minetest.libmthelpers.datastructs")

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
groupmap = {
	-- indexed by group ID:
	[group1] = {
		-- set of groups connected to this one
		group2,
		group3,
		...
	}
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
local unlink_edge_for_vertex = function(self, hash, edge)
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

	-- early return if the hash does not exist yet.
	if self.vertexmap[hash] == nil then return {} end

	-- get the other vertex associated with each of the edges this vertex is part of.
	-- update the tracking entries for those other vertices to remove their link to those edges
	for edge in self.vertexmap[hash]:iterator() do
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
-- !! implies the group IDs are by-value comparable!
local hash_rope = function(a, b)
	local x, y
	if a < b then
		x, y = a, b
	else
		x, y = b, a
	end
	return tostring(a).."!!"..tostring(b)
end

-- obtains the set of other groups on edges leading away from a given group ID.
-- creates it if it does not exist.
local getgroupset = function(self, groupid)
	local map = self.groupmap
	local groupset = map[groupid]
	if not groupset then
		print("creating group set for ID "..groupid)
		groupset = ns_datastructs.tableset.new_raw()
		map[groupid] = groupset
	end
	return groupset
end

-- obtains the reference to a rope given it's group pair hash,
-- or creates a new one if it didn't exist
local countup = function(self) self.count = self.count + 1 end
local countdown = function(self) self.count = self.count - 1 end
local getrope = function(self, groupa, groupb)
	local gpairhash = hash_rope(groupa, groupb)
	local ropes = self.ropes
	local rhandle = ropes[gpairhash]
	if rhandle == nil then
		rhandle = {
			group1 = groupa,
			group2 = groupb,
			count = 0,
			countup = countup,
			countdown = countdown,
		}
		ropes[gpairhash] = rhandle
		-- set up tracking entries from one group to another for successor
		local groupseta = getgroupset(self, groupa)
		groupseta:add(groupb)
		local groupsetb = getgroupset(self, groupb)
		groupsetb:add(groupa)
	end

	return rhandle
end

-- similar to the above, but for individual vertices (not edges).
-- obtains the edge set for a given vertex or initialises it to empty if it does not exist.
local getedgeset = function(self, hash)
	local map = self.vertexmap
	local edgeset = map[hash]
	if not edgeset then
		edgeset = ns_datastructs.tableset.new_raw()
		map[hash] = edgeset
	end
	return edgeset
end

-- creates an edge between two vertex hashes and associates the edge into both of their edge sets.
-- this ensures that an edge is "accessible" from either of the vertices in it.
local add_edge = function(self, hasha, hashb)
	local seta = getedgeset(self, hasha)
	local setb = getedgeset(self, hashb)
	local edge = { hasha, hashb }
	seta:add(edge)
	setb:add(edge)
	return edge
end

-- check to see if a group pair should be stored or not.
local validate_group_pair = function(groupa, groupb)
	return (
		(groupa ~= nil) and
		(groupb ~= nil) and
		(groupa ~= groupb))
end

-- clean up a list of candidate removal ropes if their refcount is zero.
local cleanup_ropes = function(self, candidate_list)
	for _, rope in ipairs(candidate_list) do
		if rope.count == 0 then
			local rhash = hash_rope(rope.group1, rope.group2)
			print("rope is being discarded: "..rhash)
			self.ropes[rhash] = nil
			-- when a rope is to be vanished,
			-- also update the successor entries to reflect the removal.
			groupmap[rope.group1]:remove(rope.group2)
			groupmap[rope.group2]:remove(rope.group1)
		end
	end
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
	for _, edge in ipairs(removed_edges) do
		local rope = ropemap[edge]
		rope:countdown()
		ropes_to_check[rope] = true
	end
	-- defer refcount checking until later...
	-- adding links back in may raise them again.

	-- now add links back for the specified successors.
	-- here we have to check if a given group pair already exists as a rope.
	for shash, svertex in pairs(svertices) do
		local sgroup = sgroups[shash]
		-- validate the group pair.
		-- if either group is nil or they are the same,
		-- don't store it as else it'll break invariants
		-- (not to mention causing nil key errors)
		if validate_group_pair(ogroup, sgroup) then
			-- see definition above
			local rope = getrope(self, ogroup, sgroup)
			-- create an edge for this pair of vertices and link it to these hashes
			local edge = add_edge(self, ohash, shash)
			-- associate it with it's containing rope
			self.ropemap[edge] = rope
			rope:countup()
		else
			print("discarding invalid group pair")
		end
	end

	-- now check if the ropes that were decremented earlier are still non-zero.
	cleanup_ropes(self, ropes_to_check)
end

-- successor function for using the rope graph:
-- given the data structure and a starting group ID,
-- returns the set of groups which are connected to the starting one.
local successor = function(self, startgroup)
	local groupset = self.groupmap[startgroup]
	local result = {}
	if groupset ~= nil then
		for group in groupset:iterator() do
			print("successor found entry: "..tostring(group))
			table.insert(result, group)
		end
	else
		print("group doesn't exist. groupid="..tostring(startgroup))
	end
	return result
end



local interface = {}

local newropegraph = function()
	local self = {}
	self.vertexmap = {}
	self.ropemap = {}
	self.ropes = {}
	self.groupmap = {}
	self.successor = successor
	self.update = update
	return self
end
interface.new = newropegraph
interface.successor = successor

return interface
