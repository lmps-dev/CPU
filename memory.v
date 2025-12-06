module memory (
    input wire clk,                // Clock
    input wire reset,              // Reset (para zerar todos os registradores)
    input wire [3:0] read_reg1,    // Endereço do primeiro registrador a ser lido
    input wire [3:0] read_reg2,    // Endereço do segundo registrador a ser lido
    input wire [3:0] write_reg,    // Endereço do registrador a ser escrito
    input wire [15:0] write_data,  // Dado a ser escrito
    input wire reg_write_en,       // Sinal de habilitação de escrita
    output reg [15:0] read_data1,  // Dado lido do primeiro registrador
    output reg [15:0] read_data2   // Dado lido do segundo registrador
);

    // Declaração da memória de registradores: 16 registradores de 16 bits cada
    reg [15:0] registers [0:15];

    // Leitura dos registradores (assíncrona)
    always @(*) begin
        read_data1 = registers[read_reg1];
        read_data2 = registers[read_reg2];
    end

    // Escrita no registrador (síncrona) e reset
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Zera todos os registradores quando reset = 1
            integer i;
            for (i = 0; i < 16; i = i + 1) begin
                registers[i] <= 16'b0;
            end
        end else if (reg_write_en) begin
            // Escreve no registrador apenas se reg_write_en = 1
            registers[write_reg] <= write_data;
        end
    end

endmodule