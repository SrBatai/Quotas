class_name SchedProbe
## Linux scheduler counters of the calling thread (diagnostics for the streaming budget, W1): where did the wall
## time of a step go — our code on the CPU, the run queue (another thread of ours or another process had the core),
## a sleep (a lock / page cache wait) or the hypervisor (steal)? Reads /proc/thread-self (a few µs each; only used
## by tools, never in the game). Values are cumulative; subtract two samples.
##   [0] exec ns      schedstat field 1: time on the CPU (with CONFIG_PARAVIRT_TIME_ACCOUNTING the vCPU steal time
##                    is NOT included; IRQ time is, without CONFIG_IRQ_TIME_ACCOUNTING)
##   [1] wait ns      schedstat field 2: time runnable but waiting on a run queue (preempted by another thread)
##   [2] slices       schedstat field 3: times scheduled in
##   [3] minflt       /proc/thread-self/stat field 10: minor page faults
##   [4] majflt       field 12: major page faults
##   [5] nvcsw        /proc/thread-self/status voluntary_ctxt_switches: the thread blocked (lock, I/O)
## `available()` is false off Linux or without CONFIG_SCHED_INFO (all zeros then).

static var _ok: int = -1


static func available() -> bool:
	if _ok < 0:
		_ok = 1 if OS.get_name() == "Linux" and FileAccess.file_exists("/proc/thread-self/schedstat") else 0
	return _ok == 1


static func sample() -> PackedInt64Array:
	var out := PackedInt64Array([0, 0, 0, 0, 0, 0])
	if not available():
		return out
	var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if f != null:
		var p := f.get_line().split(" ", false)
		if p.size() >= 3:
			out[0] = p[0].to_int()
			out[1] = p[1].to_int()
			out[2] = p[2].to_int()
	f = FileAccess.open("/proc/thread-self/stat", FileAccess.READ)
	if f != null:
		var line := f.get_line()
		# the command name (field 2) may contain spaces: split after its closing parenthesis
		var rest := line.substr(line.rfind(")") + 2).split(" ", false)
		# rest[0] = field 3 (state) … minflt = field 10 → rest[7], majflt = field 12 → rest[9]
		if rest.size() > 9:
			out[3] = rest[7].to_int()
			out[4] = rest[9].to_int()
	out[5] = vol_switches()
	return out


## [on-CPU ns, run-queue wait ns] of the calling thread (schedstat fields 1–2, one small read). The wait is updated
## when the thread gets the CPU back, so a sample taken while running includes every wait that ended before it; the
## on-CPU time excludes hypervisor steal (CONFIG_PARAVIRT_TIME_ACCOUNTING) and lags by up to one scheduler tick
## (4 ms at HZ = 250) for the running thread.
static func exec_wait_ns() -> PackedInt64Array:
	var out := PackedInt64Array([0, 0])
	if not available():
		return out
	var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if f == null:
		return out
	var p := f.get_line().split(" ", false)
	if p.size() >= 2:
		out[0] = p[0].to_int()
		out[1] = p[1].to_int()
	return out


## Scheduler tick of the kernel (µs): the granularity of the on-CPU counter of a running thread.
const TICK_USEC := 4000


## Cumulative run-queue wait (ns) of the calling thread: schedstat field 2 only (one small read). It is updated when
## the thread gets the CPU back, so a sample taken while running includes every wait that ended before it.
static func wait_ns() -> int:
	if not available():
		return 0
	var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if f == null:
		return 0
	var p := f.get_line().split(" ", false)
	return p[1].to_int() if p.size() >= 2 else 0


## Voluntary context switches of the calling thread (/proc/thread-self/status): it grows when the thread blocks
## (a lock held by a preempted thread, I/O). Reads the whole status file (≈ 60 lines): tools only.
static func vol_switches() -> int:
	if not available():
		return 0
	var f := FileAccess.open("/proc/thread-self/status", FileAccess.READ)
	if f == null:
		return 0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("voluntary_ctxt_switches:"):
			return line.split(":")[1].strip_edges().to_int()
		if line == "":
			break
	return 0


## System-wide steal time (hypervisor took the vCPUs), in jiffies (USER_HZ, normally 10 ms), all CPUs.
static func steal_jiffies() -> int:
	if OS.get_name() != "Linux":
		return 0
	var f := FileAccess.open("/proc/stat", FileAccess.READ)
	if f == null:
		return 0
	var p := f.get_line().split(" ", false)
	return p[8].to_int() if p.size() > 8 else 0


## CPUs this process may run on (/proc/self/status Cpus_allowed_list, e.g. "0-1" under `taskset -c 0,1`).
static func allowed_cpus() -> PackedInt32Array:
	var out := PackedInt32Array()
	if OS.get_name() != "Linux":
		return out
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("Cpus_allowed_list:"):
			for part in line.split(":")[1].strip_edges().split(","):
				var r := part.split("-")
				var a := r[0].to_int()
				var b := r[1].to_int() if r.size() > 1 else a
				for c in range(a, b + 1):
					out.append(c)
			break
		if line == "":
			break
	return out


## Steal jiffies of the given CPUs (/proc/stat "cpuN" lines, field 8); all CPUs when `cpus` is empty. A frame during
## which it grew had its vCPU(s) descheduled by the hypervisor: invisible to the guest's run-queue counters.
static func steal_of(cpus: PackedInt32Array) -> int:
	if OS.get_name() != "Linux":
		return 0
	var f := FileAccess.open("/proc/stat", FileAccess.READ)
	if f == null:
		return 0
	var total := 0
	var line := f.get_line()
	if cpus.is_empty():
		var p := line.split(" ", false)
		return p[8].to_int() if p.size() > 8 else 0
	var want := cpus.duplicate()
	while not f.eof_reached() and not want.is_empty():
		line = f.get_line()
		if not line.begins_with("cpu"):
			break
		var p := line.split(" ", false)
		var id := p[0].substr(3).to_int()
		if want.has(id):
			want.remove_at(want.find(id))
			total += p[8].to_int() if p.size() > 8 else 0
	return total


## b − a.
static func delta(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	var d := PackedInt64Array()
	d.resize(a.size())
	for i in a.size():
		d[i] = b[i] - a[i]
	return d
