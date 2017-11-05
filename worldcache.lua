-- caching system to postpone node overwrites until the end of an operation,
-- and to alleviate multiple read accesses of the same node.
-- the rationale for this is that the vertex space code makes a deep assumption that the graph is not changed until it is finished.
-- changing a node from callbacks counts as violating this rule.
-- instead, this object allows writes to be postponed until completion, then written out all at once.
-- anything that uses this must be prepared for arbitary orders of writes of node data and metadata,
-- but a node write to position x is guaranteed to complete before a metadata write starts at same position x.
local mthasher = _mod.util.node_hasher

-- creates cache handlers from a table and callbacks.
-- read callback is invoked if a key is not present in the cache.
-- write callback is invoked for each cached key when written out.
-- returns three functions: get, set, and flush, which do as you would expect.
local mkcache = function(store, read, write)
	local get = function(key)
		if store[key] == nil then
			store[key] = read(key)
		end
		return store[key]
	end
	local set = function(key, value) store[key] = value end
	local flush = function()
		for k, v in pairs(store) do write(k, v) end
	end
	return get, set, flush
end

-- alt. form of the above which hashes keys which have non-value-type properties
-- (such as minetest xyz coord tables),
-- where hasher(ka) can equal hasher(kb) even when ka != kb.
-- (for the MT coords case, tables can be distinct but refer to the same position).
-- values in the store are indexed by the hash instead of the key directly,
-- but the underlying read/write callbacks still see the unhashed key.
-- returns the store instead of taking it, and also returns the mapping table.
local mkcachehashed = function(read, write, hasher)
	local store = {}
	local maptokey = {}
	local get = function(key)
		local hash = hasher(key)
		local v = store[hash]
		if v == nil then
			v = read(key)
			store[hash] = v
			maptokey[hash] = key
		end
		return v
	end
	local set = function(key, value)
		local hash = hasher(key)
		store[hash] = value
		if maptokey[hash] == nil then maptokey[hash] = key end
	end
	local flush = function()
		for h, v in pairs(store) do
			local k = maptokey[h]
			write(k, v)
		end
	end
	return get, set, flush, store, maptokey
end



-- metadata access object that caches and batches changes.
local mkmetadelayer = function(pos)
	local m = minetest.get_meta(pos)

	local icache = {}
	local iread = function(key) return m:get_int(key) end
	local iwrite = function(key, value) return m:set_int(key, value) end

	local fcache = {}
	local fread = function(key) return m:get_float(key) end
	local fwrite = function(key, value) return m:set_float(key, value) end

	local scache = {}
	local sread = function(key) return m:get_string(key) end
	local swrite = function(key, value) return m:set_string(key, value) end

	local iget, iset, iflush = mkcache(icache, iread, iwrite)
	local fget, fset, fflush = mkcache(fcache, fread, fwrite)
	local sget, sset, sflush = mkcache(scache, sread, swrite)

	local flush_all = function() iflush() fflush() sflush() end
	local interface = {
		get_int = iget,
		set_int = iset,
		get_float = fget,
		set_float = fset,
		get_string = sget,
		set_string = sset,
		flush = flush_all,
	}
	return interface
end



-- default "grid" implementation referring to the minetest world.
local mkmtgrid = function()
	local grid = {}
	grid.get = function(pos)
		return minetest.get_node(pos)
	end
	grid.getmetaref = function(pos)
		return mkmetadelayer(pos)
	end
	grid.set = function(pos, node)
		minetest.set_node(pos, node)
	end
	grid.hasher = mthasher
	return grid
end



local newcache = function(rawgrid)
	-- in most cases, rawgrid should be omitted to refer to the global MT world.
	if rawgrid == nil then
		rawgrid = mkmtgrid()
	end
	local grid = rawgrid
	local hasher = grid.hasher
	local metarefs = {}
	local metaflushers = {}

	local nget, nset, nflush = mkcachehashed(grid.get, grid.set, hasher)
	-- isolate the meta ref's flush() function so that it can only be called via flushing this.
	local getmetaraw = function(pos)
		local m = grid.getmetaref(pos)
		local flush = m.flush
		m.flush = nil
		return m, flush
	end
	local getmetaref = function(pos)
		local hash = hasher(pos)
		local m = metarefs[hash]
		if m == nil then
			local meta, flush = getmetaraw(pos)
			metarefs[hash] = meta
			metaflushers[hash] = flush
			return meta
		else
			return m
		end
	end
	local flush = function()
		nflush()
		for _, mflush in pairs(metaflushers) do mflush() end
	end

	return {
		get = nget,
		set = nset,
		getmetaref = getmetaref,
		flush = flush,
	}
end



return {
	mkcache = mkcache,
	mkmetadelayer = mkmetadelayer,
	mkmtgrid = mkmtgrid,
	new = newcache,
}
