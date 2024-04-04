#include "list.h"
#include "interrupt.h"

void list_init(struct list* list) {
  //  注意，这里要取地址 &
  list->head.next = &list->tail;
  list->tail.prev = &list->head;
  
  list->head.prev = NULL;
  list->tail.next = NULL;
}

// 把链表元素 elem 插入在元素 before 之前
void list_insert_before(struct list_elem* before, struct list_elem* elem) {
  enum intr_status old_status = intr_disable();
  
  before->prev->next = elem;
  elem->prev = before->prev;
  elem->next = before;
  
  before->prev = elem;
  
  intr_set_status(old_status);
}

// 添加元素到队首
void list_push(struct list* plist, struct list_elem* elem) {
  list_insert_before(&plist->head, elem);
}

// 添加元素到队尾
void list_append(struct list* plist, struct list_elem* elem) {
  list_insert_before(&plist->tail, elem);
}

void list_remove(struct list_elem* elem) {
  enum intr_status old_status = intr_disable();
  
  elem->prev->next = elem->next;
  elem->next->prev = elem->prev;
  
  intr_set_status(old_status);
}

// 将链表的第一个元素弹出并返回
struct list_elem* list_pop(struct list* plist) {
  struct list_elem* elem = plist->head.next;
  list_remove(elem);
  return elem;
}

bool list_empty(struct list* plist) {
  return (plist->head.next == &plist->tail ? true : false);
}


struct list_elem* list_traversal(struct list* plist, function func, int arg) {
  struct list_elem* elem = plist->head.next;
  if (list_empty(plist)) {
    return NULL;
  }
  
  while (elem != &plist->tail)
  {
    if (func(elem, arg)) {
      return elem;
    }
    elem = elem->next;
  }
  return NULL;
}
bool elem_find(struct list* plist, struct list_elem* obj_elem) {
  struct list_elem* elem = plist->head.next;
  while (elem != &plist->tail) {
    if (elem == obj_elem) {
      return true;
    }
    elem = elem->next;
  }
  return false;
}

uint32_t list_len(struct list* plist) {
  struct list_elem* elem = plist->head.next;
  uint32_t length = 0;
  while (elem != &plist->tail) {
    length++;
    elem = elem->next;
  }
  return length;
}