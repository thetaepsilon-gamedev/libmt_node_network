--[[
Please read all of this before exploring the code.
It's long, but that's because it's a tricky concept to get around at first.

A vertex space is an abstract set of vertexes.
Within the vertex space, these vertexes may be grouped into connected graphs.
A vertex is at any time a member of exactly one graph;
"floating" vertexes not connected to anything become their own graph.
A vertex space as an object supports adding and removing of vertex references,
and obtaining a handle to the graph a vertex reference belongs to.

Adding a new vertex causes it's successors to be examined,
by calling the successor function on it.
If the vertex has no successors, then this vertex is "floating on it's own",
and a new graph is created to contain this isolated vertex.

Otherwise, each of these successors is checked to see if it is already a part of a graph.
If the successors all name a single unique graph,
then the original vertex is simply added to the vertex set of that graph.
If there are multiple graphs referenced by the successors connected to the original vertex,
then the new vertex effectively constructs a bridge between those graphs;
one of the graphs is picked to have the others merged into,
then the original vertex is added to the merged network.

It is also possible that the successor vertexes also do not belong to a tracked graph yet.
After the above consideration is applied,
any vertex that is NOT part of an existing graph spawns a search to map out potential new graph segments.
It is assumed that the graph has not been modified without notifying the vertex space,
therefore each explored successor graph does NOT check any vertexes that it comes across to see if they also already belong to a graph.
After processing one successor's graph,
any of the successors now in the graph's visited set
(that is, that successor is *reachable* from a successor mapped before it) are skipped.
These graphs are then merged with any others connected to the initiating vertex as above.

For removing a vertex, prior to it's actual removal,
again it's successors are examined.
If the vertex has no successors then it is simply removed from it's containing graph;
as by the time this can happen the graph will only have that one vertex left,
this will trigger the deletion of the now-empty graph.

Otherwise, one of the successors is picked and the search algorithm is run on it.
When the search has completed, the other successors are compared against the search's visited set.
If any of the successors are NOT contained in the visited set,
then they are no longer reachable from the current graph and represent a completely disconnected section.
Each candidate successor then has the search algorithm ran on it and it's results inserted into a new graph;
checking along the way to see if any of the new networks now include the candidate,
until no candidates remain.

It should be noted that in a sense the vertex space does not "own" the vertexes per se.
The vertexes and the graphs they form exist anyway
(the graphs are implied by connections between vertexes).
The vertex space merely acts as a tracking mechanism.
It also assumes that the graphs are undirected.

It should also be noted that there is the assumption that vertexes do not care about being reassigned to graphs.
As above, for instance, if an existing graph is detected during a new graph's search,
that graph is emptied and then the new graph will take it's nodes.
This is in general to prevent stale state issues.
The callbacks for graph creation/destruction etc. should be comfortable dealing with this;
potentially they must be able to deal with a complete destruction and recalculation of all graphs every time any vertex is added/removed.
]]
local dname_new = "vertexspace.new()"
local newsearch = _mod.modules.bfmap.new
local check = _mod.util.mkfnexploder(dname_new)

return {
	-- impl contains functions that handle vertex-type-specific functionality.
	-- contains the following function keys:
	--	hasher: like in bfmap, must return a uniquely identifying value.
	--		references to the same vertex must hash to the same value.
	--	successor: also like in bfmap,
	--		returns references to the vertexes connected to the given vertex.
	new = function(impl)
		if type(impl) ~= "table" then
			error(dname_new.." no impl table passed for vertex functions")
		end

		-- vertex-to-graph mapping.
		-- keys are determined by the hasher function.
		local maptograph = {}
		-- actual graph sets table.
		-- graph IDs are numerical indexes.
		-- the graphs themselves are also tables,
		-- where for each entry the value is the vertex ref itself,
		-- and the keys are the hashes.
		local nextfree = 1
		local graphs = {}

		local hasher = check(impl.hasher, "vertex hasher")
		local successor = check(impl.successor, "vertex successor")

		local interface = {}

		-- helper function to get a vertex's graph ID from it's hash.
		-- returns nil if the vertex belongs to no network.
		local whichgraph = function(vertexhash)
			return maptograph[vertexhash]
		end

		local comparebyvalue = function(array)
			local compare = nil
			for index, item in ipairs(array) do
				if compare == nil then
					compare = item
				elseif item ~= compare then
					return false
				end
			end
			return true
		end
		-- helper to determine if a set of vertexes are all on the same graph.
		-- returns true if all vertexes map to the same graph ID.
		-- if any of them are *not* on a graph this returns false.
		-- otherwise returns true, as well as the graph ID in that case.
		local comparesamegraph = function(vertexes)
			local hashes = {}
			local graphs = {}
			for index, vertex in ipairs(vertexes) do
				hash = hasher(vertex)
				table.insert(hashes, hash)
			end
			for index, hash in ipairs(hashes) do
				local graphid = whichgraph(hash)
				if graphid == nil then return false end
				table.insert(graphs, graphid)
			end
			local result = comparebyvalue(graphs)
			local resultid
			if result then resultid = graphs[1] end
			return result, resultid
		end

		-- insert a new vertex into the vertex space.
		-- returns true if inserted, false if it already exists.
		local addvertex = function(vertex)
			local hash = hasher(vertex)
			if maptograph[hash] ~= nil then return false end
			error("vertexspace.addvertex() vertex new, stub!")
		end

		return interface
	end,
}
