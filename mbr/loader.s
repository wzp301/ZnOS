%include "boot.inc"
SECTION MBR vstart=LOADER_BASE_ADDR
    mov ax, 0xb800
    mov gs, ax

; clear screen
; use 0x06 
; input:
; AH function number : 0x06
; AL up roll rows (0 means all)
;  BH : up roll row property
    mov ax, 0600h
    mov bx, 0700h
    mov cx, 0   ; up lift (0, 0)
    mov dx, 184fh ; (80, 25)
    int 10h

    mov byte [gs : 0x00], '2'
    mov byte [gs: 0x01], 0xa4

    mov byte [gs : 0x02], ' '
    mov byte [gs: 0x03], 0xa4

    mov byte [gs : 0x04], 'L'
    mov byte [gs: 0x05], 0xa4

    mov byte [gs : 0x06], '0'
    mov byte [gs: 0x07], 0xa4

    mov byte [gs : 0x08], 'A'
    mov byte [gs: 0x09], 0xa4

    mov byte [gs : 0x0a], 'D'
    mov byte [gs: 0x0b], 0xa4

    mov byte [gs : 0x0c], 'E'
    mov byte [gs: 0x0d], 0xa4

    mov byte [gs : 0x0e], 'R'
    mov byte [gs: 0x0f], 0xa4
    jmp $

