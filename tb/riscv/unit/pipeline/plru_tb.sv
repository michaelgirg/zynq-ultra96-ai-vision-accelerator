`timescale 1ns/1ps

module plru_tb #(
    parameter int NUM_RANDOM_TESTS = 1000
);
    localparam int NUM_SETS_2 = 4;
    localparam int NUM_WAYS_2 = 2;
    localparam int SET_BITS_2 = $clog2(NUM_SETS_2);
    localparam int WAY_BITS_2 = $clog2(NUM_WAYS_2);

    localparam int NUM_SETS_4 = 4;
    localparam int NUM_WAYS_4 = 4;
    localparam int SET_BITS_4 = $clog2(NUM_SETS_4);
    localparam int WAY_BITS_4 = $clog2(NUM_WAYS_4);
    localparam int TREE_BITS_4 = NUM_WAYS_4 - 1;

    localparam int NUM_SETS_8 = 4;
    localparam int NUM_WAYS_8 = 8;
    localparam int SET_BITS_8 = $clog2(NUM_SETS_8);
    localparam int WAY_BITS_8 = $clog2(NUM_WAYS_8);
    localparam int TREE_BITS_8 = NUM_WAYS_8 - 1;

    logic clk;
    logic rst;

    logic [SET_BITS_2-1:0] lookup_set_2;
    logic [WAY_BITS_2-1:0] victim_way_2;
    logic                  update_2;
    logic [SET_BITS_2-1:0] update_set_2;
    logic [WAY_BITS_2-1:0] accessed_way_2;

    logic [SET_BITS_4-1:0] lookup_set_4;
    logic [WAY_BITS_4-1:0] victim_way_4;
    logic                  update_4;
    logic [SET_BITS_4-1:0] update_set_4;
    logic [WAY_BITS_4-1:0] accessed_way_4;

    logic [TREE_BITS_4-1:0] model_tree_4 [0:NUM_SETS_4-1];

    logic [SET_BITS_8-1:0] lookup_set_8;
    logic [WAY_BITS_8-1:0] victim_way_8;
    logic                  update_8;
    logic [SET_BITS_8-1:0] update_set_8;
    logic [WAY_BITS_8-1:0] accessed_way_8;
    logic [TREE_BITS_8-1:0] model_tree_8 [0:NUM_SETS_8-1];

    int errors;
    int tests;

    plru #(
        .NUM_SETS(NUM_SETS_2),
        .NUM_WAYS(NUM_WAYS_2)
    ) dut_2way (
        .clk         (clk),
        .rst         (rst),
        .lookup_set  (lookup_set_2),
        .victim_way  (victim_way_2),
        .update      (update_2),
        .update_set  (update_set_2),
        .accessed_way(accessed_way_2)
    );

    plru #(
        .NUM_SETS(NUM_SETS_4),
        .NUM_WAYS(NUM_WAYS_4)
    ) dut_4way (
        .clk         (clk),
        .rst         (rst),
        .lookup_set  (lookup_set_4),
        .victim_way  (victim_way_4),
        .update      (update_4),
        .update_set  (update_set_4),
        .accessed_way(accessed_way_4)
    );

    plru #(
        .NUM_SETS(NUM_SETS_8),
        .NUM_WAYS(NUM_WAYS_8)
    ) dut_8way (
        .clk         (clk),
        .rst         (rst),
        .lookup_set  (lookup_set_8),
        .victim_way  (victim_way_8),
        .update      (update_8),
        .update_set  (update_set_8),
        .accessed_way(accessed_way_8)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic logic [WAY_BITS_4-1:0] model_victim_4(
        input logic [TREE_BITS_4-1:0] tree_bits
    );
        logic [WAY_BITS_4-1:0] way;
        logic direction;
        int node;

        begin
            way  = '0;
            node = 0;

            for (int level = 0; level < WAY_BITS_4; level++) begin
                direction = tree_bits[node];
                way = (way << 1) | WAY_BITS_4'(direction);
                node = (node << 1) + 1 + int'(direction);
            end

            model_victim_4 = way;
        end
    endfunction

    function automatic logic [TREE_BITS_4-1:0] model_mark_used_4(
        input logic [TREE_BITS_4-1:0] current_tree,
        input logic [WAY_BITS_4-1:0] used_way
    );
        logic [TREE_BITS_4-1:0] next_tree;
        logic direction;
        int node;

        begin
            next_tree = current_tree;
            node      = 0;

            for (int level = 0; level < WAY_BITS_4; level++) begin
                direction = used_way[WAY_BITS_4-1-level];
                next_tree[node] = ~direction;
                node = (node << 1) + 1 + int'(direction);
            end

            model_mark_used_4 = next_tree;
        end
    endfunction

    function automatic logic [WAY_BITS_8-1:0] model_victim_8(
        input logic [TREE_BITS_8-1:0] tree_bits
    );
        logic [WAY_BITS_8-1:0] way;
        logic direction;
        int node;

        begin
            way  = '0;
            node = 0;

            for (int level = 0; level < WAY_BITS_8; level++) begin
                direction = tree_bits[node];
                way = (way << 1) | WAY_BITS_8'(direction);
                node = (node << 1) + 1 + int'(direction);
            end

            model_victim_8 = way;
        end
    endfunction

    function automatic logic [TREE_BITS_8-1:0] model_mark_used_8(
        input logic [TREE_BITS_8-1:0] current_tree,
        input logic [WAY_BITS_8-1:0] used_way
    );
        logic [TREE_BITS_8-1:0] next_tree;
        logic direction;
        int node;

        begin
            next_tree = current_tree;
            node      = 0;

            for (int level = 0; level < WAY_BITS_8; level++) begin
                direction = used_way[WAY_BITS_8-1-level];
                next_tree[node] = ~direction;
                node = (node << 1) + 1 + int'(direction);
            end

            model_mark_used_8 = next_tree;
        end
    endfunction

    task automatic check_2way(
        input int set_index,
        input int expected_way,
        input string test_name
    );
        lookup_set_2 = SET_BITS_2'(set_index);
        #1;
        tests++;

        if (victim_way_2 !== WAY_BITS_2'(expected_way)) begin
            $error(
                "%s: set=%0d expected victim=%0d actual=%0d",
                test_name,
                set_index,
                expected_way,
                victim_way_2
            );
            errors++;
        end
    endtask

    task automatic use_2way(
        input int set_index,
        input int used_way
    );
        @(negedge clk);
        update_set_2  = SET_BITS_2'(set_index);
        accessed_way_2 = WAY_BITS_2'(used_way);
        update_2       = 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);
        update_2 = 1'b0;
    endtask

    task automatic check_4way(
        input int set_index,
        input logic [WAY_BITS_4-1:0] expected_way,
        input string test_name
    );
        lookup_set_4 = SET_BITS_4'(set_index);
        #1;
        tests++;

        if (victim_way_4 !== expected_way) begin
            $error(
                "%s: set=%0d expected victim=%0d actual=%0d tree=%03b",
                test_name,
                set_index,
                expected_way,
                victim_way_4,
                model_tree_4[set_index]
            );
            errors++;
        end
    endtask

    task automatic use_4way(
        input int set_index,
        input int used_way
    );
        model_tree_4[set_index] = model_mark_used_4(
            model_tree_4[set_index],
            WAY_BITS_4'(used_way)
        );

        @(negedge clk);
        update_set_4   = SET_BITS_4'(set_index);
        accessed_way_4 = WAY_BITS_4'(used_way);
        update_4       = 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);
        update_4 = 1'b0;
    endtask

    task automatic check_8way(
        input int set_index,
        input logic [WAY_BITS_8-1:0] expected_way,
        input string test_name
    );
        lookup_set_8 = SET_BITS_8'(set_index);
        #1;
        tests++;

        if (victim_way_8 !== expected_way) begin
            $error(
                "%s: set=%0d expected victim=%0d actual=%0d tree=%07b",
                test_name,
                set_index,
                expected_way,
                victim_way_8,
                model_tree_8[set_index]
            );
            errors++;
        end
    endtask

    task automatic use_8way(
        input int set_index,
        input int used_way
    );
        model_tree_8[set_index] = model_mark_used_8(
            model_tree_8[set_index],
            WAY_BITS_8'(used_way)
        );

        @(negedge clk);
        update_set_8   = SET_BITS_8'(set_index);
        accessed_way_8 = WAY_BITS_8'(used_way);
        update_8       = 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);
        update_8 = 1'b0;
    endtask

    initial begin
        errors = 0;
        tests  = 0;

        rst            = 1'b1;
        lookup_set_2   = '0;
        update_2       = 1'b0;
        update_set_2   = '0;
        accessed_way_2 = '0;
        lookup_set_4   = '0;
        update_4       = 1'b0;
        update_set_4   = '0;
        accessed_way_4 = '0;
        lookup_set_8   = '0;
        update_8       = 1'b0;
        update_set_8   = '0;
        accessed_way_8 = '0;

        for (int set_index = 0; set_index < NUM_SETS_4; set_index++)
            model_tree_4[set_index] = '0;

        for (int set_index = 0; set_index < NUM_SETS_8; set_index++)
            model_tree_8[set_index] = '0;

        repeat (2) @(posedge clk);
        #1;
        rst = 1'b0;

        // Reset chooses way 0 independently in every set.
        for (int set_index = 0; set_index < NUM_SETS_2; set_index++)
            check_2way(set_index, 0, "2-way reset");

        for (int set_index = 0; set_index < NUM_SETS_4; set_index++)
            check_4way(set_index, '0, "4-way reset");

        for (int set_index = 0; set_index < NUM_SETS_8; set_index++)
            check_8way(set_index, '0, "8-way reset");

        // In a 2-way tree, using one way makes the opposite way the victim.
        use_2way(1, 0);
        check_2way(1, 1, "2-way use way 0");
        check_2way(0, 0, "2-way other set unchanged");

        use_2way(1, 1);
        check_2way(1, 0, "2-way use way 1");

        // Directed 4-way traversal visits all four leaves and checks the
        // expected path changes after each access.
        use_4way(2, 0);
        check_4way(2, 2, "4-way after using way 0");

        use_4way(2, 2);
        check_4way(2, 1, "4-way after using way 2");

        use_4way(2, 1);
        check_4way(2, 3, "4-way after using way 1");

        use_4way(2, 3);
        check_4way(2, 0, "4-way after using way 3");
        check_4way(3, 0, "4-way independent set");

        // Walk every 8-way leaf and compare each update against the independent
        // tree model. This covers the largest supported configuration used by
        // the current cache experiments.
        for (int way = 0; way < NUM_WAYS_8; way++) begin
            use_8way(1, way);
            check_8way(
                1,
                model_victim_8(model_tree_8[1]),
                $sformatf("8-way directed use way %0d", way)
            );
        end
        check_8way(0, 0, "8-way independent set");

        // Random accesses are checked against an independent tree model.
        for (int test_index = 0;
             test_index < NUM_RANDOM_TESTS;
             test_index++) begin
            int random_set;
            int random_way;
            int random_set_8;
            int random_way_8;

            random_set = $urandom_range(0, NUM_SETS_4 - 1);
            random_way = $urandom_range(0, NUM_WAYS_4 - 1);
            random_set_8 = $urandom_range(0, NUM_SETS_8 - 1);
            random_way_8 = $urandom_range(0, NUM_WAYS_8 - 1);

            use_4way(random_set, random_way);
            check_4way(
                random_set,
                model_victim_4(model_tree_4[random_set]),
                $sformatf("random PLRU update %0d", test_index)
            );

            // Also sample a different set to catch accidental cross-set
            // updates.
            check_4way(
                (random_set + 1) % NUM_SETS_4,
                model_victim_4(
                    model_tree_4[(random_set + 1) % NUM_SETS_4]
                ),
                $sformatf("random set isolation %0d", test_index)
            );

            use_8way(random_set_8, random_way_8);
            check_8way(
                random_set_8,
                model_victim_8(model_tree_8[random_set_8]),
                $sformatf("random 8-way PLRU update %0d", test_index)
            );

            check_8way(
                (random_set_8 + 1) % NUM_SETS_8,
                model_victim_8(
                    model_tree_8[(random_set_8 + 1) % NUM_SETS_8]
                ),
                $sformatf("random 8-way set isolation %0d", test_index)
            );
        end

        if (errors == 0)
            $display("PASS: plru_tb (%0d checks)", tests);
        else
            $fatal(1, "FAIL: plru_tb had %0d errors across %0d checks",
                   errors, tests);

        $finish;
    end

endmodule
