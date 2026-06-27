---
name: python-env
description: Stateful, batteries-included Python environment
metadata:
  act: {}
---

# python-env

A persistent Python environment for agents. Each session keeps its own
namespace — define something in one `exec` call, use it in the next.
Preloaded with common pure-Python libraries plus **numpy 2.5.0**,
**pandas 3.0.3**, **regex**, **Pillow** (images — PNG/BMP/GIF/PPM, not JPEG), and
**msgpack** (binary serialization), **lxml** (XML/HTML+XPath) — real C-extension libs compiled to wasm.
Pyodide-style scientific Python as a hardened ACT component.

`sqlite3` is built in — an in-process SQL database (`sqlite3.connect(":memory:")`
needs no capabilities), great for joins/aggregations alongside numpy/pandas.

Tools: `exec(code)`, `reset_session()`, `install(package)`.

`install(package)` adds a pure-Python (`*-none-any`) PyPI package at runtime;
it then imports in any session. Requires the `wasi:http` capability. The full
CPython stdlib is frozen in, so most of the pure-Python ecosystem works
(e.g. `sympy`, `networkx`). Packages needing compiled extensions (Rust/C, e.g.
`pydantic-core`) are rejected — but numpy and pandas are built in (incl. pandas
datetime/time-series).
