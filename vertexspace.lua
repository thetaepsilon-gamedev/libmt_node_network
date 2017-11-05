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
local newbfmap = _mod.modules.bfmap.new
local check = _mod.util.mkfnexploder(dname_new)
local mkassert_plain = _mod.util.mkassert
local mkassert = function(fname)
	return mkassert_plain("vertexspace."..fname.."() internal inconsistency")
end
local table_or_missing = _mod.util.mk_table_or_missing(dname_new)
local callback_or_missing = _mod.util.mk_callback_or_missing(dname_new)
local mkwarning = _mod.util.mkwarning
local table_get_single = _mod.util.table_get_single

local stub = function() end

return {
	-- impl contains functions that handle vertex-type-specific functionality.
	-- contains the following function keys:
	--	hasher: like in bfmap, must return a uniquely identifying value.
	--		references to the same vertex must hash to the same value.
	--	successor: also like in bfmap,
	--		returns references to the vertexes connected to the given vertex.
	new = function(impl, callbacks, opts, label)
		if label ~= nil then
			label = " "..tostring(label)
		else
			label = ""
		end

		if type(impl) ~= "table" then
			error(dname_new.." no impl table passed for vertex functions")
		end
		callbacks = table_or_missing(callbacks, "callbacks")
		opts = table_or_missing(opts, "opts")

		local debugger = callback_or_missing(callbacks, "debugger", stub)
		local warn_caller = callback_or_missing(callbacks, "warning", stub)
		local warning = mkwarning("vertexspace"..label, warn_caller)
		--print(debugger)
		--print(stub)
		debugger(dname_new..".entry")

		local c_onappend = callback_or_missing(callbacks, "graph_append", stub)
		local c_onnewgraph = callback_or_missing(callbacks, "graph_new", stub)
		local c_graph_delete_pre = callback_or_missing(callbacks, "graph_delete_pre", stub)
		local c_graph_delete_post = callback_or_missing(callbacks, "graph_delete_post", stub)
		local c_graph_assign = callback_or_missing(callbacks, "graph_assign", stub)
		local c_vertex_delete_single = callback_or_missing(callbacks, "graph_remove_single", stub)

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
			local graph = graphs[graphid]
			graph[hash] = vertex
			c_onappend(vertex, hash, graphid)
		end



		-- internal function to delete a given graph ID.
		-- takes care of emptying each vertex from the mapping,
		-- before removing the graph set itself.
		local deletegraph = function(graphid)
			local assert = mkassert("deletegraph")
			local oldgraph = graphs[graphid]
			assert(oldgraph ~= nil, "non-existant graph", { graphid=graphid })

			c_graph_delete_pre(graphid, oldgraph)
			for hash, vertex in pairs(oldgraph) do
				-- mapping should point each vertex in this graph to this graphid.
				-- if not, something blew up.
				local actual = maptograph[hash]
				assert(actual == graphid, "vertexes in graph should map back to the same graph, currentgraph="..graphid.." hash="..hash.." actual="..actual)
				-- otherwise, clear the mapping
				maptograph[hash] = nil
			end
			-- now the mappings are gone but the graph set is still stored.
			-- remove that from the graphs table and it's completely gone.
			graphs[graphid] = nil
			c_graph_delete_post(graphid)

			return oldgraph
		end

		-- allocates a new graph ID.
		local newgraph = function()
			local newgraph = nextfree
			nextfree = newgraph + 1
			c_onnewgraph(newgraph)
			return newgraph
		end

		-- helper function to get a vertex's graph ID from it's hash.
		-- returns nil if the vertex belongs to no network.
		local whichgraph = function(vertexhash)
			return maptograph[vertexhash]
		end

		-- internal function to delete a single vertex from a graph.
		-- does some sanity checking and then invokes the relevant callbacks.
		local delete_vertex_single = function(vertex, hash, graphid)
			local checkid = whichgraph(hash)
			if checkid ~= graphid then
				warning("specified graphid did not match requested for single deletion", {expectedid=checkid, requested=graphid, hash=hash})
			end
			graphid = checkid
			maptograph[hash] = nil
			local graph = graphs[graphid]
			if graph[hash] == nil then
				warning("hash did not exist exist in graph!?", { graphid=graphid, hash=hash })
			else
				graph[hash] = nil
			end
			c_vertex_delete_single(vertex, hash, graphid)
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
				local hash = hasher(vertex)
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

		-- convert successors list into table with hashes as keys.
		-- used within the visitor callbacks below.
		local successormap = function(successors)
			local successor_check = {}
			for index, s in ipairs(successors) do
				local hash = hasher(s)
				successor_check[hash] = s
			end
			return successor_check
		end


		-- insert a new vertex into the vertex space.
		-- returns true if inserted, false if it already exists.
		local addvertex = function(addedvertex)
			local fname="vertexspace.addvertex"
			debugger(fname..".entry")
			local assert = mkassert("addvertex")
			local vertexhash = hasher(addedvertex)
			-- don't do anything if this vertex already exists.
			if whichgraph(vertexhash) ~= nil then
				debugger(fname..".duplicateinsert", {hash=vertexhash})
				return false
			end

			local visited_set = {}
			local successors = successor(addedvertex)
			local successor_check = successormap(successors)

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
			if #successors > 0 then
				-- it doesn't make sense here to compare an empty set for equality.
				local samecase, graphid = comparesamegraph(successors)
				if samecase then
					insertintograph(graphid, addedvertex, vertexhash)
					return true
				end
			end

			local newgraphid = newgraph()
			-- start the search at the originating vertex.
			-- when the search is complete, search.getvisited() is used to retrieve the entire visited set;
			-- as this is a map from hashes to vertexes, that set is simply assigned as the new vertex set.
			local searchcallbacks = {}
			-- destroy any old graphs encountered.
			searchcallbacks.visitor = function(vertex, vertexhash)
				local graphid = whichgraph(vertexhash)
				if graphid ~= nil then
					deletegraph(graphid)
					if successor_check[vertexhash] == nil then
						warning("vertex found during search already belonged to a graph but wasn't a merged successor!", {hash=vertexhash, graph=graphid})
					end
				end
				maptograph[vertexhash] = newgraphid
			end
			local search = newsearch(addedvertex, searchcallbacks, {})
			-- then run search to completion
			while search.advance() do end

			-- when finished, the collected vertex set becomes the new graph.
			local graphset = search.getvisited()
			assert(graphset ~= nil, "graph set should be obtainable when search completes")
			graphs[newgraphid] = graphset
			c_graph_assign(newgraphid, graphset)

			return true
		end
		interface.addvertex = addvertex



		-- removes a vertex from the space.
		-- returns true if removed, false if it did not exist or wasn't tracked.
		-- in the false case the graph will not be modified.
		-- the set of successors prior to the vertex's removal must also be passed;
		-- this is because the vertex has to have been removed before this is called,
		-- so that it doesn't get re-added.
		local removevertex = function(oldvertex, oldsuccessors)
			local oldhash = hasher(oldvertex)
			local oldgraphid = whichgraph(oldhash)
			if oldgraphid == nil then
				return false
			end

			-- to preserve the existing graph where possible,
			-- run a search from the first successor,
			-- where any unexpected graphs are logged instead of immediately deleted,
			-- and have the visitor callback clear any matching vertexes from the remaining successors.
			-- *if* after this first search all successors are cleared,
			-- then the graph is still intact and we just take that vertex off,
			-- but any foreign graphs encountered above trigger a warning.
			-- otherwise, the old graph is deleted,
			-- the visited set of the search is assigned to a new graph,
			-- and the remaining successors spawn new searches until none remain.

			-- find the first successor (if any) that is on the same network as the removed one.
			-- if one is found, start a search from there to check if the other successors are still reachable.
			-- if so, then that graph remains intact and we simply remove the entry for that node from the tracking data.
			local saveid = nil
			local savevertex = nil
			local successor_map = successormap(oldsuccessors)
			for hash, vertex in pairs(successor_map) do
				local theirid = whichgraph(hash)
				if theirid == oldgraphid then
					saveid = theirid
					savevertex = vertex
					break
				end
			end

			local foreign_graphs = {}
			if saveid ~= nil then
				-- clear out successors if they're found during the search,
				-- and make a note of any foreign graphs encountered.
				local clear_successor_visitor = function(vertex, vertexhash)
					local currentid = whichgraph(vertexhash)
					if (currentid ~= nil) and (currentid ~= saveid) then
						foreign_graphs[currentid] = true
					end
					successor_map[vertexhash] = nil
				end
				local callbacks = { visitor = clear_successor_visitor }
				local search = newsearch(savevertex, callbacks, {})
				while search.advance() do end

				-- if no successors remain, we're done.
				-- for now, warn about any encountered foriegn graphs here,
				-- then remove that entry.
				for fid, _ in pairs(foreign_graphs) do
					warning("foreign graph found during removal search", { expectedgraph=saveid, actualgraph=fid })
				end
				if table_get_single(successor_map) == nil then
					delete_vertex_single(oldvertex, oldhash, oldgraphid)
					return true
				end
			end

			error("vertexspace.removevertex incomplete!")
		end
		interface.removevertex = removevertex



		return interface
	end,
}
