// ============================================================================
// CONTROLADOR DE REDIMENSIONAMENTO COM CORTE (apenas Zoom IN)
// ============================================================================
module ControladorRedimensionamento #(
    parameter LARGURA_ORIG = 160,
    parameter ALTURA_ORIG  = 120,
    parameter MAX_LARGURA  = 320,  // Limite de largura da RAM
    parameter MAX_ALTURA   = 240   // Limite de altura da RAM
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [1:0] algoritmo,      // 00:Replicacao, 01:Decimacao, 10:VMP, 11:Media
    input  wire [1:0] zoom_select,
    input  wire [7:0] pixel_in,       // Pixel da ROM
    
    output reg  [14:0] rom_addr,      // Endereço para ROM
    output reg  [18:0] ram_addr,      // Endereço para RAM
    output reg  [7:0]  pixel_out,     // Pixel para RAM
    output reg         wren,          // Write enable
    output reg         done
);

    // Estados
    localparam IDLE    = 3'b000;
    localparam LOAD    = 3'b001;
    localparam WAIT    = 3'b010;
    localparam PROCESS = 3'b011;
    localparam WRITE   = 3'b100;
    localparam FINAL   = 3'b101;
    
    reg [2:0] estado, prox_estado;
    reg [2:0] escala_reg;
    
    // Contador para latência da ROM (3 ciclos)
    reg [1:0] wait_counter;
    
    // Contadores de posição
    reg [9:0] x_orig, y_orig;    // Posição na origem (ROM)
    reg [9:0] x_dest, y_dest;    // Posição no destino (RAM)
    reg [4:0] local_x, local_y;  // Para média de blocos
    
    // ========================================
    // LÓGICA DE CORTE (apenas Zoom IN)
    // ========================================
    
    // Dimensões da imagem ampliada COMPLETA (antes do corte)
    wire [9:0] largura_ampliada = LARGURA_ORIG * escala_reg;
    wire [9:0] altura_ampliada = ALTURA_ORIG * escala_reg;
    
    // Verifica se precisa cortar
    wire precisa_cortar_x = (largura_ampliada > MAX_LARGURA);
    wire precisa_cortar_y = (altura_ampliada > MAX_ALTURA);
    
    // Calcula offsets de corte (centro da imagem ampliada)
    wire [9:0] offset_corte_x = precisa_cortar_x ? ((largura_ampliada - MAX_LARGURA) >> 1) : 10'd0;
    wire [9:0] offset_corte_y = precisa_cortar_y ? ((altura_ampliada - MAX_ALTURA) >> 1) : 10'd0;
    
    // Dimensões finais na RAM (após corte)
    wire [9:0] largura_final = precisa_cortar_x ? MAX_LARGURA : largura_ampliada;
    wire [9:0] altura_final = precisa_cortar_y ? MAX_ALTURA : altura_ampliada;
    
    // ========================================
    // Dimensões calculadas (por algoritmo)
    // ========================================
    wire [9:0] largura_dest = (algoritmo == 2'b00 || algoritmo == 2'b10) ? 
                               largura_final :  // Zoom IN (com corte)
                               (LARGURA_ORIG / escala_reg);  // Zoom OUT
                               
    wire [9:0] altura_dest = (algoritmo == 2'b00 || algoritmo == 2'b10) ? 
                              altura_final :  // Zoom IN (com corte)
                              (ALTURA_ORIG / escala_reg);  // Zoom OUT
    
    wire [12:0] tamanho_bloco = escala_reg * escala_reg;
    
    // Sinais dos algoritmos
    reg alg_enable, new_block;
    
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
    
    // Decimação (NÃO MODIFICA)
    wire [7:0] dcm_pixel;
    wire dcm_should_write, dcm_ready;
    
    Decimacao dcm_inst (
        .clk(clk), 
		  .rst(rst),
        .enable(alg_enable && algoritmo == 2'b01),
        .pixel_in(pixel_in),
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
    wire [14:0] vmp_rom_calc;
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
        .rom_addr_calc(vmp_rom_calc),
        .ready(vmp_ready)
    );
    
    // Média de Blocos (NÃO MODIFICA)
    wire [7:0] mdb_pixel;
    wire mdb_block_done;
    
    MediaDeBlocos mdb_inst (
        .clk(clk),
		  .rst(rst),
        .enable(alg_enable && algoritmo == 2'b11),
        .new_block(new_block),
        .pixel_in(pixel_in),
        .tamanho_bloco(tamanho_bloco),
        .pixel_out(mdb_pixel),
        .block_done(mdb_block_done)
    );
    
	 
	 //Registradores
	  reg [9:0] x_ampliada;
     reg [9:0] y_ampliada;
	  reg [9:0] x_ram;
     reg [9:0] y_ram;
                                
     // Verifica se está dentro da janela de corte
     reg dentro_janela_x;
	  reg dentro_janela_y;                                                
     reg dentro_janela;
	  
	  reg [9:0] x_ampliada_vmp;  // x_dest JÁ É a posição ampliada
     reg [9:0] y_ampliada_vmp;
                                
     // Verifica se está dentro da janela
     reg dentro_janela_x_vmp;
	  reg dentro_janela_y_vmp;
     reg dentro_janela_vmp;
	  reg [9:0] x_ram_vmp;
     reg [9:0] y_ram_vmp;
                                    
                                
                            
    // Captura da escala
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
                        2'b00: begin  // Replicação 
                            rom_addr <= y_orig * LARGURA_ORIG + x_orig;
                        end
                        
                        2'b01: begin  // Decimação
                            rom_addr <= y_orig * LARGURA_ORIG + x_orig;
                        end
                        
                        2'b10: begin  // VMP
                            rom_addr <= vmp_rom_calc;
                        end
                        
                        2'b11: begin  // Média
                            rom_addr <= (y_dest * escala_reg + local_y) * LARGURA_ORIG 
                                      + (x_dest * escala_reg + local_x);
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
                        2'b00: begin  // ===== REPLICAÇÃO COM CORTE =====
                            // Calcula posição na imagem ampliada COMPLETA
                            x_ampliada <= x_orig * escala_reg + rep_offset_x;
                            y_ampliada <= y_orig * escala_reg + rep_offset_y;
                            
                            // Verifica se está dentro da janela de corte
                            dentro_janela_x <= (x_ampliada >= offset_corte_x) && 
                                                  (x_ampliada < offset_corte_x + largura_final);
                            dentro_janela_y <= (y_ampliada >= offset_corte_y) && 
                                                  (y_ampliada < offset_corte_y + altura_final);
                            dentro_janela <= dentro_janela_x && dentro_janela_y;
                            
                            // Só escreve se estiver dentro da janela
                            if (dentro_janela) begin
                                // Calcula posição na RAM (ajustada pelo offset)
                                x_ram <= x_ampliada - offset_corte_x;
                                y_ram <= y_ampliada - offset_corte_y;
                                
                                ram_addr <= y_ram * largura_final + x_ram;
                                pixel_out <= rep_pixel;
                                wren <= 1;
                            end else begin
                                wren <= 0;  // Pixel fora da janela, não escreve
                            end
                            
                            if (rep_done) begin
                                // Avança para próximo pixel origem
                                if (x_orig == LARGURA_ORIG-1) begin
                                    x_orig <= 0;
                                    if (y_orig == ALTURA_ORIG-1)
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
                                    ram_addr <= (y_orig / escala_reg) * largura_dest 
                                              + (x_orig / escala_reg);
                                    pixel_out <= dcm_pixel;
                                    wren <= 1;
                                end else
                                    wren <= 0;
                                
                                if (x_orig == LARGURA_ORIG-1) begin
                                    x_orig <= 0;
                                    if (y_orig == ALTURA_ORIG-1)
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
                        
                        2'b10: begin  // ===== VMP COM CORTE =====
                            if (vmp_ready) begin
                                // Calcula posição na imagem ampliada COMPLETA
                                x_ampliada_vmp <= x_dest;  // x_dest JÁ É a posição ampliada
                                y_ampliada_vmp <= y_dest;
                                
                                // Verifica se está dentro da janela
                                dentro_janela_x_vmp <= (x_ampliada_vmp >= offset_corte_x) && 
                                                          (x_ampliada_vmp < offset_corte_x + largura_final);
                                dentro_janela_y_vmp <= (y_ampliada_vmp >= offset_corte_y) && 
                                                          (y_ampliada_vmp < offset_corte_y + altura_final);
                                dentro_janela_vmp <= dentro_janela_x_vmp && dentro_janela_y_vmp;
                                
                                if (dentro_janela_vmp) begin
                                    // Calcula posição na RAM (ajustada)
                                    x_ram_vmp <= x_ampliada_vmp - offset_corte_x;
                                    y_ram_vmp <= y_ampliada_vmp - offset_corte_y;
                                    
                                    ram_addr <= y_ram_vmp * largura_final + x_ram_vmp;
                                    pixel_out <= vmp_pixel;
                                    wren <= 1;
                                end else begin
                                    wren <= 0;
                                end
                                
                                // Avança destino (sempre, mesmo fora da janela)
                                if (x_dest == largura_ampliada-1) begin  // Usa largura_ampliada COMPLETA
                                    x_dest <= 0;
                                    if (y_dest == altura_ampliada-1)
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
                        
                        2'b11: begin  // ===== MÉDIA (NÃO MODIFICA) =====
                            if (mdb_block_done) begin
                                ram_addr <= y_dest * largura_dest + x_dest;
                                pixel_out <= mdb_pixel;
                                wren <= 1;
                                local_x <= 0;
                                local_y <= 0;
                                
                                if (x_dest == largura_dest-1) begin
                                    x_dest <= 0;
                                    if (y_dest == altura_dest-1)
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
                                
                                if (local_x < escala_reg-1) begin
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