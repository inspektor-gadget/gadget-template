# gadget-template

Create your own [Inspektor Gadget](https://inspektor-gadget.io/) gadget: an OCI
image containing eBPF programs and metadata, runnable with `ig` or
`kubectl gadget`. Start by choosing a **data source type**, IG's term for how
collected information reaches users.

## Choose a data source type

| Starter | What it offers | When to use it | Upstream example |
|---|---|---|---|
| **Tracer** (`tracer`) | A stream of events as actions happen. This starter traces chdir syscall attempts. | Individual actions, their timing, and process context. | [trace_open](https://github.com/inspektor-gadget/inspektor-gadget/tree/main/gadgets/trace_open) |
| **Iterator (snapshotter)** (`iterator`) | Current kernel state through a BPF iterator. This starter lists existing processes. | Inventory or snapshots, including objects created before collection started. | [snapshot_process](https://github.com/inspektor-gadget/inspektor-gadget/tree/main/gadgets/snapshot_process) |
| **Map iterator** (`map-iterator`) | In-kernel aggregates periodically fetched from a hash map. This starter counts chdir attempts by process. | Top-style statistics, high-volume counters, profiles, and metrics without an event for every action. | [top_file](https://github.com/inspektor-gadget/inspektor-gadget/tree/main/gadgets/top_file), [profile_cpu](https://github.com/inspektor-gadget/inspektor-gadget/tree/main/gadgets/profile_cpu) |

These are data source types, not mutually exclusive gadget categories: a gadget
can eventually combine several sources. Profiling and metrics are use cases,
not additional starter types.

The iterator starter uses `GADGET_ITER`; the older `GADGET_SNAPSHOTTER` macro is
deprecated. Iterators can collect repeatedly; a snapshot does not necessarily mean
the command exits after one collection. `GADGET_MAPITER` is different: fetching
**drains** hash-map entries, so each output represents an interval, not a lifetime
total. Non-destructive `iter/bpf_map_elem` programs are kernel iterators, not this
map-iterator starter.

## Create and initialize your repository

1. Click [Use this template](https://github.com/new?template_name=gadget-template&template_owner=inspektor-gadget).
2. Name the repository after your gadget. Initialization derives the gadget name,
   source URLs, and lowercase `ghcr.io/owner/repository` image reference from it.
   To sign the first published image, configure the optional Actions secrets in
   [Signing and verifying gadgets](SIGNING.md) before initialization.
3. In the new repository, open **Actions > Initialize gadget > Run workflow** and
   choose the data source type.

The job validates the selected gadget and commits the prepared files directly to
the repository's **configured default branch**, regardless of the branch selected
in the workflow UI. It uses `GITHUB_TOKEN` with `contents: write`; no custom token
or workflow-write permission is needed. Actions must be enabled and repository
policies must allow the write. Branch protection is not bypassed.

Initialization replaces this README with the selected gadget's instructions,
places `program.bpf.c`, `gadget.yaml`, and `config.mk` at the root, and removes all
starter directories and initialization-only scripts/tests. Shared build tools,
licenses, validation, and workflows remain. Subsequent initialization workflow
runs succeed with **Already initialized** and do not change files or commits,
even if another type is selected. Switching types afterward is a manual edit.

The job builds before committing, then publishes the initialized commit to GHCR
through a separate publishing job: pushes made by `GITHUB_TOKEN` normally do not
trigger a second push workflow. Ordinary CI still runs on later user pushes/PRs.
After successful validation, default-branch pushes publish new gadget images.
Pull requests, other branches, uninitialized repositories, and the upstream
`inspektor-gadget/gadget-template` repository never publish.

Images are published to lowercase `ghcr.io/owner/repository` with `latest` and
`sha-<full-commit-SHA>` tags. Publishing uses `GITHUB_TOKEN` with `packages: write`;
repository/organization policies must permit package creation and writes.
If the package already exists, grant this repository Actions access in its
package settings. GHCR packages are private by default; change the package
visibility if others should be able to pull without authentication.
Signing is optional: configure `COSIGN_PRIVATE_KEY` and `COSIGN_PASSWORD` as
repository Actions secrets to enable it. Without a key, CI warns and publishes
unsigned images. See [Signing and verifying gadgets](SIGNING.md) for key
generation, secret setup, and trusted-key configuration for `ig` and
`kubectl gadget` (including Helm deployments).

### Initialize locally

Use Linux, Bash 4+, Git, and standard GNU utilities. Clone **your new repository**,
then run the interactive picker:

```bash
bash scripts/init.sh
```

Or select explicitly for automation:

```bash
bash scripts/init.sh --type tracer
bash scripts/init.sh --type iterator
bash scripts/init.sh --type map-iterator
```

Run only one of those commands. The script supports GitHub HTTPS and SSH origins.
If the checkout has no usable origin, or a fork retained the template's origin:

```bash
bash scripts/init.sh --type tracer --repository your-owner/your-gadget
```

Use a repository name compatible with an OCI image path (letters, digits, and
separated dots, underscores, or hyphens). A fork can retain the original
`gadget-template` name; **Use this template** makes naming a new gadget clearer.
The canonical upstream template cannot initialize itself.

Local initialization requires clean tracked files and refuses to overwrite
existing root gadget files. Unrelated untracked files are preserved; unknown files
inside `templates/` cause an error rather than being deleted. Review the diff
afterward. The script never commits, pushes, installs dependencies, or runs
privileged builds. If Actions cannot write to a protected branch, use this path
and your normal review/merge process instead.

## Build your gadget

After initialization, follow the new README. The supplied Makefile uses
**IG v0.57.0** and the matching containerized builder; install IG and Docker,
then run:

```bash
PARAMS="--host" make run-local
```

`make run-local` builds your current sources with the containerized builder, then
runs the unsigned image without pulling from a registry. Pass runtime options
through `PARAMS`. For separate build and run steps:

```bash
make build IMAGE_TAG=latest
PARAMS="--verify-image=false --host" make run IMAGE_TAG=latest
```

Linux 5.10+ with BTF and the selected hook/iterator support is the starter
baseline. Kernel configuration matters; see the generated requirements.
Unsigned local images need `--verify-image=false`; sign images for distribution.
Use `--host` to include host activity; IG otherwise collects from containers.
`make push` is explicit and requires registry authentication.

Builds validate metadata without changing it. After extending the BPF structures,
run `make metadata`, then review the updated `gadget.yaml`.
`IG`, `SUDO`, `BUILDER_IMAGE`, `CONTAINER_REPO`, and `IMAGE_TAG` are overridable
Make variables. The initial template deliberately cannot build, run, or push
before you choose a starter.

## Developing this template

`make test` runs isolated initialization tests without building images.
`make check` checks C formatting; `make clang-format` fixes it.
`bash scripts/validate.sh` runs shell checks, initialization tests, and all three
generated image builds. It needs ShellCheck, jq, clang-format (CI uses version 18),
IG v0.57.0, Docker, and sudo access. The retained CI also checks workflow
definitions with actionlint. After initialization, validation checks and builds
only the selected root gadget.

See [Hello world gadget](https://www.inspektor-gadget.io/docs/latest/gadget-devel/hello-world-gadget)
and the [Gadget eBPF API](https://www.inspektor-gadget.io/docs/latest/gadget-devel/gadget-ebpf-api)
for development guidance.

## License

Userspace tooling is [Apache-2.0](LICENSE). BPF starters are
[GPL-2.0 WITH Linux-syscall-note](LICENSE-bpf.txt).
