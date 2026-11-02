// SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note
/* Copyright (c) 2026 The gadget authors */

#include <vmlinux.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_helpers.h>

#include <gadget/filter.h>
#include <gadget/macros.h>
#include <gadget/types.h>

GADGET_ITER(processes, gadget_process, gadget_snapshot_process);

/*
 * This starter uses a kernel iterator, not an event probe. Other targets
 * include iter/task_file and iter/tcp, depending on kernel support.
 * Discover candidate iterator contexts in the target kernel's BTF:
 *   sudo bpftool btf dump file /sys/kernel/btf/vmlinux format c |
 *     grep 'struct bpf_iter__'
 * A bpf_iter__<target> context corresponds to SEC("iter/<target>"); see
 * tools/testing/selftests/bpf/progs/bpf_iter* in the kernel source for
 * examples. BTF presence alone does not guarantee attachment support.
 *
 * Keep the GADGET_ITER callback name, SEC(), context type, field reads,
 * and emitted record type in sync; write records to ctx->meta->seq.
 * Tracepoints/kprobes do not provide that iterator output context: choose
 * the tracer or map-iterator starter for event-driven collection instead.
 * Update README requirements; if record fields change, run make metadata
 * and review gadget.yaml.
 */
SEC("iter/task")
int gadget_snapshot_process(struct bpf_iter__task *ctx)
{
	struct task_struct *task = ctx->task;
	/* The whole record is exported, including unused fields and padding. */
	struct gadget_process process = {};

	/* The kernel also calls the iterator with NULL at the end of a
	 * sequence. */
	if (!task)
		return 0;

	/* This task is not necessarily current. Keep CO-RE reads and the
	 * explicit filter below instead of using current-task population/filter
	 * helpers.
	 */
	process.pid = BPF_CORE_READ(task, tgid);
	process.tid = BPF_CORE_READ(task, pid);
	if (process.pid != process.tid)
		return 0;

	process.mntns_id = BPF_CORE_READ(task, nsproxy, mnt_ns, ns.inum);
	process.creds.uid = BPF_CORE_READ(task, cred, uid.val);
	process.creds.gid = BPF_CORE_READ(task, cred, gid.val);
	if (BPF_CORE_READ_STR_INTO(&process.comm, task, comm) < 0) {
		bpf_printk("gadget: reading process name failed");
		return 0;
	}
	if (gadget_should_discard_data(process.mntns_id, process.pid,
				       process.tid, process.comm,
				       process.creds.uid, process.creds.gid))
		return 0;

	struct task_struct *parent = BPF_CORE_READ(task, real_parent);
	if (parent) {
		process.parent.pid = BPF_CORE_READ(parent, tgid);
		process.parent.tid = BPF_CORE_READ(parent, pid);
		if (BPF_CORE_READ_STR_INTO(&process.parent.comm, parent, comm) <
		    0) {
			bpf_printk("gadget: reading parent name failed");
			return 0;
		}
	}

	/* Preserve output-error checks; --trace-pipe exposes these diagnostics.
	 */
	if (bpf_seq_write(ctx->meta->seq, &process, sizeof(process)))
		bpf_printk("gadget: writing process snapshot failed");
	return 0;
}

char LICENSE[] SEC("license") = "GPL";
