#include <stdlib.h>
#include "skiplist.h"

int slRandomLevel(void) {
    int level = 1;
    while ((random()&0xFFFF) < (SKIPLIST_P * 0xFFFF))
        level += 1;
    return (level<CPU_SKIPLIST_MAXLEVEL) ? level : CPU_SKIPLIST_MAXLEVEL;
}

skiplistNode *slCreateNode(int level, _key_t key, value_t value) {
    skiplistNode *node =(skiplistNode*)malloc(sizeof(skiplistNode)+level*sizeof(void*));
    node->key = key;
    node->value = value;
    return node;
}

skiplist *slCreate(void) {
    int j;
    skiplist *sl;

    sl = (skiplist*)malloc(sizeof(skiplist));
    sl->level = 1;
    sl->length = 0;
    sl->header = slCreateNode(CPU_SKIPLIST_MAXLEVEL,0,0);
    for (j = 0; j < CPU_SKIPLIST_MAXLEVEL; j++) {
        sl->header->level[j].forward = NULL;
    }
    sl->header->backward = NULL;
    sl->tail = NULL;
    return sl;
}

/* Free the specified skiplist node. The referenced SDS string representation
 * of the element is freed too, unless node->ele is set to NULL before calling
 * this function. */
void slFreeNode(skiplistNode *node) {
    free(node);
}

/* Free a whole skiplist. */
void slFree(skiplist *sl) {
    skiplistNode *node = sl->header->level[0].forward, *next;

    free(sl->header);
    while(node) {
        next = node->level[0].forward;
        slFreeNode(node);
        node = next;
    }
    free(sl);
}

skiplistNode *slInsert(skiplist *sl, _key_t key, value_t value) {
    skiplistNode *update[CPU_SKIPLIST_MAXLEVEL], *x;
    int i, level;

    x = sl->header;
    for (i = sl->level-1; i >= 0; i--) {
        while (x->level[i].forward && x->level[i].forward->key < key)
            x = x->level[i].forward;
        update[i] = x;
    }
    /* we assume the element is not already inside, since we allow duplicated
     * scores, reinserting the same element should never happen since the
     * caller of slInsert() should test in the hash table if the element is
     * already inside or not. */
    level = slRandomLevel();
    if (level > sl->level) {
        for (i = sl->level; i < level; i++) {
            update[i] = sl->header;
        }
        sl->level = level;
    }
    x = slCreateNode(level, key, value);
    for (i = 0; i < level; i++) {
        x->level[i].forward = update[i]->level[i].forward;
        update[i]->level[i].forward = x;
    }

    x->backward = (update[0] == sl->header) ? NULL : update[0];
    if (x->level[0].forward)
        x->level[0].forward->backward = x;
    else
        sl->tail = x;
    sl->length++;
    return x;
}

skiplistNode* slSearch(skiplist* sl, _key_t key) {
    skiplistNode* node = sl->header;
    int level;
    for (int i = sl->level - 1; i >= 0; i--) {
        while (node->level[i].forward && node->level[i].forward->key < key)
            node = node->level[i].forward;
    }
    return node;
}