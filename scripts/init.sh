#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
stage=

fail() {
    printf 'Initialization failed: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: bash scripts/init.sh [--type tracer|iterator|map-iterator]
                            [--repository OWNER/NAME]

Without --type, choose a data source type interactively.
The gadget name comes from the GitHub repository name.
This only prepares local files; it never commits, pushes, or publishes.
EOF
}

main() {
    local type='' repository='' remote='' choice=''
    while (($#)); do
        case "$1" in
            --type|--repository)
                (($# >= 2)) || fail "Missing value for $1"
                if [[ $1 == --type ]]; then type=$2; else repository=$2; fi
                shift 2
                ;;
            -h|--help) usage; return ;;
            *) fail "Unknown argument: $1 (use --help)" ;;
        esac
    done
    if [[ -z $type ]]; then
        [[ -t 0 ]] || fail "Use --type tracer|iterator|map-iterator without a terminal"
        printf 'Data source type:\n1) Tracer\n2) Iterator (snapshotter)\n3) Map iterator\n'
        read -r -p 'Choose [1-3]: ' choice || fail "No selection received"
        case "$choice" in
            1) type=tracer ;;
            2) type=iterator ;;
            3) type=map-iterator ;;
            *) fail "Invalid selection: $choice" ;;
        esac
    fi
    case "$type" in
        tracer|iterator|map-iterator) ;;
        *) fail "Invalid data source type: $type" ;;
    esac

    local root
    root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
    cd -- "$root"
    [[ $(git rev-parse --show-toplevel) == "$root" ]] ||
        fail "Run from a generated repository, not a nested source directory"
    [[ -d templates && ! -L templates ]] ||
        fail "Already initialized, or the templates directory is missing"
    [[ -z $(git status --porcelain --untracked-files=no) ]] ||
        fail "Commit or stash tracked changes before initializing"

    if [[ -z $repository ]]; then
        if [[ ${GITHUB_ACTIONS:-} == true ]]; then
            repository=${GITHUB_REPOSITORY:-}
        else
            remote=$(git remote get-url origin) ||
                fail "No origin remote; use --repository OWNER/NAME"
            case "$remote" in
                https://github.com/*) repository=${remote#https://github.com/} ;;
                git@github.com:*) repository=${remote#git@github.com:} ;;
                ssh://git@github.com/*) repository=${remote#ssh://git@github.com/} ;;
                *) fail "Cannot infer a GitHub repository; use --repository OWNER/NAME" ;;
            esac
            repository=${repository%.git}
        fi
    fi
    [[ $repository =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] ||
        fail "Expected a GitHub repository in OWNER/NAME form"
    [[ ${repository,,} != inspektor-gadget/gadget-template ]] ||
        fail "Create your own repository with Use this template first"

    local -a template_files=() cleanup=()
    local kind file path
    for kind in tracer iterator map-iterator; do
        [[ -d templates/$kind && ! -L templates/$kind ]] ||
            fail "Missing or unsafe starter directory: $kind"
        for file in program.bpf.c gadget.yaml README.md; do
            path=templates/$kind/$file
            [[ -f $path && ! -L $path ]] || fail "Missing or unsafe starter: $path"
            template_files+=("$path")
        done
    done
    # Refuse unknown files before deleting starter directories.
    while IFS= read -r -d '' path; do
        case "$path" in
            templates/tracer|templates/iterator|templates/map-iterator) ;;
            *)
                local known=false
                for file in "${template_files[@]}"; do
                    if [[ $path == "$file" ]]; then known=true; break; fi
                done
                [[ $known == true ]] || fail "Unexpected template path: $path"
                ;;
        esac
    done < <(find templates -mindepth 1 -print0)

    for file in program.bpf.c gadget.yaml config.mk; do
        [[ ! -e $file && ! -L $file ]] || fail "Refusing to overwrite $file"
    done
    for file in README.md Makefile LICENSE LICENSE-bpf.txt scripts/init.sh tests/init.sh; do
        [[ -f $file && ! -L $file ]] || fail "Missing or unsafe file: $file"
    done
    [[ ! -L scripts && ! -L tests ]] || fail "Bootstrap directories cannot be symlinks"
    cleanup=("${template_files[@]}" scripts/init.sh tests/init.sh)

    local name=${repository#*/} image=ghcr.io/${repository,,}
    [[ ${repository,,} =~ ^[a-z0-9]+(-[a-z0-9]+)*/[a-z0-9]+(([._]|__|-+)[a-z0-9]+)*$ ]] ||
        fail "Repository name is not a valid OCI image path; use --repository OWNER/NAME"
    stage=$(mktemp -d)
    # The staging directory contains only these explicitly created files.
    trap 'rm -f -- "$stage/program.bpf.c" "$stage/gadget.yaml" "$stage/README.md" "$stage/config.mk"; rmdir -- "$stage"' EXIT
    for file in program.bpf.c gadget.yaml README.md; do
        local line
        while IFS= read -r line || [[ -n $line ]]; do
            line=${line//@GADGET_NAME@/$name}
            line=${line//@REPOSITORY@/$repository}
            line=${line//@IMAGE@/$image}
            printf '%s\n' "$line"
        done < "templates/$type/$file" > "$stage/$file"
        [[ -s $stage/$file ]] || fail "Empty generated file: $file"
        if grep -Eq '@(GADGET_NAME|REPOSITORY|IMAGE)@' "$stage/$file"; then
            fail "Unresolved placeholder in $file"
        fi
    done
    printf 'CONTAINER_REPO ?= %s\n' "$image" > "$stage/config.mk"

    for file in program.bpf.c gadget.yaml README.md config.mk; do
        mv -- "$stage/$file" "$file"
    done
    rm -- "${cleanup[@]}"
    rmdir -- templates/tracer templates/iterator templates/map-iterator templates
    rmdir --ignore-fail-on-non-empty -- scripts tests
    printf 'Initialized %s as %s.\nReview git diff, then run make build.\n' "$name" "$type"
}

# Read the whole implementation before removing this script during initialization.
main "$@"
