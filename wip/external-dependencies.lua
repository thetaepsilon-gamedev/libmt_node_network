local libmthelpers = modns.get("com.github.thetaepsilon.minetest.libmthelpers")
_mod.util.increment_counter = libmthelpers.stats.increment_counter
_mod.new.queue = libmthelpers.datastructs.new.queue
_mod.util.mkfnexploder = libmthelpers.check.mkfnexploder
_mod.util.mkassert = libmthelpers.check.mkassert
_mod.util.table_get_single = libmthelpers.tableutils.getsingle
_mod.util.arraytomap = libmthelpers.tableutils.arraytomap
_mod.util.mkprofiler = libmthelpers.profiling.create_profiler
