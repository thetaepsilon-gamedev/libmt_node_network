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
local dname_new = "vertexspace.new"
local newbfsearch = _mod.modules.bfmap.new
local check = _mod.util.mkfnexploder(dname_new)
local mkassert_plain = _mod.util.mkassert
local mkassert = function(fname)
	return mkassert_plain("vertexspace."..fname.."() internal inconsistency")
end
local table_or_missing = _mod.util.mk_table_or_missing(dname_new)
local callback_or_missing = _mod.util.mk_callback_or_missing(dname_new)

local stub = function() end

return {
	-- impl contains functions that handle vertex-type-specific functionality.
	-- contains the following function keys:
	--	hasher: like in bfmap, must return a uniquely identifying value.
	--		references to the same vertex must hash to the same value.
	--	successor: also like in bfmap,
	--		returns references to the vertexes connected to the given vertex.
	new = function(impl, callbacks, opts)
		if type(impl) ~= "table" then
			error(dname_new.." no impl table passed for vertex functions")
		end
		callbacks = table_or_missing(callbacks, "callbacks")
		opts = table_or_missing(opts, "opts")

		local debugger = callback_or_missing(callbacks, "debugger", stub)
		--print(debugger)
		--print(stub)
		debugger(dname_new..".entry")

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

		-- inner insert into actual graph by it's ID.
		-- will calculate the hash if not provided.
		-- also updates the mapping of vertex to graph.
		local insertintograph = function(graphid, vertex, hash)
			if hash == nil then hash = hasher(vertex) end
			-- vertex should not be added twice.
			local oldgraph = maptograph[hash]
			if oldgraph ~= nil then
				error("vertexspace.insertintograph() internal inconsistency: vertex already exists graph="..graphid.." hash="..tostring(hash).." oldgraph="..oldgraph)
			end
			maptograph[hash] = graphid
			graphs[graphid][hash] = vertex
			-- TODO here: vertex insertion callbacks
		end

		-- internal function to delete a given graph ID.
		-- takes care of emptying each vertex from the mapping,
		-- before removing the graph set itself.
		local deletegraph = function(graphid)
			local assert = mkassert("deletegraph")
			-- TODO: pre-delete callback
			for hash, vertex in pairs(graphs[graphid]) do
				-- mapping should point each vertex in this graph to this graphid.
				-- if not, something blew up.
				local actual = maptograph[hash]
				assert(actual == graphid, "vertexes in graph should map back to the same graph, currentgraph="..graphid.." hash="..hash.." actual="..actual)
				-- otherwise, clear the mapping
				maptograph[hash] = nil
			end
			-- now the mappings are gone but the graph set is still stored.
			-- remove that from the graphs table and it's completely gone.
			local oldgraph = graphs[graphid]
			graphs[graphid] = nil
			-- TODO: post-delete callback with oldgraph
		end

		-- allocates a new graph ID.
		local newgraph = function()
			local newgraph = nextfree
			nextfree = newgraph + 1
			return newgraph
		end

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

		-- helper function which "curries" (pre-applies) the hasher and successor functions to bfmap.
		local newsearch = function(initialvertex, callbacks, localopts)
			return newbfmap(initialvertex, successor, hasher, callbacks, {})
		end



		-- insert a new vertex into the vertex space.
		-- returns true if inserted, false if it already exists.
		local addvertex = function(addedvertex)
			local assert = mkassert("addvertex")
			-- don't do anything if this vertex already exists.
			if maptograph(addedvertex) ~= nil then return false end

			visited_set = {}
			local successors = successor(addedvertex)

			local vertexhash = hasher(addedvertex)

			local connected_graphs = {}
			-- in general, to avoid issues with stale graph state,
			-- where possible we just recalculate from scratch the complete graph.
			-- however, as an optimisation, if all successor vertexes belong to the same graph
			-- (that is, the new vertex is connected to only that graph on all "sides"),
			-- it is obvious that the vertex will become part of that graph.
			-- so, two special cases:
			-- * no successors, vertex is "floating" and becomes it's own graph.
			-- * all successors belong to the same network, vertex is simply added to that graph.

			-- in a mixed scenario, a search is started at the new vertex.
			-- any existed graphs touched by the search are removed,
			-- under the assumption that if they are still reachable,
			-- then they will become part of the new graph.
			local samecase, graphid = comparesamegraph(successors)
			if samecase then
				insertintograph(graph, addedvertex, vertexhash)
				return true
			end

			-- start the search at the originating vertex.
			-- when the search is complete, search.getvisited() is used to retrieve the entire visited set;
			-- as this is a map from hashes to vertexes, that set is simply assigned as the new vertex set.
			local searchcallbacks = {}
			-- destroy any old graphs encountered.
			-- TODO: invocation of vertexspace callbacks here also
			searchcallbacks.visitor = function(vertex, vertexhash)
				local graphid = whichgraph(vertexhash)
				if graphid ~= nil then deletegraph(graphid) end
			end
			local search = newsearch(addedvertex, callbacks, {})
			-- then run search to completion
			while search.advance() do end

			-- when finished, the collected vertex set becomes the new graph.
			local newgraphid = newgraph()
			local graphset = search.getvisited()
			assert(graphset ~= nil, "graph set should be obtainable when search completes")
			graphs[graphid] = graphset
			-- TODO: post-graph setup callbacks

			return true
		end



		return interface
	end,
}
