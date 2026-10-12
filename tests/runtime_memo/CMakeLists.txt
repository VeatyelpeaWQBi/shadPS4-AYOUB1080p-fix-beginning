# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
cmake_minimum_required(VERSION 3.24)
project(shadps4_runtime_memo_test LANGUAGES CXX)
enable_testing()
add_executable(shadps4_runtime_memo_test test_runtime_memo.cpp)
target_compile_features(shadps4_runtime_memo_test PRIVATE cxx_std_23)
target_include_directories(shadps4_runtime_memo_test PRIVATE ../../src)
add_test(NAME runtime_memo COMMAND shadps4_runtime_memo_test)
set_tests_properties(runtime_memo PROPERTIES TIMEOUT 10)
