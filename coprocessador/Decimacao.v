// ============================================================================
// ALGORITMO: Decimação
// Recebe: coordenadas origem + escala
// Calcula: se deve amostrar (módulo)
// Retorna: pixel + flag de escrita
// ============================================================================
module Decimacao (
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,
    input  wire [7:0] pixel_in,
    input  wire [9:0] x_orig,         // Coordenada X na origem
    input  wire [9:0] y_orig,         // Coordenada Y na origem
    input  wire [2:0] escala,
    
    output reg  [7:0] pixel_out,
    output reg        should_write,   // Este pixel deve ser escrito?
    output reg        ready
);

    // Lógica combinacional para verificar se deve amostrar
    wire amostravel = ((x_orig % escala) == 0) && ((y_orig % escala) == 0);
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pixel_out <= 0;
            should_write <= 0;
            ready <= 1;
        end else begin
            if (enable) begin
                pixel_out <= pixel_in;
                should_write <= amostravel;  // Calcula se deve escrever
                ready <= 1;  // Instantâneo
            end else begin
                should_write <= 0;
                ready <= 1;
            end
        end
    end

endmodule