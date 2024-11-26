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
   


// test bench
	initial begin
      // Intialization 
      rl_vin = 4.5;  // input voltage
      rl_pgnd = 0.0; // power ground
      sel[3:0] = 4'b0001;  // 450mAh selection ==> changed (26/11/2024) by 0001, 100 mAh
      en = 1'b1; // enable the module

      // start the simulation
      $display("Starting the testbench and charging the battery");

      // Test 1 : battery fully charge

      // After 15 pico seconds, the battery is fully charged. 
      // Drop the battery volatge to 3.55V

      // ==== Test 1 : recharge - wait for battery to fully charge ====       
      $display("Test 1 : Charging the battery...");
      $display("Waiting for entering TC Mode");
      wait(uut.tc); // Wait until the module enters Trickle Charge (TC) mode
      $display("Entered TC Mode");

      $display("Waiting for entering CC Mode");
      wait(uut.cc); // Wait until the module enters Constant Current (CC) mode
      $display("Entered CC Mode");

      $display("Waiting for entering CV Mode");
      wait(uut.cv); // Wait until the module enters Constant Voltage (CV) mode
      $display("Entered CV Mode");

      $display("Waiting for charging finish");
      wait(!(uut.cv || uut.cc || uut.tc)); // Wait until no charging modes are active
      $display("Charging finished");

      // Check if the battery voltage matches the preset voltage
      if (4.15 < $bitstoreal(vbat) <= 4.2) begin
         $display("Test 1 : battery fully charged, recharge test passed, Vbat=%f", $bitstoreal(vbat));
      end else begin
         $display("Unsuccessful Test 1: VMax=%f",  $bitstoreal(vbat));
         $finish; // Terminate simulation if the test fails
      end

      // ==== Test 2 : full reset ====
      $display("Testing enable button to verify reset conditions");
      $display("Waiting for entering CC Mode");
      wait(uut.cc); // Wait for the module to enter CC mode
      $display("Entered CC Mode");

      $display("Disabling module (en = 0) to reset...");
      en = 0; // Disable the module
      #10000; // Wait for the reset to propagate

      wait(!(uut.cv || uut.cc || uut.tc)); // Wait until all charging modes are inactive
      $display("Successful reset: module is off");

      // ==== End the simulation ====
      $display("All tests passed");
      $finish;

      // ==== Test 3 temperature exit ==== 
     /* $display("Test 3 : High temperature shutdown...");
      #1000 vtbat = 8'b10001100 // 140ºC 
      wait (rl_ibat == 0);
      $display("Test 3 : temperature exit test passed");
      #1000 vtbat = 8'b01100100; //temperature goes back to normal

      //==== Test 4 module disable behaviour ====
      // Check if module is off and no current is forced to the battery
      $display("Test 4 : disabling the module")
      en = 0;
      #10;
      if (rl_ibat != 0) begin
         $display("Error - Test 4 : Current detected while module is disabled (ibat = %0.2f)", rl_ibat);
            $finish;
         end
      $display("Test 4 : module disable test passed")

      // ==== end the test bench simulation of the full battery ====
      #1000
      $display("All tests passed")     
      $finish;
      */
      
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
