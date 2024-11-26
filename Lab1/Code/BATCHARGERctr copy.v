module BATCHARGERctr (
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

    // State Encoding
    parameter IDLE   = 3'b000,
              START  = 3'b001,
              WAITC  = 3'b010,
              TCMODE = 3'b011,
              CCMODE = 3'b100,
              CVMODE = 3'b101,
              ENDC   = 3'b110;

    reg [2:0] state, nxt_state;

    // Timer for charge time
    reg [7:0] charge_time;

    reg [7:0] counter;
    // Condition Signals
    reg C0, C1, C2, C3, C4, C5, C6, C7;

    // Explicit Initialization
    initial begin
        cc = 0;
        tc = 0;
        cv = 0;
        imonen = 0;
        vmonen = 0;
        tmonen = 0;
        state = IDLE;
        nxt_state = IDLE;
        charge_time = 0;
    end

    // State Transition Logic
    always @(posedge clk or negedge rstz) begin : state_register
        if (!rstz)
            state <= IDLE;
        else
            state <= nxt_state;
    end

    // Condition Evaluation Logic
    always @(*) begin
        C0 = (tempmin <= tbat) && (tbat <= tempmax);
        C1 = (vbat < 8'hd6); // 4.2V threshold
        C2 = (vbat < vcutoff);
        C3 = (vbat > vcutoff);
        C4 = (vbat == vpreset);
        C5 = (charge_time >= tmax*8);
        C6 = (ibat < iend);
        C7 = (vbat <= 8'hd5); // Recharge condition
    end

    // Next State Logic (Transitions remain as they were)
    always @(*) begin : next_state_logic
        nxt_state = IDLE; // Default state
        case (state)
            IDLE: begin
                if (vtok && rstz && en && C7)
                    nxt_state = START;
                else 
                    nxt_state = IDLE;
            end
            START: begin
                if (!(vtok && rstz && en)) 
                    nxt_state = IDLE;
                else if (!C0)  
                    nxt_state = WAITC;
                else if (!C1)  
                    nxt_state = ENDC;
                else if (C2)  
                    nxt_state = TCMODE;
                else    
                    nxt_state = CCMODE;
            end
            WAITC: begin
                if (!(vtok && rstz && en)) 
                    nxt_state = IDLE;
                else
                    nxt_state = START;
            end
            TCMODE: begin
                if (!(vtok && rstz && en)) 
                    nxt_state = IDLE;
                else if (!C0) 
                    nxt_state = START;
                else if (C3) 
                    nxt_state = CCMODE;
                else
                    nxt_state = TCMODE;  
            end
            CCMODE: begin
                if (!(vtok && rstz && en)) 
                    nxt_state = IDLE;
                else if (!C0) 
                    nxt_state = START;
                else if (C4)
                    nxt_state = CVMODE;
                else
                    nxt_state = CCMODE; 
            end
            CVMODE: begin
                if (!(vtok && rstz && en)) 
                    nxt_state = IDLE;
                else if (!C0) 
                    nxt_state = START;
                else if (C5 || C6)
                    nxt_state = ENDC;
                else
                    nxt_state = CVMODE;            
            end
            ENDC: begin
                nxt_state = IDLE;
            end
            default: nxt_state = IDLE;
        endcase
    end

    // Output Logic
    always @(*) begin : output_logic
        // Default values for outputs
        cc = 0;
        tc = 0;
        cv = 0;
        imonen = 0;
        vmonen = 0;
        tmonen = 0;

        case (state)
            IDLE: begin
                vmonen = 1;
                tmonen = 1;
            end
            START: begin
                vmonen = 1;
                tmonen = 1;
            end
            WAITC: ;
            TCMODE: begin
                tc = 1;
                vmonen = 1;
                tmonen = 1;
            end
            CCMODE: begin
                cc = 1;
                vmonen = 1;
                tmonen = 1;
            end
            CVMODE: begin
                cv = 1;
                imonen = 1;
                tmonen = 1;
            end
            ENDC: begin
                vmonen = 1;
            end
        endcase
    end


    // Time Counter
    always @(posedge clk) begin
        if (state == CVMODE) begin
            counter <= counter + 1;
            if (counter == 8'hff) 
                charge_time <= charge_time + 1;
        end else begin
            charge_time <= 0;
            counter <= 0;
        end
    end


endmodule
