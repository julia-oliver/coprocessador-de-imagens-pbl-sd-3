// ============================================================================
// ALGORITMO: Vizinho Mais Próximo
// Recebe: coordenadas DESTINO + escala
// Calcula: coordenadas ORIGEM correspondentes (divisão)
// Retorna: pixel + coordenadas origem
// ============================================================================
module VizinhoMaisProximo #(
    parameter LARGURA_ORIG = 160
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,
    input  wire [7:0] pixel_in,
    input  wire [9:0] x_dest,         // Coordenada X no destino
    input  wire [9:0] y_dest,         // Coordenada Y no destino
    input  wire [2:0] escala,
    
    output reg  [7:0]  pixel_out,
    output wire [9:0]  x_orig,        // Coordenada X calculada na origem
    output wire [9:0]  y_orig,        // Coordenada Y calculada na origem
    output wire [14:0] rom_addr_calc, // Endereço ROM calculado
    output reg         ready
);

    // Cálculo combinacional: qual pixel da origem mapeia para este destino?
    assign x_orig = x_dest / escala;
    assign y_orig = y_dest / escala;
    assign rom_addr_calc = y_orig * LARGURA_ORIG + x_orig;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pixel_out <= 0;
            ready <= 1;
        end else begin
            if (enable) begin
                pixel_out <= pixel_in;
                ready <= 1;  // Instantâneo
            end else begin
                ready <= 1;
            end
        end
    end

endmodule