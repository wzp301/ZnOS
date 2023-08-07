%include "boot.inc"
SECTION MBR vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR

jmp loader_start

; 构建gdt及其内部描述符
    GDT_BASE: 
        dd 0x00000000
        dd 0x00000000
    CODE_DESC:
        dd 0x0000FFFF
        dd DESC_CODE_HIGH4
    DATA_STACK_DESC:    
        dd 0x0000FFFF
        dd DESC_DATA_HIGH4
    VIDEO_DESC:
        dd 0x80000007   ;limit=(0xbffff-0xb8000)/4k=0x7
        dd DESC_VIDEO_HIGH4
    GDT_SIZE equ $ - GDT_BASE
    GDT_LIMIT equ GDT_SIZE - 1
    times 60 dq 0   ; 此处预留 60 个描述符的空位
    ; total_mem_bytes 保存BIOS返回的内存容量，以字节为单位
    ; loader.bin加载地址为0x900
    ; gdt定义和times 60 dq 0占用内存为：4 * 64 + 60 * 8 = 0x200个字节
    ; total_mem_bytes 的地址为0xb00
    total_mem_bytes dd 0

    SELECTOR_CODE equ (0x0001 << 3) + TI_GDT + RPL0
    SELECTOR_DATA equ (0x0002 << 3) + TI_GDT + RPL0
    SELECTOR_VIDEO equ (0x0003 << 3) + TI_GDT + RPL0

    ;以下是 gdt 的指针，前 2 字节是 gdt 界限，后 4 字节是 gdt 起始地址
    gdt_ptr dw GDT_LIMIT
                dd GDT_BASE
    
    ards_buf times 244 db 0 
    ards_nr dw 0 ; total_mem_bytes(4字节) + gdt_ptr(6字节) + ards_buf(244字节) + ards_nr(2字节) = 256字节

loader_start:
    ; int 15h eax = 0000e820h, edx=534D4150h ('SMAP') 获取内存布局
    xor ebx, ebx
    mov edx, 0x534d4150
    mov di, ards_buf
.e820_get_mem_loop:
    mov eax, 0x0000e820
    mov ecx, 20
    int 0x15
    jc .e820_failed_so_try_e801
    add di, cx
    inc word [ards_nr]
    cmp ebx, 0
    jnz .e820_get_mem_loop
    mov cx, [ards_nr]
    mov ebx, ards_buf
    xor edx, edx
.find_max_mem_area:
    mov eax, [ebx]
    add eax, [ebx + 8]
    add ebx, 20
    cmp edx, eax
    jge .next_ards
    mov edx,  eax
.next_ards:
    loop .find_max_mem_area
    jmp .mem_get_ok

.e820_failed_so_try_e801:
    mov eax, 0xe801
    int 0x15
    jc .e801_failed_so_try88

    mov cx, 0x400
    mul cx
    shl edx, 16
    and eax, 0x0000ffff
    or edx, eax
    add edx, 0x100000
    mov esi, edx
    xor eax, eax
    mov ax, bx
    mov ecx, 0x10000
    mul ecx
    add esi, eax
    mov edx, esi
    jmp .mem_get_ok

.e801_failed_so_try88:
    mov ah, 0x88
    int 0x15
    jc .error_hlt
    and eax, 0x0000ffff
    mov cx, 0x400
    mul cx
    shl edx, 16
    or edx, eax
    add edx, 0x100000

.mem_get_ok:
    mov [total_mem_bytes], edx
    jmp .enter_pe

.error_hlt:
    jmp $
    ; mov sp, LOADER_BASE_ADDR
    ; mov bp, loadermsg
    ; mov cx, 19
    ; mov ax, 0x1301
    ; mov bx, 0x001f
    ; mov dx, 0x1800
    ; int 0x10

.enter_pe:
;=========准备进入保护模式==========
; 1.打开A20
; 2.加载gdt
; 3.将cr0的pe位置为1

    ;打开A20
    in al, 0x92
    or al, 0000_0010B
    out 0x92, al

    ; 加载gdt
    lgdt [gdt_ptr]

    ; 设置cr0的pe位
    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax

    jmp dword SELECTOR_CODE:p_mode_start  ;刷新流水线


[bits 32]
p_mode_start:
    mov ax, SELECTOR_DATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp,LOADER_STACK_TOP
    mov ax, SELECTOR_VIDEO
    mov gs, ax
        ; 创建页目录表
    call setup_page

    ; 将描述符表地址和偏移量写入内粗gdt_ptr
    sgdt [gdt_ptr]
    
    ;将gdt描述符中视频段描述符的段基地址+0xc0000000
    mov ebx, [gdt_ptr + 2]
    or dword [ebx + 0x18 + 4], 0xc0000000

    ; 将gdt的基址加上0xc0000000，使其成为内核所在的高地址
    add dword [gdt_ptr + 2], 0xc0000000

    add esp, 0xc0000000 ; 将栈帧映射到内核空间

    ; cr3设置页目录地址
    mov eax, PAGE_DIR_TABLE_ADDR
    mov cr3, eax
    
    ; 打开cr0的pg位
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    ; 重新加载gdt
    lgdt [gdt_ptr]

    mov byte [gs:160], 'V'

    jmp $

setup_page:
    mov ecx, 4096
    mov esi, 0
.clear_page_dir: ; 把页目录项表清零
    mov byte [PAGE_DIR_TABLE_ADDR + esi], 0
    inc esi
    loop .clear_page_dir
.create_pde:
    mov eax, PAGE_DIR_TABLE_ADDR
    add eax, 0x1000
    mov ebx,  eax
    or eax, PG_US_U | PG_RW_W | PG_P ; 页目录项的属性RW，P为1, US为1,所有特权级用户都可以访问
    mov dword [PAGE_DIR_TABLE_ADDR + 0X0], eax
    mov dword [PAGE_DIR_TABLE_ADDR + 0xc00], eax ; 第768个页目录和第0个页目录都指向第0个页表

    sub eax, 0x1000
    mov dword [PAGE_DIR_TABLE_ADDR + 4092], eax ; 最后一个页目录项指向页目录表的地址，方便用户进程访问内核空间页表
    
    ; 创建第1个页表项
    mov ecx, 256
    mov esi, 0
    mov edx, PG_US_U | PG_RW_W | PG_P ; edx初始为0
.create_pte:
    mov [ebx + esi * 4], edx
    add edx, 4096  ; edx指向1MB内存中下一个页
    inc esi
    loop .create_pte

    ;创建内核其它页的页目录项（769～1022），第1023个目录项指向页目录表的地址
    mov eax, PAGE_DIR_TABLE_ADDR
    add eax, 0x2000
    or eax, PG_US_U | PG_RW_W | PG_P
    mov ebx, PAGE_DIR_TABLE_ADDR
    mov ecx, 254
    mov esi, 769
.create_kernel_pde:
    mov [ebx + esi * 4], eax
    inc esi
    add eax, 0x1000
    loop .create_kernel_pde
    ret