cmake_minimum_required(VERSION 3.16)

# T10 bench probe - a throwaway IDF project, deliberately outside the product
# build. It captures Smoke X4 LoRa traffic for the parser fixture corpus.
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(t10_probe)
