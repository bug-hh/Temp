#include "bitmap.h"
#include "debug.h"
#include "string.h"
#include "stdint.h"
#include "print.h"
#include "interrupt.h"
#include "global.h"

void bitmap_init(struct bitmap* btmp) {
  memset(btmp->bits, 0, btmp->btmp_bytes_len);
}

/*
如果 bit_idx 为 1 返回 true，否则 false
*/
bool bitmap_scan_test(struct bitmap* btmp, uint32_t bit_idx) {
  int index = bit_idx/8;
  int offset = bit_idx%8;
  return (btmp->bits[index] & (BITMAP_MASK << offset));
}
/*
在位图中申请连续的 cnt 个位，如果成功，则返回起始下标，否则返回 -1
*/
int bitmap_scan(struct bitmap* btmp, uint32_t cnt) {
  uint32_t idx_byte = 0;
  while (0xff == btmp->bits[idx_byte] && idx_byte < btmp->btmp_bytes_len) {
    idx_byte++;
  }
  ASSERT(idx_byte < btmp->btmp_bytes_len);
  if (idx_byte == btmp->btmp_bytes_len) {
    return -1;
  }
  
  int idx_bit = 0;
  while ((uint8_t)(BITMAP_MASK << idx_bit) & btmp->bits[idx_byte]) {
    idx_bit++;
  }
  
  int bit_idx_start = idx_byte * 8 + idx_bit;
  if (cnt == 1) {
    return bit_idx_start;
  }
  
  uint32_t bit_left = btmp->btmp_bytes_len * 8 - bit_idx_start;
  uint32_t next_bit = bit_idx_start + 1;
  uint32_t count = 1;
  
  bit_idx_start = -1;
  while (bit_left-- > 0) {
    // next_bit 位已经被分配了，count 清零
    if (bitmap_scan_test(btmp, next_bit)) {
      count = 0;
    } else {
      count++;
    }
    if (count == cnt) {
      bit_idx_start = next_bit - cnt + 1;
      break;
    }
    next_bit++;
  }
  return bit_idx_start;
}

// 将位图的 bit_idx 设置成 value
void bitmap_set(struct bitmap* btmp, uint32_t bit_idx, int8_t value) {
  ASSERT(value == 0 || value == 1);
  uint32_t index = bit_idx / 8;
  uint32_t offset = bit_idx % 8;
  
  if (value) {
    btmp->bits[index] |= (BITMAP_MASK << offset);
  } else {
    btmp->bits[index] &= ~(BITMAP_MASK << offset);
  }
}