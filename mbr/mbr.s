%include "boot.inc"

SECTION MBR vstart=0x7c00
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov sp, 0x7c00
    mov ax, 0xb800
    mov gs, ax

    ; show text
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

    ; load section of disk
    mov eax, LOADER_START_SECTOR
    mov bx, LOADER_BASE_ADDR
    mov cx, 1
    call read_disk_m_16

    jmp LOADER_BASE_ADDR

;===============
; function : read_disk_m_16
read_disk_m_16:
    mov esi, eax    ; backup eax
    mov di, cx      ; backup cx
    
    ; set sector numbers for read
    mov dx, 0x1f2
    mov al, cl
    out dx, al

    mov eax, esi    ; recover eax

    ; set LBA address
    ; 0x1f3 -> 0~7bit
    mov dx, 0x1f3
    out dx, al

    ; 0x1f4> 8~15bit
    mov cl, 8
    shr eax, cl
    mov dx, 0x1f4
    out dx, al

    ; 0x1f5> 16~23bit
    shr eax, cl
    mov dx, 0x1f5
    out dx, al

     ; 0x1f6> 24~28bit, en_lba, master/slave mode
     shr eax, cl
    and al, 0x0f
    or al, 0xe0
    mov dx, 0x1f6
    out dx, al

    ; 0x1f7 : command addr
    mov dx, 0x1f7
    mov al, 0x20 ; set write mode
    out dx, al

; check status of disk
.not_ready:
    nop
    in al, dx ; dx=0x1f7, 
    and al, 0x88 ; bit4 : 1 is ready, bit8 : 1 is busy
    cmp al, 0x08
    jnz .not_ready ; disk is busy

    ; read data form 0x1f0
    mov ax, di
    mov dx, 256
    mul dx ; clac read count di * (512 / 2) = di * 256
    mov cx, ax
    mov dx, 0x1f0

; loop for reading data
.go_on_read:
    in ax, dx
    mov [bx], ax
    add bx, 2
    loop .go_on_read ; the cx controls loop
    ret

    times 510 - ($ - $$) db 0
    db 0x55, 0xaa

