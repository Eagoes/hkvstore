#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/time.h>
#include <tclap/CmdLine.h>
#include <iostream>
#include "skiplist.h"

#define RANGEBITS 22
#define RANGE (1 << RANGEBITS)
#define MIN 0
#define MAX 0xffffffff

void RangeTest(skiplist* sl, value_t* results, _key_t min, _key_t max, int maxLength) {
    skiplistNode* start = slSearch(sl, min);
    skiplistNode* end = slSearch(sl, max);
    skiplistNode* node = start;
    for (int index = 0; start != end; index += 1, node = node->level[0].forward) {
        if (index >= maxLength)break;
        results[index] = node->value;
    }   
}

int main(int argc, char* argv[]) {
    int round, groupSize;
    value_t* results;
    struct timeval t1, t2;
    double timeuse;
    try {
        //parse the command args
        TCLAP::CmdLine cmd("Command Description Message", ' ', "1.0");
        TCLAP::ValueArg<int> roundArg("r", "round", "Rounds of the test", false, 16, "int");
        cmd.add(roundArg);

        TCLAP::ValueArg<int> groupSizeArg("s", "size", "The size of searching group and equals to the scale of the result array", false, 1024, "int");
        cmd.add(groupSizeArg);

        cmd.parse(argc, argv);
        round = roundArg.getValue();
        groupSize = groupSizeArg.getValue();
    } catch(TCLAP::ArgException &e) {
        std::cerr << "error: " << e.error() << " for arg " << e.argId() << std::endl;
        exit(1);
    }
    results = (value_t*)malloc(RANGE * sizeof(value_t));
    if (!results) {
        printf("No More Memory For Malloc\n");
        exit(1);
    }

    FILE* file = fopen("keys.txt", "r");
    uint32_t key, value;
    skiplist* sl = slCreate();
    while(!feof(file)) {
        fscanf(file, "%u %u", &key, &value);
        skiplistNode* node = slInsert(sl, key, value);
        if (!node) {
            exit(1);
        }
    }
    printf("Finish input\n");

    for (int size = 1024; size <= groupSize; size *= 2) {
        gettimeofday(&t1, NULL);
        for (int r = 0; r < round; r++) {
            RangeTest(sl, results, MIN, MAX, size);
        }
        gettimeofday(&t2, NULL);
        timeuse = ((t2.tv_sec - t1.tv_sec) * 1000.0 + (t2.tv_usec - t1.tv_usec)/1000.0) / round;
        std::cout << "Group Size:\t" << size << "\tTime:\t" << timeuse << std::endl;
        std::cout.flush();
    }
    slFree(sl);
}
