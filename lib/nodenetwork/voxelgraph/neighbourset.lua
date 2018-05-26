local handler_lut =
	mtrequire("com.github.thetaepsilon.minetest.libmthelpers.datastructs.handler_lut")
--[[
voxelgraph: neighbour candidate set determination
The first phase of the voxel graph successor is to examine a node,
and determine which adjacent nodes are candidates for successors in a search.
This has nothing to do with checking said nodes to see if they are a certain type;
this is simply "without any extra information, which sides can you connect on?".

The below object is used to hold such registrations for nodes.
It can have handler functions installed which will be invoked
when it is queried for the neighbours of a given node,
based on the node's name.

The handler functions registered must behave as follows...
-- function signature (**):
local candidates = callback(node)
-- node is the usual data from minetest.get_node() but may contain extra data.
-- hook should return nil to indicate a graceful error instead of throwing;
--	deliberately throwing errors in general is discouraged.

Return value:
A table of keys mapping to minetest XYZ vectors representing offsets of neighbours.
The keys can be anything (including just numerical if they don't mean anything);
the neighbour filter stage will see whatever values the keys are.
So the keys could be e.g. tables which contain property data,
such as e.g. "this neighbour is a side with less conductivity than normal".

-- This could be done like the following.
-- note "resistance" is an arbitary property;
-- as long as the neighbour filter understands it,
-- any fields in the key table are fine.
local neighbours = {
	[{ resistance = 100 }] = { x=0, y=1, z=0 },
	[{ resistance = 200 }] = { x=0, y=-1, z=0 },
	-- ...
}
-- or like this:
-- (note that each key table must be unique!)
local p1 = { resistance = 100 }
local neighbours = {
	[p1] = { x=0, y=1, z=0 },
	-- ...
}
-- however, if no extra data needs to be specified,
-- normal list-like tables will do fine.
local neighbours = {
	{ x=0, y=1, z=0 },
	{ x=0, y=-1, z=0 },
	-- ...
}

** Note that the callback is not passed a position;
checking the indicated neighbours should be done in the neighbour filter step.
If the callback requires metadata, then the source grid must provide a means to access it,
e.g. provide node:getmeta() in the node data it returns.
See searchimpl.lua for how this is done.
]]
local i = {}

--[[
Constructor mk_neighbour_lut() returns two functions, query and register.
query = function(node)
	-- call query with the data from a source node
	-- (a la minetest.get_node(), should have have at least { name = "..." }),
	-- to invoke an appropriate handler;
	-- the function registered with the matching name
	-- (if any, see below) will be called,
	-- and node will be passed as the handler's single argument.
	-- nil and an error code are returned if something failed or no handler exists.
register = function(name, hookf)
	-- register a hook for a given node name.
	-- when a query is run, node.name is inspected,
	-- and the hook whose name matches (if any) is run.
]]
local getkey = function(nodedata)
	local n = nodedata.name
	assert(n ~= nil, "expected node data to have name field")
	return n
end
local mk_neighbour_lut = function()
	return handler_lut.mk_handler_lut(
		getkey,
		"neighbour_lut",
		{ hooklabel = "neighbour hook", reglabel="add_custom_hook()" })
end
i.mk_neighbour_lut = mk_neighbour_lut



return i

