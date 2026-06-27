# python-env

> Stateful, batteries-included Python for AI agents. One `.wasm`, per-session
> namespaces, common pure-Python libraries built in.

Each `act:sessions` session is a persistent Python namespace; separate
sessions are isolated. Preloaded with curated pure-Python libraries (see
below). No C extensions (use `python-eval` for the locked-down stateless
sandbox; numpy is tracked separately).

## Tools
| Tool | Description |
|------|-------------|
| `exec` | Run Python against the session namespace; returns combined stdout/result/traceback |
| `reset_session` | Clear the session namespace |

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

## Build
```bash
just build && just test
```

## License
MIT OR Apache-2.0
