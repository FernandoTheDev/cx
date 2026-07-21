ENTRY(_start_trampoline)
OUTPUT_FORMAT("binary")

SECTIONS
{
    /* Diz ao linker que o bootloader carrega tudo em 0x1000 */
    . = 0x1000;

    .text : ALIGN(4) {
        /* Garante que o trampolim seja literalmente o primeiro byte */
        entry.o(.text)
        *(.text)
        *(.text.*)
    }

    .rodata : ALIGN(4) {
        *(.rodata)
        *(.rodata.*)
    }

    .data : ALIGN(4) {
        *(.data)
    }

    .bss : ALIGN(4) {
        *(COMMON)
        *(.bss)
    }
}
