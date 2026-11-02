// SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note
/* Copyright (c) 2026 The gadget authors */

#include <vmlinux.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_helpers.h>

#include <gadget/buffer.h>
#include <gadget/common.h>
#include <gadget/filter.h>
#include <gadget/macros.h>
#include <gadget/types.h>

/* Keep custom types gadget_-prefixed to avoid collisions with vmlinux.h. */
struct gadget_event {
	gadget_timestamp timestamp;
	struct gadget_process proc;
};

/* 256 KiB bounds buffering during bursts; full buffers report lost samples. */
GADGET_TRACER_MAP(gadget_events, 256 * 1024);
GADGET_TRACER(events, gadget_events, gadget_event);

/*
 * This hook is an example: GADGET_TRACER selects event output, not a probe
 * type. Other tracepoints, kprobes/fentry (kernel functions), or uprobes
 * (userspace functions) can emit events too.
 *
 * On the target host, with tracefs mounted:
 *   sudo cat /sys/kernel/tracing/available_events
 * A group:event entry maps to SEC("tracepoint/group/event"); inspect its
 * fields in /sys/kernel/tracing/events/<group>/<event>/format.
 * With bpftrace installed, discover other probes with:
 *   sudo bpftrace -l 'kprobe:*'
 *   sudo bpftrace -l 'uprobe:/path/to/binary:*'
 *
 * Changing the hook requires matching SEC(), callback arguments/context,
 * and helper support. fentry also needs kernel BTF and attachment support.
 * Update README requirements; if event fields change, run make metadata
 * and review gadget.yaml.
 */
SEC("tracepoint/syscalls/sys_enter_chdir")
int gadget_trace_chdir(struct trace_event_raw_sys_enter *ctx)
{
	if (gadget_should_discard_data_current())
		return 0;

	struct gadget_event *event =
	    gadget_reserve_buf(&gadget_events, sizeof(*event));
	if (!event)
		return 0;

	/* Reserved buffers are not zeroed. Clear unused fields and padding too,
	 * especially when extending this event with conditionally set fields.
	 */
	__builtin_memset(event, 0, sizeof(*event));
	event->timestamp = bpf_ktime_get_boot_ns();
	/* Reuse IG's process fields so standard container/pod enrichment works.
	 */
	gadget_process_populate(&event->proc);
	/* Preserve output-error checks; --trace-pipe exposes these diagnostics.
	 */
	if (gadget_submit_buf(ctx, &gadget_events, event, sizeof(*event)))
		bpf_printk("gadget: submitting chdir event failed");
	return 0;
}

char LICENSE[] SEC("license") = "GPL";
