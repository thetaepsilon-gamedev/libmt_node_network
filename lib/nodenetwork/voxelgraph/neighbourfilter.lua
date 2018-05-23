--[[
Neighbour filter: filter the set of neighbours from the neighbour set,
based on the target node's data, and extradata from the keys of the neighbour set.
This is a wrapper around libmthelpers.datastructs.handler_lut,
with handler functions returning boolean predicate values.
The purpose of these functions is to answer the question
"Is this neighbour a suitable node?" for each neighbour returned in the neighbour set.
]]

local handler_lut =
	mtrequire("com.github.thetaepsilon.minetest.libmthelpers.datastructs.handler_lut")

--[[
The data object that handlers are passed consists of the following.
{
	src = { nodedata },	-- source node data as seen by neighbour set handlers
	dest = { nodedata },	-- destination node data
	extradata = { ... },	-- extra data as defined by keys of neighbour set table.
		-- this value is opaque, and is intended to further affect filtering decisions,
		-- e.g. extradata.groups to require that nodes possess certain data.
		-- it is up to client code and handlers to define what to do with this.
}
]]
local getkey = function(data)
	local src = data.src
	local name = src.name
	assert(name ~= nil)
	return name
end

local copy_member_list = function(src, target, list)
	for i, k in ipairs(list) do
		target[k] = src[k]
	end
end



local label = "filter_lut"
local mk_filter_lut = function(_sopts)
	local opts = {}
	-- allow the caller to specify a default value.
	copy_member_list(_sopts, opts, { "default" })
	opts.hooklabel = "filter callback"

	return handler_lut.mk_handler_lut(getkey, label, opts)
end

local i = {}
i.mk_filter_lut = mk_filter_lut
return i
