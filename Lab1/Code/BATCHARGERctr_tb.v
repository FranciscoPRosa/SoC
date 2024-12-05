`timescale 1ns / 1ps

module BATCHARGERctr_tb;

    // Declare wires for module outputs
    wire cc;         // constant current mode
    wire tc;         // trickle mode
    wire cv;         // constant voltage mode
    wire imonen;     // current monitor enable
    wire vmonen;     // voltage monitor enable
    wire tmonen;     // temperature monitor enable

    // Declare regs for module inputs
    reg vtok;        // Voltage and temperature valid signal
    reg [7:0] vbat;  // Battery voltage
    reg [7:0] ibat;  // Battery current
    reg [7:0] tbat;  // Battery temperature
    reg [7:0] vcutoff; // Voltage cutoff threshold for trickle mode
    reg [7:0] vpreset; // Voltage for constant voltage mode
    reg [7:0] tempmin; // Minimum temperature
    reg [7:0] tempmax; // Maximum temperature
    reg [7:0] tmax;    // Maximum charge time (in clock cycles)
    reg [7:0] iend;    // Current end criteria (for end of charging)
    reg clk;           // Clock signal
    reg en;            // Enable signal
    reg rstz;          // Reset signal
    wire dvdd;         // Digital supply
    wire dgnd;         // Digital ground

    // Instantiate the BATCHARGERctr module
    BATCHARGERctr uut (
        .cc(cc),
        .tc(tc),
        .cv(cv),
        .imonen(imonen),
        .vmonen(vmonen),
        .tmonen(tmonen),
        .vtok(vtok),
        .vbat(vbat),
        .ibat(ibat),
        .tbat(tbat),
        .vcutoff(vcutoff),
        .vpreset(vpreset),
        .tempmin(tempmin),
        .tempmax(tempmax),
        .tmax(tmax),
        .iend(iend),
        .clk(clk),
        .en(en),
        .rstz(rstz),
        .dvdd(dvdd),
        .dgnd(dgnd)
    );

    // Task for trickle mode testing
    task tcmode;
        begin            
            $display("Testing with Vbat < Vcutoff, checking for tc mode");
            #100;
            if (tc) begin
                $display("Entered tc mode");
            end else begin
                $display("ERROR: Expected tc mode, but condition not met at time %0t", $time);
                $finish;
            end
        end
    endtask

    // Task for constant current mode testing
    task ccmode;
        begin
            // Change voltage to exit tc mode
            vbat = 8'b10100100;  // Vbat = vcutoff + 1 (to exit tc mode)
            #100; // Small delay before checking conditions
            $display("Vbat > Vcutoff, checking for cc mode");
            if (cc) begin
                $display("Entered cc mode");
            end else begin
                $display("ERROR: Expected cc mode, but condition not met at time %0t", $time);
                $finish;
            end
        end
    endtask

    // Task for constant voltage mode testing
    task cvmode;
        begin
            // Change voltage to exit cc mode
            vbat = 8'b11001000;  // Vbat = vpreset + 1 (to exit cc mode)
            #100; // Small delay before checking conditions
            $display("Vbat > Vpreset, checking for cv mode");
            if (cv) begin
                $display("Entered cv mode");
            end else begin
                $display("ERROR: Expected cv mode, but condition not met at time %0t", $time);
                $finish;
            end
            #100; // Additional delay to simulate CV mode
            // Changing the voltage to simulate any possible increases in CV MODE (due to Vpreset!=Vcv)
            vbat = 8'b11010110;  // Example voltage
        end
    endtask

    // Task for exiting CV mode based on current threshold
    task cvmode_current_exit;
        begin
            #100 ibat = 8'b00110010;  // Current < 0.1C to exit cv mode
            #30; // Small delay before checking conditions
            if (cv == 1) begin
                $display("ERROR: Did not exit cv mode by minimum current");
                $finish();
            end else begin
                $display("Exited cv mode by minimum current");
                $display("SUCCESS: Exit by minimum current condition");
            end
        end
    endtask

    // Task for exiting CV mode based on timeout
    task cvmode_timeout;
        begin
            #2000000; // Simulate timeout period
            if (cv == 1) begin
                $display("ERROR: Did not exit cv mode by timeout");
                $finish();
            end else begin
                $display("Exited cv mode by timeout");
                $display("SUCCESS: Exit by timeout condition");
            end
        end
    endtask

    // Task for temperature-based exit testing
    task temperature_exit;
        begin
            #40 tbat = 8'b10001100; // Example temperature above maximum
            #20; // Small delay before checking conditions
            if (tc == 1 || cv == 1 || cc == 1) begin
                $display("ERROR: Temperature condition (C0) not met, wrong state");
                $finish;
            end else begin
                $display("Temperature condition met");
            end

            #100 tbat = 8'b01100100; // Cool down temperature
            $display("Cooled out, temperature down");
            $display("Tmin <= Tbat <= Tmax, checking for charge beginning");

            #100; // Small delay before rechecking states
            if (((vbat < 8'hd5) && (tc || cc)) || ((vbat >= 8'hd5) && (!cc || !cv || !tc))) begin
                $display("Entered tc mode, cc mode for recharge or idle for voltage drop");
                $display("SUCCESS: Temperature control test");
            end else begin
                $display("ERROR: Expected tc or cc mode not entered after temperature control");
                $finish;
            end
        end
    endtask

    // Task for reset behavior testing
    task reset;
        begin            
            $display("===== TESTING RESET EXIT =====");
            initialization;
            en = 1;
            rstz = 1;
            tcmode;
            #50 en = 0; // Reset signal activated
            #20; // Small delay
            if (tc == 1 || cv == 1 || cc == 1) begin
                $display("ERROR: Reset confirmation failed");
                $finish;
            end else begin
                $display("SUCCESS: Reset confirmation passed");
            end
        end
    endtask

    // Task for simulating a complete charge with current exit
    task charge_with_current_exit;
        begin
            $display("===== TESTING CHARGING PROCESS WITH CURRENT EXIT =====");

            initialization;
            rstz = 1;

            tcmode;
            ccmode;
            cvmode;
            cvmode_current_exit;

            rstz = 0;
        end
    endtask

    // Task for simulating a complete charge with current exit
    task recharge_cycle;
        begin
            $display("===== TESTING RECHARGING PROCESS WITH CURRENT EXIT =====");

            initialization;
            rstz = 1;

            tcmode;
            ccmode;
            cvmode;

            // to ensure exit from CV mode
            #10 ibat = 8'b00110010;

            recharge_check;

            rstz = 0;
        end
    endtask

    task recharge_check;
        begin
            $display("Voltage decrease to lead to discharge");
            #10 vbat = 8'hc5;
            #2000;
            $display("Testing if it entered one of the charging modes (either TC or CC)");
            if(((vbat<vcutoff) && tc) || ((vbat>=vcutoff) && cc)) begin
                $display("SUCCESS: Recharge process test passed");
            end else begin
                $display("ERROR: Recharge process test failed");
                $finish;
            end
        end
    endtask


    // Task for simulating a complete charge with timeout exit
    task charge_with_timeout;
        begin
            $display("===== TESTING CHARGING PROCESS WITH TIMEOUT EXIT =====");

            initialization;
            rstz = 0;
            #1000 rstz = 1;

            tcmode;
            ccmode;
            cvmode;
            cvmode_timeout;

            rstz = 0;
        end
    endtask

    // Task for simulating a complete charge with temperature exit
    task charge_with_temperature_exit;
        begin
            $display("===== TESTING CHARGING PROCESS WITH TEMPERATURE EXIT =====");

            initialization;
            rstz = 1;

            tcmode;
            ccmode;
            temperature_exit;

            rstz = 0;
        end
    endtask

    // Task for exiting charge process based on full charge
    task exit_by_full_charge;
        begin
            $display("===== TESTING CHARGING PROCESS WITH FULL CHARGE EXIT =====");
            initialization;
            #100 vbat = 8'b11011111; // Battery fully charged
            rstz = 0;
            #100 rstz = 1;
            #100;
            if (tc == 0 && cc == 0 && cv == 0 && vmonen && !imonen && !tmonen) begin
                $display("Exit by battery fully charged");
                $display("SUCCESS: Exit by full charge");
            end else begin
                $display("ERROR: Did not exit by full charge");
                $finish;
            end

            rstz = 0;
        end
    endtask

    // Task for ending simulation
    task end_simulation;
        begin
            $display("End of simulation");
            $finish();
        end
    endtask

    // Task for initialization
    task initialization;
        begin
            clk = 0;
            vtok = 1;
            en = 1;      // Enable the module
            vbat = 8'b10011001;  // Example voltage (3V)
            ibat = 8'b01100110;  // Example current (0.2C)
            tbat = 8'b01100100;  // Example temperature (25ºC)
            vcutoff = 8'b10100011; // Voltage cutoff for trickle mode (2.9V)
            vpreset = 8'b11000111; // Voltage for constant voltage mode (3.7V)
            tempmin = 8'b00101110; // Minimum temperature (-10ºC)
            tempmax = 8'b10001011; // Maximum temperature (50ºC)
            tmax = 8'b00001000;    // Max charge time (2040 clock periods)
            iend = 8'b00110011;    // End current criteria (0.1C)            
            #10 rstz = 0;    // Active low reset
        end
    endtask

   //Initial block to run tests
    initial begin

        //Run tests

        //Full charge (tc,cc and cv modes) with a current exit to end ( ibat < iend )
        charge_with_current_exit;

        //Full charge (tc,cc and cv modes) with a temperature exit to end ( tbat > tempmax )
        charge_with_temperature_exit;

        //Full charge (tc,cc and cv modes) with a timeout exit to end (t > tmax)
        charge_with_timeout;

        //Exit to end by full charge (vbat > 4.2V)
        exit_by_full_charge;

        //Tests if the voltage decreases below a certain point, the charging process begins again
        recharge_cycle;

        //Reset test : check if all modes are desactivated (tc,cc and cv modes)
        reset;

        $display("===== ALL TESTS COMPLETED =====");

        end_simulation;
    end


    // Clock generation (period of 10 time units)
    always #5 clk = ~clk;

endmodule
