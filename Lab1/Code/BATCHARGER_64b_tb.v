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

   real        rl_tempmin, rl_tempmax, rl_vcutoff;
   real        rl_vpreset, rl_iend, rl_tmax;
   real        rl_icc, rl_icv, rl_itc;

   real        prop;

   reg C0, C1, C2, C3, C4, C5, C6, C7, Cs;

   reg [7:0]   charge_time, counter;



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
   C0 = ((rl_tempmin*(1-prop) <= rl_vtbat) && (rl_vtbat <= rl_tempmax*(1+prop)));
   C1 = (4.2*(1-prop) >= rl_vbat); // 4.2 in the scale
   C2 = (rl_vbat < rl_vcutoff*(1-prop/4));
   C3 = (rl_vbat >= rl_vcutoff*(1-prop/4));
   C4 = (rl_vbat >= rl_vpreset*(1-prop/2.5));
   C5 = (charge_time >= uut.tmax);
   C6 = (rl_ibat < rl_iend*(1+2*prop));
   C7 = (rl_vbat <= 4.163*(1-prop/16)); // Recharge condition (simplified for now)
   Cs = (uut.rstz && en && uut.vtok);
end

// Time Counter
always @(posedge uut.clk) begin
    if (is_cv_mode(uut.cc, uut.cv, uut.tc, uut.imeasen, uut.vmeasen, uut.tmeasen)) begin
        counter <= counter + 1;
        if (counter == 8'hff) begin 
            charge_time <= charge_time + 1;
            counter <= 0;
        end
    end else if (is_end_mode(uut.cc, uut.cv, uut.tc, uut.imeasen, uut.vmeasen, uut.tmeasen)) begin
        // No change to counter or charge_time during endC state
        counter <= counter;
    end else begin
        // Reset counter and charge_time if not in cvMode or endC
        charge_time <= 0;
        counter <= 0;
    end
end

// to compute the expected value of the current iforced bat for cc and tc mode
function real calculate_current(input [7:0] control, input real capacity);
    real current;
    begin
        current = capacity * (0.502 * control[7] + 
                              0.251 * control[6] + 
                              0.1255 * control[5] + 
                              0.0627 * control[4] + 
                              0.0314 * control[3] + 
                              0.0157 * control[2] + 
                              0.0078 * control[1] + 
                              0.0039 * control[0]);
        calculate_current = current;
    end
endfunction

// to compute Vtarget
function real calculate_vtarget(input [7:0] vcv);
    real Vtarget;
    begin
        Vtarget = 5.0 * (0.502 * vcv[7] + 
                         0.251 * vcv[6] + 
                         0.1255 * vcv[5] + 
                         0.0627 * vcv[4] + 
                         0.0314 * vcv[3] + 
                         0.0157 * vcv[2] + 
                         0.0078 * vcv[1] + 
                         0.0039 * vcv[0]);
        calculate_vtarget = Vtarget;
    end
endfunction

// function abs
function real abs(input real value);
    begin
        if (value < 0)
            abs = -value;
        else
            abs = value;
    end
endfunction


// Function to convert 8-bit unsigned integer to real
function real convert_8bit_to_real;
   input [7:0] integer_val;
   begin
      // Linear conversion from 0-255 to 0.0-1.0
      convert_8bit_to_real = $itor(integer_val); 
   end
endfunction   

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
         check_prev_state = (prev_state == 3'b000 || prev_state == 3'b100);
      end
      else if (curr_state == 3'b010) begin
         // CC MODE: Allowed previous states are IDLE, TC
         check_prev_state = ((prev_state == 3'b000) || (prev_state == 3'b001 || prev_state == 3'b100));
      end
      else if (curr_state == 3'b011) begin
         // CV MODE: Allowed previous state is CC
         check_prev_state = (prev_state == 3'b010 || (prev_state == 3'b000));
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
   real expectedCurrent;
   real rl_C;
   real rl_tol;
   real Vtarget;
   begin
      elapsed_time = 0;
      prev_state = 3'b111;  // Assume initial state is IDLE
      curr_state = 3'b000;
      rl_tol = 1e-8;
      rl_C = (0.05 + sel[0]*0.05 + sel[1]*0.1 + sel[2]*0.2 + sel[3]*0.4);
      expectedCurrent = 0.0;
      elapsed_time = 0;
      Vtarget = calculate_vtarget(uut.vcvpar);
      while (elapsed_time < timeout) begin: loop_block
         if(elapsed_time == 200) begin
            //en = 1'b1;
          //  $display("EN to 1, at time %0t", $time);
         end
         // necessary if there is no clock
         if(en == 1'b0) begin
            if (is_idle(uut.cc, uut.cv, uut.tc, uut.imeasen, uut.vmeasen, uut.tmeasen)) begin
               if (!Cs || !C7 || !C0 || C7) begin
                  if(prev_state != curr_state) begin
                     $display("Correct state - IDLE at time %0t", $time);
                     // Verify state transition coherence
                     if (!check_prev_state(curr_state, prev_state)) begin
                        $display("ERROR: Invalid state transition from %b to %b at time %0t", prev_state, curr_state, $time);
                        $finish;
                     end
                     $display("IDLE, current is 0A");
                  end                  
                  if(rl_ibat != 0.0) begin
                     $display("ERROR: Current different from 0");
                     $stop;
                  end               
                  prev_state = curr_state;
                  curr_state = 3'b000;
               end else begin
                  $display("Wrong state - should be IDLE, at time %0t", $time);
                  $finish;
               end
            end
            #30000;
            elapsed_time = elapsed_time + 1;
            // Move to the next iteration of the while loop
            disable loop_block;
         end
         @(posedge uut.clk);  // Trigger on the positive edge of the clock
         // Delay between state checks
         if(elapsed_time == 150) begin
            //$display("EN to 0, at time %0t", $time);
            //en = 1'b0;
         end
         #30000;
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
                  $display("IDLE, current is 0A");
               end                  
               if(rl_ibat != 0.0) begin
                  $display("ERROR: Current different from 0");
                  $stop;
               end               
               prev_state = curr_state;
               curr_state = 3'b000;
            end else begin
               $display("Wrong state - should be IDLE, at time %0t", $time);
               $finish;
            end
         end
         // TC MODE state verification
         else if (is_tc_mode(uut.cc, uut.cv, uut.tc, uut.imeasen, uut.vmeasen, uut.tmeasen)) begin
            if (Cs && C0 && C1 && C2 && !C3) begin
               expectedCurrent = calculate_current(uut.itc, rl_C);
               if(!(abs(rl_ibat - expectedCurrent) < rl_tol)) begin
                  $display("ERROR: In TC MODE, current should be %f, is %f", expectedCurrent, rl_ibat);
                  $stop;
               end               
               if(prev_state != curr_state) begin
                  $display("Correct state - TC MODE at time %0t", $time);
                  // Verify state transition coherence
                  if (!check_prev_state(curr_state, prev_state)) begin
                     $display("ERROR: Invalid state transition from %b to %b at time %0t", prev_state, curr_state, $time);
                     $finish;
                  end                     
                  $display("In TC MODE, current within boundaries: %f", rl_ibat);
               end
               if(elapsed_time%20==0) begin
                  $display("In TC MODE, current within boundaries: %f", rl_ibat);
               end
               prev_state = curr_state;
               curr_state = 3'b001;
            end else begin
               $display("Wrong state - should be TC MODE, at time %0t", $time);
               $finish;
            end
         end
         // CC MODE state verification
         else if (is_cc_mode(uut.cc, uut.cv, uut.tc, uut.imeasen, uut.vmeasen, uut.tmeasen)) begin
            if (Cs && C0 && C1 && !C2 && C3 && !C4) begin
               expectedCurrent = calculate_current(uut.icc, rl_C);
               if(!(abs(rl_ibat - expectedCurrent) < rl_tol)) begin
                  $display("ERROR: In CC MODE, current should be %f, is %f", expectedCurrent, rl_ibat);
                  $stop;
               end 
               if(prev_state != curr_state) begin
                  $display("Correct state - CC MODE at time %0t", $time);
                  // Verify state transition coherence
                  if (!check_prev_state(curr_state, prev_state)) begin
                     $display("ERROR: Invalid state transition from %b to %b at time %0t", prev_state, curr_state, $time);
                     $finish;
                  end
                  $display("In CC MODE, current within boundaries: %f", rl_ibat);
               end
               if(elapsed_time%20==0) begin
                  $display("In CC MODE, current within boundaries: %f", rl_ibat);
               end
               prev_state = curr_state;
               curr_state = 3'b010;
            end else begin
               $display("Wrong state - should be CC MODE, at time %0t", $time);
               $finish;
            end
         end
         // CV MODE state verification
         else if (is_cv_mode(uut.cc, uut.cv, uut.tc, uut.imeasen, uut.vmeasen, uut.tmeasen)) begin
            if (Cs && C4 && !C5 && !C6) begin
               expectedCurrent = (Vtarget-rl_vbat)/(0.4/(0.5*rl_C));
               if(!(abs(rl_ibat - expectedCurrent) < rl_tol)) begin
                  $display("ERROR: In CV MODE, current should be %f, is %f", expectedCurrent, rl_ibat);
                  $stop;
               end 
               if(prev_state != curr_state) begin
                  $display("Correct state - CV MODE at time %0t", $time);
                  // Verify state transition coherence
                  if (!check_prev_state(curr_state, prev_state)) begin
                     $display("ERROR: Invalid state transition from %b to %b at time %0t", prev_state, curr_state, $time);
                     $finish;
                  end
                  $display("In CV MODE, current within boundaries: %f", rl_ibat);
               end
               if(elapsed_time%20==0) begin
                  $display("In CV MODE, current within boundaries: %f", rl_ibat);
               end
               prev_state = curr_state;
               curr_state = 3'b011;
            end else begin
               $display("Wrong state - should be CV MODE, at time %0t", $time);
               $finish;
            end
         end
         // END MODE state verification
         else if (is_end_mode(uut.cc, uut.cv, uut.tc, uut.imeasen, uut.vmeasen, uut.tmeasen)) begin
            if (Cs && !C7 && (C6 || C5 || C1)) begin
               if(rl_ibat != 0.0) begin
                  $display("ERROR: Current different from 0");
                  $stop;
               end    
               if(prev_state != curr_state) begin
                  $display("Correct state - END MODE at time %0t", $time);
                  // Verify state transition coherence
                  if (!check_prev_state(curr_state, prev_state)) begin
                     $display("ERROR: Invalid state transition from %b to %b at time %0t", prev_state, curr_state, $time);
                     $finish;
                  end                  
                  $display("END, current is 0A");
               end
               if(elapsed_time%100==0) begin
                  $display("In END, current within boundaries: %f", rl_ibat);
               end
               prev_state = curr_state;
               curr_state = 3'b100;
            end else begin
               $display("Wrong state - should be END MODE, at time %0t", $time);
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
         $display("Test 1 : completed with success, Vbat=%f", $bitstoreal(vbat));
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
      prop = 0.01;
      C0 = 0; C1 = 0; C2 = 0; C3 = 0; C4 = 0; C5 = 0; C6 = 0; C7 = 0; Cs = 0;
      // start the simulation
      $display("===== Starting the testbench and charging the battery =====");

      // Test 1 : battery fully charge

      // After 15 pico seconds, the battery is fully charged. 
      // Drop the battery volatge to 3.55V
      // Initial delay for setup
      #110
      // ==== Test 1 : recharge - wait for battery to fully charge ====       
      verify_state(650);
      $display("==== Test concluded with success ====");
      $finish;
   end
   
  

//-- Signals conversion ---------------------------------------------------
   initial assign rl_vbat = $bitstoreal(vbat);
   initial assign rl_vtbat = $bitstoreal(vtbat);
   initial assign rl_ibat = $bitstoreal(ibat);
   initial assign rl_dvdd = $bitstoreal(dvdd);
   initial assign rl_dgnd = $bitstoreal(dgnd);   
   
   initial assign rl_tempmin = convert_8bit_to_real(uut.tempmin)/(2*255);
   initial assign rl_tempmax = convert_8bit_to_real(uut.tempmax)/(2*255);
   initial assign rl_vcutoff = convert_8bit_to_real(uut.vcutoffpar)/(255/0.5)*10;
   initial assign rl_vpreset = convert_8bit_to_real(uut.vpresetpar)/(255/0.5)*10;
   initial assign rl_iend = convert_8bit_to_real(uut.iendpar)/((2*255)/(0.4/0.5));
   initial assign rl_itc = calculate_current(uut.itc, (0.05 + sel[0]*0.05 + sel[1]*0.1 + sel[2]*0.2 + sel[3]*0.4));
   initial assign rl_icc = calculate_current(uut.icc, (0.05 + sel[0]*0.05 + sel[1]*0.1 + sel[2]*0.2 + sel[3]*0.4));
   initial assign rl_icv = (calculate_vtarget(uut.vcv)-rl_vbat)/(0.4/(0.5*((0.05 + sel[0]*0.05 + sel[1]*0.1 + sel[2]*0.2 + sel[3]*0.4))));



   assign vin = $realtobits(rl_vin);
   assign pgnd = $realtobits(rl_pgnd);
   
endmodule
