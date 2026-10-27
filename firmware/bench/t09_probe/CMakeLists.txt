cmake_minimum_required(VERSION 3.16)

# T09 bench probe — a throwaway IDF project, deliberately outside the product
# build (firmware/CMakeLists.txt does not reference it). It exists to answer the
# board-identity and GPIO0 deep-sleep-wake questions and is not product code.
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(t09_probe)
