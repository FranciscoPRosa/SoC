`timescale 100ps / 1ps 

module BATCHARGERctr(
            // Module outputs to control POWER block
            output reg   cc, // output to analog block: constant current mode with ich current
            output reg   tc, // output to analog block: trickle mode with 0.1 x ich current
            output reg   cv, // output to analog block: constant voltage mode vpreset voltage

            // Module outputs that indicate which variables should be monitored 
            output reg   imonen, // enables current monitor -> needs to monitor current
            output reg   vmonen, // enables voltage monitor -> needs to monitor voltage
            output reg   tmonen, // enables temperature monitor -> needs to monitor temperature
           
            // Inputs from ADC
            input 	     vtok, // signals that voltage and temperature values are valid 	
            input [7:0]  vbat, // 8 bits data from adc with battery voltage; vbat = adc(vref=0.5V, battery_voltage /10)
            input [7:0]  ibat, // 8 bits data from adc with battery current; ibat = adc(vref=0.5V, battery_current * Rsens); 
                // Rsens = 0.5*vref/(0.5C) ; C=nominal capacity of battery; vadc(Ibat=0.5C) = vref/2
            input [7:0]  tbat, // 8 bits data from adc with battery temperature;  vadc = Temp/330 + 20/165 ; tbat = adc(vref=0.5V, vadc); vadc(-40º)=0V, vadc(125º)=0.5V
            
            // Inputs from Memory (OTP)
            input [7:0]  vcutoff, // constant from OTP: voltage threshold for exiting trickle mode; vcutoff = Vcutof_dec * 255/5 = 51 * Vcutof_dec Ex: 2.9V - 1001_0011
            input [7:0]  vpreset, // constant from OTP: voltage for constant voltage mode; vpreset = Vpreset_dec * 255/5 = 51 * Vpreset_dec Ex: 3.7V - 1011_1100
            input [7:0]  tempmin, // constant from OTP: minimum temperature ; see tbat for scaling
            input [7:0]  tempmax, // constant from OTP: maximum temperature ; see tbat for scaling
            input [7:0]  tmax, // constant from OTP: maximum charge time; unit is 2^time_div_bits clock cycles (time_div_bits=8)
            input [7:0]  iend, // charge current to be used as "end of charging" end criteria Ex: 0.01C=0.01*3.5=0.035 0000_0010
            
            // Control signal inputs
            input 	     clk, // state machine clock
            input        en, // enables the module
            input 	     rstz, // system reset (general reset, sends to IDLE)
            
            // Vdd and Gnd 
            inout        dvdd, // digital supply
            inout        dgnd // digital ground
        );

// State parameters - Changed to Gray Enconding
parameter 
    IDLE    = 3'b000,  // Start state
    CCMODE  = 3'b001,  // Change 1 bit from IDLE (000 -> 001)
    CVMODE  = 3'b011,  // Change 1 bit from CCMODE (001 -> 011)
    TRANSIT = 3'b010,  // Change 1 bit from CVMODE (011 -> 010)
    TCMODE  = 3'b110,  // Change 1 bit from TRANSIT (010 -> 110)
    ENDC    = 3'b100;  // Change 1 bit from TCMODE (110 -> 100)

// Value obtained by analyzing the waveform of the charging process
//reg [7:0] vrecharge = 8'hd5; // D5 in hexadecimal (corresponds to 96.2% of SoC, or approx. 4.163V)

reg [2:0] state;
reg [2:0] nxt_state;

// Time updater - it is reset each time IDLE is reached
// Also it is assumed that the max value is 2^8=255 clock cycles 
reg [7:0] charge_time, counter;

// State updater
always @(posedge clk or negedge en) begin
    if (!en) begin
        state <= nxt_state;
    end else begin
        state <= nxt_state;
    end
end

// Time Counter
always @(posedge clk) begin
    if (state == TRANSIT || state == CVMODE) begin
        counter <= counter + 8'h01;
        if (counter == 8'hff) begin 
            charge_time <= charge_time + 8'h01;
            counter <= 8'h00;
        end
    end else if (state == ENDC) begin
        // No change to counter or charge_time during ENDC state
        counter <= counter;
    end else if (state != CVMODE || state != TRANSIT) begin
        charge_time <= 8'h00;
        counter <= 8'h00;
    end
end

// Simplified Next State Logic
always @(negedge clk or negedge en) begin
    if (!en) begin
        // Synchronous reset to IDLE state
        nxt_state <= IDLE;
    end else if (!rstz || !vtok) begin
        // Disable condition
        nxt_state <= IDLE;
    end else begin
        // State transition logic
        case (state)
            IDLE: begin
                if (!(tempmin <= tbat) || !(tbat <= tempmax))
                    nxt_state <= IDLE;
                else if (vbat >= 8'hd5)
                    nxt_state <= ENDC;
                else if (vbat < vcutoff)
                    nxt_state <= TCMODE;
                else
                    nxt_state <= CCMODE;
            end
            
            TCMODE: begin
                if (!(tempmin <= tbat) || !(tbat <= tempmax))
                    nxt_state <= IDLE;
                else if (vbat >= vcutoff)
                    nxt_state <= CCMODE;
            end
            
            CCMODE: begin
                if (!(tempmin <= tbat) || !(tbat <= tempmax))
                    nxt_state <= IDLE;
                else if (vbat >= vpreset)
                    nxt_state <= TRANSIT;
            end

            TRANSIT: begin
                if (!(tempmin <= tbat) || !(tbat <= tempmax))
                    nxt_state <= IDLE;
                else if(charge_time >= 8'h01)
                    nxt_state <= CVMODE;
            end

            CVMODE: begin
                if (!(tempmin <= tbat) || !(tbat <= tempmax))
                    nxt_state <= IDLE;
                else if ((charge_time >= tmax) || (ibat <= iend))
                    nxt_state <= ENDC;
                else 
                    nxt_state <= CVMODE;
            end
            
            ENDC: begin
                if (vbat <= 8'hd5)
                    nxt_state <= IDLE;
            end

            default: 
                nxt_state <= IDLE;
        endcase
    end
end
// Output Logic
always @(*) begin : output_logic
    // By default, all outputs are zeroed
    cc = 1'b0; 
    tc = 1'b0; 
    cv = 1'b0; 
    imonen = 1'b0; 
    vmonen = 1'b0; 
    tmonen = 1'b0;
    case (state)
        IDLE: begin
            vmonen = 1'b1;
            tmonen = 1'b1;
        end

        TCMODE: begin
            tc = 1'b1;
            vmonen = 1'b1;
            tmonen = 1'b1;
        end

        CCMODE: begin
            cc = 1'b1;
            vmonen = 1'b1;
            tmonen = 1'b1;
        end

        TRANSIT: begin
            cv = 1'b1;
            imonen = 1'b1;
            tmonen = 1'b1;
        end  

        CVMODE: begin
            cv = 1'b1;
            imonen = 1'b1;
            tmonen = 1'b1;
        end
        ENDC: begin
            vmonen = 1'b1;
        end
    endcase

end

endmodule
