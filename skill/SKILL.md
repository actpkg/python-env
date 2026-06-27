---
name: python-env
description: Stateful, batteries-included Python environment
metadata:
  act: {}
---

# python-env

A persistent Python environment for agents. Each session keeps its own
namespace — define something in one `exec` call, use it in the next.
Preloaded with common pure-Python libraries plus **numpy 2.5.0** and
**pandas 3.0.3** (real C-extension libs, compiled to wasm) — Pyodide-style
scientific Python as a hardened ACT component.

Tools: `exec(code)`, `reset_session()`, `install(package)`.

`install(package)` adds a pure-Python (`*-none-any`) PyPI package at runtime;
it then imports in any session. Requires the `wasi:http` capability. Non-pure
(C-extension) packages can't be installed at runtime — but numpy and pandas are
built in. pandas core (frames, numeric, groupby) works; pandas datetime/
time-series is a known limitation in this build.
