# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
cmake_minimum_required(VERSION 3.24)
project(shadps4_cache_runtime_test LANGUAGES CXX)
enable_testing()
find_package(Threads REQUIRED)
add_executable(shadps4_cache_runtime_test test_cache_runtime.cpp ../../src/video_core/cache_file.cpp)
target_compile_features(shadps4_cache_runtime_test PRIVATE cxx_std_23)
target_include_directories(shadps4_cache_runtime_test PRIVATE ../../src ../../externals/xxhash)
target_compile_definitions(shadps4_cache_runtime_test PRIVATE XXH_INLINE_ALL WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(shadps4_cache_runtime_test PRIVATE Threads::Threads)
add_test(NAME cache_runtime COMMAND shadps4_cache_runtime_test "${CMAKE_CURRENT_BINARY_DIR}")
set_tests_properties(cache_runtime PROPERTIES TIMEOUT 30)

# In-memory CPU memo checks; no Vulkan device, game files, downloads, or test data files.
add_executable(shadps4_runtime_memo_test test_runtime_memo.cpp)
target_compile_features(shadps4_runtime_memo_test PRIVATE cxx_std_23)
target_include_directories(shadps4_runtime_memo_test PRIVATE ../../src)
add_test(NAME runtime_memo COMMAND shadps4_runtime_memo_test)
set_tests_properties(runtime_memo PROPERTIES TIMEOUT 10)

# The actual publication gate used before deferred Vulkan binds, without a GPU or game.
add_executable(shadps4_compile_readiness_test test_compile_readiness.cpp)
target_compile_features(shadps4_compile_readiness_test PRIVATE cxx_std_23)
target_include_directories(shadps4_compile_readiness_test PRIVATE ../../src)
target_link_libraries(shadps4_compile_readiness_test PRIVATE Threads::Threads)
add_test(NAME compile_readiness COMMAND shadps4_compile_readiness_test)
set_tests_properties(compile_readiness PROPERTIES TIMEOUT 10)

add_executable(shadps4_buffer_access_test test_buffer_access.cpp)
target_compile_features(shadps4_buffer_access_test PRIVATE cxx_std_23)
target_include_directories(shadps4_buffer_access_test PRIVATE ../../src)
add_test(NAME buffer_access COMMAND shadps4_buffer_access_test)
set_tests_properties(buffer_access PROPERTIES TIMEOUT 10)

add_executable(shadps4_range_set_test test_range_set.cpp)
target_compile_features(shadps4_range_set_test PRIVATE cxx_std_23)
target_include_directories(shadps4_range_set_test PRIVATE ../../src ../../externals/ext-boost)
add_test(NAME range_set COMMAND shadps4_range_set_test)
set_tests_properties(range_set PROPERTIES TIMEOUT 10)
