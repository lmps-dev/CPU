`timescale 1ns / 1ps
module module_lcd (
    input clk_50MHz,          // Clock da placa
    input reset_n,            // Reset ativo baixo (global)
    input system_on,          // 1 = sistema ligado, 0 = desligado (controlado pela CPU)
    input display_enable,     // Pulso de 1 ciclo quando atualizar LCD (após instrução)
    input [2:0] opcode_last,  // Opcode 3 bits da última instrução
    input [3:0] reg_number,   // Número do reg (dest ou src para DISPLAY, 0-15)
    input [15:0] reg_value,   // Valor signed 16 bits
    // Pinos LCD DE2-115
    output reg [7:0] LCD_DATA,
    output reg LCD_RS,        // 0=comando, 1=dado
    output reg LCD_EN,
    output LCD_RW = 1'b0,     // Sempre escrita
    output LCD_ON = 1'b1      // Backlight ligado
);

// Parâmetros de delay (50MHz)
localparam 
    DELAY_15MS = 750_000,    // >15ms
    DELAY_4_1MS = 205_000,   // >4.1ms
    DELAY_100US = 5_000,     // >100us
    DELAY_40US = 2_000,      // >40us para comandos
    DELAY_2MS = 100_000,     // >2ms para clear
    DELAY_1US = 50;          // Para pulse EN high

// Estados da FSM
localparam [5:0]
    OFF = 0,                 // Sistema desligado, LCD off
    POWER_ON = 1,
    WAIT_15MS = 2,
    FUNC_SET1 = 3,           // 0x30
    PULSE_EN = 4,            // Estado reutilizável para pulse EN
    WAIT_4_1MS = 5,
    FUNC_SET2 = 6,           // 0x30 again
    WAIT_100US1 = 7,
    FUNC_SET3 = 8,           // 0x30 again
    WAIT_100US2 = 9,
    FUNC_SET_FINAL = 10,     // 0x38: 8-bit, 2 lines, 5x8 font
    WAIT_40US1 = 11,
    DISP_OFF = 12,           // 0x08
    WAIT_40US2 = 13,
    DISP_CLEAR = 14,         // 0x01
    WAIT_2MS = 15,
    ENTRY_MODE = 16,         // 0x06: increment, no shift
    WAIT_40US3 = 17,
    DISP_ON = 18,            // 0x0C: on, no cursor/blink
    WAIT_40US4 = 19,
    IDLE = 20,               // Pronto para updates
    SET_ADDR = 21,           // Set DDRAM 0x80 (linha 1 start)
    WAIT_40US5 = 22,
    WRITE_CHAR = 23,         // Escreve um char
    WAIT_40US6 = 24,
    CLEAR_SCREEN = 25;       // Para CLEAR instr

reg [5:0] state = OFF;
reg [19:0] delay_cnt = 0;
reg [4:0] char_index = 0;    // 0-15 chars
reg [7:0] line1 [0:15];      // Buffer linha 1 (ASCII)
reg write_pending = 0;
reg clear_pending = 0;

// Conversão signed para abs + sinal
wire signed [15:0] signed_value = reg_value;
reg [15:0] abs_value;
reg negative;
always @(*) begin
    negative = (signed_value < 0);
    abs_value = negative ? -signed_value : signed_value;
end

// Binário 16-bit unsigned para 5 dígitos BCD (double dabble)
reg [19:0] bcd;  // 5 nibbles (20 bits)
integer i;
always @(*) begin
    bcd = 0;
    for (i = 15; i >= 0; i = i - 1) begin
        if (bcd[3:0] >= 5) bcd[3:0] = bcd[3:0] + 3;
        if (bcd[7:4] >= 5) bcd[7:4] = bcd[7:4] + 3;
        if (bcd[11:8] >= 5) bcd[11:8] = bcd[11:8] + 3;
        if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 3;
        if (bcd[19:16] >= 5) bcd[19:16] = bcd[19:16] + 3;
        bcd = {bcd[18:0], abs_value[i]};
    end
end

// Monta line1 baseado em opcode (formato exato do PDF)
always @(posedge clk_50MHz) begin
    if (display_enable && state == IDLE) begin
        case (opcode_last)
            3'b000: begin  // LOAD
                line1[0] = "L"; line1[1] = "O"; line1[2] = "A"; line1[3] = "D";
            end
            3'b001: begin  // ADD
                line1[0] = "A"; line1[1] = "D"; line1[2] = "D"; line1[3] = " ";
            end
            3'b010: begin  // ADDI
                line1[0] = "A"; line1[1] = "D"; line1[2] = "D"; line1[3] = "I";
            end
            3'b011: begin  // SUB
                line1[0] = "S"; line1[1] = "U"; line1[2] = "B"; line1[3] = " ";
            end
            3'b100: begin  // SUBI
                line1[0] = "S"; line1[1] = "U"; line1[2] = "B"; line1[3] = "I";
            end
            3'b101: begin  // MUL
                line1[0] = "M"; line1[1] = "U"; line1[2] = "L"; line1[3] = " ";
            end
            3'b110: begin  // CLEAR
                line1[0] = "C"; line1[1] = "L"; line1[2] = "E"; line1[3] = "A";
                line1[4] = "R"; line1[5] = " "; line1[6] = " "; line1[7] = " ";
                line1[8] = " "; line1[9] = " "; line1[10]= " "; line1[11]= " ";
                line1[12]= " "; line1[13]= " "; line1[14]= " "; line1[15]= " ";
                clear_pending = 1;  // Limpa tela após escrever
                write_pending = 1;
            end
            3'b111: begin  // DISPLAY
                line1[0] = "D"; line1[1] = "P"; line1[2] = "L"; line1[3] = " ";
            end
        endcase
        
        if (opcode_last != 3'b110) begin  // Não CLEAR
            line1[4] = " ";
            // Reg number em binário 4 bits (ASCII '0'/'1')
            line1[5] = reg_number[3] ? 8'h31 : 8'h30;  // '1' or '0'
            line1[6] = reg_number[2] ? 8'h31 : 8'h30;
            line1[7] = reg_number[1] ? 8'h31 : 8'h30;
            line1[8] = reg_number[0] ? 8'h31 : 8'h30;
            line1[9] = " ";
            line1[10] = negative ? "-" : "+";
            // 5 dígitos BCD com '0' base
            line1[11] = 8'h30 + bcd[19:16];
            line1[12] = 8'h30 + bcd[15:12];
            line1[13] = 8'h30 + bcd[11:8];
            line1[14] = 8'h30 + bcd[7:4];
            line1[15] = 8'h30 + bcd[3:0];
            write_pending = 1;
            clear_pending = 0;
        end
        char_index <= 0;
    end
end

// FSM principal
always @(posedge clk_50MHz or negedge reset_n) begin
    if (!reset_n) begin
        state <= OFF;
        delay_cnt <= 0;
        LCD_EN <= 0;
        LCD_RS <= 0;
        LCD_DATA <= 8'h00;
        char_index <= 0;
        write_pending <= 0;
        clear_pending <= 0;
    end else begin
        if (!system_on) begin
            state <= OFF;
        end
        case (state)
            OFF: begin
                LCD_RS <= 0;
                LCD_DATA <= 8'h08;  // Display off
                LCD_EN <= 1;
                state <= PULSE_EN;
            end
            POWER_ON: begin
                delay_cnt <= delay_cnt + 1;
                if (delay_cnt == DELAY_15MS) begin
                    delay_cnt <= 0;
                    state <= FUNC_SET1;
                end
            end
            FUNC_SET1: begin
                LCD_RS <= 0;
                LCD_DATA <= 8'h30;
                LCD_EN <= 1;
                state <= PULSE_EN;
            end
            WAIT_4_1MS: begin
                delay_cnt <= delay_cnt + 1;
                if (delay_cnt == DELAY_4_1MS) begin
                    delay_cnt <= 0;
                    state <= FUNC_SET2;
                end
            end
            FUNC_SET2: begin
                LCD_RS <= 0;
                LCD_DATA <= 8'h30;
                LCD_EN <= 1;
                state <= PULSE_EN;
            end
            WAIT_100US1: begin
                delay_cnt <= delay_cnt + 1;
                if (delay_cnt == DELAY_100US) begin
                    delay_cnt <= 0;
                    state <= FUNC_SET3;
                end
            end
            FUNC_SET3: begin
                LCD_RS <= 0;
                LCD_DATA <= 8'h30;
                LCD_EN <= 1;
                state <= PULSE_EN;
            end
            WAIT_100US2: begin
                delay_cnt <= delay_cnt + 1;
                if (delay_cnt == DELAY_100US) begin
                    delay_cnt <= 0;
                    state <= FUNC_SET_FINAL;
                end
            end
            FUNC_SET_FINAL: begin
                LCD_RS <= 0;
                LCD_DATA <= 8'h38;  // 8-bit, 2 lines, 5x8
                LCD_EN <= 1;
                state <= PULSE_EN;
            end
            WAIT_40US1: begin
                delay_cnt <= delay_cnt + 1;
                if (delay_cnt == DELAY_40US) begin
                    delay_cnt <= 0;
                    state <= DISP_OFF;
                end
            end
            DISP_OFF: begin
                LCD_RS <= 0;
                LCD_DATA <= 8'h08;
                LCD_EN <= 1;
                state <= PULSE_EN;
            end
            WAIT_40US2: begin
                delay_cnt <= delay_cnt + 1;
                if (delay_cnt == DELAY_40US) begin
                    delay_cnt <= 0;
                    state <= DISP_CLEAR;
                end
            end
            DISP_CLEAR: begin
                LCD_RS <= 0;
                LCD_DATA <= 8'h01;
                LCD_EN <= 1;
                state <= PULSE_EN;
            end
            WAIT_2MS: begin
                delay_cnt <= delay_cnt + 1;
                if (delay_cnt == DELAY_2MS) begin
                    delay_cnt <= 0;
                    state <= ENTRY_MODE;
                end
            end
            ENTRY_MODE: begin
                LCD_RS <= 0;
                LCD_DATA <= 8'h06;  // Increment, no shift
                LCD_EN <= 1;
                state <= PULSE_EN;
            end
            WAIT_40US3: begin
                delay_cnt <= delay_cnt + 1;
                if (delay_cnt == DELAY_40US) begin
                    delay_cnt <= 0;
                    state <= DISP_ON;
                end
            end
            DISP_ON: begin
                LCD_RS <= 0;
                LCD_DATA <= 8'h0C;  // On, no cursor
                LCD_EN <= 1;
                state <= PULSE_EN;
            end
            WAIT_40US4: begin
                delay_cnt <= delay_cnt + 1;
                if (delay_cnt == DELAY_40US) begin
                    delay_cnt <= 0;
                    state <= IDLE;
                end
            end
            IDLE: begin
                if (write_pending) begin
                    state <= SET_ADDR;
                end else if (system_on == 0) begin
                    state <= OFF;
                end
            end
            SET_ADDR: begin
                LCD_RS <= 0;
                LCD_DATA <= 8'h80;  // Início linha 1
                LCD_EN <= 1;
                state <= PULSE_EN;
            end
            WAIT_40US5: begin
                delay_cnt <= delay_cnt + 1;
                if (delay_cnt == DELAY_40US) begin
                    delay_cnt <= 0;
                    state <= WRITE_CHAR;
                end
            end
            WRITE_CHAR: begin
                LCD_RS <= 1;  // Dado
                LCD_DATA <= line1[char_index];
                LCD_EN <= 1;
                state <= PULSE_EN;
            end
            WAIT_40US6: begin
                delay_cnt <= delay_cnt + 1;
                if (delay_cnt == DELAY_40US) begin
                    delay_cnt <= 0;
                    if (char_index == 15) begin
                        char_index <= 0;
                        write_pending <= 0;
                        if (clear_pending) begin
                            state <= CLEAR_SCREEN;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        char_index <= char_index + 1;
                        state <= WRITE_CHAR;
                    end
                end
            end
            CLEAR_SCREEN: begin  // Para CLEAR instr
                LCD_RS <= 0;
                LCD_DATA <= 8'h01;
                LCD_EN <= 1;
                state <= PULSE_EN;
                clear_pending <= 0;
            end
            PULSE_EN: begin
                LCD_EN <= 0;
                delay_cnt <= 0;
                state <= next_state_after_pulse;  // Defina next_state_after_pulse em cada chamada
                // Nota: Para simplificar, use uma reg next_state_after_pulse = estado_seguinte;
            end
        endcase
    end
end

// Adicione esta reg para next after pulse
reg [5:0] next_state_after_pulse;
always @(*) begin
    case (state)
        FUNC_SET1: next_state_after_pulse = WAIT_4_1MS;
        FUNC_SET2: next_state_after_pulse = WAIT_100US1;
        FUNC_SET3: next_state_after_pulse = WAIT_100US2;
        FUNC_SET_FINAL: next_state_after_pulse = WAIT_40US1;
        DISP_OFF: next_state_after_pulse = WAIT_40US2;
        DISP_CLEAR: next_state_after_pulse = WAIT_2MS;
        ENTRY_MODE: next_state_after_pulse = WAIT_40US3;
        DISP_ON: next_state_after_pulse = WAIT_40US4;
        SET_ADDR: next_state_after_pulse = WAIT_40US5;
        WRITE_CHAR: next_state_after_pulse = WAIT_40US6;
        CLEAR_SCREEN: next_state_after_pulse = WAIT_2MS;  // Volta a IDLE após
        OFF: next_state_after_pulse = DISP_CLEAR;  // Clear após off
        // etc.
    endcase
end

endmodule