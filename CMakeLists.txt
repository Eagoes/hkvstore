cmake_minimum_required(VERSION 3.10)
project(hkvstore)

find_package(CUDA REQUIRED)
find_package(OpenMP REQUIRED)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${OpenMP_CXX_FLAGS} -std=c++11")
set(CUDA_NVCC_FLAGS "${CUDA_NVCC_FLAGS} -Xcompiler ${OpenMP_CXX_FLAGS} -gencode arch=compute_70,code=sm_70")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${OpenMP_EXE_LINKER_FLAGS}")

include_directories(
        ./
        /usr/include
        /usr/local/include
        /usr/local/cuda/include/ 
)

link_directories(
        /usr/lib
        /usr/local/lib
        /usr/local/cuda/lib64
)

cuda_add_executable(gpu_test
        hashtable.h
        hashtable.cu)

add_executable(cpu_test
        skiplist.h
        skiplist.cc
        test.cc)

cuda_add_executable(sortcompare
    sortCompare.h
    sortCompare.cu)