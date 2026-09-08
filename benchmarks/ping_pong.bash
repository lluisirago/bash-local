#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# bash-local Ping-Pong Benchmark
# -----------------------------------------------------------------------------

set -euo pipefail

# -----------------------------
# Colors
# -----------------------------
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
WHITE="\033[1;97m"
RESET="\033[0m"

# -----------------------------
# Configuration
# -----------------------------
CYCLES=500
WARMUP_CYCLES=20
RUNS=3
MIN_SIZE=5
MAX_SIZE=15

# -----------------------------
# Argument parsing
# -----------------------------
MODE="single"

if [[ $# -eq 1 ]]; then
    SIZE="$1"
elif [[ $# -eq 3 && "$1" == "--range" ]]; then
    MODE="range"
    MIN_SIZE="$2"
    MAX_SIZE="$3"
else
    echo -e "${YELLOW}Usage:${RESET}"
    echo "  $0 <size>"
    echo "  $0 --range <min> <max>"
    exit 1
fi

# -----------------------------
# Paths
# -----------------------------
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
BL_PATH="${PROJECT_ROOT}/usr/share/bash-local/bash-local"

BENCH_DIR="$HOME/ping_pong"
DIR_A="$BENCH_DIR/a"
DIR_B="$BENCH_DIR/b"

CSV_FILE="$(mktemp)"

# -----------------------------
# Create environment
# -----------------------------
create_env() {

    local SIZE="$1"
    rm -rf "$BENCH_DIR"
    mkdir -p "$DIR_A/.bl/source" "$DIR_B/.bl/source"

    echo "$(( SIZE + 1 ))" > "$DIR_A/.bl/manifest"
    : > "$DIR_A/.bl/source/local"
    for ((i = 0; i < SIZE; i++)); do
        echo "var_a_$i local var $i" >> "$DIR_A/.bl/manifest"
        echo "var_a_$i=$i" >> "$DIR_A/.bl/source/local"
    done
    : > "$DIR_A/.bl/source/scoped"

    echo "$(( SIZE + 1 ))" > "$DIR_B/.bl/manifest"
    : > "$DIR_B/.bl/source/local"
    for ((i = 0; i < SIZE; i++)); do
        echo "var_b_$i local var $i" >> "$DIR_B/.bl/manifest"
        echo "var_b_$i=$i" >> "$DIR_B/.bl/source/local"
    done
    : > "$DIR_B/.bl/source/scoped"
}

# -----------------------------
# Timing function
# -----------------------------
run_cycles() {

    local cycles="$1"
    builtin cd "$DIR_B"
    
    local start
    start=$(date +%s%N)

    for ((_j_ = 0; _j_ < cycles; _j_++)); do
        cd "$DIR_A"
        cd "$DIR_B"
    done

    local end
    end=$(date +%s%N)

    echo $(( end - start ))
}

# -----------------------------
# Benchmark a given size
# -----------------------------
benchmark_size() {

    local SIZE="$1"
    echo -e "${WHITE}Size $SIZE:${RESET}"
    create_env "$SIZE"

    # Warm-up
    run_cycles "$WARMUP_CYCLES" > "/dev/null"

    local results=()

    for ((_r_ = 0; _r_ < RUNS; _r_++)); do

        elapsed_ns=$(run_cycles "$CYCLES")
        ops=$(( CYCLES * 2 ))
        avg_ns=$(( elapsed_ns / ops ))
        avg_ms=$(awk "BEGIN {printf \"%.3f\", $avg_ns/1000000}")
        results+=("$avg_ms")
        echo -e "($((_r_+1))/${RUNS}) ${avg_ms} ms"
    done

    # Compute mean and stddev
    read -r mean stddev <<< "$(printf "%s\n" "${results[@]}" | awk '
    {
        sum += $1
        sumsq += ($1)^2
        n++
    }
    END {
        mean = sum/n
        stddev = sqrt((sumsq/n) - (mean^2))
        printf "%.3f %.3f", mean, stddev
    }')"

    echo -e "  Time (${GREEN}mean${RESET} ± ${GREEN}σ${RESET}):    ${GREEN}${mean} ms${RESET} ± ${GREEN}${stddev} ms${RESET}    [$(( RUNS * CYCLES )) runs]"

    echo "$SIZE,$mean,$stddev" >> "$CSV_FILE"
    rm -rf "$BENCH_DIR"
}

# -----------------------------
# Main execution
# -----------------------------
echo "size,mean_ms,stddev_ms" > "$CSV_FILE"
source "$BL_PATH"
echo "Benchmark started" #
if [[ "$MODE" == "single" ]]; then
    benchmark_size "$SIZE"
else
    for ((s = MIN_SIZE; s <= MAX_SIZE; s++)); do
        benchmark_size "$s"
    done
fi

if [[ "$MODE" == "range" ]]; then

    # -----------------------------
    # Print table
    # -----------------------------
    echo
    echo -e "${YELLOW}Benchmark Results:${RESET}"
    column -t -s, "$CSV_FILE"

    # -----------------------------
    # Plot with gnuplot
    # -----------------------------
    if command -v gnuplot &>/dev/null; then
        gnuplot <<EOF
set datafile separator ","
set key autotitle columnhead
set terminal dumb size 100,30
set title "Ping-Pong Benchmark"
set xlabel "Environment Size"
set ylabel "Avg ms per cd"
set grid
plot "$CSV_FILE" using 1:2 with linespoints
EOF
    else
        echo -e "${RED}gnuplot not installed — skipping plot.${RESET}"
    fi
fi

rm -rf "$BENCH_DIR"
