#include "memory.h"
#include "stdint.h"
#include "print.h"
#include "global.h"
#include "debug.h"

#define PG_SIZE 4096

#define PDE_IDX(addr) ((addr & 0xffc00000) >> 22)
#define PTE_IDX(addr) ((addr & 0x003ff000) >> 12)

/*
在第五章里面，已经把虚拟地址空间 0-3G 划分给了用户进程，剩下的 1G 划分给了操作系统（内核）
我们要为 kernel 留出 1G 的内存空间，同时每个页表代表 4M 内存，
那么需要留出 1G/4M = 2^30/2^22 = 2^8 = 256 个页表,
由于页目录表中总共只有 1024 个页表，所以剩下 1024 - 256 = 768 = 0x300 个页表给所有用户进程
又因为每个页表的大小是 4K, 所以 768 * 4 = 3072 = 0xC00，
也就是说从第 768 个页目录项开始(或者说从地址 【页目录起始地址 + 0xC00】 开始属于内核空间），属于内核空间
所以从[0, 768) 这一段内存属于用户空间
*/

/*
PCB 大小为4K, 而一页刚好是 4K，PCB 不能跨页，所以 PCB 的起始地址一定是 0xXXXXX000, 结束地址一定是 0xXXXXXfff, PCB 里，0xXXXXXfff 以下，是栈，0xXXXXXfff 是栈顶，压栈的时候 esp 先减少，再往减少的地址里存数据。所以起始栈顶地址 0xXXXXXfff + 1 就是下一页的起始地址
我们在 loader.S 里初始化了内核程序的PCB 的栈顶地址为 0xC009f000, 因为PCB 大小为4K,所以 PCB 的起始地址为
0xC009e000。

bitmap 中的每一个 bit，都表示一页4k，那么一个 4K 大小的 bitmap，能够表示 2^12*8*2^12 = 2^27 = 128M
现在我们给 bitmap 分配 4页内存，所以这个 bitmap 能够表示 4*128 = 512M 内存
所以bitmap 的起始地址就是 0xC009e - 4 = 0xC009a
*/
#define MEM_BITMAP_BASE 0xC009a000

/*
因为给内核留的内存是 1M, 所以虚拟内存 [0xC0000000 0xC0100000) 是内核空间 对应的物理内存是低端的 1M 内存
*/
#define K_HEAP_START 0xC0100000

// 这个定义的是物理内存地址池
struct pool {
  struct bitmap pool_bitmap;
  uint32_t phy_addr_start; // 本内存池所管理的物理内存的起始地址
  uint32_t pool_size;
};

struct pool kernel_pool, user_pool;


struct virtual_addr kernel_vaddr;
 
static void mem_pool_init(uint32_t all_mem) {
  put_str(" mem_pool_init start\n");
  // 操作系统占 256 个页表，1个页表的大小是 4M
  uint32_t page_table_size = PG_SIZE * 256;
  // 页表本身占用的内存 + 内核占用的内存
  uint32_t used_mem = page_table_size + 0x100000;
  uint32_t free_mem = all_mem - used_mem;
  uint16_t all_free_pages = free_mem / PG_SIZE;
  
  uint16_t kernel_free_pages = all_free_pages / 2;
  uint16_t user_free_pages = all_free_pages - kernel_free_pages;
  
  // Kernel Bit Map 的长度，以字节为单位
  uint32_t kbm_length = kernel_free_pages / 8;
  // User Bit Map 的长度，以字节为单位
  uint32_t ubm_length = user_free_pages / 8;
  
  // 内核内存池的起始地址
  uint32_t kp_start = used_mem;
  // 用户内存池的起始地址
  uint32_t up_start = kp_start + kernel_free_pages * PG_SIZE;
  
  kernel_pool.phy_addr_start = kp_start;
  user_pool.phy_addr_start = up_start;
  
  kernel_pool.pool_size = kernel_free_pages * PG_SIZE;
  user_pool.pool_size = user_free_pages * PG_SIZE;
  
  kernel_pool.pool_bitmap.btmp_bytes_len = kbm_length;
  user_pool.pool_bitmap.btmp_bytes_len = ubm_length;
  
  // 内核内存池的位图起始地址
  kernel_pool.pool_bitmap.bits = (void*)MEM_BITMAP_BASE;
  
  // 用户内存池的位图起始地址
  user_pool.pool_bitmap.bits = (void*)(MEM_BITMAP_BASE + kbm_length);
  
    /******************** 输出内存池信息 **********************/
  put_str("      kernel_pool_bitmap_start:");put_int((int)kernel_pool.pool_bitmap.bits);
  put_str(" kernel_pool_phy_addr_start:");put_int(kernel_pool.phy_addr_start);
  put_str("\n");
  put_str("      user_pool_bitmap_start:");put_int((int)user_pool.pool_bitmap.bits);
  put_str(" user_pool_phy_addr_start:");put_int(user_pool.phy_addr_start);
  put_str("\n");
  
  // 将位图置 0
  bitmap_init(&kernel_pool.pool_bitmap);
  bitmap_init(&user_pool.pool_bitmap);
  
  // 初始化内核虚拟地址的位图
  kernel_vaddr.vaddr_bitmap.btmp_bytes_len = kbm_length;
  // 表示的是内核虚拟地址位图本身所在的内存地址
  kernel_vaddr.vaddr_bitmap.bits = (void*)(MEM_BITMAP_BASE + kbm_length + ubm_length);
  
  kernel_vaddr.vaddr_start = K_HEAP_START;
  
  bitmap_init(&kernel_vaddr.vaddr_bitmap);
  put_str("mem_pool_init done\n");
  
}

void mem_init() {
  put_str("mem_init start\n");
  //通过bios获取的内存有 32M
  uint32_t mem_bytes_total = (*(uint32_t*)(0xb00));
  put_str("memory size: ");
  put_int(mem_bytes_total);
  put_str("\n");
  mem_pool_init(mem_bytes_total);
  put_str("mem_init done\n");
}

// 在 pf 表示的虚拟内存池中申请 pg_cnt 个虚拟页
static void* vaddr_get(enum pool_flags pf, uint32_t pg_cnt) {
  int vaddr_start = 0, bit_idx_start = -1;
  uint32_t cnt = 0;
  if (pf == PF_KERNEL) {
    bit_idx_start = bitmap_scan(&kernel_vaddr.vaddr_bitmap, pg_cnt);
    if (bit_idx_start == -1) {
      return NULL;
    }
    while (cnt < pg_cnt) {
      bitmap_set(&kernel_vaddr.vaddr_bitmap, bit_idx_start + cnt++, 1);
    }
    vaddr_start = kernel_vaddr.vaddr_start + bit_idx_start * PG_SIZE;
  } else {
    
  }
  return (void*)vaddr_start;
}

// 得到虚拟地址 vaddr 对应的 pte 指针
uint32_t* pte_ptr(uint32_t vaddr) {
  uint32_t* pte = (uint32_t*)(0xffc00000 + \
  ((vaddr & 0xffc00000) >> 10) + \
  PTE_IDX(vaddr) * 4);
  return pte;
}

// 得到虚拟地址 vaddr 对应的 pde 指针
uint32_t* pde_ptr(uint32_t vaddr) {
  uint32_t* pde = (uint32_t*)((0xfffff000) + PDE_IDX(vaddr) * 4);
  return pde;
}

/*
在 m_pool 指向的物理内存中分配 1 个物理页，
成功则返回页框的物理地址，失败则返回 NULL
*/
static void* palloc(struct pool* m_pool) {
  int bit_idx = bitmap_scan(&m_pool->pool_bitmap, 1);
  if (bit_idx == -1) {
    return NULL;
  }
  bitmap_set(&m_pool->pool_bitmap, bit_idx, 1);
  uint32_t page_phyaddr = ((bit_idx * PG_SIZE) + m_pool->phy_addr_start);
  return (void*)page_phyaddr;
}
// 添加虚拟地址与物理地址的映射关系
static void page_table_add(void* _vaddr, void* _page_phyaddr) {
  uint32_t vaddr = (uint32_t)_vaddr;
  uint32_t page_phyaddr = (uint32_t)_page_phyaddr;
  
  uint32_t* pte = pte_ptr(vaddr);
  uint32_t* pde = pde_ptr(vaddr);
  
  if (*pde & 0x00000001) {
    ASSERT(!(*pte & 0x00000001));
    if (!(*pte & 0x00000001)) {
      *pte = (page_phyaddr | PG_US_U | PG_RW_W | PG_P_1);
    } else {
      PANIC("pte repeat");
      *pte = (page_phyaddr | PG_US_U | PG_RW_W | PG_P_1);
    }
  } else {
    uint32_t pde_phyaddr = (uint32_t)palloc(&kernel_pool);
    *pde = (pde_phyaddr | PG_US_U | PG_RW_W | PG_P_1);
    memset((void*)((int)pte & 0xfffff000), 0, PG_SIZE);
    ASSERT(!(*pte & 0x00000001));
    *pte = (page_phyaddr | PG_US_U | PG_RW_W | PG_P_1);
  }
}


// 分配 pg_cnt 个页空间，成功返回虚拟地址，失败返回 NULL
void* malloc_page(enum pool_flags pf, uint32_t pg_cnt) {
  ASSERT(pg_cnt > 0 && pg_cnt < 3840);
  void* vaddr_start = vaddr_get(pf, pg_cnt);
  if (vaddr_start == NULL) {
    return NULL;
  }
  uint32_t vaddr = (uint32_t)vaddr_start, cnt = pg_cnt;
  struct pool* mem_pool = pf & PF_KERNEL ? &kernel_pool : &user_pool;
  while (cnt-- > 0) {
    void* page_phyaddr = palloc(mem_pool);
    if (page_phyaddr == NULL) {
      return NULL;
    }
    page_table_add((void*)vaddr, page_phyaddr);
    vaddr += PG_SIZE;
  }
  return vaddr_start;
}

void* get_kernel_pages(uint32_t pg_cnt) {
  void* vaddr = malloc_page(PF_KERNEL, pg_cnt);
  if (vaddr != NULL) {
    memset(vaddr, 0, pg_cnt * PG_SIZE);
  }
  return vaddr;
}