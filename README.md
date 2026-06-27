# python-env

> Stateful, batteries-included Python for AI agents. One `.wasm`, per-session
> namespaces, common pure-Python libraries — and real **numpy** — built in.
> Pyodide-style scientific Python, but as a hardened ACT component.

Each `act:sessions` session is a persistent Python namespace; separate
sessions are isolated. Preloaded with curated pure-Python libraries (see
below), plus **numpy 2.5.0** in the published build (see [Scientific tier](#scientific-tier-numpy)).
For the locked-down stateless stdlib-only sandbox, use `python-eval` instead.

## Tools
| Tool | Description |
|------|-------------|
| `exec` | Run Python against the session namespace; returns combined stdout/result/traceback |
| `reset_session` | Clear the session namespace |
| `install` | Install a pure-Python (`*-none-any`) package from PyPI at runtime; importable in any session. Needs `wasi:http`. |

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
| `networkx` | Requires `bz2` → `_bz2` C extension (not available in WASI) |
| `sympy` | Requires `ctypes` → `_ctypes` C extension (not available in WASI) |

## Installing more packages

`install(package)` fetches a package (and its dependencies) from PyPI at
runtime and makes it importable in `exec`:

```
act call python-env.wasm install --args '{"package":"prettytable"}' --allow wasi:http
```

Constraints and honest limitations:

- **Pure-Python wheels only.** Only `*-none-any` wheels are accepted. Anything
  with a compiled extension (`numpy`, `pandas`, `pydantic-core`, …) is rejected
  with "Can't find a pure Python 3 wheel". The curated scientific tier (numpy)
  is tracked separately.
- **Network is the one exposed surface.** `install` is the only feature that
  reaches the network, and only to PyPI. It requires the `wasi:http` capability
  (`--allow wasi:http`); without a grant it is denied. The host policy bounds
  egress to the declared hosts (`pypi.org`, `files.pythonhosted.org`). Arbitrary
  PyPI fetch is a supply-chain surface — grant it deliberately.
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

## Scientific tier: numpy

The published `python-env` bundles **numpy 2.5.0** — the real C-extension numpy,
cross-compiled to WebAssembly and folded into the component, running inside the
ACT sandbox:

```bash
act call python-env.wasm exec \
  --args '{"code":"import numpy as np; np.std(np.arange(10))"}' --session-args '{}'
```

numpy is pure compute — it needs **no capabilities**. SciPy and pandas are not
included (SciPy is Fortran-blocked on wasm; pandas needs its own cross-build).

**Build note.** numpy 2.x's pocketfft uses C++ exceptions, so the numpy build
needs the wasm exception-handling (wasm-EH) toolchain — a patched componentize-py
and a wasm-EH-enabled `act` runtime. The lean `just build` (stock toolchain, no
numpy) stays CI-buildable for fast iteration and tests; the published artifact is
built locally with `just build-numpy` (and tested with `just test-numpy` against a
wasm-EH `act`). The EH toolchain build scripts live with the project design notes.

## Build
```bash
just build && just test          # lean: pure-Python, CI-buildable
just build-numpy                 # full: + numpy 2.5.0 (needs the wasm-EH toolchain)
ACT=/path/to/wasm-eh/act just test-numpy
```

## License
MIT OR Apache-2.0
