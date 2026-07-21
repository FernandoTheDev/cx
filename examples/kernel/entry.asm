bits 32
section .text
global _start_trampoline
extern _start    ; Referência para a função gerada pelo CX/C

_start_trampoline:
    call _start  ; Pula com segurança para o kernel
    cli          ; Se o kernel retornar (não deveria), desabilita interrupções
    hlt          ; Trava a CPU
    jmp $
