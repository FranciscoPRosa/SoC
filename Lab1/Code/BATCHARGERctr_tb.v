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


        //Test tasks

        task tcmode;
            begin
                // Test the behavior based on Vbat and conditions
                $display("Testing with Vbat < Vcutoff, waiting for tc mode");
                wait(tc);  // Wait for tc mode
                $display("Entered tc mode");
            end
        endtask

        task ccmode;
            begin
                // Change voltage to exit tc mode
                #100 vbat = 8'b10100100;  // Vbat = vcutoff + 1 (to exit tc mode)
                $display("Vbat > Vcutoff, waiting for cc mode");
                wait(cc);  // Wait for cc mode
                $display("Entered cc mode");
            end
        endtask
        
        task cvmode;
            begin
                // Change voltage to exit cc mode
                #100 vbat = 8'b11001000;  // Vbat = vpreset + 1 (to exit cc mode)
                $display("Vbat > Vpreset, waiting for cv mode");
                wait(cv);  // Wait for cv mode
                $display("Entered cv mode");
            end
        endtask

        task cvmode_current_exit;
            begin
                // Test for exit from cv mode by minimum current (using iend)
                #100 ibat = 8'b00110010;  // Current < 0.1C to exit cv mode
                #30 if (cv == 1) begin
                    $display("Error: did not exit cv mode by minimum current");
                    $finish();
                end else begin
                    $display("Exited cv mode by minimum current");
                end
            end
        endtask

        task cvmode_timeout;
            begin
                /*
                #200000 if (cv == 1) begin
                    $display("Error: did not exit cv mode by timeout");
                    $finish();
                end else begin
                    $display("Exited cv mode by timeout");
                end*/
                wait(!(cv || cc || tc));
                $display("Exited by timeout");
            end
        endtask

        task charge_with_current_exit;
            begin

                $display("===== TESTING CHARGING PROCESS WITH CURRENT EXIT =====");

                initialization;

                rstz=1;

                tcmode;

                ccmode;

                cvmode;

                cvmode_current_exit;

                rstz=0;
            end
        endtask


        task charge_with_temperature_exit;
            begin
                $display("===== TESTING CHARGING PROCESS WITH TEMPERATURE EXIT =====");

                initialization;

                rstz=1;

                tcmode;

                ccmode;

                cvmode;

                temperature_exit;

                rstz=0;
            end
        endtask

        task charge_with_timeout;
            begin

                $display("===== TESTING CHARGING PROCESS WITH TIMEOUT EXIT =====");

                initialization;
                rstz = 0;
                #1000
                rstz = 1;

                tcmode;

                ccmode;

                cvmode;

                cvmode_timeout;

                rstz=0;
            end
        endtask

        
        task temperature_exit;
            begin

                #40 tbat = 8'b10001100; // Example temperature above maximum
                #20 if(tc == 1 || cv == 1 || cc == 1) begin
                    $display("Error: Temperature condition (C0) not met, wrong state");
                end else begin
                    $display("Temperature condition met");
                end

                #100 tbat = 8'b01100100;
                $display("Cooled out, temperature down");

                $display("Tmin<=Tbat<=Tmax, waiting to check for charge beggining");
                wait(tc || cc);  // Wait for tc mode (indicating recharge mode)
                $display("Entered tc mode or cc mode for recharge");
                $display("Succesful temperature control");

            end
        endtask

        task reset;
        begin
            #50 rstz = 0; // test if reset conditions are met
            #20 if(tc == 1 || cv == 1 || cc == 1) begin
                $display("Error: Reset confirmation failed");
            end else begin
                $display("Reset confirmation passed");
            end    
        end    
        endtask

        task exit_by_full_charge;
            begin
            $display("===== TESTING CHARGING PROCESS WITH FULL CHARGE EXIT =====");

            #100 vbat = 8'b11001111; //Battery fully charged            
            rstz = 0;
            #100
            rstz = 1;
            #100
            if(tc==0 && cc==0 && cv==0) begin
                $display("Exit by battery fully charged");
            end else begin
                $display("Error: did not exit by full charge");
                $finish;
            end

            rstz = 0;
            end
        endtask 



        task end_simulation;
            begin
                $display("End of simulation");
                $finish();
            end
        endtask

        task initialization;
            begin
                clk = 0;
                vtok = 1;
                en = 1;      // Enable the module
                vbat = 8'b10011001;  // Example voltage (3V)
                ibat = 8'b01100110;  // Example current (0.2C)
                tbat = 8'b01100100;  // Example temperature (25ºC)
                vcutoff = 8'b10100011; // Example voltage cutoff for trickle mode (2.9V)
                vpreset = 8'b11000111; // Example voltage for constant voltage mode (3.7V)
                tempmin = 8'b00101110; // Example minimum temperature (-10ºC)
                tempmax = 8'b10001011; // Example maximum temperature (50ºC)
                tmax = 8'b00001000;    // Example max charge time (2040 clock periods)
                iend = 8'b00110011;    // Example end current criteria (0.1C)            
                #1000 rstz = 0;    // Active low reset
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

        //Exit to end by full charge (vbat > vpreset)
        exit_by_full_charge;

        //Reset test : check if all modes are desactivated (tc,cc and cv modes)
        reset;

        $display("===== ALL TESTS COMPLETED =====");

        end_simulation;
    end

    // Clock generation (period of 10 time units)
    always #5 clk = ~clk;

endmodule
