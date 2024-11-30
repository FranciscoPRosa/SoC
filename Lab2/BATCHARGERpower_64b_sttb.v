`timescale 1ns / 1ps

module BATCHARGERpower_64b_sttb;
   wire [63:0] iforcedbat; // output current to battery
   wire [63:0] vbatcurr;    // ibat value scaled 1000:1 * (R=Vref/C)
   wire [63:0] vsensbat; // voltage sensed (obtained at the battery as "voltage from iforcedbat integration" + ESR * iforcedbat )		     
   wire [63:0] vref; // voltage reference (vref = 0.5V)
   wire [63:0] vin; // input voltage; must be at least 200mV higher than vsensbat to allow iforcedbat > 0
   wire [63:0] ibias1u; // reference current	(ibias1u = 1uA)
   reg [7:0]   icc; // constant current mode output current value icc=8'b1111_1111 -> iforced = C; ex: icc=8'b01111111 & C=0.4A -> iforced = 0.2A (0.5C)
   reg [7:0]   itc; //  trickle current mode output current value itc=8'b1111_1111 -> iforced = C; ex: itc=8'b00011001 & C=0.4A -> iforced = 0.04A (0.1C)
   reg [7:0]   vcv; // constant voltage target value vcv = Vtarget*255/5 = 51*Vtarget
   reg 	       cc; // enables constant current charging mode
   reg 	       tc; // enables trickle  current charging mode 
   reg 	       cv; // enables constant voltage charging mode
   reg 	       en; // enables the module
   reg [3:0]   sel;
   wire [63:0] dvdd;  // digital supply
   wire [63:0] dgnd;  // digital ground
   wire [63:0] avdd;  // analog supply
   wire [63:0] agnd;  // analog ground
   wire [63:0] pgnd;  // power ground
   real        rl_avdd;
   real        rl_dvdd;
   real        rl_agnd;
   real        rl_dgnd;
   real        rl_pgnd;     

			    
 
   real rl_vbatcurr;        // vbatcurr real value 
   real rl_vref;         // converted value of vref to real
   real rl_iforcedbat;         // iforcedbat real value
   real rl_vsensbat;         // converted value of vsensbat to real 
   real rl_vin;         // converted value of vin to real 
   real rl_ibias1u;         // converted value of ibias1u to real 

   real rl_icc;
   real rl_itc;
   real rl_vvc;

// create the instance
BATCHARGERpower_64b uut (
			 .iforcedbat(iforcedbat),
			 .vbatcurr(vbatcurr),
			 .vsensbat(vsensbat),
			 .vref(vref),
			 .vin(vin),
			 .ibias1u(ibias1u),
			 .icc(icc),
			 .itc(itc),
			 .vcv(vcv),
			 .cc(cc),
			 .tc(tc),
			 .cv(cv),
			 .en(en),
			 .sel(sel),
                         .avdd(avdd),
                         .dvdd(dvdd),
                         .dgnd(dgnd),
                         .agnd(agnd),
                         .pgnd(pgnd)			 
); 
// declaration of all the functions and task we need for the test bench defined below

// funtion (output used in the initial begin so not a task!) to compute the real value of the capacity (given as an input in digital binary sel[3..0], 4bits) 
// for the computation of the current iforcedbat
// 50 mAh for the offset + the weights given in the datasheet of the powerblock
// C has to be between 50 mAh adnd 800 mAh
function real calculate_capacity;
    // input : sel[3..0] defined previously
    // out : calculate_capacity
    begin
        calculate_capacity = 50 + (sel[3] * 400 + sel[2] * 200 + sel[1] * 100 + sel[0] * 50);
    end
endfunction


// functions to compute the current iforcedbat for the tc, cc or cv mode
// compute the tc current
function real calculate_trickle_current;
    // input : itc defined before
    // and C from the function associated
    // output : calculate_trickle_current
    real C;
    begin
        C = calculate_capacity();
        calculate_trickle_current = C * (0.502 * itc[7] + 0.251 * itc[6] + 0.1255 * itc[5] +
                                            0.0627 * itc[4] + 0.0314 * itc[3] + 0.0157 * itc[2] +
                                            0.0078 * itc[1] + 0.0039 * itc[0]);
    end
endfunction

// compute the cc current
function real calculate_constant_current;
    // inputs : icc defined before a
    // and C from the function associated
    // output : calculate_constant_current
    real C;
    begin
        C = calculate_capacity();
        calculate_constant_current = C * (0.502 * icc[7] + 0.251 * icc[6] + 0.1255 * icc[5] +
                                            0.0627 * icc[4] + 0.0314 * icc[3] + 0.0157 * icc[2] +
                                            0.0078 * icc[1] + 0.0039 * icc[0]);
    end
endfunction

// compute the cv current
// iforcedbat is limited to iforcedbat=(vtarget-vsensedbat)/R
// with: vtarget defined by vcv[7:0] and R defined with C : R=0.4/(0.5*C)
// so first, we compute vtarget, then C (from the funciton before), R 
// and finally we calculate the output iforcedbat
function real calculate_voltage_limited_current;
    // in : vcv[7..0] and also rl_vsensbat defined before
    // out : calculate_voltage_limited_current
    real Vtarget, C, R;
    begin
        Vtarget = 5 * (0.502 * vcv[7] + 0.251 * vcv[6] + 0.1255 * vcv[5] +
                        0.0627 * vcv[4] + 0.0314 * vcv[3] + 0.0157 * vcv[2] +
                        0.0078 * vcv[1] + 0.0039 * vcv[0]);
        C = calculate_capacity();
        R = 0.4 / (0.5 * C);
        calculate_voltage_limited_current = (Vtarget - rl_vsensbat) / R;
    end
endfunction

// task to validate the current iforcedbat obtained
// validation modes to enter in tc, cc or cv mode
// with expected values in the input
// input [8*20:1] mode_name : array of bits to put string characters, e.g. "TC Mode"
// input real expected_current : contains the theoretical current value 
// (dynamically calculated for the mode in question that was put in before with "mode_name").
task validate_mode(input [8*20:1] mode_name, input real expected_current);
    begin
        if ($bitstoreal(iforcedbat) !== expected_current) begin
            $display("Error in %s: Expected Current = %f A, Measured = %f A", mode_name, expected_current, $bitstoreal(iforcedbat));
            $finish;
        end else begin
            $display("%s passed: Current = %f A", mode_name, $bitstoreal(iforcedbat));
        end
    end
endtask

// ===== test bench
initial
begin
// inputs to be initialized
sel = 4'b0111; // for example we take C=400mAh
rl_vsensbat = 3.2;   
rl_vref = 0.5; // typical value from the datasheet 
rl_vin = 5.0;   // maximum value from the ds
rl_ibias1u = 1.0e-6;  // typical value from the ds (5.) for the pmos transistor
icc = 8'b0;
itc = 8'b0;
vcv = 8'b0;
cc = 0;
tc = 0;
cv = 0;
en = 1; // we first enable the power block

// message to notify test start
$display("Starting the test bench of the power block");

// test1: trickle current mode transition TC
$display("Testing trickle current mode");
tc = 1; // with tc=1, the battery has to go in tc mode
cc = 0; 
cv = 0;
itc = 8'b00011001; // example : 0.04A for 0.4C
#10 validate_mode("TC Mode", calculate_trickle_current());

// test2: constant current mode CC
$display("Testing trickle current mode");
tc = 0; 
cc = 1; // with cc=1, the battery has to go in cc mode
cv = 0;
icc = 8'b01111111; // 0.2A for 0.4C
// we wait a little to check the current
#10 validate_mode("CC Mode", calculate_constant_current());

// test3: constant voltage mode CV
$display("Testing Constant Voltage Mode...");
tc = 0; cc = 0; cv = 1;
vcv = 8'b10111100; // vcv = 188 in decimal ==>Vtarget = 3.69V
rl_vsensbat = 3.2; // example sensed voltage, the same value as the original tb of the professor
#10 validate_mode("CV Mode", calculate_voltage_limited_current());

// end of the test bench
$display("All tests passed successfully")
$finish;
end

//-- Signal conversion ------------------

//   initial assign rl_var1    = $bitstoreal (var1_64b);
//   assign var2_64b           = $realtobits (rl_var2);
   
   assign vref = $realtobits (rl_vref);
   assign vsensbat = $realtobits (rl_vsensbat);
   assign vin = $realtobits (rl_vin);
   assign ibias1u = $realtobits (rl_ibias1u);
   assign pgnd = $realtobits (rl_pgnd);
   assign avdd               = $realtobits (rl_avdd);
   assign dvdd               = $realtobits (rl_dvdd);
   assign agnd               = $realtobits (rl_agnd);
   assign dgnd               = $realtobits (rl_dgnd);  
   
   initial assign rl_iforcedbat = $bitstoreal (iforcedbat);
   initial assign rl_vbatcurr = $bitstoreal (vbatcurr);   
   
    
endmodule // BATCHARGERpower_64b_tb