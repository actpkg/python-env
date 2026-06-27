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
(Filled in by Task 2.)

## Build
```bash
just build && just test
```

## License
MIT OR Apache-2.0
