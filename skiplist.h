#ifndef __SKIPLIST_H
#define __SKIPLIST_H

#include <stdint.h>

#define SKIPLIST_P 0.25
#define GPU_BUFFERBITS 10
#define GPU_SKIPLIST_MAXLEVEL 4
#define CPU_SKIPLIST_MAXLEVEL (GPU_SKIPLIST_MAXLEVEL + GPU_BUFFERBITS / 2)


#define BUFFERNUM 8192
#define BUFFERSCALE (1 << GPU_BUFFERBITS)

/*
the bucket type using in GPU memory,
one warp manage one bucket
 */
typedef uint32_t _key_t;
typedef uint32_t value_t;

typedef struct _key_value_t {
    _key_t key;
    value_t value;
}key_value_t;
typedef struct _bucket_t{
    key_value_t kvArray[BUFFERSCALE];
}bucket_t;

typedef struct _skiplistNode {
    uint32_t key, value;
    struct _skiplistNode *backward;
    struct skiplistLevel {
        struct _skiplistNode *forward;
    } level[];
} skiplistNode;

typedef struct _skiplist {
    bucket_t *bucketBuffer, *bucketBufferCPU;
    int level, bufferUsed;
    unsigned long length;
    struct _skiplistNode *header, *tail;
} skiplist;

typedef struct {
    uint32_t min, max;
} range_t;

int slRandomLevel(void);
skiplistNode *slCreateNode(int level, _key_t key, value_t value);
skiplist *slCreate(void);
void slFreeNode(skiplistNode *node);
void slFree(skiplist *sl);
skiplistNode *slInsert(skiplist *sl, _key_t key, value_t value);
skiplistNode* slSearch(skiplist* sl, _key_t key);
#endif