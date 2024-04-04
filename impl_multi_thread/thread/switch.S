[bits 32]
section .text
global switch_to
switch_to:
; 栈中此处是返回地址，占 4 个字节
  push esi
  push edi 
  push ebx 
  push ebp 
  ; 为什么 +20 呢，因为前面 4 个寄存器 + 返回地址 5*4B = 20B
  ; 这里拿到的是 switch_to 的第一个参数 cur 
  mov eax, [esp+20]
  ; eax 是 cur，cur 是一个 task_struct*, cur 也是 task_struct 第一个字段 self_kstack 的地址
  ; 所以相当于把 esp 的值存到了 self_kstack 里
  mov [eax], esp 
  
  ; 上面是备份当前线程的上下文环境，下面是恢复下一个线程的环境
  ; 这里拿到的是 switch_to 函数的第二个参数 next
  mov eax, [esp + 24]
  ; 这里是把 next 中的第一个字段 self_kstack 赋值给 esp
  mov esp, [eax]
  ; 注意，这里的 esp 已经变成 next 的 self_kstack 了，所以下面 pop 的 4 个寄存器值是【不等于】上面 push 的
  ; 这里 pop 的顺序和 结构体 thread_stack 中的定义顺序是一致的
  pop ebp
  pop ebx
  pop edi
  pop esi
  ret 
  
  