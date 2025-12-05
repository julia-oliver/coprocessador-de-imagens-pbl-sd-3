// ============================================================================
// ALGORITMO: Replicação
// Recebe: pixel + coordenadas origem
// Calcula: posições do bloco 2x2/4x4/8x8
// Retorna: offsets (block_x, block_y) e controle
// ============================================================================
module Replicacao (
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,         // Novo pixel para processar
    input  wire [7:0] pixel_in,       // Pixel da origem
    input  wire [2:0] escala,         // Fator de zoom
    
    output reg  [7:0]  pixel_out,     // Pixel replicado
    output reg  [3:0]  offset_x,      // Offset X no bloco (0 a escala-1)
    output reg  [3:0]  offset_y,      // Offset Y no bloco (0 a escala-1)
    output reg         done           // Terminei de replicar este pixel (todos offsets)
);

    reg [3:0] cont_x, cont_y;
    reg [7:0] pixel_hold;
    reg estado;  // 0=IDLE, 1=WORK
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            estado <= 0;
            cont_x <= 0;
            cont_y <= 0;
            pixel_out <= 0;
            pixel_hold <= 0;
            offset_x <= 0;
            offset_y <= 0;
            done <= 0;
        end else begin
            if (estado == 0) begin  // IDLE
                done <= 0;
                if (enable) begin
                    pixel_hold <= pixel_in;
                    pixel_out <= pixel_in;
                    cont_x <= 0;
                    cont_y <= 0;
                    offset_x <= 0;
                    offset_y <= 0;
                    estado <= 1;
                end
            end else begin  // WORK
                pixel_out <= pixel_hold;
                offset_x <= cont_x;
                offset_y <= cont_y;
                
                if (cont_x == escala-1 && cont_y == escala-1) begin
                    done <= 1;
                    estado <= 0;
                end else begin
                    done <= 0;
                    if (cont_x < escala-1)
                        cont_x <= cont_x + 1;
                    else begin
                        cont_x <= 0;
                        cont_y <= cont_y + 1;
                    end
                end
            end
        end
    end

endmodule