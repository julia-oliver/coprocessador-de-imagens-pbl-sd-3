module UnidadeControle(
    input  wire        clk_50,
    input  wire        reset,
    input  wire        start,
    input  wire [1:0]  SW,
    input  wire [1:0]  zoom_select,
    input  wire [7:0]  dados_pixel_hps, 
    input              SolicitaEscrita,
    input  wire [18:0] addr_in_hps, 
    input  wire [31:0] janela_pos,
    input  wire [31:0] janela_dim,
	 input  wire [9:0]  mouse_x,
	 input  wire [9:0]  mouse_y,
    
    output wire [1:0]  opcao_Redmn,
    output reg         ready,
    output wire        hsync,
    output wire        vsync,
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        sync,
    output wire        clk,
    output wire        blank,
    output wire        done_redim,
    output reg         done_write
);

    localparam integer ALTURA_ORIGINAL  = 240;
    localparam integer LARGURA_ORIGINAL = 320;
    localparam integer MAX_LARGURA = 640;
    localparam integer MAX_ALTURA = 480;

    // ========================================
    // CLOCKS
    // ========================================
    wire clock_25;
    divisor_clock divisor_inst (
        .clk_50(clk_50),
        .reset(!reset),
        .clk_25(clock_25)
    );
    
    wire clk_100;
    clk_100_0002 clk_100_inst (
        .refclk    (clk_50),
        .rst       (!reset),
        .outclk_0  (clk_100),
        .locked    ()
    );

    // ========================================
    // ESTADOS
    // ========================================
    localparam INICIO  = 2'b00;
    localparam EXECUTE = 2'b01;
    localparam CHECK   = 2'b10;

    localparam REPLICACAO      = 2'b00;
    localparam DECIMACAO       = 2'b01;
    localparam VIZINHO_PROXIMO = 2'b10;
    localparam MEDIA_BLOCOS    = 2'b11;

    reg [1:0] estado, prox_estado;
    reg [1:0] Tipo_redmn;
    assign opcao_Redmn = Tipo_redmn;
    reg operacao_ativa;

    // ========================================
    // EXTRAÇÃO DA JANELA
    // ========================================
    wire [8:0] janela_x_inicio = janela_pos[8:0];
    wire [7:0] janela_y_inicio = janela_pos[16:9];
    wire [8:0] janela_largura  = janela_dim[8:0];
    wire [7:0] janela_altura   = janela_dim[16:9];
    
    reg [8:0] janela_x_inicio_reg;
    reg [7:0] janela_y_inicio_reg;
    reg [8:0] janela_largura_reg;
    reg [7:0] janela_altura_reg;

    // ========================================
    // MEMÓRIA RAM1 (IMAGEM ORIGINAL - 8 bits)
    // ========================================
    wire [18:0] rom_addr_top; 
    wire [7:0] rom_pixel;     

    localparam IDLE_WRITE = 2'b00;
    localparam WRITE      = 2'b01;
    localparam WAIT_WRITE = 2'b10;

    reg [1:0] state_write, next_state_write;
    reg wren_ram1;
    reg [7:0] dados_RAM; 
    reg [18:0] addr_hps; 

    // FSM de escrita
    always @(posedge clk_100 or negedge reset) begin
        if (!reset)
            state_write <= IDLE_WRITE;
        else
            state_write <= next_state_write;
    end

    always @(*) begin
        next_state_write = state_write;
        
        case (state_write)
            IDLE_WRITE: begin
                if (SolicitaEscrita)
                    next_state_write = WRITE;
            end
            WRITE: begin
                next_state_write = WAIT_WRITE;
            end
            WAIT_WRITE: begin
                next_state_write = IDLE_WRITE;
            end
            default: next_state_write = IDLE_WRITE;
        endcase
    end

    always @(posedge clk_100 or negedge reset) begin
        if (!reset) begin
            wren_ram1 <= 1'b0;
            done_write <= 1'b0;
            dados_RAM <= 8'b0; 
            addr_hps <= 19'b0; 
        end else begin
            case (state_write)
                IDLE_WRITE: begin
                    wren_ram1 <= 1'b0;
                    done_write <= 1'b0;
                end
                WRITE: begin
                    dados_RAM <= dados_pixel_hps;
                    addr_hps <= addr_in_hps[18:0];
                    wren_ram1 <= 1'b1;
                    done_write <= 1'b0;
                end
                WAIT_WRITE: begin
                    wren_ram1 <= 1'b0;
                    done_write <= 1'b1;
                end
                default: begin
                    wren_ram1 <= 1'b0;
                    done_write <= 1'b0;
                end
            endcase
        end
    end

    mem1 memory1(
        .rdaddress(rom_addr_top), 
        .wraddress(addr_hps), 
        .clock(clk_100), 
        .data(dados_RAM), 
        .wren(wren_ram1), 
        .q(rom_pixel)     
    );                           
    
    // ========================================
    // MEMÓRIA RAM2 (JANELA PROCESSADA - 8 bits)
    // ========================================
    wire [20:0] EnderecoRAM;
    wire [7:0] ram_data_in;
    wire wren_ram;
    wire [7:0] saida_RAM;

    mem2 memory2 (
        .address (EnderecoRAM),
        .clock   (clk_100),
        .data    (ram_data_in),
        .wren    (wren_ram),
        .q       (saida_RAM)
    );

    // ========================================
    // CONTROLADOR DE REDIMENSIONAMENTO
    // ========================================
    wire [16:0] rom_addr_redim;
    wire [20:0] ram_addr_redim;
    wire [7:0] pixel_out_redim;
    wire wren_redim;

    ControladorRedimensionamento #(
        .LARGURA_ORIG(LARGURA_ORIGINAL),
        .ALTURA_ORIG(ALTURA_ORIGINAL),
        .MAX_LARGURA(MAX_LARGURA),
        .MAX_ALTURA(MAX_ALTURA)
    ) controlador_redim (
        .clk(clock_25),
        .rst(!reset),
        .start(start),
        .algoritmo(SW),
        .zoom_select(zoom_select),
        .pixel_in(rom_pixel),
		  .red_pixel(saida_RAM),
        .janela_x_inicio(janela_x_inicio_reg),
        .janela_y_inicio(janela_y_inicio_reg),
        .janela_largura(janela_largura_reg),
        .janela_altura(janela_altura_reg),
        .rom_addr(rom_addr_redim),
        .ram_addr(ram_addr_redim),
        .pixel_out(pixel_out_redim),
        .wren(wren_redim),
        .done(done_redim)
    );

    // ========================================
    // CAPTURA DA JANELA NO START
    // ========================================
    always @(posedge clock_25 or negedge reset) begin
        if (!reset) begin
            janela_x_inicio_reg <= 9'd0;
            janela_y_inicio_reg <= 8'd0;
            janela_largura_reg  <= 9'd320;
            janela_altura_reg   <= 8'd240;
        end else if (start) begin
            janela_x_inicio_reg <= janela_x_inicio;
            janela_y_inicio_reg <= janela_y_inicio;
            janela_largura_reg  <= janela_largura;
            janela_altura_reg   <= janela_altura;
        end
    end

    // ========================================
    // ✅ CÁLCULO DAS DIMENSÕES COM OFFSETS DE CENTRALIZAÇÃO
    // ========================================
    wire [3:0] BLOCK_SIZE_val = (zoom_select == 2'b00) ? 4'd1 :
                                (zoom_select == 2'b01) ? 4'd2 :
                                (zoom_select == 2'b10) ? 4'd4 :
                                (zoom_select == 2'b11) ? 4'd8 : 4'd1;

    // Offset da imagem original centralizada
    wire [9:0] x_offset = (640 - LARGURA_ORIGINAL) / 2;
    wire [9:0] y_offset = (480 - ALTURA_ORIGINAL) / 2;
    
    // Posição da janela NA TELA
    reg [9:0] janela_x_screen;
    reg [9:0] janela_y_screen;
    
    // Dimensões da imagem processada
    reg [10:0] largura_processada;
    reg [10:0] altura_processada;
    
    // Dimensões VISÍVEIS da janela
    reg [9:0] janela_largura_visivel;
    reg [9:0] janela_altura_visivel;
    
    // ✅ OFFSET APENAS PARA ZOOM IN (pular bordas da imagem ampliada)
    reg [9:0] offset_leitura_x;
    reg [9:0] offset_leitura_y;

    // ✅ Cálculo das dimensões processadas (combinacional)
    wire [10:0] largura_calc = (SW == REPLICACAO || SW == VIZINHO_PROXIMO) ?
                                ((janela_largura * BLOCK_SIZE_val > MAX_LARGURA) ? 
                                 MAX_LARGURA : janela_largura * BLOCK_SIZE_val) :
                                (janela_largura / BLOCK_SIZE_val);
                                
    wire [10:0] altura_calc = (SW == REPLICACAO || SW == VIZINHO_PROXIMO) ?
                               ((janela_altura * BLOCK_SIZE_val > MAX_ALTURA) ? 
                                MAX_ALTURA : janela_altura * BLOCK_SIZE_val) :
                               (janela_altura / BLOCK_SIZE_val);

    always @(posedge clock_25 or negedge reset) begin
        if (!reset) begin
            janela_x_screen <= 10'd0;
            janela_y_screen <= 10'd0;
            largura_processada <= 11'd320;
            altura_processada <= 11'd240;
            janela_largura_visivel <= 10'd320;
            janela_altura_visivel <= 10'd240;
            offset_leitura_x <= 10'd0;
            offset_leitura_y <= 10'd0;
        end else if (start) begin
            // Armazena dimensões processadas
            largura_processada <= largura_calc;
            altura_processada <= altura_calc;
				// Posição da janela FIXA na tela
				janela_x_screen <= x_offset + janela_x_inicio;  // 160 + 50 = 210
            janela_y_screen <= y_offset + janela_y_inicio;
            
            if (SW == REPLICACAO || SW == VIZINHO_PROXIMO) begin
                // ===== ZOOM IN =====
                // Janela visível mantém tamanho original
                janela_largura_visivel <= janela_largura;
                janela_altura_visivel <= janela_altura;
                
                // ✅ Offset para ler do CENTRO da imagem ampliada
                offset_leitura_x <= (largura_calc > {1'b0, janela_largura}) ? 
                                    ((largura_calc - {1'b0, janela_largura}) >> 1) : 10'd0;
                offset_leitura_y <= (altura_calc > {2'b0, janela_altura}) ? 
                                    ((altura_calc - {2'b0, janela_altura}) >> 1) : 10'd0;
            end 
            else if (SW == DECIMACAO || SW == MEDIA_BLOCOS) begin
                // ===== ZOOM OUT =====
                // ✅ Janela visível = tamanho da imagem processada (menor)
                janela_largura_visivel <= largura_calc[9:0];
                janela_altura_visivel <= altura_calc[9:0];
                
                // Sem offset de leitura (lê tudo da RAM2)
                offset_leitura_x <= 10'd0;
                offset_leitura_y <= 10'd0;
            end
        end
    end

    // ========================================
    // ENDEREÇAMENTO DA IMAGEM ORIGINAL
    // ========================================
    wire [16:0] rom_addr_original;
    assign rom_addr_original = (next_y - y_offset) * LARGURA_ORIGINAL + (next_x - x_offset);

    assign rom_addr_top = (operacao_ativa) ? rom_addr_redim : rom_addr_original;

    // ========================================
    // CONTROLE DE EXIBIÇÃO
    // ========================================
    reg exibe_imagem;
    always @(posedge clock_25 or negedge reset) begin
        if (!reset) 
            exibe_imagem <= 1'b0;
        else if (start) 
            exibe_imagem <= 1'b0;
        else if (done_redim)
            exibe_imagem <= 1'b1;
    end

    // ========================================
    // ✅ LÓGICA VGA COM CENTRALIZAÇÃO CORRIGIDA
    // ========================================
    wire [9:0] next_x, next_y;
    
    wire in_original_bounds = (next_x >= x_offset) && 
                              (next_x < (x_offset + LARGURA_ORIGINAL)) &&
                              (next_y >= y_offset) && 
                              (next_y < (y_offset + ALTURA_ORIGINAL));
    
    wire in_janela_bounds = (next_x >= janela_x_screen) && 
                            (next_x < (janela_x_screen + janela_largura_visivel)) &&
                            (next_y >= janela_y_screen) && 
                            (next_y < (janela_y_screen + janela_altura_visivel));

    wire [9:0] pixel_x_rel = next_x - janela_x_screen;
    wire [9:0] pixel_y_rel = next_y - janela_y_screen;
    
    // ✅ Para Zoom In: adiciona offset para ler do CENTRO da imagem ampliada
    // ✅ Para Zoom Out: sem offset (lê direto, pois janela já está reposicionada)
    wire [9:0] pixel_x_ajustado = pixel_x_rel + offset_leitura_x;
    wire [9:0] pixel_y_ajustado = pixel_y_rel + offset_leitura_y;
    
    wire pixel_dentro_processada = (pixel_x_ajustado < largura_processada[9:0]) && 
                                    (pixel_y_ajustado < altura_processada[9:0]);

    // ✅ ENDEREÇO NA RAM2 COM OFFSET
    wire [20:0] ram_addr_vga;
    assign ram_addr_vga = pixel_y_ajustado * largura_processada + pixel_x_ajustado;

    // Multiplexação RAM2
    assign EnderecoRAM = (exibe_imagem) ? ram_addr_vga : ram_addr_redim;
    assign ram_data_in = (exibe_imagem) ? 8'd0 : pixel_out_redim;
    assign wren_ram = (exibe_imagem) ? 1'b0 : wren_redim;

    // ========================================
    // CURSOR DO MOUSE
    // ========================================
    localparam [9:0] OFFSET_X = 10'd160;
    localparam [9:0] OFFSET_Y = 10'd120;
    localparam [9:0] CURSOR_SIZE = 10'd3;

    wire [9:0] cursor_vga_x = mouse_x_sync2 + OFFSET_X;
    wire [9:0] cursor_vga_y = mouse_y_sync2 + OFFSET_Y;

    reg [9:0] mouse_x_sync1, mouse_x_sync2;
    reg [9:0] mouse_y_sync1, mouse_y_sync2;

    always @(posedge clock_25 or negedge reset) begin
        if (!reset) begin
            mouse_x_sync1 <= 10'd160;
            mouse_x_sync2 <= 10'd160;
            mouse_y_sync1 <= 10'd120;
            mouse_y_sync2 <= 10'd120;
        end else begin
            mouse_x_sync1 <= mouse_x;
            mouse_x_sync2 <= mouse_x_sync1;
            mouse_y_sync1 <= mouse_y;
            mouse_y_sync2 <= mouse_y_sync1;
        end
    end

    wire in_cursor = (next_x >= cursor_vga_x) && (next_x < cursor_vga_x + CURSOR_SIZE) &&
                     (next_y >= cursor_vga_y) && (next_y < cursor_vga_y + CURSOR_SIZE);

    localparam [7:0] CURSOR_COLOR = 8'hFF;
      
    // Prioridade de exibição
    wire [7:0] out_vga;
    assign out_vga = (exibe_imagem && in_janela_bounds && pixel_dentro_processada) ? saida_RAM :
                     (in_original_bounds) ? rom_pixel : 
                     8'h00;
      
    // Pixel final: cursor sobrescreve out_vga
    wire [7:0] pixel_final;
    assign pixel_final = in_cursor ? CURSOR_COLOR : out_vga;

    // ========================================
    // FSM PRINCIPAL
    // ========================================
    always @(posedge clock_25 or negedge reset) begin
        if (!reset) begin
            estado <= INICIO;
            prox_estado <= INICIO;
            Tipo_redmn <= REPLICACAO;
            operacao_ativa <= 1'b0;
            ready <= 1'b0;
        end else begin
            estado <= prox_estado;
            
            case (estado)
                INICIO: begin
                    ready <= 1'b0;
                    prox_estado <= INICIO;
                    if (start && !operacao_ativa) begin
                        operacao_ativa <= 1'b1;
                        Tipo_redmn <= SW;
                        prox_estado <= EXECUTE;
                    end
                end
                
                EXECUTE: begin
                    prox_estado <= CHECK;
                end
                
                CHECK: begin
                    if (done_redim) begin
                        operacao_ativa <= 1'b0;
                        ready <= 1'b1;
                        prox_estado <= INICIO;
                    end else 
                        prox_estado <= CHECK;
                end
                
                default: prox_estado <= INICIO;
            endcase
        end
    end

    vga_driver draw (
        .clock(clock_25),
        .reset(!reset),
        .color_in(pixel_final),
        .next_x(next_x),
        .next_y(next_y),
        .hsync(hsync),
        .vsync(vsync),
        .red(vga_r),
        .green(vga_g),
        .blue(vga_b),
        .sync(sync),
        .clk(clk),
        .blank(blank)
    );

endmodule