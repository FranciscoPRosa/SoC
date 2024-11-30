`timescale 1 ns/10 ps


module BATCHARGER_64b_tb;
   
   wire [63:0] vin; // input voltage; must be at least 200mV higher than vsensbat to allow iforcedbat > 0
   wire [63:0] vbat;     // battery voltage (V)
   wire [63:0] ibat;     // battery current (A)
   wire [63:0] vtbat;    // Battery temperature
   wire [63:0] dvdd;  // digital supply
   wire [63:0] dgnd;  // digital ground
   wire [63:0] pgnd;  // power ground		       

                    
   reg         en;   // enables the module
   reg [3:0]   sel;  // battery capacity selection bits: b[3,2,1,0] weights are 400,200,100,50 mAh + offset of 50mAh covers the range from 50 up to 800 mAh 
   
   
   real        rl_dvdd, rl_dgnd, rl_pgnd;
   real        rl_ibat, rl_vbat, rl_vtbat;
   real        rl_vin;         // converted value of vin to real 

   reg C0, C1, C2, C3, C4, C5, C6, C7, Cs;



BATCHARGER_64b uut(
		   .iforcedbat(ibat), // output current to battery
		   .vsensbat(vbat), // voltage sensed (obtained at the battery as "voltage from iforcedbat integration" + ESR * iforcedbat)
		   .vin(vin), // input voltage; must be at least 200mV higher than vsensbat to allow iforcedbat > 0
		   .vbattemp(vtbat),	// voltage that represents the battery temperature -40ºC to 125ºC -> 0 to 0.5V	   
		   .en(en),     // block enable control
		   .sel(sel), // battery capacity selection bits: b[3,2,1,0] weights are 400,200,100,50 mAh + offset of 50mAh covers the range from 50 up to 800 mAh 
		   .dvdd(dvdd), // digital supply
		   .dgnd(dgnd), // digital ground
		   .pgnd(pgnd)  // power ground		       

);   

   
BATCHARGERlipo lipobattery(
		   .vbat(vbat),     // battery voltage (V)
		   .ibat(ibat),     // battery current (A)
		   .vtbat(vtbat)    // Battery temperature
		   );


// These conditions have to be change according to the values placed in the full charger file (BATCHARGER_64b.v)
// Since it wasn't possible to use the values from the ADC block (for example vbat[7:0]), the analog values were used
// As such, they values have to be tuned due to the sampling, for the maximum or minimum value of the ADC scale   
always @(*) begin
   C0 = ((0.121212 <= rl_vtbat) && (rl_vtbat <= 0.258206));
   C1 = (rl_vbat < 4.192); // 4.2 in the scale
   C2 = (rl_vbat < 2.99);
   C3 = (rl_vbat >= 2.99);
   C4 = (rl_vbat >= 3.77);
   C5 = (uut.BATCHctr.charge_time >= uut.tmax);
   C6 = (rl_ibat < 0.0395); // This condit
   C7 = (rl_vbat <= 4.163); // Recharge condition (simplified for now)
   Cs = (uut.rstz && en && uut.vtok);
end

   
   // Helper functions for state checks
function is_idle;
    input reg cc, cv, tc, imeasen, vmeasen, tmeasen;
    begin
        is_idle = (!cc && !cv && !tc && !imeasen && vmeasen && tmeasen);
    end
endfunction

function is_tc_mode;
    input reg cc, cv, tc, imeasen, vmeasen, tmeasen;
    begin
        is_tc_mode = (!cc && !cv && tc && !imeasen && vmeasen && tmeasen);
    end
endfunction

function is_cc_mode;
    input reg cc, cv, tc, imeasen, vmeasen, tmeasen;
    begin
        is_cc_mode = (cc && !cv && !tc && !imeasen && vmeasen && tmeasen);
    end
endfunction

function is_cv_mode;
    input reg cc, cv, tc, imeasen, vmeasen, tmeasen;
    begin
        // Return true if conditions match for CV mode
        is_cv_mode = (!cc && cv && !tc && imeasen && !vmeasen && tmeasen);
    end
endfunction


function is_end_mode;
    input reg cc, cv, tc, imeasen, vmeasen, tmeasen;
    begin
        is_end_mode = (!cc && !cv && !tc && !imeasen && vmeasen && !tmeasen);
    end
endfunction

// to be sure all transitions are being made correctly, it check which was the previous state and the transition coherence
/*
   States and previous possible state:
      - IDLE: 0b000 -> All states;
      - TC MODE: 0b001 -> IDLE;
      - CC MODE: 0b010 -> IDLE, TC;
      - CV MODE: 0b011 -> CC;
      - END: 0b100 -> IDLE, CV;
*/
function check_prev_state;
   input reg [2:0] curr_state;  // Current state
   input reg [2:0] prev_state;  // Previous state

   begin
      if (curr_state == 3'b001) begin
         // TC MODE: Allowed previous state is IDLE
         check_prev_state = (prev_state == 3'b000);
      end
      else if (curr_state == 3'b010) begin
         // CC MODE: Allowed previous states are IDLE, TC
         check_prev_state = ((prev_state == 3'b000) || (prev_state == 3'b001));
      end
      else if (curr_state == 3'b011) begin
         // CV MODE: Allowed previous state is CC
         check_prev_state = (prev_state == 3'b010);
      end
      else if (curr_state == 3'b100) begin
         // END MODE: Allowed previous states are CV, IDLE
         check_prev_state = ((prev_state == 3'b011) || (prev_state == 3'b000));
      end
      else begin
         // IDLE or unknown states: No restrictions
         check_prev_state = 1;
      end
   end
endfunction



task verify_state;
   input integer timeout;       // Maximum time (in time units) for verification
   reg [2:0] curr_state;        // Current state
   reg [2:0] prev_state;        // Previous state
   reg [31:0] elapsed_time;     // Counter for elapsed time

   begin
      elapsed_time = 0;
      prev_state = 3'b111;  // Assume initial state is IDLE
      curr_state = 3'b000;
      while (elapsed_time < timeout) begin
         @(posedge uut.clk);  // Trigger on the positive edge of the clock
         
         // Delay between state checks
         #10000;
         elapsed_time = elapsed_time + 1;
         // IDLE state verification
         if (is_idle(uut.cc, uut.cv, uut.tc, uut.imeasen, uut.vmeasen, uut.tmeasen)) begin
            if (!Cs || !C7 || !C0 || C7) begin
               if(prev_state != curr_state) begin
                  $display("Correct state - IDLE at time %0t", $time);
                  // Verify state transition coherence
                  if (!check_prev_state(curr_state, prev_state)) begin
                     $display("ERROR: Invalid state transition from %b to %b at time %0t", prev_state, curr_state, $time);
                     $finish;
                  end
               end
               prev_state = curr_state;
               curr_state = 3'b000;
            end else begin
               $display("Wrong state - should be IDLE, is STATE #%d at time %0t", uut.BATCHctr.state, $time);
               $finish;
            end
         end
         // TC MODE state verification
         else if (is_tc_mode(uut.cc, uut.cv, uut.tc, uut.imeasen, uut.vmeasen, uut.tmeasen)) begin
            if (Cs && C0 && C1 && C2 && !C3) begin
               if(prev_state != curr_state) begin
                  $display("Correct state - TC MODE at time %0t", $time);
                  // Verify state transition coherence
                  if (!check_prev_state(curr_state, prev_state)) begin
                     $display("ERROR: Invalid state transition from %b to %b at time %0t", prev_state, curr_state, $time);
                     $finish;
                  end
               end
               prev_state = curr_state;
               curr_state = 3'b001;
            end else begin
               $display("Wrong state - should be TC MODE, is STATE #%d at time %0t", uut.BATCHctr.state, $time);
               $finish;
            end
         end
         // CC MODE state verification
         else if (is_cc_mode(uut.cc, uut.cv, uut.tc, uut.imeasen, uut.vmeasen, uut.tmeasen)) begin
            if (Cs && C0 && C1 && !C2 && C3 && !C4) begin
               if(prev_state != curr_state) begin
                  $display("Correct state - CC MODE at time %0t", $time);
                  // Verify state transition coherence
                  if (!check_prev_state(curr_state, prev_state)) begin
                     $display("ERROR: Invalid state transition from %b to %b at time %0t", prev_state, curr_state, $time);
                     $finish;
                  end
               end
               prev_state = curr_state;
               curr_state = 3'b010;
            end else begin
               $display("Wrong state - should be CC MODE, is STATE #%d at time %0t", uut.BATCHctr.state, $time);
               $finish;
            end
         end
         // CV MODE state verification
         else if (is_cv_mode(uut.cc, uut.cv, uut.tc, uut.imeasen, uut.vmeasen, uut.tmeasen)) begin
            if (Cs && C4 && !C5 && !C6) begin
               if(prev_state != curr_state) begin
                  $display("Correct state - CV MODE at time %0t", $time);
                  // Verify state transition coherence
                  if (!check_prev_state(curr_state, prev_state)) begin
                     $display("ERROR: Invalid state transition from %b to %b at time %0t", prev_state, curr_state, $time);
                     $finish;
                  end
               end
               prev_state = curr_state;
               curr_state = 3'b011;
            end else begin
               $display("Wrong state - should be CV MODE, is STATE #%d at time %0t", uut.BATCHctr.state, $time);
               $finish;
            end
         end
         // END MODE state verification
         else if (is_end_mode(uut.cc, uut.cv, uut.tc, uut.imeasen, uut.vmeasen, uut.tmeasen)) begin
            if (Cs && !C7 && (C6 || C5 || C1)) begin
               if(prev_state != curr_state) begin
                  $display("Correct state - END MODE at time %0t", $time);
                  // Verify state transition coherence
                  if (!check_prev_state(curr_state, prev_state)) begin
                     $display("ERROR: Invalid state transition from %b to %b at time %0t", prev_state, curr_state, $time);
                     $finish;
                  end
               end
               prev_state = curr_state;
               curr_state = 3'b100;
            end else begin
               $display("Wrong state - should be END MODE, is STATE #%d at time %0t", uut.BATCHctr.state, $time);
               $finish;
            end
         end
         // UNKNOWN state (fallback)
         else begin
            $display("Unknown state at time %0t", $time);
            $finish;
         end
      end

      // Timeout occurred
      $display("Verification completed or timed out after %0d time units", timeout);

      // Check if the battery voltage matches the preset voltage
      if (4.15 < $bitstoreal(vbat) <= 4.2) begin
         $display("Test 1 : battery fully charged, Vbat=%f", $bitstoreal(vbat));
      end else begin
         $display("Unsuccessful Test 1: Vbat=%f",  $bitstoreal(vbat));
         $finish; // Terminate simulation if the test fails
      end
   end
endtask




// test bench
	initial begin

      // Intialization 
      rl_vin = 4.5;  // input voltage
      rl_pgnd = 0.0; // power ground
      sel[3:0] = 4'b1000;  // 450mAh selection     
      en = 1'b1; // enable the module
      C0 = 0; C1 = 0; C2 = 0; C3 = 0; C4 = 0; C5 = 0; C6 = 0; C7 = 0; Cs = 0;
      // start the simulation
      $display("===== Starting the testbench and charging the battery =====");

      // Test 1 : battery fully charge

      // After 15 pico seconds, the battery is fully charged. 
      // Drop the battery volatge to 3.55V
      // Initial delay for setup
      #110
      // ==== Test 1 : recharge - wait for battery to fully charge ====       
      verify_state(1000);
      $display("==== Test concluded with success ====")
      $finish;
   end
   
  

//-- Signals conversion ---------------------------------------------------
   initial assign rl_vbat = $bitstoreal(vbat);
   initial assign rl_vtbat = $bitstoreal(vtbat);
   initial assign rl_ibat = $bitstoreal(ibat);
   initial assign rl_dvdd = $bitstoreal(dvdd);
   initial assign rl_dgnd = $bitstoreal(dgnd);   
   
   
   assign vin = $realtobits(rl_vin);
   assign pgnd = $realtobits(rl_pgnd);
   
endmodule
