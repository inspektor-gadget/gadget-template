# @GADGET_NAME@

Report `chdir` syscall counts per process with an Inspektor Gadget **map
iterator**. The kernel aggregates attempts in a hash map instead of sending an
event for every syscall.

## Requirements

- Linux 5.10 or later with BTF (`/sys/kernel/btf/vmlinux`), syscall tracepoints,
  and hash-map batch lookup-and-delete support.
- IG v0.57.0 and Docker for the default containerized build.
- Root privileges to build/run with the supplied Makefile.

The starter is tested with IG v0.57.0, its matching builder image, and Linux 6.8.

## Build and run

```bash
# In one terminal:
PARAMS="--host --comm bash --map-fetch-interval 1s -o json" make run-local
# In another bash terminal:
for i in 1 2 3; do cd /tmp; done
```

Expect a `calls` record for bash with an aggregated count. Each fetch drains the
map: a later quiet interval does not replay the previous count. Counts describe
syscall attempts, not successes, and are not lifetime process totals. Stop with
Ctrl-C.

`make run-local` builds the current sources, then runs the unsigned local image
without pulling from a registry. Pass runtime options through `PARAMS`. To build
and run separately, use `make build IMAGE_TAG=latest`, then
`PARAMS="--verify-image=false --host" make run IMAGE_TAG=latest`.

`--map-fetch-interval` defaults to 1s; `--map-fetch-count` bounds the number of
fetches. Use `ig run @IMAGE@:latest --help` for all collection options.
`--verify-image=false` permits unsigned local images; sign distributed images.

Publish explicitly after authenticating to the registry:

```bash
make push IMAGE_TAG=latest
```

## Automatic publishing

The initialization workflow and validated default-branch pushes publish
`@IMAGE@:latest` and `@IMAGE@:sha-<full-commit-SHA>` using `GITHUB_TOKEN` with
`packages: write`. Pull requests and other branches never publish. A repeated
initialization run does not republish.

Repository/organization policies must allow package writes. For an existing
package, grant this repository Actions access in the GHCR package settings.
New packages are private by default; change their visibility to allow public
pulls. To enable signing, configure the optional `COSIGN_PRIVATE_KEY` and
`COSIGN_PASSWORD` Actions secrets. Without a key, CI warns and publishes unsigned
images. See [Signing and verifying gadgets](SIGNING.md) for setup and public-key
configuration for `ig`, `kubectl gadget deploy`, and Helm.

## Customize

`GADGET_MAPITER(calls, gadget_counts)` exposes struct keys and values from a
`BPF_MAP_TYPE_HASH` map. Extend those structs and counters for other aggregates.
Atomic increments and insert-without-overwrite handle concurrent threads.
Fetching and updates are concurrent, so interval boundaries are approximate;
this is an observability example, not lossless accounting.

The map permits 1024 active process keys per interval, roughly 100 KiB plus map
overhead. Entries are drained rather than silently LRU-evicted. If insertion
fails, counts can be dropped; inspect `--trace-pipe` diagnostics and adjust the
capacity for your workload.

Reuse IG's process population and filtering helpers. `--pid`, `--comm`, and
container filters restrict collection; mount namespace information enables
enrichment when runtime metadata is available.
`--host` includes host processes; without it, IG collects from containers by
default.
Run `make metadata IMAGE_TAG=latest` after changing fields and review
`gadget.yaml`. `make check` checks formatting; `make clang-format` fixes it.
Ordinary `make build` validates metadata without rewriting it.
The retained initialization workflow safely does nothing on subsequent runs.

## License

Userspace tooling is [Apache-2.0](LICENSE). The BPF program is
[GPL-2.0 WITH Linux-syscall-note](LICENSE-bpf.txt).
