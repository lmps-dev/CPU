`include memory.v
`include module_alu.v

module module_mini_cpu(
	input clk,
	input power,
	input send,
	input [17:0] switches,
	output reg [7:0] data,
	output reg rs,
	output reg rw
	output reg en
);
	reg [2:0] state;

	parameter OFF = 0, IDLE = 1, FETCH = 2, DECODE = 3, EXECUTE = 4, UPDATE_LCD = 5;

    reg  [2:0]  alu_opcode;
    wire [15:0] alu_result;
    
    reg  [3:0]  mem_read_reg1;
    reg  [3:0]  mem_read_reg2;
    reg  [3:0]  mem_write_reg;
    reg  [15:0] mem_write_data;
    reg         mem_write_en;
    wire [15:0] mem_read_data1;
    wire [15:0] mem_read_data2;
    
    memory mem_inst (
        .clk(clk),
        .reset(power),
        .read_reg1(mem_read_reg1),
        .read_reg2(mem_read_reg2),
        .write_reg(mem_write_reg),
        .write_data(mem_write_data),
        .reg_write_en(mem_write_en),
        .read_data1(mem_read_data1),
        .read_data2(mem_read_data2)
    );

    module_alu alu_inst (
        .register_A(mem_read_data1),
        .register_B(mem_read_data2),
        .opcode(alu_opcode),
        .result(alu_result)
    );
	
	initial begin
		data = 8'b00000000;
		rs = 0;
		state = 3'd0;
	end

	always @(negedge clk or posedge power) begin
		if (power) state <= 0;
		else begin
			case (state)
				OFF: 
				IDLE: 
				FETCH: 
				DECODE: 
				EXECUTE: 
				UPDATE_LCD: 

			endcase
		end
	end

	always @(*) begin
		case (state)
			OFF: if (power) state <= IDLE;
			IDLE:
			FETCH:
			DECODE:
			EXECUTE:
			UPDATE_LCD:

		endcase
	end
endmodule