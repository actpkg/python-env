"""Inject stub stdlib C-extension modules that WASI CPython lacks, so installed
pure-Python packages that import them load and degrade gracefully instead of
failing at import. Imported first (before _freeze_stdlib / app code) so the
stubs are in sys.modules and get captured in componentize-py's snapshot.

`ctypes` is the big one — many pure-Python packages `import ctypes` only to size
C types or to *probe* for an optional native library. The stub gives correct
wasm32 (ILP32) type sizes via `sizeof`, and makes actual FFI (loading libraries,
casting pointers) raise, so native-acceleration probes fail cleanly and the
package uses its pure-Python path.
"""

import sys
import types


def _have(name: str) -> bool:
    try:
        __import__(name)
        return True
    except Exception:  # noqa: BLE001
        return False


# ---------------------------------------------------------------- ctypes ----
if "ctypes" not in sys.modules and not _have("_ctypes"):
    _ct = types.ModuleType("ctypes")

    # wasm32 / ILP32 C type sizes (note: long == 4 bytes here).
    _SIZES = {
        "c_bool": 1, "c_char": 1, "c_byte": 1, "c_ubyte": 1, "c_wchar": 4,
        "c_short": 2, "c_ushort": 2, "c_int": 4, "c_uint": 4,
        "c_long": 4, "c_ulong": 4, "c_longlong": 8, "c_ulonglong": 8,
        "c_size_t": 4, "c_ssize_t": 4, "c_float": 4, "c_double": 8,
        "c_longdouble": 16, "c_int8": 1, "c_uint8": 1, "c_int16": 2,
        "c_uint16": 2, "c_int32": 4, "c_uint32": 4, "c_int64": 8, "c_uint64": 8,
        "c_void_p": 4, "c_char_p": 4, "c_wchar_p": 4, "py_object": 4,
    }

    class _CData:
        _wasi_size = 4

        def __init__(self, *a, **k):
            pass

    def _unavail(*a, **k):
        raise OSError("ctypes FFI is not available under WASI")

    def _sizeof(t, *a, **k):
        return getattr(t, "_wasi_size", 4)

    def _cfunctype(*a, **k):
        return lambda *aa, **kk: _unavail

    def _pointer_type(t, *a, **k):
        return type("LP_" + getattr(t, "__name__", "x"), (_CData,), {"_wasi_size": 4})

    for _n, _s in _SIZES.items():
        setattr(_ct, _n, type(_n, (_CData,), {"_wasi_size": _s}))

    for _n, _v in {
        "sizeof": _sizeof, "alignment": lambda *a, **k: 4,
        "Structure": type("Structure", (_CData,), {}),
        "Union": type("Union", (_CData,), {}),
        "Array": type("Array", (_CData,), {}),
        "BigEndianStructure": type("BigEndianStructure", (_CData,), {}),
        "LittleEndianStructure": type("LittleEndianStructure", (_CData,), {}),
        "_SimpleCData": _CData, "_Pointer": _CData, "_CFuncPtr": _CData,
        "CDLL": _unavail, "PyDLL": _unavail, "WinDLL": _unavail, "OleDLL": _unavail,
        "cdll": types.SimpleNamespace(LoadLibrary=_unavail),
        "CFUNCTYPE": _cfunctype, "PYFUNCTYPE": _cfunctype, "WINFUNCTYPE": _cfunctype,
        "POINTER": _pointer_type, "pointer": _unavail, "cast": _unavail,
        "byref": _unavail, "addressof": _unavail, "memmove": _unavail,
        "memset": _unavail, "create_string_buffer": _unavail,
        "create_unicode_buffer": _unavail, "string_at": _unavail, "wstring_at": _unavail,
        "get_errno": lambda: 0, "set_errno": lambda v: 0,
        "ArgumentError": type("ArgumentError", (Exception,), {}),
        "RTLD_LOCAL": 0, "RTLD_GLOBAL": 256, "DEFAULT_MODE": 0,
    }.items():
        setattr(_ct, _n, _v)

    _util = types.ModuleType("ctypes.util")
    _util.find_library = lambda *a, **k: None  # no native libs under WASI
    _ct.util = _util

    sys.modules["ctypes"] = _ct
    sys.modules["ctypes.util"] = _util


# ----------------------------------------------------------- bz2 / lzma ----
# No _bz2 / _lzma under WASI. Packages import them at module top only for
# optional compressed-file I/O (e.g. networkx's @open_file for .bz2/.xz).
# Importable; constructing a compressor/file raises.
def _raises(msg):
    def _f(*a, **k):
        raise OSError(msg)

    return _f


if "bz2" not in sys.modules and not _have("_bz2"):
    _bz2 = types.ModuleType("bz2")
    _bz2.BZ2File = _raises("bz2 is not available under WASI")
    _bz2.BZ2Compressor = _raises("bz2 is not available under WASI")
    _bz2.BZ2Decompressor = _raises("bz2 is not available under WASI")
    _bz2.compress = _raises("bz2 is not available under WASI")
    _bz2.decompress = _raises("bz2 is not available under WASI")
    _bz2.open = _raises("bz2 is not available under WASI")
    sys.modules["bz2"] = _bz2

if "lzma" not in sys.modules and not _have("_lzma"):
    _lzma = types.ModuleType("lzma")
    _lzma.LZMAFile = _raises("lzma is not available under WASI")
    _lzma.LZMACompressor = _raises("lzma is not available under WASI")
    _lzma.LZMADecompressor = _raises("lzma is not available under WASI")
    _lzma.compress = _raises("lzma is not available under WASI")
    _lzma.decompress = _raises("lzma is not available under WASI")
    _lzma.open = _raises("lzma is not available under WASI")
    _lzma.LZMAError = type("LZMAError", (Exception,), {})
    _lzma.FORMAT_XZ, _lzma.FORMAT_ALONE, _lzma.FORMAT_RAW, _lzma.FORMAT_AUTO = 1, 2, 3, 0
    _lzma.CHECK_NONE, _lzma.CHECK_CRC32, _lzma.CHECK_CRC64, _lzma.CHECK_SHA256 = 0, 1, 4, 10
    sys.modules["lzma"] = _lzma


# ---------------------------------------------------------------- mmap ----
# WASI has no memory-mapping syscall. pandas (io/common) and others reference
# `mmap.mmap` in isinstance() checks during normal file I/O, so the name must
# exist; constructing one raises.
if "mmap" not in sys.modules and not _have("mmap"):
    _mmap = types.ModuleType("mmap")
    _mmap.ACCESS_DEFAULT, _mmap.ACCESS_READ, _mmap.ACCESS_WRITE, _mmap.ACCESS_COPY = 0, 1, 2, 3
    _mmap.PROT_READ, _mmap.PROT_WRITE, _mmap.MAP_SHARED, _mmap.MAP_PRIVATE = 1, 2, 1, 2
    _mmap.ALLOCATIONGRANULARITY, _mmap.PAGESIZE = 4096, 4096

    class _MmapStub:
        def __init__(self, *a, **k):
            raise OSError("mmap is not available under WASI")

    _mmap.mmap = _MmapStub
    sys.modules["mmap"] = _mmap
