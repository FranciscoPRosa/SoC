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


task check_current;
    input integer timeout;       // Maximum time (in time units) for verification
    input integer enCheck;
    reg [31:0] elapsed_time;     // Counter for elapsed time
    real expectedCurrent;
    real rl_C;
    real rl_tol;
    real Vtarget;
    reg [2:0] state, statePrev;
    begin
        rl_tol = 1e-8;
        rl_C = (0.05 + sel[0]*0.05 + sel[1]*0.1 + sel[2]*0.2 + sel[3]*0.4);
        expectedCurrent = 0.0;
        elapsed_time = 0;
        Vtarget = calculate_vtarget(uut.vcvpar);
        $display("Checking current before cycle");
        state = 3'b000;
        statePrev = 3'b000;
        while (elapsed_time < timeout) begin
            @(posedge uut.clk);  // Trigger on the positive edge of the clock
            expectedCurrent = 0.0;
            // Delay between state checks
            #5000;
            state[0] = uut.tc;
            state[1] = uut.cc;
            state[2] = uut.cv;
            elapsed_time = elapsed_time + 1;
            if(elapsed_time == 1500 && enCheck == 1) begin
                en = 1'b0;
            end
            if(uut.tc && !uut.cc && !uut.cv) begin
                expectedCurrent = calculate_current(uut.itc, rl_C);
                if(abs(rl_ibat - expectedCurrent) < rl_tol) begin
                    if(state != statePrev) begin
                        $display("In TC MODE, current within boundaries");
                        statePrev = state;
                    end
                end else begin
                    $display("ERROR: In TC MODE, current should be %f, is %f", calculate_current(uut.itc, rl_C), rl_ibat);
                    $stop;
                end
            end else if(uut.cc && !uut.tc && !uut.cv) begin
                expectedCurrent = calculate_current(uut.icc, rl_C);
                if(abs(rl_ibat - expectedCurrent) < rl_tol) begin
                    if(state != statePrev) begin
                        $display("In CC MODE, current within boundaries");
                        statePrev = state;
                    end
                end else begin
                    $display("ERROR: In CC MODE, current should be %f, is %f", expectedCurrent, rl_ibat);
                    $stop;
                end
            end else if(uut.cv && !uut.tc && !uut.cc) begin
                expectedCurrent = (Vtarget-rl_vbat)/(0.4/(0.5*rl_C));
                if(abs(rl_ibat-expectedCurrent)<rl_tol) begin
                    if(state != statePrev) begin
                        $display("In CV MODE, current within boundaries");
                        statePrev = state;
                    end
                end else begin
                    $display("ERROR: In CV MODE, current should be %f, is %f", expectedCurrent, rl_ibat);
                    $stop;
                end
            end else if(!uut.cc && !uut.tc && !uut.cv) begin                    
                $display("Other modes, current is 0A");

                if(rl_ibat == 0.0 && state != statePrev)begin
                    statePrev = state;
                end
                if(rl_ibat != 0.0) begin
                    $display("ERROR: Current different from 0");
                    $stop;
                end
            end
        end
    end
endtask

initial
  begin
     rl_vin = 4.5;
     rl_pgnd = 0.0;
     sel[3:0] = 4'b1000;  // 450mAh selection     
     en = 1'b1;

    $display("==== Test 1: Verifying correct charging currents ====");
    check_current(5000, 1);

    $display("==== END OF SIMULATION ====");
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