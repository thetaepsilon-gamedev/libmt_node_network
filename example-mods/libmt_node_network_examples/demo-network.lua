-- demonstration of the vertex space code in libmt_node_network.
-- a vertex space is created which is the set of all in-world blocks from a given list.
-- successor is hence defined to be any directly adjacent nodes which are in that list.
-- additionally, there is a "uninitialised" node type which will be converted when first added.
-- hasher is libmt_node_network's node position hasher.
-- to use it, call demonet.new() with the list of nodes to use,
-- then call vertexspace.addvertex(),
-- passing as the vertex the position of any added node from that list.
-- as graphs are added, the list is cycled through;
-- for example, when a new graph is created as a result of a merger,
-- both merged networks should transform to the next node in the list.

local hasher = _mod.util.node_hasher
local mkvertexspace = _mod.new.vertexspace
local shallowcopy = _mod.util.shallowcopy
local newcache = _mod.new.worldcache
local mkstatsgrid = _mod.new.statsgrid

-- a successor function which return any neighbours which belong to a given list of names.
local adjacent_offsets = _mod.util.adjacent_offsets
local findinlist = _mod.util.search

local make_list_test = function(nodelist)
	return function(nodename)
		if findinlist(nodelist, nodename) then
			return true
		end
	end
end
local make_list_successor_gridless = function(tester)
	return function(grid, vertex)
		local positions = {}
		for _, offset in ipairs(adjacent_offsets) do
			local pos = vector.add(vertex, offset)
			local name = grid.get(pos).name
			if tester(name) then
				table.insert(positions, pos)
			end
		end
		return positions
	end
end

local make_successor_gridfull = function(successor_gridless, grid_access_table)
	return function(vertex)
		local grid = grid_access_table.grid
		return successor_gridless(grid, vertex)
	end
end

return {
	new = function(initialname, cyclelist, localcallbacks, label, localopts, grid)
		local vlabel = "demo"
		if vlabel ~= nil then vlabel = vlabel.." "..label end
		if localopts == nil then localopts = {} end
		-- node list to consider neighbours also includes the initial node.
		local nodelist = shallowcopy(cyclelist)
		table.insert(nodelist, initialname)
		local tester = make_list_test(nodelist)

		-- tracking of which graph ID gets which node.
		local wrapcount = #cyclelist
		local current = 1
		local maptonode = {}

		local callbacks = {}
		local opts = {}

		local f = localopts.forgetnode
		local forgetnode = {name="air"}
		if f then forgetnode = {name=f} end

		local w = {}
		local scache = {}
		local stats = {}
		local successor_gridless = make_list_successor_gridless(tester)
		local successor = make_successor_gridfull(successor_gridless, scache)
		local impl = { hasher=hasher, successor=successor }

		-- internal statistic helpers
		local savestats = function()
			local laststats = {}
			-- stats from raw grid accesses
			laststats.lower = w.lowerstats.getstats()
			-- stats from accesses to the world cache
			laststats.higher = w.cache.getstats()
			stats.last = laststats
		end
		local resetstats = function()
			w.lowerstats = nil
		end

		-- when entering an operation: open a world cache
		callbacks.enter = function()
			-- two hard problems: cache invalidation and naming things...
			-- we need a two-level cache here,
			-- as we want to cache successor hits,
			-- but callbacks are *not* allowed to affect the successor's behaviour.

			-- first, wrap the raw grid in a statistics tracker.
			local grid = mkstatsgrid(grid)
			w.lowerstats = grid

			-- next, wrap the tracked grid in the first level of cache.
			-- this cache is used exclusively by the successor,
			-- so that the graph remains unmodified from it's point of view.
			grid= newcache(grid)
			scache.grid = grid

			-- second-level cache where the callbacks write.
			-- the first-level cache won't see writes until the second one flushes,
			-- so the successor's behaviour doesn't change.
			-- then wrap that again in a stats grid so we can count callback operations.
			grid = newcache(grid)
			w.flusher = grid.flush
			grid = mkstatsgrid(grid)
			w.cache = grid
		end
		-- when appending a single node: look up that graph's node node
		callbacks.graph_append = function(vertex, hash, graphid)
			w.cache.set(vertex, {name=maptonode[graphid]})
		end
		-- when a new graph appears: pick the next node name for it and advance to the next one
		callbacks.graph_new = function(graphid)
			local nodename = cyclelist[current]
			maptonode[graphid] = nodename
			current = current + 1
			if current > wrapcount then current = 1 end
		end
		-- pre graph delete: revert all contained nodes to the "forgotten" node
		callbacks.graph_delete_pre = function(graphid, oldgraph)
			maptonode[graphid] = nil
			local c = w.cache
			for hash, vertex in pairs(oldgraph) do
				c.set(vertex, forgetnode)
			end
		end
		-- batch graph assign: set *all* of those nodes to that graph's node type
		callbacks.graph_assign = function(graphid, graphset)
			local nodedata = { name=maptonode[graphid] }
			local c = w.cache
			for hash, vertex in pairs(graphset) do
				c.set(vertex, nodedata)
			end
		end
		callbacks.debugger = localcallbacks.debugger
		-- single node remove: just remove that node.
		callbacks.graph_remove_single = function(vertex, hash, graphid)
			w.cache.set(vertex, { name="air" })
		end
		-- finalise: flush the cache
		callbacks.exit = function()
			w.flusher()
			scache.grid.flush()
			savestats()
			w.cache = nil
			scache.grid = nil
			resetstats()
		end

		local getstats = function()
			return stats.last
		end

		local vspace = mkvertexspace(impl, callbacks, opts, vlabel)
		vspace.successor_gridless = successor_gridless
		vspace.tester = tester
		vspace.getlaststats = getstats
		return vspace
	end,
	make_list_successor = make_list_successor,
}
