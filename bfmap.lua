local factory = function(deps)

-- abstract breadth-first graph mapping.
-- unlike a breadth-first *search* which terminates when finding a success state,
-- this algorithm attempts to exhaustively map a graph of connected neighbours (up to a limit).
-- otherwise though this is as generic as the algorithm example found on wikipedia.
local newqueue = deps.new.queue
local increment = deps.increment_counter
local mkfnexploder = deps.mkfnexploder
local mk_callback_or_missing = deps.mk_callback_or_missing

local dname_new = "bfmap.new() "
-- helpers for callbacks in the code below.
-- returns default stub implementations so the code doesn't have to go "if callback ..." all the time.
-- I wonder if luaJIT can optimise these out when encountered...
local stub = function()
end
local passthrough = function(vertex)
	return true
end

local checktable = function(tbl, label)
	-- table might be nil if not explicitly set - treat as not wanting to assign callbacks
	local result = tbl
	local t = type(tbl)
	if t == "nil" then
		result = {}
	elseif t ~= "table" then
		error(dname_new..label.." table expected to be either a table or nil, got "..t)
	end
	return result
end
local checkfn = mkfnexploder(dname_new)
local callback_or_missing = mk_callback_or_missing(dname_new)
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
	--		gets passed the vertex and it's hash.
	--	debugger: called with trace point messages if it exists.
	--	markfrontier: called when a vertex is added as a frontier.
	--	finished: called when the graph has been exhaustively mapped.
	--		gets passed the following arguments:
	--		remainder: an iterator which will return the remaining skipped vertexes.
	-- if initial is nil, advance() below is guaranteed to return false on first invocation.
	-- note that if any callbacks edit the graph nodes during or between advance steps
	-- (e.g. by editing the world, changing the outcome of the successor function),
	-- it is recommended to provide the testvertex callback.
	new = function(initial, successor, hasher, callbacks, opts)
		-- note that queues reject nil items,
		-- so if initial is nil the queue will be empty.
		-- this gives us the behaviour for advance() as stated above.
		checkfn(successor, "successor")
		checkfn(hasher, "hasher")

		callbacks = checktable(callbacks, "callbacks")
		opts = checktable(opts, "opts")

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
		debugger(dname_new.."vertexlimit="..tostring(vertexlimit))

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
			-- any still-valid frontiers popped when vertexlimit is met or exceeeded are skipped.
			vertexcount = 0,
		}
		-- invoke onfinished handler
		local whenfinished = function()
			self.finished = true
			-- frontiers queue will contain any remaining frontiers at this point if terminating due to limit
			oncompleted(self.frontiers.iterator())
		end
		-- add initial vertex to start off process
		self.frontiers.enqueue(initial)
		local interface = {
			advance = function()
				if self.finished then return false end
				local stats = self.stats

				local dname = "bfmap.advance() "
				debugger(dname.."entry")

				-- stop immediately if we've exceeded the limit,
				-- leaving all pending frontiers in the queue for the oncompleted callback.
				if (vertexlimit and self.vertexcount >= vertexlimit) then
					whenfinished()
					return false
				end

				local frontier = self.frontiers.next()
				-- if the frontier list is empty, we're done.
				if frontier == nil then
					whenfinished()
					return false
				end
				debugger(dname.."got frontier: "..tostring(frontier))

				-- remove this node from pending frontiers if it's allowed
				local frontier_hash = hasher(frontier)
				self.pending[frontier_hash] = nil

				if testvertex(frontier) then
					debugger(dname.."frontier passed testvertex")

					-- get successors of this vertex
					local successors = successor(frontier)
					increment(stats, "successor_invocation_count")
					debugger(dname.."successor ran successfully, result="..tostring(successors))
					-- check each result, and insert into frontiers if not already visited
					for index, vertex in ipairs(successors) do
						local hash = hasher(vertex)
						-- hash will have been assigned below on a previous pass if already visited.
						if self.visited[hash] == nil then
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
					self.vertexcount = self.vertexcount + 1
					visitor(frontier, frontier_hash)
					self.visited[frontier_hash] = frontier
					increment(stats, "visited_count")
				else
					debugger(dname.."frontier DISCARED by testvertex")
					increment(stats, "frontier_vertex_discarded")
				end

				increment(stats, "total_step_count")
				return true
			end,
			stats = function() return self.stats end,
			-- get visited vertexes as one table at the end,
			-- in the same form as stored internally -
			-- keys are hashes and values are vertex references.
			-- used in the vertex space code where it becomes the set of vertexes in a graph.
			-- returns nil if the search is not finished.
			getvisited = function()
				if not self.finished then return nil end
				return self.visited
			end
		}
		return interface
	end
}

end -- factory()
return factory
