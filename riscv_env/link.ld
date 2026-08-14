/* Claude wrote this
 * Link at address 0: the core's PC resets to 0 and both memories decode
 * the low 16 address bits, so the whole image (code + data) must fit in
 * 64 KB. The same image is loaded into imem and dmem by the testbench to
 * fake a unified memory. */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x0;
  .text.init : { *(.text.init) }
  .text      : { *(.text) }
  . = ALIGN(8);
  .data      : { *(.data) *(.data*) }
  .bss       : { *(.bss) *(.sbss*) }
  _end = .;

  /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
