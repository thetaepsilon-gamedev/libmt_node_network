local check = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.check")
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



local fncheck = check.mkfnexploder("neighbourtable:add_custom_hook()")
local mk_neighbour_lut = function()
	local entries = {}
	local maybe_insert = function(k, v)
		local new = (entries[k] == nil)
		if (new) then
			entries[k] = v
		end
		return new
	end
	local assert_insert = function(k, v)
		if not maybe_insert(k, v) then
			error("successor neighbour table: duplicate insertion for key "..tostring(k))
		end
	end

	local i = {}

	--[[
	register a custom function to determine candidate neighbours.
	NB: this function is not for checking nearby nodes and doesn't get a position,
	but is provided node data (get_node()) and meta ref.
	It should simply return a table mapping keys to XYZ MT vectors.
	The keys can be anything; they are preserved elsewhere,
	and can be used to tag connections to other nodes with extra data later.

	-- function signature:
	local candidates = callback(nodedata, nodemetaref)
	-- only get_* calls are specified on nodemetaref,
	--	causing world side effects while a search runs is discouraged.
	-- hook should return nil to indicate a graceful error instead of throwing.
	]]
	i.add_custom_hook = function(self, name, hook)
		local f = fncheck(hook, "neighbour hook")
		return assert_insert(name, hook)
	end

	--[[
	retrieve neighbour set based on node data.
	returns a list of candidate vectors, or nil and an error code;
	error()s by hooks are currently propogated.
	node data is only required to have .name here;
	nodemeta is not touched by this function, but may be by callbacks.
	]]
	i.query_neighbour_set = function(self, nodedata, nodemeta)
		local entry = entries[nodedata.name]
		if entry then
			-- call hook to determine set
			local candidates = entry(nodedata, nodemeta)
			if (not candidates) then
				return nil, "EHOOKFAIL"
			else
				return candidates
			end
		else
			return nil, "ENODATA"
		end
	end

	return i
end
i.mk_neighbour_lut = mk_neighbour_lut



return i

