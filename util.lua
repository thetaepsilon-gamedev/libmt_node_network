local centerpos = _mod.util.center_on_node
local node_hasher = function(vertex) return minetest.hash_node_position(centerpos(vertex)) end
_mod.util.node_hasher = node_hasher

-- helper utility for callback tables.
-- looks up a key in the table and returns that if it's a function.
-- if it's nil, return a provided default function;
-- the default function should be idempotent
-- (i.e. it does nothing or it returns a default value which doesn't affect anything).
-- if the key is neither a function nor nil then an error is thrown.
local mkfnexploder = _mod.util.mkfnexploder
local mk_callback_or_missing = function(caller)
	local checkfn = mkfnexploder(caller)
	return function(t, key, default)
		local fn = t[key]
		if fn ~= nil then
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
