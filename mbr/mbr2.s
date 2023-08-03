SECTION MBR vstart=0x7c00
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov sp, 0x7c00
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

    mov byte [gs : 0x00], '1'
    mov byte [gs: 0x01], 0xa4

    mov byte [gs : 0x02], ' '
    mov byte [gs: 0x03], 0xa4

    mov byte [gs : 0x04], 'M'
    mov byte [gs: 0x05], 0xa4

    mov byte [gs : 0x06], 'B'
    mov byte [gs: 0x07], 0xa4

    mov byte [gs : 0x08], 'R'
    mov byte [gs: 0x09], 0xa4

    jmp $

    times ($ - $$) db 0
    db 0x55, 0xaa

