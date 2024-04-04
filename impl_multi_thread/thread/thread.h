#ifndef __THREAD_THREAD_H
#define __THREAD_THREAD_H

#include "stdint.h"
#include "list.h"

typedef void thread_func(void*);

enum task_status {
  TASK_RUNNING,
  TASK_READY,
  TASK_BLOCKED,
  TASK_WAITING,
  TASK_HANGING,
  TASK_DIED
};

// 中断栈 intr_stack
struct intr_stack {
  uint32_t vec_no;   // kernel.S 宏VECTOR中 push %1 压入的中断号
  uint32_t edi;
  uint32_t esi;
  uint32_t ebp;
  uint32_t esp_dummy;
  
  uint32_t ebx;
  uint32_t edx;
  uint32_t ecx;
  uint32_t eax;
  uint32_t gs;
  uint32_t fs;
  uint32_t es;
  uint32_t ds;
  
  uint32_t err_code;
  void (*eip) (void);
  uint32_t cs;
  uint32_t eflags;
  void* esp;
  uint32_t ss;
};

// 线程栈 
struct thread_stack {
  uint32_t ebp;
  uint32_t ebx;
  uint32_t edi;
  uint32_t esi;
  
  // 线程第一次执行时，eip 指向待调用的函数 kernel_thread
  // 其他时候， eip 是指向 switch_to 的返回地址
  void (*eip) (thread_func* func, void* func_arg);
  
  // 参数 unused_ret 只为占位置充数为返回地址
  void (*unused_retaddr);
  // 由 kernel_thread 所调用的函数名
  thread_func* function;
  // 由 kernel_thread 所调用的函数所需的参数
  void* func_arg;
};

// 进程或线程的 pcb
struct task_struct {
  // 各内核线程都用自己的内核栈
  uint32_t* self_kstack;
  enum task_status status;
  char name[16];
  // 线程优先级
  uint8_t priority;
  
  // 在 CPU 上占用的时间片
  uint8_t ticks;
  
  uint32_t elapsed_ticks;
  
  struct list_elem general_tag;
  
  struct list_elem all_list_tag;
  
  // 进程自己的页表的虚拟地址，如果是线程的话，这个字段为 NULL
  uint32_t* pgdir;

  
  // 栈的边界标记，用于检测栈的溢出
  uint32_t stack_magic;
};

void thread_create(struct task_struct* pthread, thread_func function, void* func_arg);
void init_thread(struct task_struct* pthread, char* name, int prio);
struct task_struct* thread_start(char* name, int prio, thread_func function, void* func_arg);
struct task_struct* running_thread(void);
void schedule(void);
void thread_init(void);
#endif