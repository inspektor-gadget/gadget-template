# @GADGET_NAME@

Show currently running processes with an Inspektor Gadget **iterator
(snapshotter)**. Unlike event tracing, this reads kernel state, including
processes that already existed when collection began.

## Requirements

- Linux 5.10 or later with BTF (`/sys/kernel/btf/vmlinux`) and BPF task iterators.
- IG v0.57.0 and Docker for the default containerized build.
- Root privileges to build/run with the supplied Makefile.

The starter is tested with IG v0.57.0, its matching builder image, and Linux 6.8.
The kernel must enable `CONFIG_BPF_SYSCALL`, `CONFIG_DEBUG_INFO_BTF`, and
`CONFIG_BPF_ITER`.

## Build and run

```bash
# Start a process before starting the gadget:
sleep 300 &
sleep_pid=$!
make build IMAGE_TAG=latest
PARAMS="--verify-image=false --host --pid $sleep_pid --timeout 3 -o json" make run IMAGE_TAG=latest
```

Expect a `processes` record for the existing sleep process. The session stops
after three seconds; clean up with `kill "$sleep_pid"`.

The iterator enumerates process leaders rather than every thread. IG controls
collection cadence through data source fetch settings; "snapshotter" describes
the current-state view, not a guarantee that `ig run` exits after one snapshot.
The default fetch settings request one snapshot; the timeout bounds the session.
Use `sudo ig run @IMAGE@:latest --help` for the available collection flags.

`--verify-image=false` permits an unsigned local image; sign distributed images.
Publish explicitly after authenticating to the registry:

```bash
make push IMAGE_TAG=latest
```

Neither initialization nor CI publishes an image.

## Customize

`GADGET_ITER(processes, gadget_process, ...)` registers the `iter/task` program.
Use `GADGET_ITER`, not the deprecated `GADGET_SNAPSHOTTER` macro. Inspect other
supported kernel iterator hooks when extending the program; this is not
`GADGET_MAPITER`, which drains an aggregation map.

Keep the null-task check: the kernel also calls the iterator at the end of a
sequence. Preserve zero-initialization, CO-RE reads, and IG filtering.
`--pid`, `--comm`, and container filters restrict collected processes. Mount
namespace information enables enrichment when runtime metadata is available.
`--host` includes host processes; without it, IG collects from containers by
default. `--trace-pipe` exposes helper-failure diagnostics.

After changing fields, run `make metadata IMAGE_TAG=latest` and review
`gadget.yaml`. `make check` checks formatting; `make clang-format` fixes it.
Ordinary `make build` validates metadata without rewriting it.
The retained initialization workflow safely does nothing on subsequent runs.

## License

Userspace tooling is [Apache-2.0](LICENSE). The BPF program is
[GPL-2.0 WITH Linux-syscall-note](LICENSE-bpf.txt).
