@PIOS ADDR
.equ PIO_INSTRUCT,         0x00  
.equ PIO_START,            0x30
.equ PIO_DONE,             0x20
.equ PIO_RESET,            0x40
.equ PIO_JANELA_POS,       0x50  
.equ PIO_JANELA_DIM,       0x60
.equ PIO_COORDS_MOUSE,     0x70



@tamanho da ram
.equ VRAM_MAX_ADDR,     76800

@opcodes - 2 BITS (compatível com SW[1:0] do Verilog)
.equ OPCODE_REPLICACAO, 0x00   @ 2'b00
.equ OPCODE_DECIMACAO,  0x01   @ 2'b01
.equ OPCODE_NHI,        0x02   @ 2'b10
.equ OPCODE_MEDIA,      0x03   @ 2'b11

@timeouts dos algoritmos
.equ TIMEOUT_COUNT,     0x0

.section .rodata

.LC0:           .asciz "/dev/mem"

.LC1:           .asciz "ERROR: could not open '/dev/mem' ...\n"

.LC2:           .asciz "ERROR: mmap() failed ...\n"

.LC3:           .asciz "ERROR: munmap() failed ...\n"


.section .data

FPGA_ADRS:

    .space 4

FILE_DESCRIPTOR:

    .space 4

LW_SPAM:

    .word 0x1000

LW_BASE:

    .word 0xff200

MASK_ADDR:
    .word 0x000FFFE0

@ Valor de 3,000,000 para Timeout
TIMEOUT_VAL:
    .word 3000000


.text

.global iniciarAPI

.type iniciarAPI, %function


iniciarAPI:

    PUSH    {r4-r7, lr}


    LDR      r0, =.LC0

    LDR      r1, =4098

    MOV      r2, #0

    MOV      r7, #5



.L_MMAP_Call:

    SVC      0

    MOV      r4, r0



    LDR      r1, =FILE_DESCRIPTOR

    STR      r4, [r1]



    CMP      r4, #-1

    BNE      .L_MMAP_Setup



    LDR      r0, =.LC1

    BL       puts

    MOV      r0, #-1

    B        .L_Return_init



.L_MMAP_Setup:

    MOV      r0, #0



    LDR      r1, =LW_SPAM

    LDR      r1, [r1]



    MOV      r2, #3

    MOV      r3, #1



    LDR      r4, =FILE_DESCRIPTOR

    LDR      r4, [r4]



    LDR      r5, =LW_BASE

    LDR      r5, [r5]



    MOV      r7, #192



    SVC      0



    MOV      r4, r0

    LDR      r1, =FPGA_ADRS

    STR      r4, [r1]



    CMP      r4, #-1

    BNE      .L_Success_init



    LDR      r0, =.LC2

    BL       puts



    LDR      r0, =FILE_DESCRIPTOR

    LDR      r0, [r0]

    BL       close

    MOV      r0, #-1

    B        .L_Return_init



.L_Success_init:

    MOV      r0, #0



.L_Return_init:

    POP      {r4-r7, pc}

.size iniciarAPI, .-iniciarAPI



.global encerrarAPI

.type encerrarAPI, %function

encerrarAPI:

    PUSH    {r4-r7, lr}



    LDR      r0, =FPGA_ADRS

    LDR      r0, [r0]



    LDR      r1, =LW_SPAM

    LDR      r1, [r1]



    MOV      r7, #91

    SVC      0

    MOV      r4, r0



    CMP      r4, #0

    BEQ      .L_Close_Call



    LDR      r0, =.LC3

    BL       puts



    MOV      r0, #-1

    B        .L_Return_end



.L_Close_Call:

    LDR      r0, =FILE_DESCRIPTOR

    LDR      r0, [r0]



    MOV      r7, #6

    SVC      0



    MOV      r0, #0



.L_Return_end:

    POP      {r4-r7, pc}

.size encerrarAPI, .-encerrarAPI

.global write_pixel
.type write_pixel, %function
write_pixel:
    push    {r4-r6, lr}
    ldr     r4, =FPGA_ADRS
    ldr     r4, [r4]
   
    @ Validação de endereço: 19 bits de endereço suportam até 524288 (0x80000)
    ldr     r5, =524288
    cmp     r0, r5
    bhs     .L_INVALID_ADDR

.L_PACK_DATA:
    @ ============================================
    @ ✅ NOVO EMPACOTAMENTO (Adaptado ao Gráfico com WREN no Bit 4)
    @ Estrutura: [31:24]=D[7:0], [23:5]=A[18:0], [4]=WREN, [3:0]=CTRL
    @ ============================================
   
    @ 1. Empacota o Endereço (R0 - 19 bits) -> bits [23:5]
    lsl     r2, r0, #5            @ addr[18:0] -> bits[23:5] (Shift de 5)
    ldr     r6, =0x00FFFFFE0      @ Máscara para bits[23:5] (19 bits)
    and     r2, r2, r6
   
    @ 2. Empacota o Pixel Data (R1 - 8 bits) -> bits [31:24]
    lsl     r3, r1, #24           @ pixel[7:0] -> bits[31:24] (Shift de 24)
    and     r3, r3, #0xFF000000   @ Máscara para bits [31:24] (8 bits)
    orr     r2, r2, r3
   
    @ 3. Adiciona SolicitaEscrita no bit 4 (Conforme o Diagrama Gráfico)
    mov     r3, #16               @ SolicitaEscrita no bit 4 (2^4 = 16 = 0x10)
    orr     r2, r2, r3
   
    @ Envia com SolicitaEscrita = 1
    str     r2, [r4, #PIO_INSTRUCT]
    dmb     sy
   
    @ ============================================
    @ Limpa SolicitaEscrita (bit 4)
    @ ============================================
    mov     r3, #16
    bic     r2, r2, r3            @ Limpa o bit 4 (SolicitaEscrita = 0)
   
    str     r2, [r4, #PIO_INSTRUCT]
    dmb     sy
   
    mov     r0, #0                @ Sucesso
    b       .L_EXIT

.L_INVALID_ADDR:
    mov     r0, #-1

.L_EXIT:
    pop     {r4-r6, pc}
.size write_pixel, .-write_pixel


@FUNÇÃO REPLICACAO
.global replicacao
.type replicacao, %function
replicacao:
    @ r0 = zoom (0-3: 1x, 2x, 4x, 8x)
   
    PUSH {r4-r6, lr}
    LDR r4, =FPGA_ADRS
    LDR r4, [r4]              @ r4 = base da ponte FPGA

empacotamento_instrucao_replic:
    MOV r2, #OPCODE_REPLICACAO  @ 0x00 (2 bits)
   
    AND r0, r0, #0x03         @ Garante que zoom está em 2 bits
    LSL r3, r0, #2            @ Desloca zoom para bits[3:2]
    ORR r2, r2, r3            @ Junta opcode[1:0] com zoom[3:2]
   
    STR r2, [r4, #PIO_INSTRUCT]
    DMB                        @ Garante sincronização

    @ Envia pulso de START
    MOV r2, #1
    STR r2, [r4, #PIO_START]
    DMB
    MOV r2, #0
    STR r2, [r4, #PIO_START]
    DMB

    @ Aguarda o DONE do FPGA com timeout adequado (CORREÇÃO APLICADA)
    LDR r5, =TIMEOUT_VAL      @ Carrega o endereço da constante 3000000
    LDR r5, [r5]              @ Carrega o valor

.LOOP_LE_DONE_REPLIC:
    LDR r2, [r4, #PIO_DONE]
    TST r2, #1
    BNE .L_SUCCESS_REPLIC

    SUBS r5, r5, #1
    BNE .LOOP_LE_DONE_REPLIC

    @ Timeout expirado
    MOV r0, #-2               @ Erro: timeout
    B .EXIT_REPLIC

.L_SUCCESS_REPLIC:
    MOV r0, #0                @ Sucesso

.EXIT_REPLIC:
    POP {r4-r6, pc}

.size replicacao, .-replicacao


@FUNÇÃO DECIMACAO
.global decimacao
.type decimacao, %function
decimacao:
    @ r0 = zoom (0-3: 1x, 2x, 4x, 8x)
   
    PUSH {r4-r6, lr}
    LDR r4, =FPGA_ADRS
    LDR r4, [r4]

empacotamento_instrucao_dec:
    MOV r2, #OPCODE_DECIMACAO
   
    AND r0, r0, #0x03
    LSL r3, r0, #2
    ORR r2, r2, r3
   
    STR r2, [r4, #PIO_INSTRUCT]
    DMB

    MOV r2, #1
    STR r2, [r4, #PIO_START]
    DMB
    MOV r2, #0
    STR r2, [r4, #PIO_START]
    DMB

    @ Aguarda o DONE do FPGA com timeout adequado (CORREÇÃO APLICADA)
    LDR r5, =TIMEOUT_VAL      
    LDR r5, [r5]              

.LOOP_LE_DONE_DEC:
    LDR r2, [r4, #PIO_DONE]
    TST r2, #1
    BNE .L_SUCCESS_DEC

    SUBS r5, r5, #1
    BNE .LOOP_LE_DONE_DEC

    MOV r0, #-2
    B .EXIT_DEC

.L_SUCCESS_DEC:
    MOV r0, #0

.EXIT_DEC:
    POP {r4-r6, pc}

.size decimacao, .-decimacao


@FUNÇÃO NHI (VIZINHO MAIS PRÓXIMO)
.global NHI
.type NHI, %function
NHI:
    @ r0 = zoom (0-3: 1x, 2x, 4x, 8x)
   
    PUSH {r4-r6, lr}
    LDR r4, =FPGA_ADRS
    LDR r4, [r4]

empacotamento_instrucao_nhi:
    MOV r2, #OPCODE_NHI
   
    AND r0, r0, #0x03
    LSL r3, r0, #2
    ORR r2, r2, r3
   
    STR r2, [r4, #PIO_INSTRUCT]
    DMB

    MOV r2, #1
    STR r2, [r4, #PIO_START]
    DMB
    MOV r2, #0
    STR r2, [r4, #PIO_START]
    DMB

    @ Aguarda o DONE do FPGA com timeout adequado (CORREÇÃO APLICADA)
    LDR r5, =TIMEOUT_VAL      
    LDR r5, [r5]              

.LOOP_LE_DONE_NHI:
    LDR r2, [r4, #PIO_DONE]
    TST r2, #1
    BNE .L_SUCCESS_NHI

    SUBS r5, r5, #1
    BNE .LOOP_LE_DONE_NHI

    MOV r0, #-2
    B .EXIT_NHI

.L_SUCCESS_NHI:
    MOV r0, #0

.EXIT_NHI:
    POP {r4-r6, pc}

.size NHI, .-NHI


@FUNÇÃO MÉDIA DE BLOCOS
.global media_blocos
.type media_blocos, %function
media_blocos:
    @ r0 = zoom (0-3: 1x, 2x, 4x, 8x)
   
    PUSH {r4-r6, lr}
    LDR r4, =FPGA_ADRS
    LDR r4, [r4]

empacotamento_instrucao_med:
    MOV r2, #OPCODE_MEDIA
   
    AND r0, r0, #0x03
    LSL r3, r0, #2
    ORR r2, r2, r3
   
    STR r2, [r4, #PIO_INSTRUCT]
    DMB

    MOV r2, #1
    STR r2, [r4, #PIO_START]
    DMB
    MOV r2, #0
    STR r2, [r4, #PIO_START]
    DMB

    @ Aguarda o DONE do FPGA com timeout adequado (CORREÇÃO APLICADA)
    LDR r5, =TIMEOUT_VAL      
    LDR r5, [r5]              

.LOOP_LE_DONE_MED:
    LDR r2, [r4, #PIO_DONE]
    TST r2, #1
    BNE .L_SUCCESS_MED

    SUBS r5, r5, #1
    BNE .LOOP_LE_DONE_MED

    MOV r0, #-2
    B .EXIT_MED

.L_SUCCESS_MED:
    MOV r0, #0

.EXIT_MED:
    POP {r4-r6, pc}

.size media_blocos, .-media_blocos



@FUNÇÃO FLAG_DONE
.global Flag_Done
.type Flag_Done, %function
Flag_Done:
    push    {r7, lr}
   
    ldr     r3, =FPGA_ADRS
    ldr     r3, [r3]
   
    ldr     r0, [r3, #PIO_DONE]
   
   
    pop     {r7, pc}

.size Flag_Done, .-Flag_Done

.global reset_system
.type reset_system, %function

reset_system:
push {r4, lr}

@ Carrega endereço base da FPGA
ldr r4, =FPGA_ADRS
ldr r4, [r4]

@ Ativa reset (LOW)
mov r0, #0
str r0, [r4, #PIO_RESET]
dmb sy

@Pequeno delay (alguns ciclos)
@mov r0, #100 @ Contador de delay
@.delay_loop:
@subs r0, r0, #1
@bne .delay_loop

@ Desativa reset (HIGH)
mov r0, #1
str r0, [r4, #PIO_RESET]
dmb sy

mov r0, #0 @ Retorna sucesso
pop {r4, pc}

.size reset_system, .-reset_system

.global set_janela
.type set_janela, %function
set_janela:
 
    push {r4-r5, lr}
    ldr r4, =FPGA_ADRS
    ldr r4, [r4]
   
    @ Empacota PIO_JANELA_POS
    and r0, r0, #0xFF        @ Garante 9 bits para x_inicio
    and r1, r1, #0xFF         @ Garante 8 bits para y_inicio
    lsl r5, r1, #9            @ Desloca y_inicio para bits[16:9]
    orr r5, r5, r0            @ Junta x_inicio[8:0] e y_inicio[16:9]
   
    str r5, [r4, #PIO_JANELA_POS]
    dmb sy
   
    @ Empacota PIO_JANELA_DIM
    and r2, r2, #0xFF        @ Garante 9 bits para largura
    and r3, r3, #0xFF         @ Garante 8 bits para altura
    lsl r5, r3, #9            @ Desloca altura para bits[16:9]
    orr r5, r5, r2            @ Junta largura[8:0] e altura[16:9]
   
    str r5, [r4, #PIO_JANELA_DIM]
    dmb sy
   
    mov r0, #0                @ Retorna sucesso
    pop {r4-r5, pc}
.size set_janela, .-set_janela


.global write_mouse_coords
.type write_mouse_coords, %function
write_mouse_coords:
    push    {r4-r5, lr}
    ldr     r4, =FPGA_ADRS
    ldr     r4, [r4]             @ r4 = Base da ponte FPGA
   
   
    ldr     r5, =0x3FF           @ Máscara para 10 bits
    and     r0, r0, r5           @ Máscara X (r0)
    and     r1, r1, r5           @ Máscara Y (r1)
   
    @ Empacota Y (r1) -> bits [19:10]
    lsl     r5, r1, #10          @ y_coords << 10
   
    @ Empacota X (r0) -> bits [9:0]
    orr     r5, r5, r0           @ Junta (Y << 10) | X. O resultado fica em r5.
   
 
    str     r5, [r4, #PIO_COORDS_MOUSE]
    dmb     sy                   @ Garante a escrita
   
    mov     r0, #0               @ Retorna sucesso
    pop     {r4-r5, pc}

.size write_mouse_coords, .-write_mouse_coords

.section .note.GNU-stack,"",%progbits