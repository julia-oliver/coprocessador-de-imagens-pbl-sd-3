#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include "header.h"
#include <unistd.h>
#include "hps_0.h"
#include <sys/mman.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <linux/input.h>
#include <signal.h>
#include <math.h>
#include <time.h>
#include <termios.h> // Para controle do terminal

// ========================================
// >>>>> CONFIGURAÇÃO DO MOUSE (EVDEV) <<<<<
// ========================================
#define MOUSE_DEVICE "/dev/input/event0"

// Dimensões do buffer de imagem original
const int LARGURA_IMG = 320;
const int ALTURA_IMG = 240;

// Posição atual do cursor global (rastreada pelo Evdev)
int g_cursor_x = 160;
int g_cursor_y = 120;

// Variável para sinalizar a saída do loop do mouse
volatile sig_atomic_t continuar_execucao = 1;

int g_nivel_zoom_atual = 0;

// ========================================
// CONFIGURAÇÕES DE TERMINAL
// ========================================
struct termios termios_original;

// ========================================
// FUNÇÕES DA API
// ========================================
extern int iniciarAPI();
extern int encerrarAPI();
extern int NHI(int zoom);
extern int replicacao(int zoom);
extern int decimacao(int zoom);
extern int media_blocos(int zoom);
extern int Flag_Done();
extern void write_pixel(int address, unsigned char pixel_data);
extern int reset_system();
extern int set_janela(int x_inicio, int y_inicio, int largura, int altura);
extern int write_mouse_coords(int x, int y);

//Declarações das funções de controle de terminal
void disable_raw_mode();
void enable_raw_mode();
int kbhit();
char getch_nonblock();

#pragma pack(push, 1)
typedef struct {
    uint16_t type;
    uint32_t size;
    uint16_t reserved1;
    uint16_t reserved2;
    uint32_t offset;
} BMPHeader;

typedef struct {
    uint32_t size;
    int32_t width;
    int32_t height;
    uint16_t planes;
    uint16_t bits_per_pixel;
    uint32_t compression;
    uint32_t image_size;
    int32_t x_pixels_per_meter;
    int32_t y_pixels_per_meter;
    uint32_t colors_used;
    uint32_t colors_important;
} BMPInfoHeader;
#pragma pack(pop)

// ========================================
// FUNÇÕES PARA CONTROLE DO TERMINAL
// ========================================

// Desabilita o modo raw do terminal
void disable_raw_mode() {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &termios_original);
}

// Habilita o modo raw do terminal (sem echo, leitura imediata)
void enable_raw_mode() {
    tcgetattr(STDIN_FILENO, &termios_original);
    atexit(disable_raw_mode);

    struct termios raw = termios_original;
    raw.c_lflag &= ~(ECHO | ICANON); // Desabilita echo e modo canônico
    raw.c_cc[VMIN] = 0; // Retorna imediatamente
    raw.c_cc[VTIME] = 0; 

    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
}

// Verifica se há tecla pressionada
int kbhit() {
    struct timeval tv = { 0L, 0L };
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(STDIN_FILENO, &fds);
    return select(STDIN_FILENO + 1, &fds, NULL, NULL, &tv) > 0;
}

// Lê um caractere sem bloquear
char getch_nonblock() {
    char c = 0;
    if (read(STDIN_FILENO, &c, 1) < 0) {
        return 0;
    }
    return c;
}

// Função para tratar o sinal SIGINT (Ctrl+C)
void sigint_handler(int signum) {
    continuar_execucao = 0;
}

// Função para carregar e enviar imagem BMP
int enviar_imagem_bmp(const char *nome_arquivo) {
    FILE *arquivo = fopen(nome_arquivo, "rb");
    if (!arquivo) {
        printf("ERRO: Não foi possível abrir o arquivo '%s'\n", nome_arquivo);
        return -1;
    }

    BMPHeader cabecalho;
    BMPInfoHeader info_cabecalho;

    fread(&cabecalho, sizeof(BMPHeader), 1, arquivo);
    fread(&info_cabecalho, sizeof(BMPInfoHeader), 1, arquivo);

    if (cabecalho.type != 0x4D42) {
        printf("ERRO: Arquivo não é um BMP válido!\n");
        fclose(arquivo);
        return -1;
    }

    if (info_cabecalho.width != LARGURA_IMG || info_cabecalho.height != ALTURA_IMG) {
        printf("AVISO: Imagem precisa ter %dx%d pixels!\n", LARGURA_IMG, ALTURA_IMG);
        printf("Dimensões encontradas: %dx%d\n", info_cabecalho.width, info_cabecalho.height);
        fclose(arquivo);
        return -1;
    }

    fseek(arquivo, cabecalho.offset, SEEK_SET);

    int bytes_por_pixel = info_cabecalho.bits_per_pixel / 8;
    int tamanho_linha = info_cabecalho.width * bytes_por_pixel;
    int preenchimento = (4 - (tamanho_linha % 4)) % 4;

    printf("\nEnviando imagem...\n");

    unsigned char *buffer_linha = (unsigned char*)malloc(tamanho_linha);
    if (!buffer_linha) {
        printf("ERRO: Falha ao alocar memória!\n");
        fclose(arquivo);
        return -1;
    }

    int pixels_totais = info_cabecalho.width * info_cabecalho.height;
    int contador_pixel = 0;

    for(int y = info_cabecalho.height - 1; y >= 0; y--) {
        fseek(arquivo, cabecalho.offset + y * (tamanho_linha + preenchimento), SEEK_SET);
        fread(buffer_linha, 1, tamanho_linha, arquivo);

        for(int x = 0; x < info_cabecalho.width; x++) {
            unsigned char pixel_data;

            if (info_cabecalho.bits_per_pixel == 8) {
                pixel_data = buffer_linha[x];
            }
            else if (info_cabecalho.bits_per_pixel == 24) {
                int idx = x * 3;
                unsigned char b = buffer_linha[idx];
                unsigned char g = buffer_linha[idx + 1];
                unsigned char r = buffer_linha[idx + 2];
                pixel_data = (r + g + b) / 3;
            }
            else {
                printf("ERRO: Formato de pixel não suportado (%d bits)\n", info_cabecalho.bits_per_pixel);
                free(buffer_linha);
                fclose(arquivo);
                return -1;
            }

            int endereco = (info_cabecalho.height - 1 - y) * info_cabecalho.width + x;
            write_pixel(endereco, pixel_data);
            contador_pixel++;

            if(contador_pixel % 1000 == 0) {
                float progresso = (contador_pixel * 100.0) / pixels_totais;
                printf("\rProgresso: %d/%d pixels (%.1f%%) ",
                        contador_pixel, pixels_totais, progresso);
                fflush(stdout);
            }
        }
    }

    printf("\rProgresso: %d/%d pixels (100.0%%) \n", pixels_totais, pixels_totais);
    printf("Imagem enviada com sucesso!\n");

    free(buffer_linha);
    fclose(arquivo);
    return 0;
}

// ========================================
// FUNÇÃO: Selecionar Janela com MOUSE
// ========================================
int selecionar_janela_mouse(int *x_inicio, int *y_inicio, int *largura, int *altura) {
    int descritor_arquivo; // Variável para armazenar o descritor de arquivo do dispositivo do mouse.
    struct input_event evento; // Estrutura para ler os eventos do mouse (movimento, clique).
    
    // Variáveis de estado do mouse - agora gerenciadas dentro do loop de validação
    int ponto_x[2]; 
    int ponto_y[2]; 
    int ponto_atual; 

    // Variáveis de controle para forçar re-seleção e a dimensão mínima
    int validacao_sucesso = 0; // Flag que indica se a seleção atendeu aos critérios de dimensão.
    const int MIN_DIM = 50; // Dimensão mínima: 50x50
    const int MAX_DIM = 180; // Dimensão máxima: 180x180

    const struct timespec requisicao = {
        .tv_sec = 0,
        .tv_nsec = 10000 * 1000
    };

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sigint_handler;
    sigaction(SIGINT, &sa, NULL);

    // Abre o dispositivo do mouse em modo não bloqueante (O_NONBLOCK)
    descritor_arquivo = open(MOUSE_DEVICE, O_RDONLY | O_NONBLOCK);
    if (descritor_arquivo == -1) {
        perror("ERRO ao abrir o dispositivo do mouse");
        fprintf(stderr, "Verifique o caminho: %s. Tente usar 'sudo' ou outro eventX.\n", MOUSE_DEVICE);
        return -1;
    }

    printf("\n╔═════════════════════════════════════╗\n");
    printf("║ SELEÇÃO DE JANELA (MOUSE) ║\n");
    printf("╠═════════════════════════════════════╣\n");
    printf("║ Imagem base: %dx%d pixels ║\n", LARGURA_IMG, ALTURA_IMG);
    printf("║ Dimensão Mínima Requerida: > %dx%d ║\n", MIN_DIM, MIN_DIM); // Informa a nova regra
    printf("║ Clique com o BOTÃO ESQUERDO duas vezes. ║\n");
    printf("║ Pressione Ctrl+C para cancelar. ║\n");
    printf("╚═════════════════════════════════════╝\n");

    // NOVO: Loop do-while para forçar a re-seleção se a validação de dimensão falhar
    do {
        // Zera o estado para cada tentativa de seleção
        ponto_atual = 0; // 0 para Ponto A, 1 para Ponto B
        ponto_x[0] = -1; ponto_x[1] = -1;
        ponto_y[0] = -1; ponto_y[1] = -1;
        continuar_execucao = 1;

        printf("Cursor Virtual: X=%d, Y=%d. Aguardando Ponto A...", g_cursor_x, g_cursor_y);
        fflush(stdout);
        
        // Loop principal de captura de eventos do mouse
        while (continuar_execucao && ponto_atual < 2) {
            // Tenta ler um evento do dispositivo
            ssize_t bytes_lidos = read(descritor_arquivo, &evento, sizeof(struct input_event));

            if (bytes_lidos == sizeof(struct input_event)) {
                if (evento.type == EV_REL) {
                    // Atualiza as coordenadas virtuais do cursor
                    if (evento.code == REL_X) {
                        g_cursor_x += evento.value; // Atualiza a posição X pela diferença lida.
                    } else if (evento.code == REL_Y) {
                        g_cursor_y += evento.value; // Atualiza a posição Y pela diferença lida.
                    }

                    //Limita as coordenadas do cursor para que fiquem dentro dos limites da imagem (0 a LARGURA_IMG-1 / ALTURA_IMG-1).
                    if (g_cursor_x < 0) g_cursor_x = 0;
                    if (g_cursor_x >= LARGURA_IMG) g_cursor_x = LARGURA_IMG - 1;
                    if (g_cursor_y < 0) g_cursor_y = 0;
                    if (g_cursor_y >= ALTURA_IMG) g_cursor_y = ALTURA_IMG - 1;


                    printf("\rCursor Virtual: X=%4d, Y=%4d. Ponto %s. ",
                            g_cursor_x, g_cursor_y, (ponto_atual == 0) ? "A" : "B");
                    fflush(stdout);

                    // Envia as coordenadas para o hardware
                    write_mouse_coords(g_cursor_x, g_cursor_y);
                }
                // Evento de clique de botão (EV_KEY)
                else if (evento.type == EV_KEY && evento.code == BTN_LEFT) {
                    if (evento.value == 1) { // Se o botão foi pressionado 
                        ponto_x[ponto_atual] = g_cursor_x; // Salva o ponto
                        ponto_y[ponto_atual] = g_cursor_y;

                        printf("\n%s Clicado em: (%d, %d)\n",
                                (ponto_atual == 0) ? "Ponto A" : "Ponto B",
                                g_cursor_x, g_cursor_y);

                        ponto_atual++;

                        if (ponto_atual == 1) {
                            printf("Aguardando Ponto B...");
                            fflush(stdout);
                        }
                    }
                }
            }
            else if (bytes_lidos == -1 && errno == EAGAIN) {
                nanosleep(&requisicao, NULL);
            } else if (bytes_lidos == -1 && errno != EINTR) {
                perror("Erro na leitura do Evdev");
                continuar_execucao = 0; // Sai do loop interno
                break;
            }
        } // Fim do loop de captura de 2 pontos

        if (ponto_atual < 2) {
            // Se saiu do loop porque 'continuar_execucao' foi 0 (Ctrl+C ou erro de Evdev)
            if (!continuar_execucao) {
                printf("\nSeleção de janela cancelada/interrompida.\n");
            }
            close(descritor_arquivo);
            return -1;
        }

        // Calcula as dimensões e o canto superior esquerdo da janela
        int x1 = ponto_x[0];
        int y1 = ponto_y[0];
        int x2 = ponto_x[1];
        int y2 = ponto_y[1];

        *x_inicio = (x1 < x2) ? x1 : x2;
        *y_inicio = (y1 < y2) ? y1 : y2;
        *largura = abs(x2 - x1);
        *altura = abs(y2 - y1);

        // 1. Verificação de largura/altura zero (verificação existente)
        if (*largura == 0 || *altura == 0) {
            printf("\nERRO: Janela não pode ter largura ou altura zero (%dx%d). Por favor, selecione novamente.\n", *largura, *altura);
            // validacao_sucesso = 0 -> loop continua
        }
        // 2. Verificação de dimensão mínima (NOVA REGRA: 50x50 ou menor)
        else if (*largura <= MIN_DIM && *altura <= MIN_DIM) {
            printf("\nERRO: A dimensão mínima de %dx%d pixels não foi atingida. Selecionado: %dx%d.\n",
                   MIN_DIM, MIN_DIM, *largura, *altura);
            printf("Ambas as dimensões devem ser estritamente maiores que %d para serem válidas. Por favor, selecione novamente.\n", MIN_DIM);
            // validacao_sucesso = 0 -> loop continua
        }
        // 3. Verificação de dimensão máxima (NOVA REGRA: > 180x180)
        else if (*largura > MAX_DIM || *altura > MAX_DIM) {
            printf("\nERRO: A dimensão máxima de %dx%d pixels foi excedida. Selecionado: %dx%d.\n",
                   MAX_DIM, MAX_DIM, *largura, *altura);
            printf("Nenhuma dimensão pode ser maior que %d. Por favor, selecione novamente.\n", MAX_DIM);
        }
        else {
            // Validação bem-sucedida
            validacao_sucesso = 1;
        }

    } while (!validacao_sucesso); // Repete se a validação falhar

    close(descritor_arquivo); // Fecha o descritor apenas após a validação ser bem-sucedida

    // Imprime o resultado final
    printf("\n╔═════════════════════════════════════╗\n");
    printf("║ JANELA SELECIONADA ║\n");
    printf("╠═════════════════════════════════════╣\n");
    printf("║ Posição inicial: (%d, %d)\n", *x_inicio, *y_inicio);
    printf("║ Dimensões: %dx%d pixels\n", *largura, *altura);
    printf("╚═════════════════════════════════════╝\n");

    return 0;
}

// ========================================
// FUNÇÃO: Modo Interativo de Zoom
// ========================================
int modo_zoom_interativo(int x_inicio, int y_inicio, int largura, int altura,
                             int algo_zoom_in, int algo_zoom_out) {

    printf("\n╔═════════════════════════════════════════════╗\n");
    printf("║ MODO INTERATIVO DE ZOOM ║\n");
    printf("╠═════════════════════════════════════════════╣\n");
    printf("║ Pressione '+' para Zoom In (magnificar) ║\n");
    printf("║ Pressione '-' para Zoom Out (reduzir) ║\n");
    printf("║ Pressione 'q' ou 'ESC' para sair ║\n");
    printf("╠═════════════════════════════════════════════╣\n");
    printf("║ Algoritmo Zoom In: %s ║\n",
             algo_zoom_in == 1 ? "Vizinho Próximo (NHI)" : "Replicação");
    printf("║ Algoritmo Zoom Out: %s ║\n",
             algo_zoom_out == 3 ? "Decimação" : "Média de Blocos");
    printf("╚═════════════════════════════════════════════╝\n");

    enable_raw_mode(); // Ativa o modo raw para captura imediata de teclas

    continuar_execucao = 1;

    // Configura o handler para Ctrl+C (SIGINT)
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sigint_handler;
    sigaction(SIGINT, &sa, NULL);

    printf("\nNível atual: %dx - Aguardando comando...\n", 1 << g_nivel_zoom_atual);
    fflush(stdout);

    while (continuar_execucao) {
        if (kbhit()) { // Verifica se há uma tecla pressionada (não bloqueante)
            char c = getch_nonblock();

            // ESC ou 'q' para sair
            if (c == 27 || c == 'q' || c == 'Q') {
                printf("\nSaindo do modo interativo...\n");
                break;
            }

            // Zoom In (+)
            else if (c == '+' || c == '=') {
                if (g_nivel_zoom_atual >= 2) {
                    // Limite máximo de zoom (4x)
                    printf("\rNível máximo (4x) atingido! Não é possível ampliar mais. \n");
                    printf("Nível atual: %dx - Aguardando comando...\n", 1 << g_nivel_zoom_atual);
                    fflush(stdout);
                    continue;
                }

                int zoom_real = g_nivel_zoom_atual + 1;
                int fator_zoom = 1 << zoom_real;
                
                // >>> VALIDAÇÃO DE LIMITE PARA ZOOM IN (Existente) <<<
                int limite_max = 0;
                if (zoom_real == 1) { // Próximo nível é 2x
                    limite_max = 180;
                } else if (zoom_real == 2) { // Próximo nível é 4x
                    limite_max = 130;
                }

                if (limite_max > 0 && (largura >= limite_max || altura >= limite_max)) {
                    printf("\rERRO: Dimensões da janela (%dx%d) são maiores ou iguais ao limite (%dx%d) para Zoom In %dx. \n",
                        largura, altura, limite_max, limite_max, fator_zoom);
                    printf("Nível atual: %dx - Aguardando comando...\n", 1 << g_nivel_zoom_atual);
                    fflush(stdout);
                    continue; // Aborta a operação de zoom
                }
                // >>> FIM: VALIDAÇÃO DE LIMITE PARA ZOOM IN <<<


                printf("\rAplicando Zoom In (%s) -> %dx... \n",
                        algo_zoom_in == 1 ? "NHI" : "Replicação", fator_zoom);
                fflush(stdout);

                int resultado;
                if (algo_zoom_in == 1) {
                    resultado = NHI(zoom_real);
                } else {
                    // A replicação sempre volta para 1x (zoom=0) antes de aplicar o novo zoom
                    resultado = replicacao(0); 
                    resultado = replicacao(zoom_real);
                }

                if (resultado == 0) {
                    g_nivel_zoom_atual = zoom_real;
                    printf("✓ Zoom aplicado com sucesso! Nível atual: %dx\n", 1 << g_nivel_zoom_atual);
                } else {
                    printf("✗ ERRO ao aplicar zoom (código: %d)\n", resultado);
                }

                printf("Nível atual: %dx - Aguardando comando...\n", 1 << g_nivel_zoom_atual);
                fflush(stdout);
            }

            // Zoom Out (-)
            else if (c == '-' || c == '_') {
                if (g_nivel_zoom_atual == 0) {
                    printf("\rNível mínimo (1x) atingido! Não é possível reduzir mais. \n");
                    printf("Nível atual: %dx - Aguardando comando...\n", 1 << g_nivel_zoom_atual);
                    fflush(stdout);
                    continue;
                }

                int fator_reducao = 1; // Sempre reduz de 1 nível (2x)
                int fator_reducao_real = 1 << fator_reducao;
                int novo_nivel_zoom = g_nivel_zoom_atual - fator_reducao;

                printf("\rAplicando Zoom Out (%s) -> redução %dx... \n",
                        algo_zoom_out == 3 ? "Decimação" : "Média Blocos", fator_reducao_real);
                fflush(stdout);

                int resultado;

                // Lógica de Zoom Out
                if (g_nivel_zoom_atual == 2) {
                    // Se estiver em 4x e reduzir, volta para 2x usando Replicação (zoom=1)
                    printf("\rAplicando Zoom Out: Reposicionando com Replicação para %dx... \n", 1 << novo_nivel_zoom);
                    resultado = replicacao(0); // Reseta
                    if (resultado == 0) {
                        resultado = replicacao(novo_nivel_zoom); // Aplica 2x
                    }
                } else {
                    // Decimação ou Média de Blocos para 2x -> 1x
                    if (algo_zoom_out == 3) {
                        resultado = decimacao(fator_reducao);
                    } else {
                        resultado = media_blocos(fator_reducao);
                    }
                }
            
                if (resultado == 0) {
                    g_nivel_zoom_atual = novo_nivel_zoom;
                    printf("✓ Redução aplicada com sucesso! Nível atual: %dx\n", 1 << g_nivel_zoom_atual);
                } else {
                    printf("✗ ERRO ao aplicar redução (código: %d)\n", resultado);
                }

                printf("Nível atual: %dx - Aguardando comando...\n", 1 << g_nivel_zoom_atual);
                fflush(stdout);
            }
        }

        usleep(50000); 
    }

    disable_raw_mode(); // Restaura as configurações originais do terminal
    return 0;
}

int main() {
    int opcao, resultado;
    int x_inicio, y_inicio, largura, altura;

    printf("\n=== INICIANDO API ===\n");

    int resultado_init = iniciarAPI(); // Inicia a comunicação com o hardware (FPGA)

    if (resultado_init != 0) {
        printf("ERRO ao iniciar API!\n");
        return 1;
    }

    printf("API OK!\n");
    reset_system(); // Garante que o sistema está em estado inicial

    do {
        printf("\n╔═════════════════════════════════════╗\n");
        printf("║ MENU PRINCIPAL ║\n");
        printf("╠═════════════════════════════════════╣\n");
        printf("║ [1]-> Modo Zoom Interativo (+/-) ║\n");
        printf("║ [2]-> Enviar imagem BMP (%dx%d) ║\n", LARGURA_IMG, ALTURA_IMG);
        printf("║ [3]-> Reset ║\n");
        printf("║ [4]-> Sair ║\n");
        printf("╚═════════════════════════════════════╝\n");
        printf("Nível de Zoom Atual: %dx\n", 1 << g_nivel_zoom_atual);
        printf("→ Opção: ");

        if (scanf("%d", &opcao) != 1) {
            printf("Entrada inválida!\n");
            while(getchar() != '\n');
            continue;
        }
        while(getchar() != '\n');

        switch (opcao) {
            case 1: {
                // PASSO 1: Selecionar janela
                printf("\nPasso 1: Selecione a janela com o mouse.\n");
                if (selecionar_janela_mouse(&x_inicio, &y_inicio, &largura, &altura) != 0) {
                    printf("Seleção de janela abortada. Voltando ao menu.\n");
                    break;
                }

                // PASSO 2: Enviar janela para o FPGA
                printf("\nEnviando janela para o FPGA...\n");
                if (set_janela(x_inicio, y_inicio, largura, altura) != 0) {
                    printf("ERRO ao enviar janela para o FPGA!\n");
                    break;
                }
                printf("Janela configurada com sucesso!\n");

                // PASSO 3: Escolher algoritmos
                int algo_zoom_in, algo_zoom_out;

                printf("\n╔═════════════════════════════════════╗\n");
                printf("║ ESCOLHA OS ALGORITMOS ║\n");
                printf("╠═════════════════════════════════════╣\n");
                printf("║ Algoritmo para Zoom In: ║\n");
                printf("║ [1] Vizinho Próximo (NHI) ║\n");
                printf("║ [2] Replicação ║\n");
                printf("╚═════════════════════════════════════╝\n");
                printf("→ Escolha: ");

                if (scanf("%d", &algo_zoom_in) != 1 || (algo_zoom_in != 1 && algo_zoom_in != 2)) {
                    printf("Opção inválida! Voltando ao menu.\n");
                    while(getchar() != '\n');
                    break;
                }
                while(getchar() != '\n');

                printf("\n╔═════════════════════════════════════╗\n");
                printf("║ Algoritmo para Zoom Out: ║\n");
                printf("║ [3] Decimação ║\n");
                printf("║ [4] Média de Blocos ║\n");
                printf("╚═════════════════════════════════════╝\n");
                printf("→ Escolha: ");

                if (scanf("%d", &algo_zoom_out) != 1 || (algo_zoom_out != 3 && algo_zoom_out != 4)) {
                    printf("Opção inválida! Voltando ao menu.\n");
                    while(getchar() != '\n');
                    break;
                }
                while(getchar() != '\n');

                // PASSO 4: Entrar no modo interativo
                modo_zoom_interativo(x_inicio, y_inicio, largura, altura,
                                     algo_zoom_in, algo_zoom_out);
                break;
            }

            case 2: {
                printf("\nDigite o caminho da imagem BMP (%dx%d): ", LARGURA_IMG, ALTURA_IMG);
                char nome_arquivo[256];
                if (scanf("%s", nome_arquivo) != 1) {
                    printf("Entrada inválida!\n");
                    while(getchar() != '\n');
                    break;
                }
                while(getchar() != '\n');

                if (enviar_imagem_bmp(nome_arquivo) == 0) {
                    printf("Imagem carregada na RAM1!\n");
                    g_nivel_zoom_atual = 0;
                    reset_system();
                    set_janela(0, 0, LARGURA_IMG, ALTURA_IMG);
                } else {
                    printf("ERRO ao carregar imagem!\n");
                }
                break;
            }

            case 3:
                reset_system();
                g_nivel_zoom_atual = 0;
                printf("Sistema resetado (Limpo)!\n");
                break;

            case 4:
                printf("\nSaindo...\n");
                break;

            default:
                printf("\nOpção inválida!\n");
        }
    } while (opcao != 4);

    printf("\nEncerrando API...");
    if (encerrarAPI() == 0) {
        printf(" OK!\n");
    } else {
        printf(" ERRO!\n");
    }

    return 0;
}