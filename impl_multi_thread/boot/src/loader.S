%include "boot.inc"
SECTION LOADER vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP	equ	LOADER_BASE_ADDR

; 构建 gdt，gdt 本质上是一段内存区域，每 8 个字节一个表项，即段描述符
; dd 指令定义双字，一个字 = 两个字节，所有 dd 就是定义 4 个字节
; 规定 第 0 个表项没有用，所以全部定义为 0

; 程序编译后的地址从上往下是越来越高的，所以上面 dd 命令定义的是段描述符的低 4 字节，
; 下面 dd 命令定义的是段描述符的高 4 字节。
GDT_BASE:
    dd 0x00000000
    dd 0x00000000

CODE_DESC:
    dd 0x0000ffff ; 段描述符的低 4 字节
    dd DESC_CODE_HIGH4 ; 段描述符的高 4 字节

DATA_STACK_DESC:
    dd 0x0000ffff ; 段描述符的低 4 字节
    dd DESC_DATA_HIGH4 ; 段描述符的高 4 字节

VIDEO_DESC:
	dd	0x80000007	;limit=(0xbffff - 0xb8000)/4k = 7
	dd	DESC_VIDEO_HIGH4;此时dpl为0

GDT_SIZE	equ	$ - GDT_BASE	;获取 GDT 大小
GDT_LIMIT	equ	GDT_SIZE - 1	;获取 段界限

times	60	dq	0	;预留60个空位，为以后填入中断描述符表和任务状态段TSS描述符留空间
				;times 60 表示后面的内容循环60次，是nasm提供的伪指令

SELECTOR_CODE 	equ	(0x0001 << 3) + TI_GDT + RPL0
SELECTOR_DATA 	equ	(0x0002 << 3) + TI_GDT + RPL0
SELECTOR_VIDEO 	equ	(0x0003 << 3) + TI_GDT + RPL0

; total_mem_bytes用于保存内存容量,以字节为单位,此位置比较好记。
; 当前偏移loader.bin文件头0x200字节(0x200 = 512 = dd 表示 4B, 前面有 8个 dd，
; 所以是 4*8=32B, 60个dq，dq代表8B, 所以有 480B, 所以总共 32+480 = 512B),loader.bin的加载地址是0x900 = LOADER_BASE_ADDR,
; 故total_mem_bytes内存中的地址是0xb00.将来在内核中咱们会引用此地址
total_mem_bytes dd 0	
;以下是 gdt 指针，前2字节是gdt界限，后4字节是gdt起始地址
gdt_ptr	dw	GDT_LIMIT
	dd	GDT_BASE

;人工对齐:total_mem_bytes4字节+gdt_ptr6字节+ards_buf244字节+ards_nr2,共256字节
ards_buf times 244 db 0
ards_nr dw 0		      ;用于记录ards结构体数量

loader_start:

;-------  通过 bios 获取内存大小  -------
;-------  int 15h eax = 0000E820h ,edx = 534D4150h ('SMAP') 获取内存布局  -------

   xor ebx, ebx		      ;第一次调用时，ebx值要为0
   mov edx, 0x534d4150	      ;edx只赋值一次，循环体中不会改变
   mov di, ards_buf	      ;ards结构缓冲区
.e820_mem_get_loop:	      ;循环获取每个ARDS内存范围描述结构
   mov eax, 0x0000e820	      ;执行int 0x15后,eax值变为0x534d4150,所以每次执行int前都要更新为子功能号。
   mov ecx, 20		      ;ARDS地址范围描述符结构大小是20字节
   int 0x15
   jc .e820_failed_so_try_e801   ;若cf位为1则有错误发生，尝试0xe801子功能
   add di, cx		      ;使di增加20字节指向缓冲区中新的ARDS结构位置
   inc word [ards_nr]	      ;记录ARDS数量
   cmp ebx, 0		      ;若ebx为0且cf不为1,这说明ards全部返回，当前已是最后一个
   jnz .e820_mem_get_loop

;在所有ards结构中，找出(base_add_low + length_low)的最大值，即内存的容量。
   mov cx, [ards_nr]	      ;遍历每一个ARDS结构体,循环次数是ARDS的数量
   mov ebx, ards_buf 
   xor edx, edx		      ;edx为最大的内存容量,在此先清0
.find_max_mem_area:	      ;无须判断type是否为1,最大的内存块一定是可被使用
   mov eax, [ebx]	      ;base_add_low
   add eax, [ebx+8]	      ;length_low
   add ebx, 20		      ;指向缓冲区中下一个ARDS结构
   cmp edx, eax		      ;冒泡排序，找出最大,edx寄存器始终是最大的内存容量
   jge .next_ards
   mov edx, eax		      ;edx为总内存大小
.next_ards:
   loop .find_max_mem_area
   jmp .mem_get_ok

;------  int 15h ax = E801h 获取内存大小,最大支持4G  ------
; 返回后, ax cx 值一样,以KB为单位,bx dx值一样,以64KB为单位
; 在ax和cx寄存器中为低16M,在bx和dx寄存器中为16MB到4G。
.e820_failed_so_try_e801:
   mov ax,0xe801
   int 0x15
   jc .e801_failed_so_try88   ;若当前e801方法失败,就尝试0x88方法

;1 先算出低15M的内存,ax和cx中是以KB为单位的内存数量,将其转换为以byte为单位
   mov cx,0x400	     ;cx和ax值一样,cx用做乘数
   mul cx 
   shl edx,16
   and eax,0x0000FFFF
   or edx,eax
   add edx, 0x100000 ;ax只是15MB,故要加1MB
   mov esi,edx	     ;先把低15MB的内存容量存入esi寄存器备份

;2 再将16MB以上的内存转换为byte为单位,寄存器bx和dx中是以64KB为单位的内存数量
   xor eax,eax
   mov ax,bx		
   mov ecx, 0x10000	;0x10000十进制为64KB
   mul ecx		;32位乘法,默认的被乘数是eax,积为64位,高32位存入edx,低32位存入eax.
   add esi,eax		;由于此方法只能测出4G以内的内存,故32位eax足够了,edx肯定为0,只加eax便可
   mov edx,esi		;edx为总内存大小
   jmp .mem_get_ok

;-----------------  int 15h ah = 0x88 获取内存大小,只能获取64M之内  ----------
.e801_failed_so_try88: 
   ;int 15后，ax存入的是以kb为单位的内存容量
   mov  ah, 0x88
   int  0x15
   jc .error_hlt
   and eax,0x0000FFFF
      
   ;16位乘法，被乘数是ax,积为32位.积的高16位在dx中，积的低16位在ax中
   mov cx, 0x400     ;0x400等于1024,将ax中的内存容量换为以byte为单位
   mul cx
   shl edx, 16	     ;把dx移到高16位
   or edx, eax	     ;把积的低16位组合到edx,为32位的积
   add edx,0x100000  ;0x88子功能只会返回1MB以上的内存,故实际内存大小要加上1MB

.mem_get_ok:
   mov [total_mem_bytes], edx	 ;将内存换为byte单位后存入total_mem_bytes处。



;----启用 保护模式----
	;1.打开A20地址线
	in al, 0x92
	or al, 00000010B
	out 0x92, al

	;2.加载GDT
	lgdt [gdt_ptr]

	;3.将CR0的PE位置1
	mov eax, cr0
	or eax, 0x00000001
	mov cr0, eax

	jmp dword SELECTOR_CODE:p_mode_start	;刷新流水线
						;流水线是CPU 的工作方式，会把当前指令和后面的几个指令同时放在流水线中重叠执行，由于之前的代码是16位，接下来的代码变成32位了，指令按照16位进行译码会出错，通过刷新流水线可以解决这个问题

.error_hlt:         ;出错则挂起
   hlt
   
[bits 32]
p_mode_start:
	;初始化为32位的段寄存器
	mov ax, SELECTOR_DATA
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov esp, LOADER_STACK_TOP

	;显示“P”到屏幕上
	mov ax, SELECTOR_VIDEO
	mov gs, ax
	mov byte [gs:160],'P'

;----加载 kernel----
; 这里把 kernel.bin 从硬盘拷贝到内存的高地址
	mov eax, KERNEL_START_SECTOR	;kernel.bin所在的扇区号
	mov ebx, KERNEL_BIN_BASE_ADDR	;从硬盘读出后写入的地址
	mov ecx, 200			;读入的扇区数
	
	call rd_disk_m_32		;从硬盘读取文件到内存，上面eax，ebx，ecx是参数

;----启用 分页机制----
	;创建页目录和页表并初始化页内存位图
	call setup_page
  
  ; 把 gdt 放到内核空间（内核所对应的虚拟地址空间）
  ; 这里先把 gdt 的信息保存到 [gdt_ptr]
  sgdt [gdt_ptr]
  
  ; 把视频段放到内核空间与其他用户进程共享
  ; 先要找到 gdt 的起始位置, gdt 指针，前2字节是gdt界限，后4字节是gdt起始地址
  mov ebx, [gdt_ptr + 2] ; 现在 ebx 里的值就是 GDT_BASE
  or dword [ebx + 0x18 + 4], 0xC0000000
  
  ; 把 gdt 放到内核空间
  add dword [gdt_ptr + 2], 0xC0000000
  add esp, 0xC0000000
  
	;页目录赋值给CR3
	mov eax, PAGE_DIR_TABLE_POS
	mov cr3, eax
	
	;打开cr0的pg位（第31位）
	mov eax, cr0
	or eax, 0x80000000
	mov cr0, eax

	;开启分页后，用gdt新的地址重新加载
	lgdt [gdt_ptr]

	mov eax, SELECTOR_VIDEO
	mov gs, eax
	mov byte [gs :320], 'V'
  
  jmp SELECTOR_CODE:enter_kernel

enter_kernel:
  ; 这里是按照 ELF 格式，把 kernel.bin 中的段（segment) 展开到（复制到）内存中的相应位置。
  call kernel_init
	mov esp, 0xc009f000	;给栈选个高地址且不影响内存其他位置的地方
	jmp KERNEL_ENTRY_POINT	
  
  
kernel_init:
  xor eax, eax
  xor ebx, ebx  ; ebx 记录程序头表地址
  xor ecx, ecx  ; ecx 记录程序头表中 program header 数量
  xor edx, edx  ; edx 记录 program header 的尺寸，即 e_phentsize
  
  ; 获取 program header 的尺寸, e_phentsize
  mov dx, [KERNEL_BIN_BASE_ADDR + 42]
  ; 获取第一个程序头在文件中的偏移量, e_phoff
  mov ebx, [KERNEL_BIN_BASE_ADDR + 28]
  
  ; 获取第一个文件头的地址
  add ebx, KERNEL_BIN_BASE_ADDR
  ; 获取 program header 的数量
  mov cx, [KERNEL_BIN_BASE_ADDR + 44]

.each_segment:
  ; 获取程序头的 p_type
  cmp byte [ebx + 0], PT_NULL
  je .PTNULL
  
  ; 类似与调用 memcpy 函数
  ; size 获取程序头的 p_filesz, 然后压栈
  push dword [ebx + 16]
  
  ; src 获取程序头的起始偏移字节，然后压栈  
  mov eax, [ebx + 4] ; 获取程序头的 p_offset
  add eax, KERNEL_BIN_BASE_ADDR
  push eax 
  
  ; dst 获取程序头在内存中的虚拟地址，然后压栈
  push dword [ebx + 8]
  
  call mem_cpy
  ; 因为压栈，会让 esp 不断减小，现在函数调用完成后，把 esp 加回来
  ; 3 个 4 字节的参数
  add esp, 12
  
.PTNULL: 
  add ebx, edx				;程序头的地址 + 程序头的大小 = 下一个程序头的地址
	loop .each_segment			;复制下一个程序头
	ret
  
;----逐字节拷贝 mem_cpy(dst, src, size)---
mem_cpy:
	cld		;控制进行字符串操作时esi和edi的递增方式，cld增大，sld减小
	push ebp
	mov ebp, esp
	push ecx	;rep指令用到了ecx，外层指令也用到了ecx，所以备份
	
	mov edi, [ebp + 8]	;dst
	mov esi, [ebp + 12]	;src
	mov ecx, [ebp + 16]	;size
	rep movsb		;逐字节拷贝

	;恢复环境
	pop ecx
	pop ebp
	ret
  
  

;-------- 创建页目录和页表 --------
setup_page:
;把页目录所占空间清0, 一个页目录表有 1024 个页目录项，每个页目录占 4B，所以一个页目录表就占 4096B
	mov ecx, 4096
	xor esi, esi
.clear_page_dir:
	mov byte [PAGE_DIR_TABLE_POS + esi], 0
	inc esi
	loop .clear_page_dir

; 开始创建页目录项，这个页目录表起始地址是在 0x100000,这个地址是任选的，只要可用就行
.create_pde:
    mov eax, PAGE_DIR_TABLE_POS
    ;这里让页表和页目录表紧挨着，因为页目录表本身大小是 4K，4K = 2^12 = 0x1000, 
    ;所以第一个页表的位置就是，0x101000
    add eax, 0x1000
    mov ebx, eax 
    
    ; 设置页目录项的属性，用户级别 | 可写 | 存在于内存中
    or eax, PG_US_U | PG_RW_W | PG_P 
    ; 我们要为 kernel 留出 1G 的内存空间，同时每个页表代表 4M 内存，
    ; 那么需要留出 1G/4M = 2^30/2^22 = 2^8 = 256 个页表,
    ; 由于页目录表中总共只有 1024 个页表，所以剩下 1024 - 256 = 768 = 0x300 个页表给所有用户进程
    ; 又因为每个页表的大小是 4K, 所以 768 * 4 = 3072 = 0xC00，
    ; 也就是说从第 768 个页目录项开始(或者说从地址 【页目录起始地址 + 0xC00】 开始属于内核空间），属于内核空间
    ; 所以从[0, 768) 这一段内存属于用户空间
    ; 这里把第 0 个目录项 和 第 768 个目录项都保存【第一个页表】的地址
    mov [PAGE_DIR_TABLE_POS + 0x00], eax
    mov [PAGE_DIR_TABLE_POS + 0xC00], eax 
    
    ; 这里让最后一个页目录项指向页目录表自己, 注意，是 4092，不是 4096
    sub eax, 0x1000
    mov [PAGE_DIR_TABLE_POS + 4092], eax 
    
    ; 现在开始给内核空间创建页表项 PTE
    ; 因为我们的内核占用内存不会超过 1M，所以就只创建 1M 大小的页表项, 因为每个页表项大小为 4K, 所以
    ; 1M/4K  = 2^20 / 2^12 = 2^8 = 256 个页表项
    mov ecx, 256
    mov esi, 0
    mov edx, PG_US_U | PG_RW_W | PG_P
.create_pte:
    ; 此时的 ebx 正是第一个页表的位置
    mov [ebx + esi*4], edx 
    add edx, 4096
    inc esi
    loop .create_pte
; 创建内核其他页表的 PDE
    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x2000 ; 这是第二个页表的位置
    or eax, PG_US_U | PG_RW_W | PG_P 
    mov ebx, PAGE_DIR_TABLE_POS
    mov ecx, 254
    mov esi, 769
.create_kernel_pde:
    mov [ebx+esi*4], eax 
    inc esi 
    add eax, 0x1000
    loop .create_kernel_pde
    ret 

;----读取文件到内存----
;参数
;eax ：扇区号
;ebx ：待读入的地址
;ecx ：读入的扇区数

rd_disk_m_32:
        mov esi ,eax    ;备份eax
        mov di ,cx      ;备份cx

;读写硬盘
;1---设置要读取的扇区数
        mov dx ,0x1f2   ;设置端口号，dx用来存储端口号的
        mov al ,cl
        out dx ,al      ;读取的扇区数

        mov eax ,esi    ;恢复eax


;2---将LBA地址存入0x1f3～0x1f6
        ;LBA 7～0位写入端口0x1f3
        mov dx ,0x1f3
        out dx ,al

        ;LBA 15~8位写入端口0x1f4
        mov cl ,8
        shr eax ,cl     ;逻辑右移8位,将eax的最低8位移掉，让最低8位al的值变成接下来8位
        mov dx ,0x1f4
        out dx ,al

        ;LBA 24～16位写入端口0x1f5
        shr eax ,cl
        mov dx ,0x1f5
        out dx ,al

        shr eax ,cl
        and al ,0x0f    ;设置lba 24～27位
        or al ,0xe0     ;设置7～4位是1110表示LBA模式
        mov dx ,0x1f6
        out dx ,al

;3---向0x1f7端口写入读命令0x20
        mov dx ,0x1f7
        mov al ,0x20
        out dx ,al

;4---检测硬盘状态
.not_ready:
        ;同写入命令端口，读取时标示硬盘状态，写入时是命令
        nop
        in al ,dx
        and al ,0x88    ;第三位为1表示已经准备好了，第7位为1表示硬盘忙
        cmp al ,0x08
        jnz .not_ready

;5---0x1f0端口读取数据
        mov ax ,di      ;要读取的扇区数
        mov dx ,256     ;一个扇区512字节，一次读取2字节，需要读取256次
        mul dx          ;结果放在ax里
        mov cx ,ax      ;要读取的次数

        mov dx ,0x1f0
.go_on_read:
        in ax, dx
        mov [ebx], ax    ;bx是要读取到的内存地址
        add ebx, 0x02
        loop .go_on_read        ;循环cx次
        ret
