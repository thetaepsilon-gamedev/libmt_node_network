--[[
Graph tracker object:
whenever something about the structure of a graph changes,
notify this object so it can update it's internal tracking of connected graphs.

The purpose of this object is to remember which nodes are
(directly or indirectly) reachable from each other.
The vertices and edges of a given graph are not owned by this object;
they exist regardless, either implicitly or explicitly
(e.g. in the minetest world case,
edges are implied by two suitable nodes next to each other).
The successor function can be used to step from a vertex to it's linked neighbours,
but that doesn't give us the bigger picture:
O---O---O---O---O   O---O
We can tell by looking at this diagram
that the five vertices on the left can all reach each other,
by walking along the neighbour links (edges) to reach the target one.
However, the two left-most vertices, while they can reach each other,
can *never* reach the other five, because there's no links to get there.
Hence, we can intuitively see that there are two independent groups of nodes.

However, all an algorithm can "see" is the immediate neighbours,
as returned by the successor function.
So, we need to do some book-keeping to retain the "bigger picture".
In the example above, we can start a "flood fill"
of the graph starting from the left-most vertex,
by looking at it's successors, and then the successors of those successors,
and so on, keeping track of all visited vertexes, until we can proceed no further;
exploring all possible links to other nodes that we can find.
[X = visited, O = not visited]
X---O---O---O---O   O---O
vvvvv
X---X---O---O---O   O---O
...
X---X---X---X---X   O---O

At this point, we can put all these visited vertexes into a bucket,
and label them as a "group" (say we give it some unique ID).
In the above diagram, the two on the left were not touched by this flood search,
but they remain anyway, so if we add those into tracking
we know they're an independent group.

The flood fill searching is done via a breadth-first traversal (see bfmap.lua).
Among other things, this search algorithm doesn't visit a vertex more than once,
and in general is O(n) time on the size of the group it must map out.
]]



--[[
First, some prerequisites.
Sets of vertexes, as discussed elsewhere in this mod,
are expressed as tables, with the keys being "hashes" of the vertex
for the purposes of testing whether or not the vertex is present in a given table.
In the code below, it is assumed that at any one time,
a vertex belongs to zero or one groups.
So we need a way to determine what vertexes belong to a group,
as well as which group a vertex belongs to.

Groups themselves are stored in the master set of all groups,
which is a table mapping some opaque, unique ID to the group objects themselves.
master_set = {
	[some_id_object] = /* group object */,
	...
}
These group objects are tables of the following form:
{
	vertices = { /* hashed vertex set */ },
}
The reverse mapping is simply one table mapping hashes back to ids.
reverse_mapping = {
	"somevertexhash_0xdeadbeef" = another_id_object,
	...
}
The reverse mapping below is not exposed directly but is passed around as a function,
however it's principle is the same - pass it a hash,
and it'll either respond wich an ID or nil.
]]



-- the bfmap routine offers various hooks that can be run during the search.
-- for the most part, we're only interested in the visitor callback,
-- and we just want to lump all found vertices into a table.
-- so first, the visitor hook:
local mk_set_visitor = function()
	local gathered = {}
	local visitor = function(vertex, hash)
		assert(gathered[hash] == nil, "WTF condition: duplicate visitation!?")
		gathered[hash] = vertex
	end
	return visitor, gathered
end
local m_bfmap = mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.floodsearch.bfmap")
local newsearch = m_bfmap.new
-- then, kick off a search from a given vertex,
-- again gathering up vertices it finds.
local callbacks = {}
local init_search = function(initialv, initialhash, successor)
	local visitor, gathered = mk_set_visitor()
	callbacks.visitor = visitor
	local opts = nil
	local search = newsearch(initialv, initialhash, successor, callbacks, opts)
	return search, gathered
end
-- finally, bake in the initial hasher for code that doesn't need to see it.
local bake_constructor_hasher_ = function(hasher)
	return function(initialv, successor)
		return init_search(initialv, hasher(initialv), successor)
	end
end




-- wrap a successor and only allow vertices which are currently untracked,
-- but make a note of which other groups have been touched.
local mk_untracked_successor = function(base, maptogroup)
	assert(type(base) == "function")
	local touchedset = {}

	local successor = function(vertex, hash)
		local b = base(vertex, hash)
		-- NB: the lua 5.1 manual says we're allowed to clear fields here
		for hash, vertex in pairs(b) do
			local groupid = maptogroup(hash)
			if groupid ~= nil then
				b[hash] = nil	-- remove from set
				touchedset[groupid] = true
			end
		end
		return b
	end

	return successor, touchedset
end



--[[
To deal with a newly created vertex (one that previously didn't exist,
e.g. a new cable node was added to the minetest world),
the first step is for some code to pass the vertex reference to the graph tracker.
To handle this, we must first examine the neighbours of the newly created vertex
by calling the successor on it to retrieve the set of neigbours.

The simplest case is when the new vertex "floats" alone, unconnected:
...X---X---X         N [the new vertex]        X---X---X...
In this case, the successor set will be empty (size zero / no entries).
Then we can just assign a new group ID and add N to it.

Another case is when there is a connection to exactly one existing group.
...X---X---X     N--[new connection!]--X---X---X...
In that case, we update our tracking as appropriate, simply adding N to the existing group.

Yet another case is when the new vertex bridges two or more existing groups:
...X---X---X---N---X---X---X...
Now we have the situation where multiple groups are connected,
which isn't allowed as groups are supposed to represent logically disconnected fragments.
So, we create a new group, re-assign all their vertices (plus the new one)
to the new group, and mark the formerly separate groups as merged.

Finally, because we're always effectively at least one step behind the "real" state,
we have to deal with the case where there is an area of untracked vertexes,
of which the added vertex is a part.
This effectively changes the handling of the above three cases.
X---X---X---X---U---U---N---U---U---X...
To handle this, a search is run which only crosses untracked vertices,
noting the boundaries where it crosses into tracked vertices, if any.
Then, this group of previously untracked vertices is handled similarly to the above:
+ boundaries form connections to one existing group:
	append untracked vertices to existing group, keep existing group ID
+ boundaries form connections to no existing groups:
	allocate new group ID and assign found vertices to it
+ boundaries form connections to multiple existing groups:
	create new group ID, migrate vertexes from old groups,
	add in found vertices, remove old group IDs.
]]

-- gauge the size of a table, specifically for the code below;
-- does it have zero, one or many entries.
-- this is primarily useful as the number of touched groups in an addition
-- is only special (when considereng the broader range of sizes)
-- when considering 0 or 1 existing groups, otherwise just "many".
local table_quick_size = function(t)
	assert(type(t) == "table")
	local k, _ = next(t)
	if k == nil then return "none" end
	-- must be at least a single entry then; there another after that?
	local k2, _ = next(t, k)
	return (k2 == nil) and "single" or "many"
end
-- also a useful shorthand below
local isempty = function(t)
	return (next(t) == nil)
end
-- and this just something I came up with just now...
local matchvf = function(v, t)
	local f = t[v]
	if not f then error("matchvf(): no handler for case of "..tostring(v))
	return f(v)
end

-- decide what action should be taken given the results coming back from an addition search.
local decide_add_result = function(gathered, touchedset)
	local category = table_quick_size(touchedset)
	return matchvf(category, {
		"none" = function() return { type="new", newset=gathered } end,
		"single" = function() return { type="append", appendset=gathered } end,
		"many" = function() return {
			type="merge",
			mergeset=touchedset,
			extraset=gathered,
		} end,
	})
end

-- this function just analyses the addition but perfoms no action.
local add_vertex_inner = function(bsuccessor, searchfactory, groups, maptogroup, vertex)
	-- we must start by running a search from the starting vertex.
	-- to only follow untracked vertices,
	-- we wrap the successor to filter through returned successor sets
	-- and only indicate untracked vertices to the search,
	-- while making a note of which tracked groups it would have touched.
	local successor, touchedset = mk_untracked_successor(bsuccessor, maptogroup)
	local search, gathered = searchfactory(vertex, successor)
	while search.advance() do end
	-- at this point, we should end up with
	-- * the untracked nodes (should be at least one!) in gathered
	-- * the touched set of groups (may be empty)
	-- if gathered is empty for some reason,
	-- it was probably an erroneous call.
	if isempty(gathered) then
		local result = {}
		result.type = "noop"
		return result
	end
	return decide_add_result(gathered, touchedset)
end

local i = {}
i.add_vertex_inner = add_vertex_inner

return i

