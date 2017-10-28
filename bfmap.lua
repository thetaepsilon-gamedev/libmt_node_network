local factory = function(deps)

-- abstract breadth-first graph mapping.
-- unlike a breadth-first *search* which terminates when finding a success state,
-- this algorithm attempts to exhaustively map a graph of connected neighbours (up to a limit).
-- otherwise though this is as generic as the algorithm example found on wikipedia.
local newqueue = deps.new.queue
local increment = deps.increment_counter

local checkfn = function(f, label, callername)
	if type(f) ~= "function" then
		error(callername..label.." expected to be a function, got "..tostring(f))
	end
end

local dname_new = "bfmap.new() "
-- helpers for callbacks in the code below.
-- returns default stub implementations so the code doesn't have to go "if callback ..." all the time.
-- I wonder if luaJIT can optimise these out when encountered...
local stub = function()
end
local passthrough = function(vertex)
	return true
end
local callback_or_missing = function(t, key, default)
	local fn = t[key]
	if fn ~= nil then
		checkfn(fn, "callback "..key, dname_new)
		return fn
	else
		return default
	end
end

return {
	-- set up the initial state of the search.
	-- requires an initial graph vertex and a successor function.
	-- the successor function understands how to interpret the vertex data structure.
	-- the successor function, when invoked with a vertex as it's sole argument,
	-- must return the vertexes connected to the provided one.
	-- the successor is allowed to return the previously visited node just fine,
	-- as the algorithm checks for already visited nodes anyway.
	-- hasher must return a unique string representation of a vertex.
	-- hash collisions will result in a vertex being incorrectly skipped.
	-- supported callbacks:
	--	testvertex: additional test stage when frontier is popped from queue.
	--	if it returns false the frontier vertex is simply discarded.
	--	visitor: called when vertex is added to the visited list.
	--	debugger: called with trace point messages if it exists.
	--	markfrontier: called when a vertex is added as a frontier.
	--	finished: called when the graph has been exhaustively mapped.
	-- if initial is nil, advance() below is guaranteed to return false on first invocation.
	-- note that if any callbacks edit the graph nodes during or between advance steps
	-- (e.g. by editing the world, changing the outcome of the successor function),
	-- it is recommended to provide the testvertex callback.
	new = function(initial, successor, hasher, callbacks, opts)
		-- note that queues reject nil items,
		-- so if initial is nil the queue will be empty.
		-- this gives us the behaviour for advance() as stated above.
		checkfn(successor, "successor", dname_new)
		checkfn(hasher, "hasher", dname_new)

		if (callbacks ~= nil) then
			if type(callbacks) ~= "table" then
				error(dname_new.."callbacks expected to be nil or a table")
			end
		else
			callbacks = {}
		end
		local testvertex = callback_or_missing(callbacks, "testvertex", passthrough)
		local visitor = callback_or_missing(callbacks, "visitor", stub)
		local debugger = callback_or_missing(callbacks, "debugger", stub)
		local markfrontier = callback_or_missing(callbacks, "markfrontier", stub)
		local oncompleted = callback_or_missing(callbacks, "finished", stub)
		local vertexlimit = opts.vertexlimit
		if type(vertexlimit) ~= "number" or vertexlimit < 0 then
			vertexlimit = nil
		end
		debugger(dname_new.."entry, callbacks ready")

		-- now onto the actual algorith data/code
		local self = {
			-- frontier list.
			-- will be checked in FIFO order as discovered when advanced.
			frontiers = newqueue(),
			-- discovered node list, hashed by the hasher function.
			-- already-visited nodes are checked for in successor vertexes.
			visited = {},
			-- cache of pending frontiers.
			-- used to avoid re-adding a vertex if it's already pending
			pending = {},
			-- flag to indicate completion.
			-- used so the completion callback is only invoked once.
			finished = false,
			-- various statistical data gathered during the run
			stats = {},
			-- separate node count which is checked against vertexlimit.
			-- any frontiers popped when vertexlimit is met or exceeeded are skipped.
			vertexcount = 0,
			-- vertex set to which skipped frontiers are added.
			-- can be queried when the algorithm is complete.
			-- utilises hasher so that "equal" vertexes are not inserted twice.
			limitskipped = {}
		}
		-- add initial vertex to start off process
		self.frontiers.enqueue(initial)
		local interface = {
			advance = function()
				if self.finished then return false end
				local stats = self.stats

				local dname = "bfmap.advance() "
				debugger(dname.."entry")
				local frontier = self.frontiers.next()

				-- if the frontier list is empty, we're done.
				if frontier == nil then
					self.finished = true
					oncompleted()
					return false
				end
				debugger(dname.."got frontier: "..tostring(frontier))

				-- remove this node from pending frontiers if it's allowed
				local frontier_hash = hasher(frontier)
				self.pending[frontier_hash] = false

				if testvertex(frontier) then
					debugger(dname.."frontier passed testvertex")
					-- get successors of this vertex
					local successors = successor(frontier)
					increment(stats, "successor_invocation_count")
					debugger(dname.."successor ran successfully, result="..tostring(successors))
					-- check each result, and insert into frontiers if not already visited
					for index, vertex in ipairs(successors) do
						local hash = hasher(vertex)
						if not self.visited[hash] then
							if not self.pending[hash] then
								markfrontier(vertex)
								self.pending[hash] = true
								self.frontiers.enqueue(vertex)
							else
								increment(stats, "discarded_successor_pending")
							end
						else
							increment(stats, "discarded_successor_visited")
						end
						increment(stats, "successor_result_total")
					end
					-- mark this node visited
					visitor(frontier)
					self.visited[frontier_hash] = true
					increment(stats, "visited_count")
				else
					debugger(dname.."frontier DISCARED by testvertex")
					increment(stats, "frontier_vertex_discarded")
				end

				increment(stats, "total_step_count")
				return true
			end,
			stats = function() return self.stats end,
		}
		return interface
	end
}

end -- factory()
return factory
