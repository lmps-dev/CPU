`timescale 1ns / 1ps

module lcd (
    input clk_50MHz,
    input reset_n,           // Reset ativo baixo
    input system_on,
    input display_enable,
    input [2:0] opcode_last,
    input [3:0] reg_number,
    input [15:0] reg_value,
    output reg [7:0] LCD_DATA,
    output reg LCD_RS,
    output reg LCD_EN,
    output LCD_RW,
    output wire LCD_ON
);
    // Configuração inicial das saídas
    assign LCD_RW = 1'b0; // Sempre modo de escrita
    assign LCD_ON = 1'b1; // LCD sempre ligado
   
    // Parâmetros de Delay (Clock 50MHz)
    localparam DELAY_15MS  = 750_000;    // 15ms @ 50MHz
    localparam DELAY_4_1MS = 205_000;    // 4.1ms
    localparam DELAY_100US = 5_000;      // 100us
    localparam DELAY_40US  = 2_000;      // 40us
    localparam DELAY_2MS   = 100_000;    // 2ms
   
    // Estados da FSM
    localparam [5:0]
        OFF = 0,
        POWER_ON = 1,
        WAIT_15MS = 2,
        FUNC_SET1 = 3,
        PULSE_EN = 4,
        WAIT_4_1MS = 5,
        FUNC_SET2 = 6,
        WAIT_100US1 = 7,
        FUNC_SET3 = 8,
        WAIT_100US2 = 9,
        FUNC_SET_FINAL = 10,
        WAIT_100US3 = 11,
        DISP_OFF = 12,
        WAIT_100US4 = 13,
        DISP_CLEAR = 14,
        WAIT_2MS = 15,
        ENTRY_MODE = 16,
        WAIT_100US5 = 17,
        DISP_ON = 18,
        IDLE = 20,
        SET_ADDR1 = 21,
        WAIT_ADDR1 = 22,
        WRITE_CHAR1 = 23,
        CHECK_LOOP1 = 24,
        SET_ADDR2 = 25,
        WAIT_ADDR2 = 26,
        WRITE_CHAR2 = 27,
        CHECK_LOOP2 = 28,
        CLEAR_SCREEN = 29;
   
    reg [5:0] state = OFF;
    reg [5:0] next_state_after_pulse;
    reg [19:0] delay_cnt = 0;
    reg [4:0] char_index = 0;
    reg [7:0] line1 [0:15];
    reg [7:0] line2 [0:15];
    reg write_pending = 0;
    reg clear_pending = 0;
    reg init_mode = 0;
    reg lcd_ready = 0; // Indica que LCD está pronto para receber comandos
   
    // Conversão Numérica
    wire signed [15:0] signed_value = reg_value;
    reg [15:0] abs_value;
    reg negative;
   
    // Binário para BCD
    reg [19:0] bcd;
    integer i, j;
   
    always @(*) begin
        // Cálculo de valor absoluto e sinal
        negative = (signed_value < 0);
        if (signed_value == 16'sh8000)
            abs_value = 32768;
        else
            abs_value = negative ? -signed_value : signed_value;
            
        // Conversão binário para BCD
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
   
    // FSM Principal Unificada
    always @(posedge clk_50MHz or negedge reset_n) begin
        if (!reset_n) begin
            state <= OFF;
            LCD_EN <= 0;
            LCD_RS <= 0;
            LCD_DATA <= 0;
            write_pending <= 0;
            clear_pending <= 0;
            init_mode <= 0;
            lcd_ready <= 0;
            delay_cnt <= 0;
            char_index <= 0;
            
            // Inicializar buffers com espaços
            for (j = 0; j < 16; j = j + 1) begin
                line1[j] <= " ";
                line2[j] <= " ";
            end
        end else begin
            // Se system_on = 0, força estado OFF
            if (!system_on) begin
                state <= OFF;
                LCD_EN <= 0;
                LCD_RS <= 0;
                LCD_DATA <= 0;
                lcd_ready <= 0;
                // Limpar buffers quando desligado
                for (j = 0; j < 16; j = j + 1) begin
                    line1[j] <= " ";
                    line2[j] <= " ";
                end
            end else begin
                case (state)
                    // Sequência de Inicialização
                    OFF: begin
                        LCD_DATA <= 8'h00;
                        LCD_EN <= 0;
                        LCD_RS <= 0;
                        lcd_ready <= 0;
                        state <= POWER_ON;
                    end
                   
                    POWER_ON: begin
                        init_mode <= 1;
                        delay_cnt <= 0;
                        state <= WAIT_15MS;
                    end
                   
                    WAIT_15MS: begin
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_15MS) begin
                            delay_cnt <= 0;
                            state <= FUNC_SET1;
                        end
                    end
                   
                    // Comandos de Init
                    FUNC_SET1: begin
                        LCD_RS <= 0;
                        LCD_DATA <= 8'h30;
                        next_state_after_pulse <= WAIT_4_1MS;
                        state <= PULSE_EN;
                    end
                   
                    WAIT_4_1MS: begin
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_4_1MS) begin
                            delay_cnt <= 0;
                            state <= FUNC_SET2;
                        end
                    end
                   
                    FUNC_SET2: begin
                        LCD_RS <= 0;
                        LCD_DATA <= 8'h30;
                        next_state_after_pulse <= WAIT_100US1;
                        state <= PULSE_EN;
                    end
                   
                    WAIT_100US1: begin
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_100US) begin
                            delay_cnt <= 0;
                            state <= FUNC_SET3;
                        end
                    end
                   
                    FUNC_SET3: begin
                        LCD_RS <= 0;
                        LCD_DATA <= 8'h30;
                        next_state_after_pulse <= WAIT_100US2;
                        state <= PULSE_EN;
                    end
                   
                    WAIT_100US2: begin
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_100US) begin
                            delay_cnt <= 0;
                            state <= FUNC_SET_FINAL;
                        end
                    end
                   
                    FUNC_SET_FINAL: begin
                        LCD_RS <= 0;
                        LCD_DATA <= 8'h38; // 2 lines, 5x8 font
                        next_state_after_pulse <= WAIT_100US3;
                        state <= PULSE_EN;
                    end
                   
                    WAIT_100US3: begin
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_100US) begin
                            delay_cnt <= 0;
                            state <= DISP_OFF;
                        end
                    end
                   
                    DISP_OFF: begin
                        LCD_RS <= 0;
                        LCD_DATA <= 8'h08;
                        next_state_after_pulse <= WAIT_100US4;
                        state <= PULSE_EN;
                    end
                   
                    WAIT_100US4: begin
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_100US) begin
                            delay_cnt <= 0;
                            state <= DISP_CLEAR;
                        end
                    end
                   
                    DISP_CLEAR: begin
                        LCD_RS <= 0;
                        LCD_DATA <= 8'h01; // Comando Hardware Clear Screen
                        next_state_after_pulse <= WAIT_2MS;
                        state <= PULSE_EN;
                    end
                   
                    WAIT_2MS: begin
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_2MS) begin
                            delay_cnt <= 0;
                            if (init_mode)
                                state <= ENTRY_MODE;
                            else begin
                                state <= IDLE;
                                clear_pending <= 0;
                            end
                        end
                    end
                   
                    ENTRY_MODE: begin
                        LCD_RS <= 0;
                        LCD_DATA <= 8'h06; // Increment cursor
                        next_state_after_pulse <= WAIT_100US5;
                        state <= PULSE_EN;
                    end
                   
                    WAIT_100US5: begin
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_100US) begin
                            delay_cnt <= 0;
                            state <= DISP_ON;
                        end
                    end
                   
                    DISP_ON: begin
                        LCD_RS <= 0;
                        LCD_DATA <= 8'h0C; // Display ON, Cursor OFF
                        next_state_after_pulse <= IDLE;
                        state <= PULSE_EN;
                    end
                   
                    // Estado IDLE e Preparação de Dados
                    IDLE: begin
                        init_mode <= 0;
                        lcd_ready <= 1;  // LCD pronto
                        LCD_EN <= 0;
                        
                        if (display_enable && lcd_ready) begin
                            // 1. Limpa Buffers (Preenche tudo com espaços)
                            for (j = 0; j < 16; j = j + 1) begin
                                line1[j] <= " ";
                                line2[j] <= " ";
                            end
                           
                            // 2. Preenche Texto da Linha 1 baseado no Opcode
                            case (opcode_last)
                                3'b000: begin 
                                    line1[0] <= "L"; line1[1] <= "O"; line1[2] <= "A"; line1[3] <= "D"; 
                                end
                                3'b001: begin 
                                    line1[0] <= "A"; line1[1] <= "D"; line1[2] <= "D"; 
                                end
                                3'b010: begin 
                                    line1[0] <= "A"; line1[1] <= "D"; line1[2] <= "D"; line1[3] <= "I"; 
                                end
                                3'b011: begin 
                                    line1[0] <= "S"; line1[1] <= "U"; line1[2] <= "B"; 
                                end
                                3'b100: begin 
                                    line1[0] <= "S"; line1[1] <= "U"; line1[2] <= "B"; line1[3] <= "I"; 
                                end
                                3'b101: begin 
                                    line1[0] <= "M"; line1[1] <= "U"; line1[2] <= "L"; 
                                end
                                3'b110: begin
                                    // Configura o texto CLEAR
                                    line1[0] <= "C"; line1[1] <= "L"; line1[2] <= "E";
                                    line1[3] <= "A"; line1[4] <= "R";
                                end
                                3'b111: begin 
                                    line1[0] <= "D"; line1[1] <= "P"; line1[2] <= "L"; 
                                end
                                default: begin 
                                    // Mantém valores atuais ou espaços
                                end
                            endcase
                           
                            // 3. Preenche Dados da Linha 2
                            if (opcode_last == 3'b110) begin
                                clear_pending <= 0;
                            end else begin
                                // Lógica normal para mostrar números
                                
                                line2[0] <= "[";
										  line2[1] <= 8'h30 + reg_number[3];
                                line2[2] <= 8'h30 + reg_number[2];
                                line2[3] <= 8'h30 + reg_number[1];
                                line2[4] <= 8'h30 + reg_number[0];
                                line2[5] <= "]";
                                
                                // Sinal e Valor
                                line2[10] <= negative ? "-" : "+";
                                
                                // Converter BCD para ASCII
                                line2[11] <= (bcd[19:16] == 0) ? " " : 8'h30 + bcd[19:16];
                                line2[12] <= (bcd[15:12] == 0 && bcd[19:16] == 0) ? " " : 8'h30 + bcd[15:12];
                                line2[13] <= 8'h30 + bcd[11:8];
                                line2[14] <= 8'h30 + bcd[7:4];
                                line2[15] <= 8'h30 + bcd[3:0];
                                
                                clear_pending <= 0;
                            end
                           
                            write_pending <= 1;
                            lcd_ready <= 0;  // LCD ocupado
                            state <= IDLE;   // Recarrega IDLE para iniciar a escrita no próximo clock
                            
                        end else if (write_pending) begin
                            if (clear_pending) begin
                                state <= CLEAR_SCREEN;
                                write_pending <= 0;
                            end else begin
                                char_index <= 0;
                                state <= SET_ADDR1;
                            end
                        end
                    end
                   
                    // Sequência de Escrita no LCD
                    SET_ADDR1: begin
                        LCD_RS <= 0;
                        LCD_DATA <= 8'h80;  // Endereço linha 1 (0x00)
                        next_state_after_pulse <= WAIT_ADDR1;
                        state <= PULSE_EN;
                    end
                   
                    WAIT_ADDR1: begin
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_40US) begin
                            delay_cnt <= 0;
                            state <= WRITE_CHAR1;
                        end
                    end
                   
                    WRITE_CHAR1: begin
                        LCD_RS <= 1;
                        LCD_DATA <= line1[char_index];
                        next_state_after_pulse <= CHECK_LOOP1;
                        state <= PULSE_EN;
                    end
                   
                    CHECK_LOOP1: begin
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_40US) begin
                            delay_cnt <= 0;
                            if (char_index == 15) begin
                                char_index <= 0;
                                state <= SET_ADDR2;
                            end else begin
                                char_index <= char_index + 1;
                                state <= WRITE_CHAR1;
                            end
                        end
                    end
                   
                    SET_ADDR2: begin
                        LCD_RS <= 0;
                        LCD_DATA <= 8'hC0; // Endereço linha 2 (0x40)
                        next_state_after_pulse <= WAIT_ADDR2;
                        state <= PULSE_EN;
                    end
                   
                    WAIT_ADDR2: begin
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_40US) begin
                            delay_cnt <= 0;
                            state <= WRITE_CHAR2;
                        end
                    end
                   
                    WRITE_CHAR2: begin
                        LCD_RS <= 1;
                        LCD_DATA <= line2[char_index];
                        next_state_after_pulse <= CHECK_LOOP2;
                        state <= PULSE_EN;
                    end
                   
                    CHECK_LOOP2: begin
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_40US) begin
                            delay_cnt <= 0;
                            if (char_index == 15) begin
                                char_index <= 0;
                                write_pending <= 0;
                                state <= IDLE;
                            end else begin
                                char_index <= char_index + 1;
                                state <= WRITE_CHAR2;
                            end
                        end
                    end
                   
                    CLEAR_SCREEN: begin
                        LCD_RS <= 0;
                        LCD_DATA <= 8'h01;
                        next_state_after_pulse <= WAIT_2MS;
                        state <= PULSE_EN;
                    end
                   
                    // Gerador de Pulso Enable
                    PULSE_EN: begin
                        if (delay_cnt == 0) begin
                            LCD_EN <= 1;
                        end
                       
                        delay_cnt <= delay_cnt + 1;
                        if (delay_cnt >= DELAY_40US) begin
                            LCD_EN <= 0;
                            delay_cnt <= 0;
                            state <= next_state_after_pulse;
                        end
                    end
                   
                    default: begin
                        state <= OFF;
                    end
                endcase
            end
        end
    end
endmodule