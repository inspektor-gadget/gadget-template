# gadget-template

This repository is a template repository to help you create your own gadgets.

Steps to use this template:
- Click on [use this template](https://github.com/new?template_name=gadget-template&template_owner=inspektor-gadget)
- Choose a name for your repository
- Click on *Create repository*
- Update the placeholders (`git grep -i CHANGEME`, `git grep -i TODO`)
- Write your eBPF program (follow [Hello world gadget](https://inspektor-gadget.io/docs/latest/devel/hello-world-gadget/))
- Delete this section from README.md

---

# CHANGEME-GADGET-NAME

CHANGEME-GADGET-NAME is a [gadget from Inspektor
Gadget](https://inspektor-gadget.io/). It detects CHANGEME...

## How to use

```bash
$ export IG_EXPERIMENTAL=true
$ sudo -E ig run ghcr.io/CHANGEME-ORG/CHANGEME-GADGET-NAME:latest
```

## Requirements

- ig v0.26.0 (CHANGEME)
- Linux v5.15 (CHANGEME)

## License (CHANGEME)

The user space components are licensed under the [Apache License, Version
2.0](LICENSE). The BPF code templates are licensed under the [General Public
License, Version 2.0, with the Linux-syscall-note](LICENSE-bpf.txt).
