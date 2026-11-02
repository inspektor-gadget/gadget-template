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

struct gadget_event {
	gadget_timestamp timestamp;
	struct gadget_process proc;
};

/* 256 KiB bounds buffering during bursts; full buffers report lost samples. */
GADGET_TRACER_MAP(gadget_events, 256 * 1024);
GADGET_TRACER(events, gadget_events, gadget_event);

SEC("tracepoint/syscalls/sys_enter_chdir")
int gadget_trace_chdir(struct trace_event_raw_sys_enter *ctx)
{
	if (gadget_should_discard_data_current())
		return 0;

	struct gadget_event *event =
	    gadget_reserve_buf(&gadget_events, sizeof(*event));
	if (!event)
		return 0;

	__builtin_memset(event, 0, sizeof(*event));
	event->timestamp = bpf_ktime_get_boot_ns();
	gadget_process_populate(&event->proc);
	if (gadget_submit_buf(ctx, &gadget_events, event, sizeof(*event)))
		bpf_printk("gadget: submitting chdir event failed");
	return 0;
}

char LICENSE[] SEC("license") = "GPL";
