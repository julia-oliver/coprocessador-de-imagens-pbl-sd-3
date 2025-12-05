module VizinhoMaisProximo #(
    parameter LARGURA_ORIG = 320  // ✅ CORRIGIDO PARA 320
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,
    input  wire [7:0] pixel_in,
    input  wire [9:0] x_dest,
    input  wire [9:0] y_dest,
    input  wire [2:0] escala,
    
    output reg  [7:0]  pixel_out,
    output wire [9:0]  x_orig,
    output wire [9:0]  y_orig,
    output wire [16:0] rom_addr_calc,  // ✅ AUMENTADO PARA 22 BITS (por segurança)
    output reg         ready
);
    
    assign x_orig = x_dest / escala;
    assign y_orig = y_dest / escala;
    
    // ✅ CÁLCULO SEGURO COM EXPANSÃO EXPLÍCITA
    wire [21:0] y_mult = {12'b0, y_orig} * LARGURA_ORIG;  // 22 bits
    assign rom_addr_calc = y_mult + {12'b0, x_orig};      // 22 bits
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pixel_out <= 0;
            ready <= 1;
        end else begin
            if (enable) begin
                pixel_out <= pixel_in;
                ready <= 1;
            end else begin
                ready <= 1;
            end
        end
    end
endmodule