`timescale 1 ns/10 ps

module BATCHARGER_64b_tb;
   
   wire [63:0] vin;
   wire [63:0] vbat;     
   wire [63:0] ibat;     
   wire [63:0] vtbat;    
   wire [63:0] dvdd;  
   wire [63:0] dgnd;  
   wire [63:0] pgnd;		       
                    
   reg         en;   
   reg [3:0]   sel;  
   reg [3:0]   simulation_phase;  // Track simulation phase
   
   real        rl_dvdd, rl_dgnd, rl_pgnd;
   real        rl_ibat, rl_vbat, rl_vtbat;
   real        rl_vin;         


    // Declare a reg for forced current
    reg [63:0] forced_current;
   // UUT and Battery Model Instantiations
   BATCHARGER_64b uut(
      .iforcedbat(ibat),
      .vsensbat(vbat),
      .vin(vin),
      .vbattemp(vtbat),	
      .en(en),     
      .sel(sel),
      .dvdd(dvdd),
      .dgnd(dgnd),
      .pgnd(pgnd)  
   );   
   
   BATCHARGERlipo lipobattery(
      .vbat(vbat),     
      .ibat(ibat),     
      .vtbat(vtbat)    
   );

   // Test Tasks
    task test_full_charge;
        begin
            // Reset all test-specific variables
            simulation_phase = 1;  // Marking test phase
            $display("===== SIMULATION PHASE %0d: Full Battery Charge Test =====", simulation_phase);
            
            rl_vin = 4.5;  
            rl_pgnd = 0.0; 
            sel = 4'b0001;  // 450mAh selection    
            en = 1'b1;      // enable the module

            $display("Test 1 : Charging the battery...");
            $display("Waiting for entering TC Mode");
            wait(uut.tc);
            $display("Entered TC Mode");

            wait(uut.cc);
            $display("Entered CC Mode");

            wait(uut.cv);
            $display("Entered CV Mode");

            wait(!(uut.cv || uut.cc || uut.tc));
            $display("Charging finished");

            // Voltage check
            if (4.15 < $bitstoreal(vbat) && $bitstoreal(vbat) <= 4.2) begin
            $display("Test 1 : battery fully charged, recharge test passed, Vbat=%f", $bitstoreal(vbat));
            end else begin
            $display("Unsuccessful Test 1: VMax=%f",  $bitstoreal(vbat));
            $finish;
            end
        end
    endtask

    // Reset and Disable Test Task
    task test_module_reset;
        begin
            simulation_phase = 2;  // Marking test phase
            $display("===== SIMULATION PHASE %0d: Module Reset Test =====", simulation_phase);
            
            // Ensure a clean state before starting
            en = 1'b1;

            $display("Testing enable button to verify reset conditions");
            wait(uut.cc);
            $display("Entered CC Mode");

            $display("Disabling module (en = 0) to reset...");
            en = 0;
            #10000; 

            wait(!(uut.cv || uut.cc || uut.tc));
            $display("Successful reset: module is off");
        end
    endtask

    // Full System Reset Task
    task system_reset;
        begin
            $display("===== SYSTEM RESET =====");
            
            // Force critical signals to known state
            force en = 0;
            force sel = 4'b0001;
            rl_vin = 0.0;
            // Wait a bit and release forces
            #100;
            release en;
            release sel;
        end
    endtask

    // Initial block to run tests
    initial begin
        // Initialize simulation phase and signals
        simulation_phase = 0;
        rl_vin = 0;
        rl_pgnd = 0;
        sel = 4'b0001;
        en = 0;

        // Wait for initial stabilization
        #1000;

        // Run first test
        test_full_charge;  // Removed empty parentheses

        // System reset between tests
        system_reset;  // Removed empty parentheses

        //test_battery_discharge;
        
        // Wait between tests to ensure complete reset
        #50000;

        // Run second test
        test_module_reset;  // Removed empty parentheses

        // Final simulation wrap-up
        $display("===== ALL TESTS COMPLETED =====");
        $display("Simulation completed successfully. Ready for SimVision restart.");
        
        // Helpful for SimVision restart
        $finish;
    end

   // Signal conversion block (unchanged from original)
   initial assign rl_vbat = $bitstoreal(vbat);
   initial assign rl_vtbat = $bitstoreal(vtbat);
   initial assign rl_ibat = $bitstoreal(ibat);
   initial assign rl_dvdd = $bitstoreal(dvdd);
   initial assign rl_dgnd = $bitstoreal(dgnd);   
   
   assign vin = $realtobits(rl_vin);
   assign pgnd = $realtobits(rl_pgnd);
   
endmodule