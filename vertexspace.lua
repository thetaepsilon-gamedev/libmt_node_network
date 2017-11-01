--[[
A vertex space is an abstract set of vertexes.
Within the vertex space, these vertexes may be grouped into connected graphs.
A vertex is at any time a member of exactly one graph;
"floating" vertexes not connected to anything become their own graph.
A vertex space as an object supports adding and removing of vertex references,
and obtaining a handle to the graph a vertex reference belongs to.

Adding a new vertex causes it's successors to be examined,
by calling the successor function on it.
If the vertex has no successors, then this vertex is "floating on it's own",
and a new graph is created to contain this isolated vertex.

Otherwise, each of these successors is checked to see if it is already a part of a graph.
If the successors all name a single unique graph,
then the original vertex is simply added to the vertex set of that graph.
If there are multiple graphs referenced by the successors connected to the original vertex,
then the new vertex effectively constructs a bridge between those graphs;
one of the graphs is picked to have the others merged into,
then the original vertex is added to the merged network.

For removing a vertex, prior to it's actual removal,
again it's successors are examined.
If the vertex has no successors then it is simply removed from it's containing graph;
as by the time this can happen the graph will only have that one vertex left,
this will trigger the deletion of the now-empty graph.

Otherwise, one of the successors is picked and the search algorithm is run on it.
When the search has completed, the other successors are compared against the search's visited set.
If any of the successors are NOT contained in the visited set,
then they are no longer reachable from the current graph and represent a completely disconnected section.
Each candidate successor then has the search algorithm ran on it and it's results inserted into a new graph;
checking along the way to see if any of the new networks now include the candidate,
until no candidates remain.
]]
local dname_new = "vertexspace.new()"
local newsearch = _mod.modules.bfmap.new
local check = _mod.util.mkfnexploder(dname_new)

return {
	-- impl contains functions that handle vertex-type-specific functionality.
	-- contains the following function keys:
	--	hasher: like in bfmap, must return a uniquely identifying value.
	--		references to the same vertex must hash to the same value.
	new = function(impl)
		if type(impl) ~= "table" then
			error(dname_new.." no impl table passed for vertex functions")
		end

		-- vertex-to-graph mapping.
		-- keys are determined by the hasher function.
		local maptograph = {}
		-- actual graph sets table.
		-- graph IDs are numerical indexes.
		-- the graphs themselves are also tables,
		-- where for each entry the value is the vertex ref itself,
		-- and the keys are the hashes.
		local nextfree = 1
		local graphs = {}

		local hasher = check(impl.hasher, "vertex hasher")

		local interface = {}

		return interface
	end,
}
