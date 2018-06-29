#!/usr/bin/env lua51s

local require = mtrequire
local bfmap = require("com.github.thetaepsilon.minetest.libmt_node_network.floodsearch.bfmap")

local bindio = function(file)
	return function(data)
		return file:write(data)
	end
end
errwrite = bindio(io.stderr)
local debug = function(s)
	errwrite(tostring(s).."\n")
end

local edge = function(self, a, b)
	local v1 = self:get_vertex(a, "a")
	local v2 = self:get_vertex(b, "b")
	v1[b] = true
	v2[a] = true
end

local get_vertex = function(self, k, label)
	local t = self.vertices
	local v = t[k]
	if (not v) then
		error("non-existant vertex "..tostring(k).." ("..label..")")
	end
	return v
end

local new_vertex = function(self, k)
	self.vertices[k] = {}
end

local dump = function(self, writer)
	local t = self.vertices
	writer("digraph {\n")
	for label, edgetable in pairs(t) do	
		local label_a = string.format("%q", tostring(label))
		writer("\t"..label_a.."\n")

		for otherlabel, _ in pairs(edgetable) do
			local label_b = string.format("%q", tostring(otherlabel))

			writer("\t"..label_a.." -> "..label_b.."\n")
		end
	end
	writer("}\n")
end

local it = function(state)
	local entries = state.entries
	local key = state.lastkey
	local index, value = next(entries, key)
	if (index == nil) then return nil end
	state.lastkey = index

	return { label=index, neighbours=value }
end

local mk_graph_iterator = function(self)
	local t = self.vertices
	return it, { entries=t }
end

local create_successor = function(self)
	local entries = self.vertices
	return function(vertex, hash)
		-- for in-memory graphs, tables can be safely identity compared.
		-- the vertex here is the table index.
		local neighbours = entries[vertex]
		local result = {}
		for k, _ in pairs(neighbours) do
			result[k] = k
		end
		return result
	end
end

local mk_graph = function()
	return {
		edge = edge,
		get_vertex = get_vertex,
		emit_graphviz = dump,
		vertices = {},
		vertex = new_vertex,
		iterator = mk_graph_iterator,
		mk_successor = create_successor,
	}
end








local minfactor = 2
local random_not_equal = function(n, i)
	local n2 = i
	while (n2 == i) do
		n2 = math.random(1, n)
	end
	return n2
end
local table_empty = function(t)
	local i, v = next(t)
	return (i == nil)
end

local mk_fuzzing_graph = function(n)
	local g = mk_graph()
	for i = 1, n, 1 do
		g:vertex(i)
		if (i > 1) then
			-- we must at least have one path to an existing vertex,
			-- which in turn has a link to one before it, etc.
			-- this is to ensure there are no disjoint graphs.
			local range = i
			local neighbour = random_not_equal(range, i)
			g:edge(i, neighbour)
		end
	end

	-- then add extra edges
	for i = 1, n*minfactor, 1 do
		local n1 = math.random(1, n)
		local n2 = random_not_equal(n, n1)
		g:edge(n1, n2)
	end

	return g
end

--[[
local g = mk_graph()
for i = 1, 5, 1 do
	g:vertex(i)
end

g:edge(1, 2)
g:edge(1, 3)
g:edge(2, 3)
g:edge(2, 4)
g:edge(2, 5)
g:edge(3, 5)
g:edge(4, 1)
]]

math.randomseed(os.time())
local callbacks = {
}

local limit = 4000
local scale = 1
local g
debug("# Starting randomised graph fuzzing")
for i = 1, limit, 1 do
	local size = math.random(50*scale, 100*scale)
	io.stderr:write("Pass "..i.." of "..limit..", size="..size.."\r")

	local expected = {}
	local remaining = {}
	for i = 1, size, 1 do
		expected[i] = true
		remaining[i] = true
	end
	local anomalies = {}
	local duplicates = {}
	callbacks.visitor = function(vertex, hash)
		if expected[vertex] then
			if remaining[vertex] then
				remaining[vertex] = nil
			else
				duplicates[vertex] = true
			end
		else
			anomalies[vertex] = true
		end
	end

	g = mk_fuzzing_graph(size)
	local successor = g:mk_successor()
	local opts = {}
	local start = math.random(1, size)
	local search = bfmap.new(start, start, successor, callbacks, opts)
	while search.advance() do end

	local success = true
	if not table_empty(anomalies) then
		debug("# ERROR: spurious anomalies found")
		success = false
		for k, _ in pairs(anomalies) do
			debug(k)
		end
	end
	if not table_empty(duplicates) then
		debug("# ERROR: duplicates found")
		success = false
		for k, _ in pairs(duplicates) do
			debug(k)
		end
	end
	if not table_empty(remaining) then
		debug("# ERROR: some entries expected clear remained!")
		success = false
		for k, _ in pairs(remaining) do
			debug(k)
		end
	end
	if (not success) then
		g:emit_graphviz(bindio(io.stdout))
	end
	assert(success, "fuzz round failure")
end
debug("")
debug("All rounds passed successfully.")
--g:emit_graphviz(bindio(io.stdout))

