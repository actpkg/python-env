# python-env

> Stateful, batteries-included Python for AI agents. One `.wasm`, per-session
> namespaces, common pure-Python libraries — and real **numpy + pandas** — built in.
> Pyodide-style scientific Python, but as a hardened ACT component.

Each `act:sessions` session is a persistent Python namespace; separate
sessions are isolated. Preloaded with curated pure-Python libraries (see
below), plus **numpy 2.5.0** and **pandas 3.0.3** in the published build
(see [Scientific tier](#scientific-tier-numpy--pandas)).
For the locked-down stateless stdlib-only sandbox, use `python-eval` instead.

## Tools
| Tool | Description |
|------|-------------|
| `exec` | Run Python against the session namespace; returns combined stdout/result/traceback. Call `show(data, mime=None)` to also return binary/image parts (e.g. a PNG from Pillow) |
| `reset_session` | Clear the session namespace |
| `install` | Install a pure-Python (`*-none-any`) package from PyPI at runtime; importable in any session. Needs `wasi:http`. |

## Built-in SQL

`sqlite3` is compiled into the wasm CPython, so an in-process SQL database is
available with **no capabilities** for an in-memory DB (`sqlite3.connect(":memory:")`)
— load data into tables, run joins/aggregations, alongside the Python namespace.
A file-backed DB needs `wasi:filesystem`. Works in both the lean and full builds.

## Bundled libraries

The following pure-Python libraries are frozen into the wasm at build time and
available to every `exec` call without any installation step.

### Text / Templating
| Package | Import as | Notes |
|---------|-----------|-------|
| `jinja2` | `import jinja2` | Jinja2 template engine |
| `markdown` | `import markdown` | Markdown → HTML converter |
| `beautifulsoup4` | `from bs4 import BeautifulSoup` | HTML/XML parser |
| `rich` | `import rich` | Rich text and formatting |
| `tabulate` | `from tabulate import tabulate` | ASCII/HTML table formatter |
| `python-slugify` | `import slugify` | Unicode-aware slug generator |
| `pyyaml` | `import yaml` | YAML parser (pure-Python path; C ext not in WASI) |

### Data / Utilities
| Package | Import as | Notes |
|---------|-----------|-------|
| `python-dateutil` | `import dateutil` | Date/time parsing and relativedelta |
| `attrs` | `import attr` | Class boilerplate reduction |
| `more-itertools` | `import more_itertools` | Extended itertools recipes |
| `sortedcontainers` | `from sortedcontainers import SortedList` | Sorted list/dict/set |

### Math / Symbolic
| Package | Import as | Notes |
|---------|-----------|-------|
| `mpmath` | `import mpmath` | Arbitrary-precision floating-point math |

### Dropped candidates (incompatible with WASI / componentize-py)
| Package | Reason |
|---------|--------|
| `jsonschema` | Transitively requires `rpds` (Rust C extension via `referencing`) |

(`networkx` and `sympy` were dropped as *bundled* batteries but now **install at
runtime** — the full stdlib is frozen in and WASI-absent modules are stubbed.)

## Installing more packages

`install(package)` fetches a package (and its dependencies) from PyPI at
runtime and makes it importable in `exec`. The full CPython stdlib is frozen
into the component, so most of the pure-Python ecosystem works — e.g.:

```
act call python-env.wasm install --args '{"package":"sympy"}' --allow wasi:http
act call python-env.wasm install --args '{"package":"networkx"}' --allow wasi:http
```

Constraints and honest limitations:

- **Pure-Python wheels only.** Only `*-none-any` wheels are accepted. Anything
  with a compiled extension (`pydantic-core` (Rust), …) is rejected with "Can't
  find a pure Python 3 wheel". numpy/pandas are built in (scientific tier above),
  not installed.
- **WASI-absent stdlib modules are stubbed.** `ctypes` (FFI), `bz2`/`lzma`
  (compression), and `mmap` don't exist under WASI CPython, so they're shimmed:
  `import` succeeds (packages that merely size C types or *probe* for an optional
  native library work), but actually using FFI / compression / memory-mapping
  raises. A package whose core path needs real FFI won't work.
- **Network is the one exposed surface.** `install` is the only feature that
  reaches the network. It requires the `wasi:http` capability (`--allow wasi:http`);
  without a grant it is denied. The host policy bounds egress to the declared hosts
  (`pypi.org`, `files.pythonhosted.org`). Arbitrary PyPI fetch is a supply-chain
  surface — grant it deliberately.

  **Hardened / private index.** `install(package, index_url=...)` targets any
  PEP 503/691 index instead of PyPI. Combined with the egress allowlist this is a
  curated supply chain *enforced by the capability model, not by trusting the
  caller*: grant `wasi:http` only to your index host (e.g. `--grant
  '{"wasi:http":{"mode":"allowlist","allow":[{"host":"pkgs.corp.example"}]}}'`)
  and every install is confined to it — a request to any other index is denied at
  the host, regardless of what `index_url` the agent passes. Good fit for
  air-gapped / regulated deployments.
- **Code only — no data files or namespace packages.** Only the Python
  modules in a wheel are installed; bundled *data files* (e.g. `certifi`'s
  CA bundle, `tzdata`/`pytz` zoneinfo, locale data) and PEP 420 implicit
  namespace packages are not served. A package that reads packaged data at
  runtime may import but then fail, and namespace-only packages may not
  import at all.
- **Installs are process-global, not per-session.** An installed package is
  importable from every session of a running instance; per-session isolation
  covers *variables and definitions* (the `exec` namespace), but
  imported-module state is shared process-wide — a module imported in one
  session is the same object in another. Installs do not persist across a
  restart of the component.

## Scientific tier: numpy + pandas + regex + Pillow + msgpack + lxml + lz4 + bottleneck

The published `python-env` bundles **numpy 2.5.0**, **pandas 3.0.3**, **regex**
(fast/extended `re`), **Pillow** (image processing), **msgpack** (binary
serialization), **lxml** (fast XML/HTML parsing + XPath), **lz4** (fast compression), and **bottleneck** (fast NaN-aware array reductions) — real C-extension
libraries, cross-compiled to WebAssembly and folded into the component, running
inside the ACT sandbox:

```bash
act call python-env.wasm exec --session-args '{}' \
  --args '{"code":"import pandas as pd; pd.DataFrame({\"x\":[1,2,3]}).x.sum()"}'
```

All are pure compute — they need **no capabilities**. SciPy is not included
(Fortran is unavailable on wasm).

**Pillow** does PNG / BMP / GIF / PPM (create, transform, encode → bytes; works
with numpy via `np.asarray`). Return an image to the caller with
`show(buf.getvalue())` — `exec` emits it as an `image/png` content part next to
the text result (mime is sniffed from the bytes, or pass it explicitly). **JPEG is not built in** — libjpeg's `setjmp` error
handling lowers to a wasm SjLj `__c_longjmp` tag that componentize-py can't fold;
PNG (via zlib) needs no `setjmp`. Text rendering (`ImageFont`, freetype) is also
not built in yet.

pandas is broadly functional: `DataFrame`/`Series`, numeric reductions,
arithmetic, `groupby`, and **datetime / time-series** (`to_datetime`,
`date_range`, the `.dt` accessor — the build pins `NPY_TARGET_VERSION` to numpy
2.0 so pandas' tslibs reads the numpy datetime metadata with the right ABI).
What's **not** available: compression I/O (`bz2`/`lzma`), memory-mapped reads,
and the dataframe interchange protocol — WASI CPython lacks the underlying
modules (`bz2`/`lzma`/`mmap`/`ctypes`), so those niche paths are stubbed or guarded.

**Build note.** numpy 2.x's pocketfft uses C++ exceptions, so the scientific build
needs the wasm exception-handling (wasm-EH) toolchain — a patched componentize-py
and a wasm-EH-enabled `act` runtime. The lean `just build` (stock toolchain, no
numpy/pandas) stays CI-buildable for fast iteration and tests; the published
artifact is built locally with `just build-sci` (and tested with `just test-sci`
against a wasm-EH `act`). The EH toolchain build scripts live with the project
design notes.

## Build
```bash
just build && just test          # lean: pure-Python, CI-buildable
just build-sci                   # full: + numpy 2.5.0 + pandas 3.0.3 (wasm-EH toolchain)
ACT=/path/to/wasm-eh/act just test-sci
```

## License
MIT OR Apache-2.0
