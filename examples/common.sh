#!/bin/bash

set -e           # Fail in case of error
set -o nounset   # Fail if undefined variables are used
set -o pipefail  # Fail if one of the piped commands fails


function setup_colors() {
    # Only use colors if connected to a terminal
    if [ -t 1 ]; then
        RED=$(printf '\033[31m')
        GREEN=$(printf '\033[32m')
        YELLOW=$(printf '\033[33m')
        BLUE=$(printf '\033[34m')
        BOLD=$(printf '\033[1m')
        RESET=$(printf '\033[m')
        PREVIOUS_LINE=$(printf '\e[1A')
        CLEAR_LINE=$(printf '\e[K')
    else
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        BOLD=""
        RESET=""
        PREVIOUS_LINE=""
        CLEAR_LINE=""
    fi
}

function error() {
    echo -e "${RED}${BOLD}ERROR${RESET}\t$1"
}

function warning() {
    echo -e "${YELLOW}${BOLD}WARN${RESET}\t$1"
}

function info() {
    echo -e "${BLUE}${BOLD}INFO${RESET}\t$1"
}

function success_clear_line() {
    echo -e "${PREVIOUS_LINE}${CLEAR_LINE}${GREEN}${BOLD}SUCCESS${RESET}\t$1"
}

function success() {
    echo -e "${GREEN}${BOLD}SUCCESS${RESET}\t$1"
}

setup_colors