local errors =
	mtrequire("com.github.thetaepsilon.minetest.libmthelpers.errors")

local check = mtrequire("com.github.thetaepsilon.minetest.libmthelpers.check")
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



local fncheck = check.mkfnexploder("neighbourtable:add_custom_hook()")
local eduplicate = errors.stdcodes.register.duplicate

local maybe_insert = function(entries, k, v)
	local new = (entries[k] == nil)
	if (new) then
		entries[k] = v
	end
	return new
end
local assert_insert = function(entries, label, k, v)
	if not maybe_insert(entries, k, v) then
		error(eduplicate.." "..label.." duplicate insertion for key "..tostring(k))
	end
end

--[[
Query routine:
attempt to look up an appropriate handler based on the provided data.
]]
local query_inner = function(entries, data, getkey)
	local key = getkey(data)
	local handler = entries[key]
	if handler then
		local result, err = handler(data)
		if (result == nil) then
			-- allow passing through explicit non-fatal "no data",
			-- otherwise default to hook fail to catch bugs like missing returns
			local is_nonfatal = (err == "ENODATA")
			local msg = (is_nonfatal and "ENODATA" or "EHOOKFAIL")
			return nil, msg
		else
			return result
		end
	else
		return nil, "ENODATA"
	end
end

-- check if a provided value is a string, or provide a default if nil.
local string_or_missing = function(caller, label, v, default)
	local t = type(v)
	if t ~= nil then
		assert(
			t == "string",
			caller.." "..label.."expected to be a string, got "..t)
		return v
	else
		return default
	end
end
-- similar to the above but retrieve from a table, and assume key == label
local string_from_table = function(caller, tbl, key, default)
	return string_or_missing(caller, key, tbl[key], default)
end


--[[
Construct a handler lookup table.
* getkey is a function used to extract the "primary key" from input data.
	This key is used to determine which handler to call.
* label is the "display name" string of this object in errors.
* opts should be a table consisting of:
	* [optional] hooklabel is a string used to refer to the handler functions,
		e.g. "neighbour set hook".
		May be nil, in which case a sane but not very descriptive string is used.
	* [optional] reglabel similarly refers to the "outer" register function if applicable,
		if this object is used as part of some larger interface.

Returns *two functions*, query and register.
query should be called with an opaque data argument,
which will be passed to both getkey and the found handler, if any.
register should be called with a key (as returned by the getkey function)
and the handler function to associate with that key.
]]
local n_chl = "create_handler_lut():"
local create_handler_lut = function(getkey, label, opts)
	assert(type(label) == "string", n_chl.."label expected to be a string")
	local hooklabel = string_from_table(n_chl, opts, "hooklabel", "handler function")
	local reglabel = string_from_table(n_chl, opts, "reglabel", "register()")

	reglabel = label .. ":" .. reglabel
	local fncheck = check.mkfnexploder(reglabel)
	local entries = {}
	getkey = fncheck(getkey, n_chl)

	local query = function(data)
		return query_inner(entries, data, getkey)
	end

	local register = function(key, handler)
		local f = fncheck(handler, hooklabel)
		return assert_insert(entries, reglabel, key, handler)
	end

	return query, register
end



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

