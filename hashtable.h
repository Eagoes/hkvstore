#ifndef __HASHTABLE_H
#define __HASHTABLE_H

#include <stdint.h>
#include <cuda_runtime.h>

#define SKIPLIST_P 0.25
#define GPU_BUFFERBITS 10
#define GPU_SKIPLIST_MAXLEVEL 4
#define CPU_SKIPLIST_MAXLEVEL (GPU_SKIPLIST_MAXLEVEL + GPU_BUFFERBITS / 2)

//hash table
#define ROUND 16
//CPU parallel level, equal to cores of CPU
#define GROUP 4
#define GROUPSIZE 1024

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
    int bucketId, numInBucket;
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
void slInsert(skiplist *sl, _key_t key, value_t value);
skiplistNode* slSearch(skiplist* sl, _key_t key);
#endif