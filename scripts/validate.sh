#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

fail() {
    printf 'Validation failed: %s\n' "$*" >&2
    exit 1
}

state() {
    local kind file
    if [[ -d templates && ! -L templates ]]; then
        for kind in tracer iterator map-iterator; do
            for file in program.bpf.c gadget.yaml README.md; do
                [[ -f templates/$kind/$file && ! -L templates/$kind/$file ]] ||
                    fail "Incomplete starter inventory"
            done
        done
        [[ -f scripts/init.sh && -f tests/init.sh &&
           ! -e program.bpf.c && ! -e gadget.yaml && ! -e config.mk ]] ||
            fail "Mixed initialized and template files"
        printf 'template\n'
    elif [[ ! -e templates && ! -L templates &&
            ! -e scripts/init.sh && ! -e tests/init.sh ]]; then
        for file in program.bpf.c gadget.yaml README.md config.mk; do
            [[ -f $file && ! -L $file ]] || fail "Incomplete initialized gadget"
        done
        printf 'initialized\n'
    else
        fail "Inconsistent repository state"
    fi
}

layout=$(state)
if [[ ${1:-} == --state && $# == 1 ]]; then
    printf '%s\n' "$layout"
    exit 0
fi
(($# == 0)) || fail "Usage: bash scripts/validate.sh [--state]"

shell_files=(scripts/*.sh)
if [[ $layout == template ]]; then shell_files+=(tests/init.sh); fi
for file in "${shell_files[@]}"; do bash -n "$file"; done
shellcheck "${shell_files[@]}"
make check
git diff --check
if [[ $layout == template ]]; then
    BUILD_GADGETS=1 bash tests/init.sh
else
    make build IMAGE_TAG="${IMAGE_TAG:-ci}"
fi
