local check = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.check")
--[[
voxelgraph: neighbour candidate set determination
The first phase of the voxel graph successor is to examine a node,
and determine which adjacent nodes are candidates for successors in a search.
This has nothing to do with checking said nodes to see if they are a certain type;
this is simply "without any extra information, which sides can you connect on?".
]]
local i = {}



--[[
Look-up table object: create this and pass it to a voxelgraph successor to provide the necessary data.
Ensures that added entries (if using static tables) are only integer node offsets.
Please note that faking this and returning fractional values is considered undefined behaviour.
]]
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
	NB: this function should *not* check nearby nodes!
	therefore it is not provided the grid reference.
	it should simply return a list of xyz offset vectors.
	(for a way for the *source node* to filter based on node type,
	see the filter hook.)
	for example, this function could examine a node's metadata
	to see which of it's sides are "enabled",
	and only return those in the list.
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
	retrieve data about a node once loaded from a grid.
	returns a list of candidate vectors, or nil and an error code;
	error()s by hooks are currently propogated.
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

