local node_virus = {}
local modhelpers = mtrequire("com.github.thetaepsilon.minetest.libmthelpers")

-- an example use of the breadth-first map utility: a "node virus".
-- takes a victim node name and a replacement node.
-- vertexes are node positions, the successor function returns any neighbours which are the victim node.
-- the visitor function swaps the node with the replacement.

local hasher = _mod.util.node_hasher
local formatvec = _mod.util.formatvec
local shallowcopy = _mod.util.shallowcopy
local newbfmap = _mod.new.bfmap

local make_node_virus = function(initialpos, offsets, victimname, replacement, markernode, callbacks, searchopts, localdebugger)
	local successor = function(vertex)
		--debugger("node virus successor")
		--debugger("vertex="..formatvec(vertex))
		local results = {}
		for _, offset in ipairs(offsets) do
			local pos = vector.add(vertex, offset)
			local nodename = minetest.get_node(pos).name
			if nodename == victimname then
				table.insert(results, pos)
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
	-- this has been disabled as there's now a separate searcher
	--[[
	if not readonly then
	]]
		local visitor = function(pos)
			minetest.swap_node(pos, replacement)
			if oldvisitor then oldvisitor(pos) end
		end
		callbacks.visitor = visitor
	--[[
	end
	]]
	callbacks.markfrontier = markerfn
	callbacks.testvertex = testvertex
	return newbfmap(initialpos, successor, hasher, callbacks, searchopts)
end
node_virus.new_with_offsets = make_node_virus

local offsets = modhelpers.coords.neighbour_offsets
--local offsets = {x=0,y=-1,z=0}
node_virus.new = function(initialpos, victimname, replacement, markernode, callbacks, searchopts, localdebugger)
	return make_node_virus(initialpos, offsets, victimname, replacement, markernode, callbacks, searchopts, localdebugger)
end



-- stripped form of the above for searching nodes.
-- takes a function which is provided the node data to determine if the node should be considered.
node_virus.mksearcher = function(initialpos, neighbourfn, callbacks, searchopts)
	local successor = function(vertex)
		local results = {}
		for _, offset in ipairs(offsets) do
			local pos = vector.add(vertex, offset)
			local neighbour = minetest.get_node(pos)
			if neighbourfn(neighbour) then
				table.insert(results, pos)
			end
		end
		return results
	end

	--local testvertex = nil
	local testvertex = function(pos) return neighbourfn(minetest.get_node(pos)) end

	callbacks = shallowcopy(callbacks)
	callbacks.testvertex = testvertex
	return newbfmap(initialpos, successor, hasher, callbacks, searchopts)
end

return node_virus
