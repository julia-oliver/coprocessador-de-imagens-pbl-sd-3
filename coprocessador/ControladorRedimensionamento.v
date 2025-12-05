// ============================================================================
// CONTROLADOR DE REDIMENSIONAMENTO COM JANELA SELECIONÁVEL
// ✅ ATUALIZADO PARA 21 BITS DE ENDEREÇAMENTO
// ============================================================================
module ControladorRedimensionamento #(
    parameter LARGURA_ORIG = 320,      
    parameter ALTURA_ORIG   = 240,
    parameter MAX_LARGURA   = 640,
    parameter MAX_ALTURA   = 480
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [1:0]  algoritmo,
    input  wire [1:0]  zoom_select,
    input  wire [7:0]  pixel_in, 
	 input wire [7:0]   red_pixel,
    
    input  wire [8:0]  janela_x_inicio,    
    input  wire [7:0]  janela_y_inicio,    
    input  wire [10:0]  janela_largura,     
    input  wire [9:0]  janela_altura,      
    
    output reg  [18:0] rom_addr,       
    // ✅ AUMENTADO PARA 21 BITS
    output reg  [20:0] ram_addr, 
    output reg  [7:0]  pixel_out,
    output reg         wren,
    output reg         done
);

    localparam IDLE    = 3'b000;
    localparam LOAD    = 3'b001;
    localparam WAIT    = 3'b010;
    localparam PROCESS = 3'b011;
    localparam WRITE   = 3'b100;
    localparam FINAL   = 3'b101;
    
    reg [2:0] estado, prox_estado;
    reg [2:0] escala_reg;
    reg [1:0] wait_counter;
    
    reg [9:0] x_orig, y_orig;
    reg [9:0] x_dest, y_dest;
    reg [4:0] local_x, local_y;
    
    // ========================================
    // DIMENSÕES DA JANELA AMPLIADA
    // ========================================
    wire [10:0] largura_ampliada = janela_largura * escala_reg;
    wire [10:0] altura_ampliada = janela_altura * escala_reg;
    
    wire precisa_cortar_x = (largura_ampliada > MAX_LARGURA);
    wire precisa_cortar_y = (altura_ampliada > MAX_ALTURA);
    
    wire [9:0] offset_corte_x = precisa_cortar_x ? ((largura_ampliada - MAX_LARGURA) >> 1) : 10'd0;
    wire [9:0] offset_corte_y = precisa_cortar_y ? ((altura_ampliada - MAX_ALTURA) >> 1) : 10'd0;
    
    wire [9:0] largura_final = precisa_cortar_x ? MAX_LARGURA : largura_ampliada[9:0];
    wire [9:0] altura_final = precisa_cortar_y ? MAX_ALTURA : altura_ampliada[9:0];
    
    // ✅ LARGURA DE DESTINO AUMENTADA PARA 11 BITS
    wire [10:0] largura_dest = (algoritmo == 2'b00 || algoritmo == 2'b10) ? 
                               {1'b0, largura_final} :
                               (janela_largura / escala_reg);
                              
    wire [10:0] altura_dest = (algoritmo == 2'b00 || algoritmo == 2'b10) ? 
                              {1'b0, altura_final} :
                              (janela_altura / escala_reg);
    
    wire [12:0] tamanho_bloco = escala_reg * escala_reg;
    
    reg alg_enable, new_block;
    
    // ========================================
    // CÁLCULO DE ENDEREÇO ABSOLUTO NA ROM
    // ========================================
    wire [9:0] x_absoluto = janela_x_inicio + x_orig;
    wire [9:0] y_absoluto = janela_y_inicio + y_orig;
    wire [16:0] rom_addr_absoluto = y_absoluto * LARGURA_ORIG + x_absoluto;
    
    // Replicação
    wire [7:0] rep_pixel;
    wire [3:0] rep_offset_x, rep_offset_y;
    wire rep_done;
    
    Replicacao rep_inst (
        .clk(clk), 
        .rst(rst),
        .enable(alg_enable && algoritmo == 2'b00),
        .pixel_in(pixel_in),
        .escala(escala_reg),
        .pixel_out(rep_pixel),
        .offset_x(rep_offset_x),
        .offset_y(rep_offset_y),
        .done(rep_done)
    );
    
    // Decimação
    wire [7:0] dcm_pixel;
    wire dcm_should_write, dcm_ready;
    
    Decimacao dcm_inst (
        .clk(clk), 
        .rst(rst),
        .enable(alg_enable && algoritmo == 2'b01),
        .pixel_in(red_pixel),
        .x_orig(x_orig),
        .y_orig(y_orig),
        .escala(escala_reg),
        .pixel_out(dcm_pixel),
        .should_write(dcm_should_write),
        .ready(dcm_ready)
    );
    
    // Vizinho Mais Próximo
    wire [7:0] vmp_pixel;
    wire [9:0] vmp_x_orig, vmp_y_orig;
    wire [16:0] vmp_rom_calc_relativo;
    wire vmp_ready;
    
    VizinhoMaisProximo #(LARGURA_ORIG) vmp_inst (
        .clk(clk), 
        .rst(rst),
        .enable(alg_enable && algoritmo == 2'b10),
        .pixel_in(pixel_in),
        .x_dest(x_dest),
        .y_dest(y_dest),
        .escala(escala_reg),
        .pixel_out(vmp_pixel),
        .x_orig(vmp_x_orig),
        .y_orig(vmp_y_orig),
        .rom_addr_calc(vmp_rom_calc_relativo),
        .ready(vmp_ready)
    );
    
    wire [9:0] vmp_x_absoluto = janela_x_inicio + vmp_x_orig;
    wire [9:0] vmp_y_absoluto = janela_y_inicio + vmp_y_orig;
    wire [16:0] vmp_rom_addr_absoluto = vmp_y_absoluto * LARGURA_ORIG + vmp_x_absoluto;
    
    // Média de Blocos
    wire [7:0] mdb_pixel;
    wire mdb_block_done;
    
    MediaDeBlocos mdb_inst (
        .clk(clk),
        .rst(rst),
        .enable(alg_enable && algoritmo == 2'b11),
        .new_block(new_block),
        .pixel_in(red_pixel),
        .tamanho_bloco(tamanho_bloco),
        .pixel_out(mdb_pixel),
        .block_done(mdb_block_done)
    );
    
    // Registradores de Corte (Replicação)
    reg [9:0] x_ampliada;
    reg [9:0] y_ampliada;
    reg [9:0] x_ram;
    reg [9:0] y_ram;
    reg dentro_janela_x;
    reg dentro_janela_y;                                    
    reg dentro_janela;
    
    // Registradores de Corte (VMP)
    reg [9:0] x_ampliada_vmp;
    reg [9:0] y_ampliada_vmp;
    reg dentro_janela_x_vmp;
    reg dentro_janela_y_vmp;
    reg dentro_janela_vmp;
    reg [9:0] x_ram_vmp;
    reg [9:0] y_ram_vmp;
    
    always @(posedge clk or posedge rst) begin
        if (rst)
            escala_reg <= 1;
        else if (start) begin
            case (zoom_select)
                2'b00: escala_reg <= 1;
                2'b01: escala_reg <= 2;
                2'b10: escala_reg <= 4;
                2'b11: escala_reg <= 8;
            endcase
        end
    end
    
    // FSM Principal
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            estado <= IDLE;
            prox_estado <= IDLE;
            x_orig <= 0;
            y_orig <= 0;
            x_dest <= 0;
            y_dest <= 0;
            local_x <= 0;
            local_y <= 0;
            rom_addr <= 0;
            ram_addr <= 0;
            pixel_out <= 0;
            wren <= 0;
            alg_enable <= 0;
            new_block <= 0;
            wait_counter <= 0;
            done <= 0;
        end else begin
            estado <= prox_estado;
            
            case (estado)
                IDLE: begin
                    alg_enable <= 0;
                    new_block <= 0;
                    wren <= 0;
                    done <= 0;
                    if (start) begin
                        x_orig <= 0;
                        y_orig <= 0;
                        x_dest <= 0;
                        y_dest <= 0;
                        local_x <= 0;
                        local_y <= 0;
                        prox_estado <= LOAD;
                    end else
                        prox_estado <= IDLE;
                end
                
               LOAD: begin
                    wren <= 0;
                    alg_enable <= 0;
                    wait_counter <= 0;
                    
                    case (algoritmo)
                        2'b00: begin // Replicação (Zoom In)
                           rom_addr <= {2'b00, rom_addr_absoluto}; // Lê da RAM1/ROM
                        end
                        
                        2'b01: begin // Decimação (Zoom Out)
                          rom_addr <= 19'b0; // NÃO LÊ RAM1
                            
                            // Endereço de LEITURA na RAM2 (imagem redimensionada anterior)
                            // x_orig/y_orig = coord. do pixel a ser lido na ENTRADA
                            ram_addr <= {2'b00, y_orig} * {2'b00, largura_final} + {11'b0, x_orig};
                        end
                        
                        2'b10: begin // VMP (Zoom In)
                            rom_addr <= {2'b00, vmp_rom_addr_absoluto}; // Lê da RAM1/ROM
                        end
                        
                        2'b11: begin // Média de Blocos (Zoom Out)
                            rom_addr <= 19'b0;
                            
                            // Endereço de LEITURA na RAM2 (imagem redimensionada anterior)
                            // x_dest/y_dest = coord. do bloco a ser gerado na SAÍDA
                            // local_x/local_y = offset dentro do bloco (0 a Escala-1)
                            // Largura_RAM2_Lida = largura_final (largura ampliada do passo anterior)
                            ram_addr <= ({2'b00, y_dest} * escala_reg + {6'b0, local_y}) * {2'b00, largura_final} + 
                                        ({2'b00, x_dest} * escala_reg + {6'b0, local_x});
                            
                            // Isso é complexo se `ram_addr` for a saída de endereço da RAM2. Vamos focar no `rom_addr` por enquanto.
                            
                            if (local_x == 0 && local_y == 0)
                                new_block <= 1;
                            else
                                new_block <= 0;
                        end
                    endcase
                    
                    prox_estado <= WAIT;
                end
                
                WAIT: begin
                    new_block <= 0;
                    
                    if (wait_counter < 2) begin
                        wait_counter <= wait_counter + 1;
                        prox_estado <= WAIT;
                    end else begin
                        wait_counter <= 0;
                        prox_estado <= PROCESS;
                    end
                end
                
                PROCESS: begin
                    alg_enable <= 1;
                    prox_estado <= WRITE;
                end
                
                WRITE: begin
                    alg_enable <= 0;
                    
                    case (algoritmo)
                        2'b00: begin  // ===== REPLICAÇÃO =====
                            x_ampliada <= x_orig * escala_reg + rep_offset_x;
                            y_ampliada <= y_orig * escala_reg + rep_offset_y;
                            
                            dentro_janela_x <= (x_ampliada >= offset_corte_x) && 
                                               (x_ampliada < offset_corte_x + largura_final);
                            dentro_janela_y <= (y_ampliada >= offset_corte_y) && 
                                               (y_ampliada < offset_corte_y + altura_final);
                            dentro_janela <= dentro_janela_x && dentro_janela_y;
                            
                            if (dentro_janela) begin
                                x_ram <= x_ampliada - offset_corte_x;
                                y_ram <= y_ampliada - offset_corte_y;
                                
                                // ✅ CÁLCULO COM 21 BITS (11 bits * 10 bits)
                                ram_addr <= ({11'b0, y_ram} * largura_dest) + {11'b0, x_ram};
                                pixel_out <= rep_pixel;
                                wren <= 1;
                            end else begin
                                wren <= 0;
                            end
                            
                            if (rep_done) begin
                                if (x_orig == janela_largura - 1) begin
                                    x_orig <= 0;
                                    if (y_orig == janela_altura - 1)
                                        prox_estado <= FINAL;
                                    else begin
                                        y_orig <= y_orig + 1;
                                        prox_estado <= LOAD;
                                    end
                                end else begin
                                    x_orig <= x_orig + 1;
                                    prox_estado <= LOAD;
                                end 
                            end else begin
                                prox_estado <= WRITE;
                            end    
                        end
                        
                        2'b01: begin  // ===== DECIMAÇÃO =====
                            if (dcm_ready) begin
                                if (dcm_should_write) begin
                                    // ✅ CÁLCULO COM 21 BITS
                                    ram_addr <= ({12'b0, y_orig} / escala_reg) * largura_dest 
																	+ ({12'b0, x_orig} / escala_reg);
                                    pixel_out <= dcm_pixel;
                                    wren <= 1;
                                end else
                                    wren <= 0;
                                
                                if (x_orig == janela_largura - 1) begin
                                    x_orig <= 0;
                                    if (y_orig == janela_altura - 1)
                                        prox_estado <= FINAL;
                                    else begin
                                        y_orig <= y_orig + 1;
                                        prox_estado <= LOAD;
                                    end
                                end else begin
                                    x_orig <= x_orig + 1;
                                    prox_estado <= LOAD;
                                end
                            end else
                                prox_estado <= WRITE;
                        end
                        
                        2'b10: begin  // ===== VMP =====
                            if (vmp_ready) begin
                                x_ampliada_vmp <= x_dest;
                                y_ampliada_vmp <= y_dest;
                                
                                dentro_janela_x_vmp <= (x_ampliada_vmp >= offset_corte_x) && 
                                                       (x_ampliada_vmp < offset_corte_x + largura_final);
                                dentro_janela_y_vmp <= (y_ampliada_vmp >= offset_corte_y) && 
                                                       (y_ampliada_vmp < offset_corte_y + altura_final);
                                dentro_janela_vmp <= dentro_janela_x_vmp && dentro_janela_y_vmp;
                                
                                if (dentro_janela_vmp) begin
                                    x_ram_vmp <= x_ampliada_vmp - offset_corte_x;
                                    y_ram_vmp <= y_ampliada_vmp - offset_corte_y;
                                    
                                    // ✅ CÁLCULO COM 21 BITS
                                    ram_addr <= ({12'b0, y_ram_vmp} * largura_dest) 
														+ {12'b0, x_ram_vmp};
                                    pixel_out <= vmp_pixel;
                                    wren <= 1;
                                end else begin
                                    wren <= 0;
                                end
                                
                                if (x_dest == largura_ampliada[9:0] - 1) begin
                                    x_dest <= 0;
                                    if (y_dest == altura_ampliada[9:0] - 1)
                                        prox_estado <= FINAL;
                                    else begin
                                        y_dest <= y_dest + 1;
                                        prox_estado <= LOAD;
                                    end
                                end else begin
                                    x_dest <= x_dest + 1;
                                    prox_estado <= LOAD;
                                end
                            end else
                                prox_estado <= WRITE;
                        end
                        
                        2'b11: begin  // ===== MÉDIA =====
                            if (mdb_block_done) begin
                                // ✅ CÁLCULO COM 21 BITS
                                 ram_addr <= ({12'b0, y_dest} * largura_dest) + {12'b0, x_dest};
                                pixel_out <= mdb_pixel;
                                wren <= 1;
                                local_x <= 0;
                                local_y <= 0;
                                
                                if (x_dest == largura_dest - 1) begin
                                    x_dest <= 0;
                                    if (y_dest == altura_dest - 1)
                                        prox_estado <= FINAL;
                                    else begin
                                        y_dest <= y_dest + 1;
                                        prox_estado <= LOAD;
                                    end
                                end else begin
                                    x_dest <= x_dest + 1;
                                    prox_estado <= LOAD;
                                end
                            end else begin
                                wren <= 0;
                                
                                if (local_x < escala_reg - 1) begin
                                    local_x <= local_x + 1;
                                end else begin
                                    local_x <= 0;
                                    local_y <= local_y + 1;
                                end
                                
                                prox_estado <= LOAD;
                            end
                        end
                    endcase
                end
                
                FINAL: begin
                    wren <= 0;
                    done <= 1;
                    prox_estado <= IDLE;
                end
                
                default: prox_estado <= IDLE;
            endcase
        end
    end

endmodule