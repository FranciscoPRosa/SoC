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

   real rl_tol; // tolerance for the computations of the current iforced and voltage 
   real rl_C; // real capacity value
   // expected value of the current for the different modes and the voltage for cv mode
   real expected_tc;
   real expected_cc;
   real expected_cv; 

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

// declaration of the functions we need for the testbench below

// function abs
function real abs(input real value);
    begin
        if (value < 0)
            abs = -value;
        else
            abs = value;
    end
endfunction

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


// test bench
initial
begin
// initialization of the variables
rl_vsensbat = 3.2;
rl_vref = 0.5;
rl_vin = 5.0; // max value from datasheet
rl_ibias1u = 1.0e-6; // typical value from the ds to bias the pmos transistor
rl_tol = 1e-3; // tolerance of 1 mA for the comparison

// current of the differents modes
icc[7:0]=8'b01111111;      // cc mode (iforcedbat = 0.2A)
itc[7:0]=8'b00011001;      // tc mode (iforcedbat 0.04A)
vcv[7:0]=8'b10111100;      // cv mode (3.7V ==> target voltage)

// initialization of the modes to 0
cc = 1'b0; 
tc = 1'b0; 
cv = 1'b0; 

sel = 4'b0111; // for 400mAh
// to compute the value of the capa
rl_C = (0.05 + sel[0]*0.05 + sel[1]*0.1 + sel[2]*0.2 + sel[3]*0.4);


en = 1'b1; // enables the powerblock module

#10 // we wait to let the module working well

// cc mode test 
cc = 1'b1;   
tc = 1'b0; 
cv = 1'b0; 
expected_cc = calculate_current(icc, rl_C); // call to the function defined before

#100 $display("cc=%b, tc=%b, cv=%b, (cv_voltage=%f V cc=%f A tc=%f A) output current is: %f A", cc, tc, cv, expected_cv, expected_cc, expected_tc, rl_iforcedbat);
if (abs(rl_iforcedbat - expected_cc) > rl_tol) begin
        $display("Error: Expected %f A for cc mode, but got %f A",expected_cc, rl_iforcedbat);
        $stop; // stop the simulation
end
#10 $display("CC mode PASSED");

// tc mode test
cc = 1'b0; 
tc = 1'b1;
cv = 1'b0;
expected_tc = calculate_current(itc,rl_C);

#100 $display("cc=%b, tc=%b, cv=%b, (cv_voltage=%f V cc=%f A tc=%f A) output current is: %f A", cc, tc, cv, expected_cv, expected_cc, expected_tc, rl_iforcedbat);
if (abs(rl_iforcedbat - expected_tc) > rl_tol) begin
    $display("Error: Expected %f A for tc mode, but got %f A",expected_tc, rl_iforcedbat);
    $stop; 
end
#10 $display("TC mode PASSED");

// cv mode test
cc = 1'b0;
tc = 1'b0;
cv = 1'b1;
expected_cv = calculate_vtarget(vcv);

#100
#100 $display("cc=%b, tc=%b, cv=%b, (cv_voltage=%f V cc=%f A tc=%f A) output current is: %f A", cc, tc, cv, expected_cv, expected_cc, expected_tc, rl_iforcedbat);
if (abs(rl_vsensbat-expected_cv>rl_tol)) begin
        $display("Error: Expected %f V for cv mode, but got %f V", expected_cv, rl_vsensbat);
        $stop; 
end
#10 $display("CV mode PASSED");

// test enable = 0 ==> no current iforcedbat?
en = 1'b0; // desactivate the module
#10; // waiting
if (rl_iforcedbat != 0) begin
    $display("Error: Expected iforcedbat = 0 A when en = 0, but got %f A", rl_iforcedbat);
    $stop;  
end else begin
    $display("Success: iforcedbat is correctly 0 A when en = 0.");
end


$finish();

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

endmodule