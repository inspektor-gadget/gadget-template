// SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note
/* Copyright (c) 2026 The gadget authors */

#include <vmlinux.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_helpers.h>

#include <gadget/common.h>
#include <gadget/filter.h>
#include <gadget/macros.h>
#include <gadget/types.h>

/* Maps compare raw key bytes. If adding fields creates padding, zero it
 * identically on every lookup/insertion path so logically equal keys match.
 */
struct gadget_key {
	__u32 process_id;
};

struct gadget_value {
	struct gadget_process proc;
	__u64 calls;
};

/* At most 1024 active processes per fetch interval, roughly 100 KiB plus
 * overhead. Fetching drains entries; a hash map avoids silent LRU eviction.
 * Revisit this budget when enlarging key/value structs: preallocation scales
 * with entry size as well as max_entries.
 */
struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 1024);
	__type(key, struct gadget_key);
	__type(value, struct gadget_value);
} gadget_counts SEC(".maps");

GADGET_MAPITER(calls, gadget_counts);

/*
 * GADGET_MAPITER selects how aggregates are collected from the map, not
 * the hook that updates it. Other tracepoints, kprobes/fentry (kernel
 * functions), or uprobes (userspace functions) can populate this map.
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
 * Update README requirements; if map fields change, run make metadata
 * and review gadget.yaml.
 */
SEC("tracepoint/syscalls/sys_enter_chdir")
int gadget_count_chdir(struct trace_event_raw_sys_enter *ctx)
{
	if (gadget_should_discard_data_current())
		return 0;

	struct gadget_key key = {
	    .process_id = bpf_get_current_pid_tgid() >> 32,
	};
	struct gadget_value *value = bpf_map_lookup_elem(&gadget_counts, &key);
	if (value) {
		/* Multiple CPUs can update this process; plain ++ loses
		 * increments. */
		__sync_fetch_and_add(&value->calls, 1);
		return 0;
	}

	struct gadget_value initial = {};
	/* Reuse IG's process fields so standard container/pod enrichment works.
	 */
	gadget_process_populate(&initial.proc);
	initial.calls = 1;
	long err =
	    bpf_map_update_elem(&gadget_counts, &key, &initial, BPF_NOEXIST);
	if (!err)
		return 0;

	/* BPF_NOEXIST avoids overwriting another thread's counters. If that
	 * thread inserted first, retry the lookup rather than replacing its
	 * value.
	 */
	if (err == -17 /* EEXIST */) {
		value = bpf_map_lookup_elem(&gadget_counts, &key);
		if (value) {
			__sync_fetch_and_add(&value->calls, 1);
			return 0;
		}
	}
	/* Keep failures visible (including a full map); inspect --trace-pipe.
	 */
	bpf_printk("gadget: chdir count dropped, map update error %ld", err);
	return 0;
}

char LICENSE[] SEC("license") = "GPL";
