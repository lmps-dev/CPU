module module_mini_cpu(
    input clk,              // Clock 50MHz (PIN_Y2)
    input power,            // Botão Reset/Power (PIN_M23 / KEY0)
    input send,             // Botão Enviar (PIN_R24 / KEY3)
    input [17:0] switches,  // Switches de dados (PIN_Y23...PIN_AB28)
   
    // Saídas para o LCD
    output wire [7:0] data, // LCD_DATA
    output wire rs,         // LCD_RS
    output wire rw,         // LCD_RW
    output wire en,         // LCD_EN
    output wire lcd_on,     // LCD_ON (Ligado ao PIN_L5)
    output wire lcd_blon    // LCD Backlight (Ligado ao PIN_L6)
);
    // --- Parâmetros de Estado ---
    localparam OFF        = 3'd0;
    localparam IDLE       = 3'd1;
    localparam FETCH      = 3'd2;
    localparam DECODE     = 3'd3;
    localparam EXECUTE    = 3'd4;
    localparam UPDATE_LCD = 3'd5;

    // --- Registradores e Controle ---
    reg [2:0] state = OFF;
    reg system_on = 0;
    reg prev_power = 1;
    reg prev_send = 1;

    // --- Backlight sempre ligado ---
    assign lcd_blon = 1'b1;
   
    // REMOVIDO: assign lcd_on = system_on; // LCD deve ser controlado pelo módulo LCD

    // --- Decodificação da Instrução ---
    reg [2:0] opcode;
    reg [3:0] dest_reg;
    reg [3:0] src1_reg;
    reg [3:0] src2_reg;
    reg [15:0] immediate;
    reg use_immediate;
    reg is_load;

    // --- Sinais Internos ---
    // Memória
    wire [15:0] mem_read_data1;
    wire [15:0] mem_read_data2;
    reg [3:0] mem_read_addr1 = 0;
    reg [3:0] mem_read_addr2 = 0;
    reg [3:0] mem_write_addr = 0;
    reg [15:0] mem_write_data = 0;
    reg mem_write_en = 0;
    reg mem_reset = 0;

    // ULA
    wire [15:0] alu_result;
    reg [15:0] alu_in_A = 0;
    reg [15:0] alu_in_B = 0;

    // LCD
    reg lcd_update_en = 0;
    wire [15:0] lcd_reg_value;

    // --- Instanciação dos Módulos ---
   
    // Memória RAM 16x16
    memory mem_inst (
        .clk(clk),
        .reset(mem_reset),
        .read_reg1(mem_read_addr1),
        .read_reg2(mem_read_addr2),
        .write_reg(mem_write_addr),
        .write_data(mem_write_data),
        .reg_write_en(mem_write_en),
        .read_data1(mem_read_data1),
        .read_data2(mem_read_data2)
    );

    // Unidade Lógica Aritmética
    module_alu alu_inst (
        .register_A(alu_in_A),
        .register_B(alu_in_B),
        .opcode(opcode),
        .result(alu_result)
    );

    // Driver do LCD
    lcd lcd_inst (
        .clk_50MHz(clk),
        .reset_n(system_on),    // Usar system_on como reset (ativo baixo quando desligado)
        .system_on(system_on),
        .display_enable(lcd_update_en),
        .opcode_last(opcode),
        .reg_number(src1_reg),  
        .reg_value(lcd_reg_value),
        .LCD_DATA(data),
        .LCD_RS(rs),
        .LCD_EN(en),
        .LCD_RW(rw),
        .LCD_ON(lcd_on) // O módulo LCD controla este sinal
    );

    // Multiplexador LCD
    assign lcd_reg_value = (opcode == 3'b111) ? mem_read_data1 : mem_write_data;

    always @(posedge clk) begin
    // Controle Power
    prev_power <= power;
    prev_send <= send;
    
    if (power && !prev_power) begin
        system_on <= ~system_on;
        if (system_on) begin
            state <= OFF;
            mem_reset <= 1;
        end else begin      
            state <= IDLE;
            mem_reset <= 1;  
        end
    end
    
    if (system_on) begin
        // Reset deve ser ativo por apenas um ciclo
        if (mem_reset) begin
            mem_reset <= 0;
        end
        
        case (state)
            OFF: begin
                // Estado de desligado
                mem_write_en <= 0;
                lcd_update_en <= 0;
            end

            IDLE: begin
                mem_write_en <= 0;
                lcd_update_en <= 0;
                if (send && !prev_send) begin
                    state <= FETCH;
                end
            end

            FETCH: begin
                state <= DECODE;
            end

            DECODE: begin
                // Lógica de switches mantida igual ao original
                opcode <= switches[17:15];
					 if (switches[17:15] == 3'b010 || switches[17:15] == 3'b100 || switches[17:15] == 3'b101) begin // Imediato
                    dest_reg <= switches[14:11];
                    src1_reg <= switches[10:7];
                    immediate <= switches[6] ? -{10'd0, switches[5:0]} : {10'd0, switches[5:0]};
                    use_immediate <= 1;
                    is_load <= 0;
                end
                else if (switches[17:15] == 3'b001 || switches[17:15] == 3'b011) begin // Reg-Reg
                    dest_reg <= switches[14:11];
                    src1_reg <= switches[10:7];
                    src2_reg <= switches[6:3];
                    use_immediate <= 0;
                    is_load <= 0;
                end
                else if (switches[17:15] == 3'b000) begin // LOAD
                    dest_reg <= switches[14:11];
                    immediate <= switches[10] ? -{10'd0, switches[9:4]} : {10'd0, switches[9:4]};
                    use_immediate <= 1;
                    is_load <= 1;
                end
                else begin // Especiais
                    if (switches[17:15] == 3'b111) begin // DISPLAY
                        src1_reg <= switches[14:11];
                    end else begin // CLEAR
                        mem_reset <= 1;
                    end
                    use_immediate <= 0;
                    is_load <= 0;
                end

                // NOVA: Configure os endereços de leitura AQUI (para que estejam prontos no próximo ciclo)
                if (opcode != 3'b000 && opcode != 3'b110) begin  // Só se precisar ler (não para LOAD ou CLEAR)
                    mem_read_addr1 <= src1_reg;
                    if (!use_immediate) begin
                        mem_read_addr2 <= src2_reg;
                    end else begin
                        mem_read_addr2 <= 4'b0;  // Valor dummy, já que não é usado
                    end
                end
                
                state <= EXECUTE;
            end

            EXECUTE: begin
                if (opcode == 3'b110) begin
                    mem_reset <= 0;
                end

                // REMOVIDO: mem_read_addr1 e mem_read_addr2 (agora setados em DECODE)

                alu_in_A <= mem_read_data1;
                alu_in_B <= (use_immediate) ? immediate : mem_read_data2;

                if (opcode != 3'b111 && opcode != 3'b110) begin
                    mem_write_en <= 1;
                    mem_write_addr <= dest_reg;
                    if (is_load) mem_write_data <= immediate;
                    else mem_write_data <= alu_result;
                end                 
                
                state <= UPDATE_LCD;
            end

            UPDATE_LCD: begin
                mem_write_en <= 0;
                if (opcode != 3'b111) src1_reg <= dest_reg;
                lcd_update_en <= 1;
                state <= IDLE;
            end
            
            default: state <= IDLE;
        endcase
    end
end
endmodule