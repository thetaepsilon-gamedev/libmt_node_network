--[[
A vertex space is an abstract set of vertexes.
Within the vertex space, these vertexes may be grouped into connected graphs.
A vertex is at any time a member of exactly one graph;
"floating" vertexes not connected to anything become their own graph.
A vertex space as an object supports adding and removing of vertex references,
and obtaining a handle to the graph a vertex reference belongs to.

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
local shallowcopy = _mod.util.shallowcopy

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

		-- callbacks which are invoked at various points during operations.
		-- graph_append: called when a single vertex is added to a graph.
		-- graph_new: called when a new, initially empty graph is created.
		-- graph_delete_pre: called to batch delete entries from a graph prior to removal.
		-- graph_delete_post: called when a graph is removed entirely.
		--	note that either delete_pre or delete_single can precede this.
		-- graph_assign: called to add a set of vertexes all at once.
		-- graph_remove_single: called when just one vertex is removed from a graph,
		--	and it is known that a recalculation is not necessary.
		-- enter/exit are called whenever entry/exit happens with a vertexspace operation.
		--	in particular, any calls to other callbacks or the successor/hasher function
		--	are guaranteed to happen after begin() and before exit().
		--	if any changes are to be made to a graph, they should be done inside exit().
		local c_onappend = callback_or_missing(callbacks, "graph_append", stub)
		local c_onnewgraph = callback_or_missing(callbacks, "graph_new", stub)
		local c_graph_delete_pre = callback_or_missing(callbacks, "graph_delete_pre", stub)
		local c_graph_delete_post = callback_or_missing(callbacks, "graph_delete_post", stub)
		local c_graph_assign = callback_or_missing(callbacks, "graph_assign", stub)
		local c_vertex_delete_single = callback_or_missing(callbacks, "graph_remove_single", stub)
		local c_enter = callback_or_missing(callbacks, "enter", stub)
		local c_exit = callback_or_missing(callbacks, "exit", stub)

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
		-- this mostly serves as a marker in code below -
		-- read accesses are done through this function,
		-- write accesses modify the maptograph table directly
		local whichgraph = function(vertexhash)
			return maptograph[vertexhash]
		end

		-- update a single mapping entry.
		-- sanity checks the entry by ensuring that there is no existing mapping first.
		local assert_ume = mkassert("update_map_entry")
		local update_map_entry = function(hash, newid)
			local assert = assert_ume
			local existing = whichgraph(hash)
			assert(existing == nil, "mapping entry should not already exist", {hash=hash, existing=existing, attempted=newid})
			maptograph[hash] = newid
		end

		-- clears a single mapping entry.
		-- ensures the mapping actually exists first.
		-- optionally checks for an expected mapping ID first.
		local assert_cme = mkassert("clear_map_entry")
		local clear_map_entry = function(hash, checkid)
			local assert = assert_cme
			local existing = whichgraph(hash)
			local valid
			if checkid ~= nil then
				valid = (existing == checkid)
			else
				valid = (existing ~= nil)
			end
			assert(valid, "mapping entry must already exist before clearing", {hash=hash})
			maptograph[hash] = nil
		end



		-- inner insert into actual graph by it's ID.
		-- will calculate the hash if not provided.
		-- also updates the mapping of vertex to graph.
		local insertintograph = function(graphid, vertex, hash)
			if hash == nil then hash = hasher(vertex) end
			update_map_entry(hash, graphid)
			local graph = graphs[graphid]
			graph[hash] = vertex
			c_onappend(vertex, hash, graphid)
		end

		-- set up the graph mapping for a set of vertexes
		-- does some sanity checking then updates all vertexes to map to the target graph id.
		local assert_um = mkassert("updatemapping")
		local updatemapping = function(graphset, graphid)
			local assert = assert_um
			assert(graphset ~= nil, "graph set expected to be non-nil")
			for hash, vertex in pairs(graphset) do
				update_map_entry(hash, graphid)
			end
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
				clear_map_entry(hash, graphid)
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
			-- check if the graph is empty now - if so, remove it.
			if table_get_single(graph) == nil then
				graphs[graphid] = nil
				c_graph_delete_post(graphid)
			end
		end

		-- internal function to assign a graph set.
		-- assigns the table then invokes the relevant callback.
		local graph_assign = function(graphid, graphset)
			if type(graphset) ~= "table" then error("vertexspace graph_assign() graph must be a table!") end
			graphs[graphid] = graphset
			c_graph_assign(graphid, graphset)
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



		-- construct a visitor which:
		--  destroys any graphs encountered, on the assumption they'll be re-added by the search.
		--  causes warnings for encountered foreign graphs,
		--    optionally ignoring this if expected of successors (used in addvertex).
		--  assigns any found vertexes to the new graph.
		--  clears out successors if found (used by removevertex).
		local create_search_visitor = function(targetgraphid, successor_map, opts)
			-- create a copy of the initial state of the successor map,
			-- so we can cause warnings when a vertex belongs to a foriegn graph,
			-- even as they are removed.
			local successor_check = shallowcopy(successor_map)
			local warnanyway = not opts.ignore_foreign_successors

			return function(vertex, vertexhash)
				local graphid = whichgraph(vertexhash)
				if graphid ~= nil then
					deletegraph(graphid)
					local isnotsuccessor = (successor_check[vertexhash] == nil)
					-- check the vertex for foreign-ness if it's either not a successor or we've been asked to do so anyway.
					local shouldcheck = isnotsuccessor or warnanyway
					if shouldcheck and (graphid ~= targetgraphid) then
						warning("vertex found during search already belonged to a graph but wasn't a merged successor!", {hash=vertexhash, graph=graphid})
					end
				end
				successor_map[vertexhash] = nil
				maptograph[vertexhash] = targetgraphid
			end
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

			local opts = { ignore_foreign_successors = true }
			-- the visitor helper deletes any graphs that is comes across.
			-- while this might seem destructive,
			-- if they are still connected then the contained vertexes will be re-added.
			-- this effectively implements the graph merge behaviour.
			searchcallbacks.visitor = create_search_visitor(newgraphid, successor_check, opts)
			local search = newsearch(addedvertex, searchcallbacks, {})
			-- then run search to completion
			while search.advance() do end

			-- when finished, the collected vertex set becomes the new graph.
			local graphset = search.getvisited()
			assert(graphset ~= nil, "graph set should be obtainable when search completes")
			graph_assign(newgraphid, graphset)

			return true
		end



		-- removes a vertex from the space.
		-- returns true if removed, false if it did not exist or wasn't tracked.
		-- in the false case the graph will not be modified.
		-- the set of successors prior to the vertex's removal must also be passed;
		-- this is because the vertex has to have been removed before this is called,
		-- so that it doesn't get re-added.
		local removevertex = function(oldvertex, oldsuccessors)
			local assert = mkassert("removevertex")
			local oldhash = hasher(oldvertex)
			local oldgraphid = whichgraph(oldhash)
			if oldgraphid == nil then
				return false
			end

			-- unconditionally remove the tracking data for the old vertex up front.
			-- this is to work better with callback sets that work differently with batch deletes vs single removes.
			-- note also that this will automatically delete the graph if it's empty.
			delete_vertex_single(oldvertex, oldhash, oldgraphid)

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
			-- beyond this point, DO NOT USE oldgraphid as we must assume it's graph is gone.
			-- if it still exists it will be in saveid.

			local foreign_graphs = {}
			local clobbered_graph = nil
			if saveid ~= nil then
				-- clear out successors if they're found during the search,
				-- and make a note of any foreign graphs encountered.
				-- we *do not* use the helper here as we defer setting up mapping entries,
				-- until we know that the vertex set needs moving to a new graph.
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
					return true
				else
					-- save the found graph for the code below
					clobbered_graph = search.getvisited()
					assert(clobbered_graph[oldhash] == nil, "old vertex should not appear in connectivity search")
				end
			end

			-- if we get this far, then entries remain in the successor map that haven't been covered.
			-- spawn searches at each remaining successor until they're all covered.
			if clobbered_graph ~= nil then
				deletegraph(saveid)
				local nid = newgraph()
				graph_assign(nid, clobbered_graph)
				updatemapping(clobbered_graph, nid)
			end

			-- while successors still remain that haven't been visited,
			-- create a new graph and spawn a search for it from the next available successor.
			-- the visitor helper clears successors out of the list if a search runs across one,
			-- so that successor will not spawn another redundant search.
			while true do
				local hash, vertex = table_get_single(successor_map)
				if hash == nil then break end
				local newgraphid = newgraph()
				local visitor = create_search_visitor(newgraphid, successor_map, {})
				local callbacks = { visitor = visitor }
				local search = newsearch(vertex, callbacks, {})
				while search.advance() do end
				local graphset = search.getvisited()
				assert(graphset[oldhash] == nil, "old vertex should not appear in a remainder search")
				assert(successor_map[hash] == nil, "successor should have been covered by search")
				graph_assign(newgraphid, graphset)
			end

			return true
		end

		interface.addvertex = function(...)
			c_enter()
			local result = addvertex(...)
			c_exit()
			return result
		end
		interface.removevertex = function(...)
			c_enter()
			local result = removevertex(...)
			c_exit()
			return result
		end

		return interface
	end,
}
