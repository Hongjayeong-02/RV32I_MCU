/* RV32I MCU linker script (spec 7, 9)
 *   ROM 4 KB @ 0x0000_0000 : .text .rodata, and the load image of .data
 *   RAM 1 KB @ 0x1000_0000 : .data .bss, stack grows down from the top */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY
{
        ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
        RAM (rw)  : ORIGIN = 0x10000000, LENGTH = 1K
}
SECTIONS
{
        .text : {
                KEEP(*(.text.init))
                *(.text .text.*)
        } > ROM
        .rodata : {
                *(.rodata .rodata.* .srodata .srodata.*)
                . = ALIGN(4);
        } > ROM
        .data : {
                __data_start = .;
                *(.data .data.* .sdata .sdata.*)
                . = ALIGN(4);
                __data_end = .;
        } > RAM AT > ROM
        __data_load = LOADADDR(.data);
        .bss (NOLOAD) : {
                __bss_start = .;
                *(.bss .bss.* .sbss .sbss.* COMMON)
                . = ALIGN(4);
                __bss_end = .;
        } > RAM
        __stack_top = ORIGIN(RAM) + LENGTH(RAM);
        /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame*) }
}
