#!/usr/bin/env python3
"""Require every component test module to appear in its shared runner."""

import re
from pathlib import Path


def missing_imports(root: Path) -> list[str]:
    missing = []
    for component in ("nimkit", "kosmo", "tekton", "integrations"):
        runner = root / "tests" / f"t{component}.nim"
        source = re.sub(r"#.*", "", runner.read_text())
        imports = set()
        pattern = rf"\bimport\s+{component}/(?:\[([^]]+)\]|(\w+))"
        for group, single in re.findall(pattern, source):
            names = re.findall(r"\w+", group) if group else [single]
            imports.update(names)
        for module in sorted((root / "tests" / component).glob("*.nim")):
            if module.stem not in imports:
                missing.append(
                    f"{module.relative_to(root)}: add an import to "
                    f"{runner.relative_to(root)}"
                )
    return missing


if __name__ == "__main__":
    missing = missing_imports(Path(__file__).resolve().parents[2])
    if missing:
        raise SystemExit("Unreferenced test modules:\n" + "\n".join(missing))
    print("All component test modules are referenced by their shared runners.")
