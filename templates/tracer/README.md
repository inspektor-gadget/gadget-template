# @GADGET_NAME@

Trace `chdir` syscall attempts with [Inspektor Gadget](https://inspektor-gadget.io/).
Each event includes its timestamp and process information. An event records an
attempt, not whether changing directory succeeded.

## Requirements

- Linux 5.10 or later with BTF (`/sys/kernel/btf/vmlinux`) and syscall tracepoints.
- IG v0.57.0 and Docker for the default containerized build.
- Root privileges to build/run with the supplied Makefile.

The starter is tested with IG v0.57.0, its matching builder image, and Linux 6.8.

## Build and run

```bash
make build IMAGE_TAG=latest
# In one terminal:
PARAMS="--verify-image=false --host --comm bash" make run IMAGE_TAG=latest
# In another bash terminal:
cd /tmp
```

Expect an `events` record with a timestamp, your bash PID, and command name.
Stop tracing with Ctrl-C. `--verify-image=false` permits your unsigned local image;
sign images before distributing them for production use.

```bash
sudo ig run @IMAGE@:latest --verify-image=false --host -o json
make push IMAGE_TAG=latest
```

Push requires registry authentication and permission to publish to `@IMAGE@`.
Pushing is explicit; neither initialization nor CI publishes an image.

## Customize

`program.bpf.c` defines `GADGET_TRACER(events, ...)`. Change its tracepoint and
event structure to observe another action. Reuse `gadget_process_populate()` and
`gadget_should_discard_data_current()` for process information and filtering.
`--pid`, `--comm`, and IG's container filters restrict collected events; mount
namespace information enables container/Kubernetes enrichment when IG has the
corresponding runtime metadata. `--host` includes host processes; without it,
IG collects from containers by default.

The 256 KiB event buffer is bounded. IG reports buffer exhaustion as lost samples;
additional helper failures can be diagnosed with `--trace-pipe`.
Run `make metadata IMAGE_TAG=latest` after changing the event structure, review
`gadget.yaml`, then `make check` to check formatting (`make clang-format` fixes it).
Ordinary `make build` validates metadata without rewriting it.

The retained initialization workflow safely does nothing on subsequent runs.

## License

Userspace tooling is [Apache-2.0](LICENSE). The BPF program is
[GPL-2.0 WITH Linux-syscall-note](LICENSE-bpf.txt).
