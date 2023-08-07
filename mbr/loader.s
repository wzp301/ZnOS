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

    mov eax, KERNEL_START_SECTOR
    mov ebx, KERNEL_BIN_BASE_ADDR
    mov ecx, KERNEL_SECTOR_NUM
    call rd_disk_m_32 ; 从硬盘加载内核到内存

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

    jmp SELECTOR_CODE:enter_kernel	  ;强制刷新流水线,更新gdt
enter_kernel:    
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   call kernel_init
   mov esp, 0xc009f000
   jmp KERNEL_ENTRY_POINT            ; 用地址0x1500访问测试，结果ok

;==========加载内核到内存分页中
kernel_init:
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx

    mov dx, [KERNEL_BIN_BASE_ADDR + 42] ; ELF偏移42字节是e_phentsize字段，表示程序段头大小
    mov ebx, [KERNEL_BIN_BASE_ADDR + 28] ; ELF偏移28字节是e_phoff字段，表示第1个程序段偏移
    add ebx, KERNEL_BIN_BASE_ADDR
    mov cx, [KERNEL_BIN_BASE_ADDR + 44] ; ELF偏移44字节是e_phnum字段，表示程序段头的个数

.each_segment:
    cmp byte [ebx + 0], PT_NULL
    je .PTNULL

    push dword [ebx + 16] ; 获取段size,作为copy函数参数
    mov eax, [ebx + 4] ; 获取程序段在ELF中的偏移地址
    add eax, KERNEL_BIN_BASE_ADDR
    push eax ;
    push dword [ebx + 8] ; 获取段在内存中的虚拟地址
    call mem_cpy
    add esp , 12 ; 清理压栈参数

.PTNULL:
    add ebx, edx ; edx为程序段的大小，这里是让ebx指向下一个段
    loop .each_segment
    ret

;========逐字节拷贝函数
mem_cpy:
    cld
    push ebp
    mov ebp, esp
    push ecx
    mov edi, [ebp + 8]
    mov esi, [ebp + 12]
    mov ecx, [ebp + 16]
    rep movsb

    pop ecx
    pop ebp
    ret

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

;-------------------------------------------------------------------------------
			   ;功能:读取硬盘n个扇区
rd_disk_m_32:	   
;-------------------------------------------------------------------------------
							 ; eax=LBA扇区号
							 ; ebx=将数据写入的内存地址
							 ; ecx=读入的扇区数
      mov esi,eax	   ; 备份eax
      mov di,cx		   ; 备份扇区数到di
;读写硬盘:
;第1步：设置要读取的扇区数
      mov dx,0x1f2
      mov al,cl
      out dx,al            ;读取的扇区数

      mov eax,esi	   ;恢复ax

;第2步：将LBA地址存入0x1f3 ~ 0x1f6

      ;LBA地址7~0位写入端口0x1f3
      mov dx,0x1f3                       
      out dx,al                          

      ;LBA地址15~8位写入端口0x1f4
      mov cl,8
      shr eax,cl
      mov dx,0x1f4
      out dx,al

      ;LBA地址23~16位写入端口0x1f5
      shr eax,cl
      mov dx,0x1f5
      out dx,al

      shr eax,cl
      and al,0x0f	   ;lba第24~27位
      or al,0xe0	   ; 设置7～4位为1110,表示lba模式
      mov dx,0x1f6
      out dx,al

;第3步：向0x1f7端口写入读命令，0x20 
      mov dx,0x1f7
      mov al,0x20                        
      out dx,al

;;;;;;; 至此,硬盘控制器便从指定的lba地址(eax)处,读出连续的cx个扇区,下面检查硬盘状态,不忙就能把这cx个扇区的数据读出来

;第4步：检测硬盘状态
  .not_ready:		   ;测试0x1f7端口(status寄存器)的的BSY位
      ;同一端口,写时表示写入命令字,读时表示读入硬盘状态
      nop
      in al,dx
      and al,0x88	   ;第4位为1表示硬盘控制器已准备好数据传输,第7位为1表示硬盘忙
      cmp al,0x08
      jnz .not_ready	   ;若未准备好,继续等。

;第5步：从0x1f0端口读数据
      mov ax, di	   ;以下从硬盘端口读数据用insw指令更快捷,不过尽可能多的演示命令使用,
			   ;在此先用这种方法,在后面内容会用到insw和outsw等

      mov dx, 256	   ;di为要读取的扇区数,一个扇区有512字节,每次读入一个字,共需di*512/2次,所以di*256
      mul dx
      mov cx, ax	   
      mov dx, 0x1f0
  .go_on_read:
      in ax,dx		
      mov [ebx], ax
      add ebx, 2
			  ; 由于在实模式下偏移地址为16位,所以用bx只会访问到0~FFFFh的偏移。
			  ; loader的栈指针为0x900,bx为指向的数据输出缓冲区,且为16位，
			  ; 超过0xffff后,bx部分会从0开始,所以当要读取的扇区数过大,待写入的地址超过bx的范围时，
			  ; 从硬盘上读出的数据会把0x0000~0xffff的覆盖，
			  ; 造成栈被破坏,所以ret返回时,返回地址被破坏了,已经不是之前正确的地址,
			  ; 故程序出会错,不知道会跑到哪里去。
			  ; 所以改为ebx代替bx指向缓冲区,这样生成的机器码前面会有0x66和0x67来反转。
			  ; 0X66用于反转默认的操作数大小! 0X67用于反转默认的寻址方式.
			  ; cpu处于16位模式时,会理所当然的认为操作数和寻址都是16位,处于32位模式时,
			  ; 也会认为要执行的指令是32位.
			  ; 当我们在其中任意模式下用了另外模式的寻址方式或操作数大小(姑且认为16位模式用16位字节操作数，
			  ; 32位模式下用32字节的操作数)时,编译器会在指令前帮我们加上0x66或0x67，
			  ; 临时改变当前cpu模式到另外的模式下.
			  ; 假设当前运行在16位模式,遇到0X66时,操作数大小变为32位.
			  ; 假设当前运行在32位模式,遇到0X66时,操作数大小变为16位.
			  ; 假设当前运行在16位模式,遇到0X67时,寻址方式变为32位寻址
			  ; 假设当前运行在32位模式,遇到0X67时,寻址方式变为16位寻址.

      loop .go_on_read
      ret
