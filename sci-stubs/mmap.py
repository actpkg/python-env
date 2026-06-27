"""Minimal `mmap` stub for the WASI CPython used by the scientific-tier build.

WASI has no memory-mapping syscall, so componentize-py's CPython ships no `mmap`
module. pandas (`pandas/io/common.py`, `openpyxl`) imports `mmap` at module top
and references `mmap.mmap` in `isinstance(...)` checks during normal file I/O, so
the name must exist. Actual memory-mapping isn't reachable for core DataFrame ops;
constructing an `mmap` raises. Only used by the `just build-sci` (-p sci-stubs) path.
"""

ACCESS_DEFAULT = 0
ACCESS_READ = 1
ACCESS_WRITE = 2
ACCESS_COPY = 3
PROT_READ = 1
PROT_WRITE = 2
MAP_SHARED = 1
MAP_PRIVATE = 2
ALLOCATIONGRANULARITY = 4096
PAGESIZE = 4096


class mmap:  # noqa: N801 — mirror stdlib name
    def __init__(self, *args, **kwargs):
        raise OSError("mmap is not available under WASI")
