#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

source_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
workspace=$(mktemp -d -t gadget-template-test.XXXXXX)
trap 'rm -rf -- "$workspace"' EXIT
fixture=

cat > "$workspace/ig" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$IG_TEST_LOG"
if [[ $1 == image && $2 == build ]]; then
    exit "${IG_TEST_BUILD_STATUS:-0}"
fi
EOF
chmod +x "$workspace/ig"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

new_fixture() {
    fixture=$workspace/$1
    mkdir -- "$fixture"
    tar -C "$source_root" --exclude=.git -cf - . | tar -C "$fixture" -xf -
    git -C "$fixture" init -q -b main
    git -C "$fixture" add -f .
    git -C "$fixture" -c user.name=Test -c user.email=test@example.invalid \
        -c core.hooksPath=/dev/null commit -qm fixture
    git -C "$fixture" remote add origin https://github.com/Example/My-Gadget.git
}

initialize() {
    env -u GITHUB_ACTIONS -u GITHUB_REPOSITORY bash "$fixture/scripts/init.sh" "$@"
}

fingerprint() {
    (
        cd -- "$fixture"
        find . -path ./.git -prune -o -type f -print0 |
            sort -z | xargs -0 sha256sum
        git status --porcelain --untracked-files=all
    )
}

expect_failure() {
    local message=$1 before
    shift
    before=$(fingerprint)
    if initialize "$@" > "$workspace/error.log" 2>&1; then
        fail "Expected failure: $message"
    fi
    grep -Fq "$message" "$workspace/error.log" ||
        { cat "$workspace/error.log" >&2; fail "Missing diagnostic: $message"; }
    [[ $(fingerprint) == "$before" ]] || fail "Failure changed user files: $message"
}

for type in tracer iterator map-iterator; do
    new_fixture "$type"
    [[ $(bash "$fixture/scripts/validate.sh" --state) == template ]] ||
        fail "Wrong initial state"
    if make -s -C "$fixture" > "$workspace/error.log" 2>&1; then
        fail "Uninitialized repository built an implicit default gadget"
    fi
    grep -q 'Initialize first' "$workspace/error.log" ||
        fail "Missing pre-initialization instructions"
    if make -s -C "$fixture" run-local SUDO= IG="$workspace/ig" \
        > "$workspace/error.log" 2>&1; then
        fail "Uninitialized repository allowed run-local"
    fi
    grep -q 'Initialize first' "$workspace/error.log" ||
        fail "Missing run-local pre-initialization instructions"
    workflow_hashes=$(sha256sum "$fixture"/.github/workflows/*.yml)
    head_before=$(git -C "$fixture" rev-parse HEAD)
    printf 'keep me\n' > "$fixture/unrelated.txt"
    mkdir "$fixture/scripts/user"
    printf 'keep me too\n' > "$fixture/scripts/user/file"
    # Invoke from outside the fixture's root.
    (cd -- "$workspace"; initialize --type "$type")
    [[ $(bash "$fixture/scripts/validate.sh" --state) == initialized ]] ||
        fail "Wrong generated state"
    [[ ! -e $fixture/templates && ! -e $fixture/scripts/init.sh &&
       ! -e $fixture/tests/init.sh ]] || fail "Bootstrap files survived"
    [[ -f $fixture/LICENSE && -f $fixture/LICENSE-bpf.txt &&
       -f $fixture/SIGNING.md && -f $fixture/.gitignore &&
       -d $fixture/.git && -f $fixture/unrelated.txt &&
       -f $fixture/scripts/user/file ]] || fail "User or license files lost"
    [[ $(git -C "$fixture" rev-parse HEAD) == "$head_before" ]] ||
        fail "Local initializer created a commit"
    printf '%s\n' "$workflow_hashes" | sha256sum --check --status ||
        fail "Initialization modified workflows"
    grep -q '^name: "My-Gadget"$' "$fixture/gadget.yaml" || fail "Wrong gadget name"
    grep -q '^CONTAINER_REPO ?= ghcr.io/example/my-gadget$' "$fixture/config.mk" ||
        fail "Wrong image name"
    grep -q '^# My-Gadget$' "$fixture/README.md" || fail "Wrong generated README"
    if grep -Eq '@(GADGET_NAME|REPOSITORY|IMAGE)@|CHANGEME' \
        "$fixture/README.md" "$fixture/gadget.yaml" "$fixture/program.bpf.c"; then
        fail "Unresolved project placeholders"
    fi
    case "$type" in
        tracer) macro=GADGET_TRACER; datasource=events ;;
        iterator) macro=GADGET_ITER; datasource=processes ;;
        map-iterator) macro=GADGET_MAPITER; datasource=calls ;;
    esac
    grep -q "^$macro(" "$fixture/program.bpf.c" || fail "Wrong starter program"
    grep -q "^  $datasource:" "$fixture/gadget.yaml" || fail "Wrong data source"
    make -s -C "$fixture" check
    make -n -C "$fixture" | grep -q ' image build' ||
        fail "Default make target did not build the initialized gadget"
    export IG_TEST_LOG=$workspace/ig.log
    : > "$IG_TEST_LOG"
    PARAMS="--host --timeout 1 -o json" make -s -C "$fixture" run-local \
        SUDO= IG="$workspace/ig" CONTAINER_REPO=example/local IMAGE_TAG=test \
        BUILDER_IMAGE=example/builder:test
    printf '%s\n' \
        'image build --builder-image example/builder:test -t example/local:test .' \
        'run example/local:test --verify-image=false --pull never --host --timeout 1 -o json' \
        > "$workspace/expected.log"
    diff -u "$workspace/expected.log" "$IG_TEST_LOG" ||
        fail "run-local did not build then run with local defaults and PARAMS"
    : > "$IG_TEST_LOG"
    if IG_TEST_BUILD_STATUS=1 make -s -C "$fixture" run-local \
        SUDO= IG="$workspace/ig" > "$workspace/error.log" 2>&1; then
        fail "run-local ignored build failure"
    fi
    if grep -q '^run ' "$IG_TEST_LOG"; then
        fail "run-local ran a stale image after build failure"
    fi
    : > "$IG_TEST_LOG"
    PARAMS="--host" make -s -C "$fixture" run SUDO= IG="$workspace/ig" \
        CONTAINER_REPO=example/local IMAGE_TAG=test
    [[ $(cat "$IG_TEST_LOG") == 'run example/local:test --host' ]] ||
        fail "run no longer runs an existing image unchanged"
    if [[ ${BUILD_GADGETS:-0} == 1 ]]; then
        IMAGE_TAG="ci-$type" bash "$fixture/scripts/validate.sh"
        read -r -a sudo_command <<< "${SUDO-sudo}"
        "${sudo_command[@]}" "${IG:-ig}" image inspect \
            "ghcr.io/example/my-gadget:ci-$type" --verify-image=false \
            --show-datasources -o json > "$workspace/metadata.json"
        jq -e --arg datasource "$datasource" \
            'length == 1 and .[0].name == $datasource and
             any(.[0].fields[]; .name == "pid")' \
            "$workspace/metadata.json" > /dev/null ||
            fail "Built image did not expose the expected process data source"
    fi

    # The retained workflow checks state before calling the removed initializer.
    before=$(fingerprint)
    for selected_type in "$type" tracer iterator map-iterator; do
        layout=$(bash "$fixture/scripts/validate.sh" --state)
        if [[ $layout == template ]]; then
            initialize --type "$selected_type"
        fi
        [[ $layout == initialized && $(fingerprint) == "$before" ]] ||
            fail "Repeat workflow run was not a no-op"
    done
    # A saved copy of the initializer must also refuse to overwrite a gadget.
    cp "$source_root/scripts/init.sh" "$fixture/scripts/init.sh"
    expect_failure "Already initialized" --type "$type"
done

new_fixture invalid
expect_failure "Invalid data source type" --type unknown
expect_failure "Missing value" --type
expect_failure "Unknown argument" --unknown
expect_failure "without a terminal" </dev/null
expect_failure "OWNER/NAME" --type tracer --repository 'bad/name;ignored'
expect_failure "Use this template" --type tracer --repository inspektor-gadget/gadget-template
printf '\nlocal edit\n' >> "$fixture/Makefile"
expect_failure "Commit or stash" --type tracer
git -C "$fixture" -c user.name=Test -c user.email=test@example.invalid \
    -c core.hooksPath=/dev/null commit -qam 'fixture edit'
printf 'untracked user program\n' > "$fixture/program.bpf.c"
expect_failure "Refusing to overwrite" --type tracer

new_fixture missing
rm -- "$fixture/templates/iterator/gadget.yaml"
git -C "$fixture" -c user.name=Test -c user.email=test@example.invalid \
    -c core.hooksPath=/dev/null commit -qam 'incomplete fixture'
expect_failure "Missing or unsafe starter" --type tracer
if bash "$fixture/scripts/validate.sh" --state > "$workspace/error.log" 2>&1; then
    fail "Incomplete state accepted"
fi

new_fixture unknown-file
printf 'do not delete\n' > "$fixture/templates/user-file"
expect_failure "Unexpected template path" --type tracer

new_fixture unsafe
rm -- "$fixture/templates/tracer/program.bpf.c"
ln -s "$fixture/README.md" "$fixture/templates/tracer/program.bpf.c"
git -C "$fixture" add templates
git -C "$fixture" -c user.name=Test -c user.email=test@example.invalid \
    -c core.hooksPath=/dev/null commit -qm 'symlink fixture'
expect_failure "Missing or unsafe starter" --type tracer

for protocol in ssh ssh-url https override workflow; do
    new_fixture "identity $protocol"
    case "$protocol" in
        ssh) remote=git@github.com:Owner/Other-Gadget.git ;;
        ssh-url) remote=ssh://git@github.com/Owner/Other-Gadget.git ;;
        https) remote=https://github.com/Owner/Other-Gadget.git ;;
        override|workflow) remote=https://github.com/inspektor-gadget/gadget-template.git ;;
    esac
    git -C "$fixture" remote set-url origin "$remote"
    case "$protocol" in
        override) initialize --type tracer --repository Owner/Other-Gadget ;;
        workflow)
            GITHUB_ACTIONS=true GITHUB_REPOSITORY=Owner/Other-Gadget \
                bash "$fixture/scripts/init.sh" --type tracer
            ;;
        *) initialize --type tracer ;;
    esac
    grep -q '^name: "Other-Gadget"$' "$fixture/gadget.yaml" ||
        fail "Repository inference failed for $protocol"
done

new_fixture no-origin
git -C "$fixture" remote remove origin
expect_failure "No origin remote" --type tracer
initialize --type tracer --repository Owner/Explicit

new_fixture interactive
# util-linux script supplies a terminal while the input is automated.
printf '2\n' | env -u GITHUB_ACTIONS -u GITHUB_REPOSITORY \
    script -qec "bash '$fixture/scripts/init.sh'" /dev/null > "$workspace/interactive.log"
grep -q '^GADGET_ITER(' "$fixture/program.bpf.c" || fail "Interactive picker failed"

printf 'All initialization tests passed.\n'
