#undef TRACE_SYSTEM
#define TRACE_SYSTEM oom

#if !defined(_TRACE_OOM_H) || defined(TRACE_HEADER_MULTI_READ)
#define _TRACE_OOM_H
#include <linux/tracepoint.h>

#define PG_COUNT_TO_KB(x) ((x) << (PAGE_SHIFT - 10))

TRACE_EVENT(oom_score_adj_update,

	TP_PROTO(struct task_struct *task),

	TP_ARGS(task),

	TP_STRUCT__entry(
		__field(	pid_t,	pid)
		__array(	char,	comm,	TASK_COMM_LEN )
		__field(	short,	oom_score_adj)
	),

	TP_fast_assign(
		__entry->pid = task->pid;
		memcpy(__entry->comm, task->comm, TASK_COMM_LEN);
		__entry->oom_score_adj = task->signal->oom_score_adj;
	),

	TP_printk("pid=%d comm=%s oom_score_adj=%hd",
		__entry->pid, __entry->comm, __entry->oom_score_adj)
);

TRACE_EVENT(mark_victim,
	TP_PROTO(struct task_struct *task, uid_t uid),

	TP_ARGS(task, uid),

	TP_STRUCT__entry(
		__field(int, pid)
		__string(comm, task->comm)
		__field(unsigned long, total_vm)
		__field(unsigned long, anon_rss)
		__field(unsigned long, file_rss)
		__field(unsigned long, shmem_rss)
		__field(uid_t, uid)
		__field(unsigned long, pgtables)
		__field(short, oom_score_adj)
	),

	TP_fast_assign(
		__entry->pid = task->pid;
		__assign_str(comm, task->comm);
		__entry->total_vm = PG_COUNT_TO_KB(task->mm->total_vm);
		__entry->anon_rss = PG_COUNT_TO_KB(get_mm_counter(task->mm, MM_ANONPAGES));
		__entry->file_rss = PG_COUNT_TO_KB(get_mm_counter(task->mm, MM_FILEPAGES));
		__entry->shmem_rss = PG_COUNT_TO_KB(get_mm_counter(task->mm, MM_SHMEMPAGES));
		__entry->uid = uid;
		/* 4.9 has no mm_pgtables_bytes(): every PTE and PMD table is one page */
		__entry->pgtables = PG_COUNT_TO_KB(atomic_long_read(&task->mm->nr_ptes) +
						   mm_nr_pmds(task->mm));
		__entry->oom_score_adj = task->signal->oom_score_adj;
	),

	TP_printk("pid=%d comm=%s total-vm=%lukB anon-rss=%lukB file-rss:%lukB shmem-rss:%lukB uid=%u pgtables=%lukB oom_score_adj=%hd",
		__entry->pid,
		__get_str(comm),
		__entry->total_vm,
		__entry->anon_rss,
		__entry->file_rss,
		__entry->shmem_rss,
		__entry->uid,
		__entry->pgtables,
		__entry->oom_score_adj
	)
);

TRACE_EVENT(wake_reaper,
	TP_PROTO(int pid),

	TP_ARGS(pid),

	TP_STRUCT__entry(
		__field(int, pid)
	),

	TP_fast_assign(
		__entry->pid = pid;
	),

	TP_printk("pid=%d", __entry->pid)
);

TRACE_EVENT(start_task_reaping,
	TP_PROTO(int pid),

	TP_ARGS(pid),

	TP_STRUCT__entry(
		__field(int, pid)
	),

	TP_fast_assign(
		__entry->pid = pid;
	),

	TP_printk("pid=%d", __entry->pid)
);

TRACE_EVENT(finish_task_reaping,
	TP_PROTO(int pid),

	TP_ARGS(pid),

	TP_STRUCT__entry(
		__field(int, pid)
	),

	TP_fast_assign(
		__entry->pid = pid;
	),

	TP_printk("pid=%d", __entry->pid)
);

TRACE_EVENT(skip_task_reaping,
	TP_PROTO(int pid),

	TP_ARGS(pid),

	TP_STRUCT__entry(
		__field(int, pid)
	),

	TP_fast_assign(
		__entry->pid = pid;
	),

	TP_printk("pid=%d", __entry->pid)
);
#endif

/* This part must be outside protection */
#include <trace/define_trace.h>
