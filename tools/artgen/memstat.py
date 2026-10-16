"""Process memory per stage (torch-free; Linux /proc, everything optional).

ru_maxrss only ever grows, so after the 14 GB model-load transient it can't show sampling or decode
peaks. reset() writes 5 to /proc/self/clear_refs, which resets VmHWM (the peak RSS) for this
process, so snapshot()["vmhwm_gb"] after a stage is that stage's own peak.
"""


def _status():
    out = {}
    try:
        with open("/proc/self/status") as f:
            for line in f:
                if line.startswith(("VmHWM:", "VmRSS:")):
                    k, v = line.split(":", 1)
                    out[k] = int(v.split()[0]) / 1024.0 / 1024.0
    except (OSError, ValueError):
        pass
    return out


def mem_available_gb():
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemAvailable:"):
                    return int(line.split()[1]) / 1024.0 / 1024.0
    except (OSError, ValueError):
        pass
    return None


def reset():
    """Reset the peak-RSS counter (VmHWM). Returns True when it worked."""
    try:
        with open("/proc/self/clear_refs", "w") as f:
            f.write("5")
        return True
    except OSError:
        return False


def snapshot():
    s = _status()
    avail = mem_available_gb()
    return {"vmhwm_gb": round(s["VmHWM"], 2) if "VmHWM" in s else None,
            "vmrss_gb": round(s["VmRSS"], 2) if "VmRSS" in s else None,
            "memavail_gb": round(avail, 2) if avail is not None else None}
