#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# @file main.bash
# @brief Benchmark suite entry point for bash-local.
#
# @description
# Executes performance stress tests to measure the overhead of directory
# context switching. It creates temporary environments with variable loads to
# simulate real-world usage.
#
# @option -s <N> | --size <N> Run a single benchmark with N variables.
# @option -r <MIN-MAX> | --range <MIN-MAX> Run a series of benchmarks from MIN to MAX vars.
# @option -h | --help Display help.
#
# @example
#   ./main.bash --size 500
#
# @example
#   ./main.bash --range 10-100   # Test scalability curve
#
# @exitcode 0 Benchmark completed successfully.
# @exitcode 1 Runtime dependency missing or setup failure.
# -----------------------------------------------------------------------------
set -euo pipefail

# MARK: Consts
# Colors
declare -r CONST_COLOR_GREEN="\033[1;32m"
declare -r CONST_COLOR_WHITE="\033[1;97m"
declare -r CONST_COLOR_RESET="\033[0m"

# Default configuration
declare CONF_CYCLES=1000
declare CONF_WARMUP_CYCLES=20
declare MIN_SIZE=5
declare MAX_SIZE=10