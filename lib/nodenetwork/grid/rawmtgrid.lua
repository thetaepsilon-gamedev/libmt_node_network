--[[
The simplest possible implementation of a linkedgrid
(see lib/nodenetwork/grid/linkedgrid.lua)
operating directly on the minetest world,
with as little abstraction as possible.
This means:
+ doesn't filter out IGNORE nodes, or attempt to force-load mapblocks.
+ subject to areas of the world becoming unloaded at any time,
	*including* between the time of a neighbour call and a get call.
	TOCTTOU races beware, you have been warned.
+ positions returned by the neighbour operation are not guaranteed to be loaded.
+ doesn't provide access to metadata in-line.
	that said, a simple method-like function added to node tables could do this:
	node.getmeta = function(self)
		return mt_get_meta(self.pos)
	end
	where mt_get_meta is minetest.get_meta,
	under the assumption that get_node() returns independent tables.
]]

-- the get operation is literally just minetest.get_node(pos),
-- as the linkedgrid interface uses the same XYZ table format for coordinates.
-- note that the constructor below requires passing the minetest object,
-- so the grid's get operation becomes whatever minetest.get_node is.

-- the neighbour operation is similarly a simple euclidian offset.
local m_add = mtrequire("ds2.minetest.vectorextras.add")
local vadd = m_add.wrapped
local mk_neighbour_inner = function(self)
	return function(pos, offset)
		local target = vadd(pos, offset)
		return {
			grid = self,
			pos = target,
			direction = offset,
		}
	end
end

-- construct an instance of the grid
local construct = function(minetest)
	local self = {}
	local get = minetest.get_node
	assert(type(get) == "function")
	self.get = get
	self.neighbour = mk_neighbour_inner(self)
	-- use the getter as the (hopefully) unique id.
	-- for minetest.get_node, this makes instances of this comparable.
	self.id = get
	return self
end

return construct

