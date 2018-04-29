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
]]
local i = {}



local getkey = function(nodedata)
	local n = nodedata.name
	assert(n ~= nil, "expected node data to have name field")
	return n
end

local label = "successor neighbour table"

local mk_neighbour_lut = function()
	local query, register = handler_lut.mk_handler_lut(
		getkey,
		"neighbour_lut",
		{ hooklabel = "neighbour hook", reglabel="add_custom_hook()" })
	local i = {}

	--[[
	register a custom function to determine candidate neighbours.
	NB: this function is not for checking nearby nodes and doesn't get a position,
	but is provided node data as returned by the grid;
	this node data must at least contain a .name member,
	though normally this object will have called the most appropriate handler anyway.
	It should simply return a table mapping keys to XYZ MT vectors.
	The keys can be anything; they are preserved elsewhere,
	and can be used to tag connections to other nodes with extra data later.

	NB: it is expected that the caller provide any extra data inside nodedata,
	*including* metadata refs.
	So it could potentially look like e.g. { name="...", param2=..., meta=... }

	-- function signature:
	local candidates = callback(nodedata)
	-- hook should return nil to indicate a graceful error instead of throwing.
	]]
	i.add_custom_hook = function(self, name, hook)
		return register(name, hook)
	end

	--[[
	retrieve neighbour set based on node data.
	returns a list of candidate vectors, or nil and an error code;
	error()s by hooks are currently propogated.
	node data is only required to have .name here.
	]]
	i.query_neighbour_set = function(self, data)
		return query(data)
	end

	return i
end
i.mk_neighbour_lut = mk_neighbour_lut



return i

