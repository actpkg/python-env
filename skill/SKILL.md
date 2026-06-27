---
name: python-env
description: Stateful, batteries-included Python environment
metadata:
  act: {}
---

# python-env

A persistent Python environment for agents. Each session keeps its own
namespace — define something in one `exec` call, use it in the next.
Preloaded with common pure-Python libraries. No C extensions.

Tools: `exec(code)`, `reset_session()`, `install(package)`.

`install(package)` adds a pure-Python (`*-none-any`) PyPI package at runtime;
it then imports in any session. Requires the `wasi:http` capability. Non-pure
(C-extension) packages are rejected.
