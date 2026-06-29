"""Generate the sci-import block in app.py from pyproject.toml's freeze table.

Usage:
    python3 sci/bake/gen-sci-imports.py

Reads [tool.python-env.freeze] and [dependency-groups].sci from pyproject.toml,
then rewrites the marked region in app.py with a uniform guarded import block per
library, ordered by the sci dependency group.  The script is idempotent.
"""

import re
import tomllib
import pathlib

root = pathlib.Path(__file__).resolve().parents[2]  # components/python-env
pp = tomllib.load(open(root / "pyproject.toml", "rb"))

# Preserve the sci dependency order from [dependency-groups].sci
order = [re.split(r"[>=<!~ ]", s)[0] for s in pp["dependency-groups"]["sci"]]
freeze = pp["tool"]["python-env"]["freeze"]


def key(name: str) -> str:
    return name.lower()


blocks = []
for dep in order:
    subs = freeze.get(key(dep)) or freeze.get(dep)
    if subs is None:
        raise KeyError(f"No freeze entry for {dep!r} (tried {key(dep)!r} and {dep!r})")
    body = "\n".join(f"    import {m}  # noqa: F401" for m in subs)
    blocks.append(f"try:\n{body}\nexcept ImportError:\n    pass")

gen = (
    "# >>> sci-imports (generated from pyproject [tool.python-env.freeze] — do not edit by hand)\n"
    + "\n".join(blocks)
    + "\n# <<< sci-imports"
)

app_path = root / "app.py"
app = app_path.read_text()
new = re.sub(r"# >>> sci-imports.*?# <<< sci-imports", gen, app, flags=re.S)
if new == app:
    print("app.py is already up-to-date (no changes made).")
else:
    app_path.write_text(new)
    print("app.py sci-import block regenerated.")
