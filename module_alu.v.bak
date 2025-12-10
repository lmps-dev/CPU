module module_alu (
    input [15:0] register_A,
    input [15:0] register_B,
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
            // Converter para signed corretamente
            // Em Verilog, quando atribuímos um valor unsigned para signed,
            // o Verilog interpreta como complemento de 2 automaticamente
            operand_A = $signed(register_A);
            operand_B = $signed(register_B);

            case (opcode)
                ADD:  result_c2 = operand_A + operand_B;
                ADDI: result_c2 = operand_A + operand_B;
                SUB:  result_c2 = operand_A - operand_B;
                SUBI: result_c2 = operand_A - operand_B;
                MUL:  begin
                    // Para multiplicação, precisamos de mais bits
                    result_c2 = operand_A * operand_B;
                end
            endcase
       
            // Truncar para 16 bits com saturação (opcional)
            if (result_c2 > 32767) begin
                result = 16'h7FFF;  // Saturação positiva
            end else if (result_c2 < -32768) begin
                result = 16'h8000;  // Saturação negativa
            end else begin
                result = result_c2[15:0];  // Apenas pega os 16 bits menos significativos
            end
        end
    end
endmodule
