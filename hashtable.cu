
#include <stdlib.h>
#include <string.h>
#include <algorithm>
#include <iostream>
#include <omp.h>
#include <sys/time.h>
#include <tclap/CmdLine.h>
#include <helper_cuda.h>
#include "hashtable.h"

__global__ void bucket_search(range_t* range,value_t* results,bucket_t* bucketArray,int* bucketIdxArray
){
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int bucketIdx = tid / BUFFERSCALE;
    int idx = tid % BUFFERSCALE;
    bucket_t* bucket = &(bucketArray[bucketIdx]);
    uint32_t min = range->min;
    uint32_t max = range->max;
    _key_t key = bucket->kvArray[idx].key;
    results[tid] = (key >= min && key <= max) ? bucket->kvArray[idx].value : 0;
}

bool compare(const key_value_t& a, const key_value_t& b) {
    return a.key < b.key;
}

void BucketInsertByCPU(
    _key_t key, 
    value_t value, 
    bucket_t* bucketArray,
    int bucketId,
    int numInBucket,
    int bucketUsed,
    _key_t* newNodeKey)
{
    bucket_t* bucket = &(bucketArray[bucketId]);
    bucket->kvArray[numInBucket].key = key;
    bucket->kvArray[numInBucket].value = value;
    if (numInBucket + 1 == BUFFERSCALE) {
        //split
        std::sort(bucket->kvArray, bucket->kvArray + BUFFERSCALE, &compare);
        *newNodeKey = bucket->kvArray[BUFFERSCALE / 2].key;
        bucket_t* newBucket = &(bucketArray[bucketUsed]);
        memcpy(newBucket->kvArray, bucket->kvArray, sizeof(BUFFERSCALE * sizeof(key_value_t) / 2));
    }
}

int slRandomLevel(void) {
    int level = 1;
    while ((random()&0xFFFF) < (SKIPLIST_P * 0xFFFF))
        level += 1;
    return (level<GPU_SKIPLIST_MAXLEVEL) ? level : GPU_SKIPLIST_MAXLEVEL;
}

skiplistNode *slCreateNode(int level, _key_t key, int bufferId, int numInBucket = 1) {
    skiplistNode *node = (skiplistNode*)malloc(sizeof(skiplistNode)+level*sizeof(skiplistNode*));
    node->key = key;
    node->bucketId = bufferId;
    node->numInBucket = numInBucket;
    return node;
}

skiplist* slCreate(void) {
    int j;
    skiplist *sl;
    sl = (skiplist*)malloc(sizeof(*sl));

    //cudaMalloc
    checkCudaErrors(cudaMalloc((void**) &sl->bucketBuffer, BUFFERNUM * sizeof(bucket_t)));

    //malloc
    sl->bucketBufferCPU = (bucket_t*)malloc(BUFFERNUM * sizeof(bucket_t));

    sl->bufferUsed = 1;
    sl->level = 1;
    sl->length = 1;
    sl->header = slCreateNode(GPU_SKIPLIST_MAXLEVEL, 0, 0, 1);
    //BucketInsert<<<1, 1>>>(0, 0, sl->bucketBuffer);
    BucketInsertByCPU(0, 0, sl->bucketBufferCPU, 0, 0, 0, NULL);
    for (j = 0; j < GPU_SKIPLIST_MAXLEVEL; j++) {
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
    checkCudaErrors(cudaFree(sl->bucketBuffer));
    free(sl->bucketBufferCPU);

    free(sl);
}

skiplistNode* slSearchForNode(skiplist *sl, _key_t key) {
    skiplistNode *node = sl->header;
    for (int i = sl-> level - 1; i >= 0; i--) {
        while (node->level[i].forward && node->level[i].forward->key < key)
            node = node->level[i].forward;
    }
    return node;
}

void slInsert(skiplist *sl, _key_t key, value_t value) {
    skiplistNode* targetNode = slSearchForNode(sl, key);
    _key_t h_result = 0;
    if (targetNode->numInBucket < BUFFERSCALE - 1) {
        BucketInsertByCPU(key, value, sl->bucketBufferCPU, targetNode->bucketId, targetNode->numInBucket, sl->bufferUsed, &h_result);
        targetNode->numInBucket += 1;
    } else {
        // need to split the node into two nodes
        if (sl->bufferUsed == BUFFERNUM){
            printf("No more buffer can be used!\n");
            exit(1);
        }
        BucketInsertByCPU(key, value, sl->bucketBufferCPU, targetNode->bucketId, targetNode->numInBucket, sl->bufferUsed, &h_result);
        targetNode->numInBucket = BUFFERSCALE / 2;
        
        //create the new node and insert into skiplist
        skiplistNode *update[GPU_SKIPLIST_MAXLEVEL], *x;
        int i, level;

        x = sl->header;
        for (i = sl->level-1; i >= 0; i--) {
            while (x->level[i].forward && x->level[i].forward->key < h_result)
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
        x = slCreateNode(level, h_result, sl->bufferUsed, BUFFERSCALE / 2);
        sl->bufferUsed += 1;
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
    }
}

void BufferMemCpy(skiplist* sl) {
    checkCudaErrors(cudaMemcpy(sl->bucketBuffer, sl->bucketBufferCPU, BUFFERNUM * sizeof(bucket_t), cudaMemcpyHostToDevice));
}

void getIndexArray(skiplist* sl, _key_t keyMin, _key_t keyMax, int* bufferIndex, int groupSize) {
    skiplistNode* startNode = slSearchForNode(sl, keyMin);
    skiplistNode* endNode = slSearchForNode(sl, keyMax);
    int idx = 0, idxInArray = 0;
    for (skiplistNode* node = startNode; node != endNode->level[0].forward; node = node->level[0].forward) {
        idxInArray += BUFFERSCALE;
        if (idxInArray >= groupSize)break;
        bufferIndex[idx++] = node->bucketId;
    }
}

int main(int argc, char* argv[]) {
    int round = 0, cthreads = 20, gthreads = 64, groupSize = 0;
    int *bufferIndex_h, *bufferIndex_d;
    value_t *result_h, *result_d;
    range_t range_h = {0, 1024}, *range_d;
    struct timeval t1, t2;
    double timeuse;
    try {
        //parse the command args
        TCLAP::CmdLine cmd("Command Description Message", ' ', "1.0");
        TCLAP::ValueArg<int> roundArg("r", "round", "Rounds of the test", false, 16, "int");
        cmd.add(roundArg);

        TCLAP::ValueArg<int> cthreadArg("t", "cpu_threads", "The number of threads of CPU utilized for testing", false, 20, "int");
        cmd.add(cthreadArg);

        TCLAP::ValueArg<int> groupSizeArg("s", "size", "The size of searching group and equals to the scale of the result array", false, 1024, "int");
        cmd.add(groupSizeArg);

        TCLAP::ValueArg<int> gthreadArg("g", "gpu_threads", "The number of threads of GPU utilized for testing", false, 64, "int");
        cmd.add(gthreadArg);

        cmd.parse(argc, argv);
        round = roundArg.getValue();
        cthreads = cthreadArg.getValue();
        groupSize = groupSizeArg.getValue();
        gthreads = gthreadArg.getValue();
    } catch(TCLAP::ArgException &e) {
        std::cerr << "error: " << e.error() << " for arg " << e.argId() << std::endl;
        exit(1);
    }

    omp_set_num_threads(cthreads);
    //printf("%d %d %d\n", round, cthreads, groupSize);
    //allocate CPU result buffer
    int groupMemSize = groupSize * sizeof(int);
    bufferIndex_h = (int*)malloc(cthreads * groupMemSize);
    result_h = (uint32_t*)malloc(cthreads * groupSize * sizeof(uint32_t));
    if (!bufferIndex_h || !result_h) {
        std::cerr << "Memory Allocation For Host Buffer has been wrong" << std::endl;
    }

    //allocate GPU result buffer
    checkCudaErrors(cudaMalloc((void**)&bufferIndex_d, cthreads * groupMemSize));
    checkCudaErrors(cudaMalloc((void**)&result_d, cthreads * groupSize * sizeof(uint32_t)));
    checkCudaErrors(cudaMalloc((void**)&range_d, sizeof(range_t)));
    checkCudaErrors(cudaMemcpy(range_d, &range_h, sizeof(range_t), cudaMemcpyHostToDevice));

    
    //init the skiplist and bucket
    skiplist* sl = slCreate();
    FILE* file = fopen("keys.txt", "r");
    uint32_t key, value;
    while (!feof(file)) {
        fscanf(file, "%u %u", &key, &value);
        slInsert(sl, key, value);
    }
    BufferMemCpy(sl);

    cudaStream_t* streams = (cudaStream_t*)malloc(cthreads * sizeof(cudaStream_t));
    if(!streams) {
        std::cerr << "Memory Allocation for streams goes wrong" << std::endl;
        exit(1);
    }
    for (int i = 0; i < cthreads; i++)
        checkCudaErrors(cudaStreamCreate(&(streams[i])));

    for (int size = 1024; size <= groupSize; size *= 2) {
        gettimeofday(&t1, NULL);
        for (int r = 0; r < round; r++) {
            //global rounds of the test
            #pragma omp parallel for
            for (int t = 0; t < cthreads; t++) {
                //thread work
                getIndexArray(sl, range_h.min, range_h.max, bufferIndex_h + t * size, size);
            }
            for (int t = 0; t < cthreads; t++) {
                checkCudaErrors(cudaMemcpyAsync(bufferIndex_d + t * size, bufferIndex_h + t * size, size * sizeof(int), cudaMemcpyHostToDevice, streams[t]));
                bucket_search<<<size / gthreads, gthreads, 0, streams[t]>>>(range_d, result_d + t * size, sl->bucketBuffer, bufferIndex_d + t * size);
                checkCudaErrors(cudaMemcpyAsync(result_h + t * size, result_d + t * size, size * sizeof(uint32_t), cudaMemcpyDeviceToHost, streams[t]));
            }
        }
        checkCudaErrors(cudaThreadSynchronize());
        gettimeofday(&t2, NULL);
        timeuse = ((t2.tv_sec - t1.tv_sec)  * 1000.0 + (t2.tv_usec - t1.tv_usec)/1000.0) / round;
        std::cout << "Group Size:\t" << size << "\tTime:\t" << timeuse << std::endl;
        std::cout.flush();
    }
    slFree(sl);

    for (int i = 0; i < cthreads; i++)
        checkCudaErrors(cudaStreamDestroy(streams[i]));
}
