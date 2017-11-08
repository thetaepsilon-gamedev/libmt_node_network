local centerpos = _mod.util.center_on_node
local rep_node_hasher = function(vertex)
	local centered = centerpos(vertex)
	local sep = ","
	return centered.x..sep..centered.y..sep..centered.z
end
local node_hasher = function(vertex) return minetest.hash_node_position(centerpos(vertex)) end
_mod.util.node_hasher = node_hasher
--_mod.util.node_hasher = rep_node_hasher

-- helper utility for callback tables.
-- looks up a key in the table and returns that if it's a function.
-- if it's nil, return a provided default function;
-- the default function should be idempotent
-- (i.e. it does nothing or it returns a default value which doesn't affect anything).
-- if the key is neither a function nor nil then an error is thrown.
local mkfnexploder = _mod.util.mkfnexploder
local mk_callback_or_missing = function(caller)
	--local dname = "callback_or_missing"
	local checkfn = mkfnexploder(caller)
	return function(t, key, default)
		local fn = t[key]
		--print(dname.." t="..tostring(t).." key="..tostring(key).." result="..tostring(fn))
		if fn ~= nil then
			--print(dname.." invoking checkfn")
			return checkfn(fn, "callback "..key)
		else
			return default
		end
	end
end
_mod.util.mk_callback_or_missing = mk_callback_or_missing

-- helper for callbacks and options table.
-- boilerplate for error checking and providing a blank table if nil is passed.
local mk_table_or_missing = function(caller)
	return function(tbl, label)
		-- table might be nil if not explicitly set - treat as not wanting to assign any values/options
		local result = tbl
		local t = type(tbl)
		if t == "nil" then
			result = {}
		elseif t ~= "table" then
			error(caller.." "..label.." table expected to be either a table or nil, got "..t)
		end
		return result
	end
end
_mod.util.mk_table_or_missing = mk_table_or_missing

-- internal warning function - currently prints to console.
local warn_console = function(msg)
	minetest.log("warning", msg)
end
_mod.util.warning = warn_console

-- formatter function for table data
local logformat = function(msg, data)
	if data ~= nil then
		for k, v in pairs(data) do
			msg = msg.." "..tostring(k).."="..tostring(v)
		end
	end
	return msg
end
_mod.util.logformat = logformat

-- get a warning function which additionally prints to a caller-passed printer.
local mkwarning = function(callername, extraprinter)
	return function(msg, data)
		local str = "["..callername.."] "..logformat(msg, data)
		warn_console(str)
		extraprinter(str)
	end
end
_mod.util.mkwarning = mkwarning

-- create a copy of a table.
-- used if a table is expected to be modified,
-- but the original also needs preserving.
local shallowcopy = function(t)
	local result = {}
	for k, v in pairs(t) do result[k] = v end
	return result
end
_mod.util.shallowcopy = shallowcopy
