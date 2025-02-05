module BATCHARGERctr(
            // Module outputs to control POWER block
            output reg   cc, // output to analog block: constant current mode with ich current
            output reg   tc, // output to analog block: trickle mode with 0.1 x ich current
            output reg   cv, // output to analog block: constant voltage mode vpreset voltage

            // Module outputs that indicate which variables should be monitored 
            output reg   imonen, //enables current monitor -> needs to monitor current
            output reg   vmonen, //enables voltage monitor -> needs to monitor voltage
            output reg   tmonen, //enables temperature monitor -> needs to monitor temperature
           
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

// State parameters
parameter   idle = 3'b000,
            tcMode = 3'b001,
            ccMode = 3'b010,
            cvMode = 3'b011,
            endC = 3'b100;

// Each of these registers will always check their respective conditions in real time, to allow for the state change
/*
    - C0: tempmin≤tbat≤tempmax
    - C1: vbat<4.2V
    - C2: vbat<vcutoff
    - C3: vbat>vcutoff
    - C4: vbat>=vpreset
    - C5: tmax≤time
    - C6: ibat<iend
    - C7: Recharge condition (if the battery voltage drops below 20% of the SoC, the charger should start charging the battery again)   
*/
reg C0, C1, C2, C3, C4, C5, C6, C7, Cs;

// Value obtained by analyzing the waveform of the charging process
reg [7:0] vrecharge = 8'hd5; // D5 in hexadecimal (corresponds to 96.2% of SoC, or approx. 4.163V)

reg [2:0] state, nxt_state;

// Time updater - it is reset each time idle is reached
// Also it is assumed that the max value is 2^8=255 clock cycles 
reg [7:0] charge_time, counter;


// Change to become sensible to changes in reset to update the state

// State updater
always @(posedge clk or negedge Cs) begin
    if (!Cs)
        state <= idle;
    else
        state <= nxt_state;
end

// Time Counter
always @(posedge clk) begin
    if (state == cvMode) begin
        counter <= counter + 1;
        if (counter == 8'hff) begin 
            charge_time <= charge_time + 1;
            counter <= 0;
        end
    end else if (state == endC) begin
        // No change to counter or charge_time during endC state
        counter <= counter;
    end else begin
        // Reset counter and charge_time if not in cvMode or endC
        charge_time <= 0;
        counter <= 0;
    end
end


// Condition Updater
always @(posedge clk or negedge rstz) begin
    if (!rstz) begin
        C0 <= 1'b0;
        C1 <= 1'b0;
        C2 <= 1'b0;
        C3 <= 1'b0;
        C4 <= 1'b0;
        C5 <= 1'b0;
        C6 <= 1'b0;
        C7 <= 1'b0;
    end else begin
        C0 <= ((tempmin <= tbat) && (tbat <= tempmax));
        C1 <= (vbat < 8'b11010110); // 4.2 in the scale
        C2 <= (vbat < vcutoff);
        C3 <= (vbat >= vcutoff);
        C4 <= (vbat >= vpreset);
        C5 <= (charge_time >= tmax);
        C6 <= (ibat < iend);
        C7 <= (vbat <= vrecharge); // Recharge condition
    end
end

// Asynchronous `Cs`
always @(*) begin
    Cs = (en && vtok && rstz);
end



// Next State Logic
/*
    For each state, is the enable is disabled, the reset is activated, or if the measures of the ADC are signaled as wrong
    it goes to IDLE until the circuit is ready again
*/
always @(*) begin : next_state_logic
    case (state)
        idle: begin
            if (!Cs) 
                nxt_state = idle;
            else if (!C0)  
                nxt_state = idle;
            else if (!C1)  
                nxt_state = endC;
            else if (C2 && C7)  
                nxt_state = tcMode;
            else if (!C2 && C7)
                nxt_state = ccMode;
            else
                nxt_state = idle;
        end
        tcMode: begin
            if (!Cs) 
                nxt_state = idle;
            else if (!C0) 
                nxt_state = idle;
            else if (C3) 
                nxt_state = ccMode;
            else
                nxt_state = tcMode;  
        end
        ccMode: begin
            if (!Cs) 
                nxt_state = idle;
            else if (!C0) 
                nxt_state = idle;
            else if (C4)
                nxt_state = cvMode;
            else
                nxt_state = ccMode; 
        end
        cvMode: begin
            if (!Cs) 
                nxt_state = idle;
            else if (!C0) 
                nxt_state = idle;
            else if (C5 || C6)
                nxt_state = endC;
            else
                nxt_state = cvMode;            
        end
        endC: begin
            if(C7 || !Cs)
                nxt_state = idle;
            else   
                nxt_state = endC;
        end
        default: nxt_state = idle;
    endcase
end


always @(*) begin : output_logic
    // by default, all output are zeroed
    cc = 0; 
    tc = 0; 
    cv = 0; 
    imonen = 0; 
    vmonen = 0; 
    tmonen = 0;
    case (state)
        idle: begin
            vmonen = 1;
            tmonen = 1;
        end
        tcMode: begin
            tc = 1;
            vmonen = 1;
            tmonen = 1;
        end
        ccMode: begin
            cc = 1;
            vmonen = 1;
            tmonen = 1;
        end
        cvMode: begin
            cv = 1;
            imonen = 1;
            tmonen = 1;
        end
        endC: begin
            vmonen = 1;
        end
        default: begin
            cc = 0;
            tc = 0;
            cv = 0;
            imonen = 0;
            vmonen = 0;
            tmonen = 0;
        end
    endcase
end

endmodule