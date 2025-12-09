module module_alu ( 
	input [15:0] register_A,
	input [15:0] register_B,
	input [2:0] opcode,
	output reg [15:0] result
);

    reg signed [15:0] operand_A;
    reg signed [15:0] operand_B;
    reg signed [15:0] result_c2;

	parameter LOAD = 0, ADD = 1, ADDI = 2, SUB = 3, SUBI = 4, MUL = 5, CLEAR = 6, DISPLAY = 7; // the last 2 operations and the first one should not be treated is this module
	
	always @(*) begin
        result = 16'd0;
        operand_A = 16'd0;
        operand_B = 16'd0;
        result_c2 = 16'd0;

        if (opcode != LOAD && opcode != CLEAR && opcode != DISPLAY) begin
            operand_A = (register_A[15]) ? -{1'b0, register_A[14:0]} : {1'b0, register_A[14:0]};
            operand_B = (register_B[15]) ? -{1'b0, register_B[14:0]} : {1'b0, register_B[14:0]};

            case (opcode)
                ADD:  result_c2 = operand_A + operand_B;
                    
                ADDI: result_c2 = operand_A + operand_B;
                
                SUB:  result_c2 = operand_A - operand_B;
                
                SUBI: result_c2 = operand_A - operand_B;
                
                MUL:  result_c2 = operand_A * operand_B;
            endcase
        
            result = (result_c2[15]) ? {1'b1, -result_c2[14:0]} : {1'b0, result_c2[14:0]}; 
        
        end
    end
endmodule