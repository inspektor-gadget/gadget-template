// SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note
/* Copyright (c) 2026 The gadget authors */

#include <vmlinux.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_helpers.h>

#include <gadget/filter.h>
#include <gadget/macros.h>
#include <gadget/types.h>

GADGET_ITER(processes, gadget_process, gadget_snapshot_process);

SEC("iter/task")
int gadget_snapshot_process(struct bpf_iter__task *ctx)
{
	struct task_struct *task = ctx->task;
	struct gadget_process process = {};

	if (!task)
		return 0;

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

	if (bpf_seq_write(ctx->meta->seq, &process, sizeof(process)))
		bpf_printk("gadget: writing process snapshot failed");
	return 0;
}

char LICENSE[] SEC("license") = "GPL";
