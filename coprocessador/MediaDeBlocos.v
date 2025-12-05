// ============================================================================
// ALGORITMO: Média de Blocos (CORRIGIDO)
// ============================================================================
module MediaDeBlocos (
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,         // Habilita processamento
    input  wire       new_block,      // Pulso: começar novo bloco
    input  wire [7:0] pixel_in,
    input  wire [12:0] tamanho_bloco, // escala²
    
    output reg  [7:0] pixel_out,      // Média calculada
    output reg        block_done      // Bloco completo, média pronta
);
    reg [18:0] acumulador;
    reg [12:0] contador;
    reg        processing;  // Flag indicando processamento ativo
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            acumulador <= 0;
            contador <= 0;
            pixel_out <= 0;
            block_done <= 0;
            processing <= 0;
        end else begin
            // Detecta início de novo bloco
            if (new_block) begin
                acumulador <= 0;
                contador <= 0;
                block_done <= 0;
                processing <= 1;  // Marca que começou processamento
            end 
            // Processa pixels quando habilitado E em processamento
            else if (enable && processing) begin
                // Acumula o pixel atual
                acumulador <= acumulador + pixel_in;
                contador <= contador + 1;
                
                // Verifica se completou o bloco (último pixel)
                if (contador == tamanho_bloco - 1) begin
                    // Calcula a média incluindo este último pixel
                    pixel_out <= (acumulador + pixel_in) / tamanho_bloco;
                    block_done <= 1;
                    processing <= 0;  // Finaliza processamento
                end else begin
                    block_done <= 0;
                end
            end 
            // Mantém block_done ativo até novo bloco começar
            else if (block_done && !new_block) begin
                block_done <= 1;  // Persiste o sinal
            end
            else begin
                block_done <= 0;
            end
        end
    end
endmodule