module module_alu (
    input [15:0] register_A,
    input [15:0] register_B,
	 input sendButton,
    input [2:0] opcode,
    output reg [15:0] result
);

    reg signed [15:0] operand_A;
    reg signed [15:0] operand_B;
    reg signed [31:0] result_c2;  // Aumentado para 32 bits para evitar overflow

    parameter LOAD = 0, ADD = 1, ADDI = 2, SUB = 3, SUBI = 4, MUL = 5, CLEAR = 6, DISPLAY = 7;

    always @(*) begin
        result = 16'd0;
        operand_A = 16'd0;
        operand_B = 16'd0;
        result_c2 = 32'd0;

        if (opcode != LOAD && opcode != CLEAR && opcode != DISPLAY) begin
            operand_A = $signed(register_A);
            operand_B = $signed(register_B);

            case (opcode)
					 3'b001: result_c2 = operand_A + operand_B;  // ADD (reg-reg)
					 3'b010: result_c2 = operand_A + operand_B;  // ADDI
					 3'b011: result_c2 = operand_A - operand_B;  // SUB (reg-reg)
					 3'b100: result_c2 = operand_A - operand_B;  // SUBI
					 3'b101: result_c2 = operand_A * operand_B;  // MUL/MULI
					 default: result_c2 = result_c2;
				endcase
       
            if (result_c2 > 32767) begin
                result = 16'h7FFF;
            end else if (result_c2 < -32768) begin
                result = 16'h8000;
            end else begin
                result = result_c2[15:0];  // Apenas pega os 16 bits menos significativos
            end
        end
    end
endmodule
