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
            start = 3'b001,
            waitC = 3'b010,
            tcMode = 3'b011,
            ccMode = 3'b100,
            cvMode = 3'b101,
            endC = 3'b110;

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
reg C0, C1, C2, C3, C4, C5, C6, C7;

// Value obtained by analyzing the waveform of the charging process
reg [7:0] vrecharge = 8'b10110101; // B5 in hexadecimal (corresponds to 20% of SoC, or approx. 3.55V)

reg [2:0] state, nxt_state;

// Time updater - it is reset each time start is reached
// Also it is assumed that the max value is 2^8=255 clock cycles 
reg [7:0] charge_time;

// State updater
always @(posedge clk or posedge rstz) begin
    if (!rstz)
        state <= idle;
    else
        state <= nxt_state;
end

// Time Counter - we assume the time starts beign counted as soon as it 
always @(posedge clk or posedge rstz) begin
    if (state == cvMode)
        charge_time <= charge_time + 1;
    else
        charge_time <= 0;

end

// Condition updater
always @(posedge clk or posedge rstz or vmonen or tmonen or imonen or vbat or ibat or tbat) begin
    if (!rstz) begin
        C0 <= 0; C1 <= 0; C2 <= 0; C3 <= 0;
        C4 <= 0; C5 <= 0; C6 <= 0; C7 <= 0;
    end else begin
        C0 <= ((tempmin <= tbat) && (tbat <= tempmax) && tmonen);
        C1 <= ((vbat < 8'b11001100) && vmonen); // 4.2 in the scale
        C2 <= ((vbat < vcutoff) && vmonen);
        C3 <= ((vbat > vcutoff) && vmonen);
        C4 <= ((vbat >= vpreset) && vmonen);
        C5 <= (charge_time >= tmax);
        C6 <= ((ibat < iend) && imonen);
        C7 <= ((vbat <= vrecharge) && vmonen); // Recharge condition (simplified for now)
    end
end


// Next State Logic
/*
    For each state, is the enable is disabled, the reset is activated, or if the measures of the ADC are signaled as wrong
    it goes to IDLE until the circuit is ready again
*/
always @(state or C0 or C1 or C2 or C3 or C4 or C5 or C6 or C7 or en or rstz or vtok) begin
    case (state)
        idle: begin
            if (vtok && rstz && en && C7)
                nxt_state = start;
            else 
                nxt_state = idle;
        end
        start: begin
            if (!(vtok && rstz && en)) 
                nxt_state = idle;
            else if (!C0)  
                nxt_state = waitC;
            else if (!C1)  
                nxt_state = endC;
            else if (C2)  
                nxt_state = tcMode;
            else    
                nxt_state = ccMode;
        end
        waitC: begin
            if (!(vtok && rstz && en)) 
                nxt_state = idle;
            else
                nxt_state = start;
        end
        tcMode: begin
            if (!(vtok && rstz && en)) 
                nxt_state = idle;
            else if (!C0) 
                nxt_state = start;
            else if (C3) 
                nxt_state = ccMode;
            else
                nxt_state = tcMode;  
        end
        ccMode: begin
            if (!(vtok && rstz && en)) 
                nxt_state = idle;
            else if (!C0) 
                nxt_state = start;
            else if (C4)
                nxt_state = cvMode;
            else
                nxt_state = ccMode; 
        end
        cvMode: begin
            if (!(vtok && rstz && en)) 
                nxt_state = idle;
            else if (!C0) 
                nxt_state = start;
            else if (C5 || C6)
                nxt_state = endC;
            else
                nxt_state = cvMode;            
        end
        endC: begin
            nxt_state = idle;
        end
        default: nxt_state = idle;
    endcase
end


always @(state) begin : output_logic
    // by default, all output are zeroed
    cc = 0; 
    tc = 0; 
    cv = 0; 
    imonen = 0; 
    vmonen = 0; 
    tmonen = 0;
    case (state)
        idle: ;
        start: begin
            vmonen = 1;
            tmonen = 1;
        end
        waitC: ;
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
    endcase
end

endmodule