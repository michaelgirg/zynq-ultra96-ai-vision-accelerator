// =============================================================================
// plru.sv -- parameterized tree pseudo-LRU replacement policy
// -----------------------------------------------------------------------------
// This module chooses which way should be replaced when every way in a cache
// set already contains valid data.
//
// It supports any power-of-two number of ways:
//   2 ways -> 1 PLRU bit per set
//   4 ways -> 3 PLRU bits per set
//   8 ways -> 7 PLRU bits per set
//
// Each cache set receives its own PLRU tree containing NUM_WAYS - 1 bits.
//
// Each tree bit points toward the side that should be replaced next:
//   0 = follow the left side
//   1 = follow the right side
//
// When a way is accessed, every tree bit along that way's path is changed to
// point away from the accessed way. This makes the opposite side the preferred
// replacement side.
// =============================================================================

module plru #(
    parameter int NUM_SETS = 16,
    parameter int NUM_WAYS = 2,

    parameter int SET_INDEX_BITS = $clog2(NUM_SETS),
    parameter int WAY_INDEX_BITS = $clog2(NUM_WAYS),
    parameter int PLRU_BITS      = NUM_WAYS - 1,
    parameter int PLRU_LEVELS    = $clog2(NUM_WAYS)
) (
    input logic clk,
    input logic rst,

    // Set whose current replacement victim is being requested.
    input  logic [SET_INDEX_BITS-1:0] lookup_set,
    output logic [WAY_INDEX_BITS-1:0] victim_way,

    // Update the PLRU state after a way is accessed or refilled.
    input logic                      update,
    input logic [SET_INDEX_BITS-1:0] update_set,
    input logic [WAY_INDEX_BITS-1:0] accessed_way
);

    typedef logic [WAY_INDEX_BITS-1:0] way_t;

    // Every cache set has its own independent PLRU tree.
    logic [PLRU_BITS-1:0] plru_q [0:NUM_SETS-1];

    // Tree PLRU requires a balanced binary tree, so the number of ways must
    // be a power of two.
    function automatic logic is_power_of_two(input int value);
        is_power_of_two = (value > 0) && ((value & (value - 1)) == 0);
    endfunction

    initial begin
        if (NUM_SETS < 2) $fatal(1, "NUM_SETS must be at least 2");
        if (NUM_WAYS < 2) $fatal(1, "NUM_WAYS must be at least 2");
        if (!is_power_of_two(NUM_SETS)) $fatal(1, "NUM_SETS must be a power of two");
        if (!is_power_of_two(NUM_WAYS)) $fatal(1, "NUM_WAYS must be a power of two for PLRU");
    end

    /*
                         node 0
                    /              \
                node 1            node 2
               /      \          /      \
           node 3   node 4   node 5   node 6
           /   \     /   \    /   \     /   \
         W0    W1  W2    W3  W4   W5   W6    W7

        This diagram shows an 8-way cache.

        The same structure becomes smaller for fewer ways:

        2-way:
                    node 0
                   /      \
                 W0        W1

        4-way:
                       node 0
                     /        \
                 node 1      node 2
                 /   \        /   \
               W0    W1     W2    W3
    */

    // -------------------------------------------------------------------------
    // Victim selection
    // -------------------------------------------------------------------------
    // Start at the root node and follow the direction stored in each PLRU bit.
    // Every node selects either the left or right child. After PLRU_LEVELS
    // decisions, the traversal reaches a leaf representing the victim way.
    // -------------------------------------------------------------------------

    always_comb begin
        int   node;
        logic direction;

        // Begin at the root of the requested set's PLRU tree.
        node       = 0;
        victim_way = '0;

        // Walk from the root to a leaf.
        for (int level = 0; level < PLRU_LEVELS; level++) begin
            // Read the replacement direction from the current tree node.
            //   0 means move left.
            //   1 means move right.
            direction = plru_q[lookup_set][node];

            // Build the victim-way number one bit at a time. The first
            // direction becomes the most significant bit of the way number.
            victim_way = (victim_way << 1) | way_t'(direction);

            // Move to the selected child node:
            //   left child  = 2 * node + 1
            //   right child = 2 * node + 2
            node = (node << 1) + 1 + int'(direction);
        end
    end

    // -------------------------------------------------------------------------
    // PLRU state update
    // -------------------------------------------------------------------------
    // When a way is accessed, walk from the root toward that way. At every
    // node, change the PLRU bit so it points away from the side just used.
    //
    // Example:
    //   If the accessed way is on the left side, store 1 so replacement looks
    //   toward the right side next time.
    //
    //   If the accessed way is on the right side, store 0 so replacement looks
    //   toward the left side next time.
    // -------------------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset every set's tree to zero. This causes the initial victim
            // traversal to follow left at every level and select way 0.
            for (int set_index = 0; set_index < NUM_SETS; set_index++) begin
                plru_q[set_index] <= '0;
            end
        end
        else if (update) begin
            logic [PLRU_BITS-1:0] next_plru;
            logic                 direction;
            int                   node;

            // Copy the selected set's current PLRU state. Only this temporary
            // copy is modified during the tree traversal.
            next_plru = plru_q[update_set];
            node      = 0;

            // Walk from the root to the way that was just accessed.
            for (int level = 0; level < PLRU_LEVELS; level++) begin

                // Read one bit of the accessed-way number at each level.
                // Start with its most significant bit because that bit chooses
                // the top-level left or right subtree.
                direction = accessed_way[WAY_INDEX_BITS-1-level];

                // Point the node away from the side that was just used.
                next_plru[node] = ~direction;

                // Continue down the path toward the accessed way.
                node = (node << 1) + 1 + int'(direction);
            end
            // Save the updated tree back into the correct cache set.
            plru_q[update_set] <= next_plru;
        end
    end

endmodule
