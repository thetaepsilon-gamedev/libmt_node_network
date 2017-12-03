local i = {}
local m_coords = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.coords")
local m_tableutils = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.tableutils")
local m_bfmap = mtrequire("com.github.thetaepsilon.minetest.libmt_node_network.bfmap")

-- an example use of the breadth-first map utility: a "node virus".
-- takes a victim node name and a replacement node.
-- vertexes are node positions, the successor function returns any neighbours which are the victim node.
-- the visitor function swaps the node with the replacement.

local formatvec = m_coords.format
local shallowcopy = m_tableutils.shallowcopy
local newbfmap = m_bfmap.new

local hasher = minetest.hash_node_position

local make_node_virus = function(initialpos, offsets, victimname, replacement, markernode, callbacks, searchopts, localdebugger)
	local successor = function(vertex)
		--debugger("node virus successor")
		--debugger("vertex="..formatvec(vertex))
		local results = {}
		for _, offset in ipairs(offsets) do
			local pos = vector.add(vertex, offset)
			local nodename = minetest.get_node(pos).name
			if nodename == victimname then
				local hash = hasher(pos)
				results[hash] = pos
			else
				if localdebugger then localdebugger("REJECTED victim node, pos="..formatvec(pos).." name="..nodename) end
			end
		end
		return results
	end

	local markerfn = nil
	local testvertex = nil
	if markernode then
		markerfn = function(pos) minetest.swap_node(pos, markernode) end
	else
		-- only enable if not using a marker node
		testvertex = function(pos) return minetest.get_node(pos).name == victimname end
	end

	callbacks = shallowcopy(callbacks)
	local oldvisitor = callbacks.visitor
	local visitor = function(pos)
		minetest.swap_node(pos, replacement)
		if oldvisitor then oldvisitor(pos) end
	end
	callbacks.visitor = visitor
	
	callbacks.markfrontier = markerfn
	callbacks.testvertex = testvertex
	return newbfmap(initialpos, hasher(initialpos), successor, callbacks, searchopts)
end
i.new_with_offsets = make_node_virus

local offsets = m_coords.neighbour_offsets
i.new = function(initialpos, victimname, replacement, markernode, callbacks, searchopts, localdebugger)
	return make_node_virus(initialpos, offsets, victimname, replacement, markernode, callbacks, searchopts, localdebugger)
end



node_virus = i
