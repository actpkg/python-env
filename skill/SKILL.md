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

Tools: `exec(code)`, `reset_session()`.
