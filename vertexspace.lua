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


]]
