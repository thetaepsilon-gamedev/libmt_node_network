## What's all this hash nonsense?

The abstract algorithms on which the network code is based come from graph theory in mathematics.
Graphs can be visualised as a bunch of dots (vertices) connected by lines (edges).
The algorithms are often described in terms of vertices and edges alone;
using terms in their pseudocode such as "if vertex is not already visited then...".

The above implies that the vertices can be compared by-value equal.
We essentially want to use the algorithms and apply them to the Minetest world,
so that vertices are nodes addressed by their co-ordinates,
and edges are neighbouring nodes which are to be considered "connected" to a given node.

*however*, within Minetest, the operations that work with node co-ordinates often produce distinct tables.
This is a minor problem as it means two co-ord tables that intuitively compare equal "by value"
(because the x, y and z co-ordinates all match up) do not in lua,
as they are distinct tables, and lua only compares them by their address.

To fix this problem without requiring metatables everywhere,
the implementations of the abstract graph algorithms understand the concept of a vertex's hash.
The hash is used to compare two vertices - if they compare by-value equal as lua determines it,
then those two vertices are compared equal.
This is used to e.g. check for the existance of a vertex using it's hash internally.

A "vertex" is actually passed around in this mod as a pairing of a vertex's *payload*
(e.g. the adformentioned co-ordinate table) and it's hash.
When being passed by value to a function,
the convention is to pass vertex payload followed by hash as two arguments,
however for historical reasons this is often referred to as just "vertex" and "hash".
When passing or returning a *set* of unique vertices,
the vertices are stored in a table where the key is the hash and the value is the payload or reference to such.
For example, the successor function, which determines "which vertices are connected to this one?",
is a function which is passed the vertex payload and hash as two separate arguments,
and returns a table as described above.
