#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

delay=10
for ((attempt = 1; attempt <= 6; attempt++)); do
    if sudo ig image push "$@"; then
        exit 0
    else
        status=$?
    fi
    if ((attempt == 6)); then
        printf '::error::Image push failed after %d attempts.\n' "$attempt" >&2
        exit "$status"
    fi
    printf '::warning::Image push attempt %d/6 failed; retrying in %d seconds.\n' \
        "$attempt" "$delay" >&2
    sleep "$delay"
    delay=$((delay * 2))
done
