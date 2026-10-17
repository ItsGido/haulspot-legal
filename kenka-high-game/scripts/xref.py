#!/usr/bin/env python3
"""Cross-reference check for things the type checker can't see.

Services and controllers reach each other through untyped tables (Services.X.Y / Controllers.X.Y),
so a misspelled function name only fails at runtime. This script checks that:
  1. every Services.<Name>.<Member> used on the server exists in src/server/Services/<Name>.luau
  2. every Controllers.<Name>.<Member> used on the client exists in src/client/Controllers/<Name>.luau
  3. every Net.Event("X") / Net.Function("X") name is declared in src/shared/Util/Net.luau
  4. every UIController.Open("X") / UI_Open "X" screen exists in src/client/UI/Screens
  5. every InteractionService.Register("Kind") kind is used by MapData, and every MapData kind is handled
Run: python3 scripts/xref.py   (exit code 1 on problems)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
problems = []


def strip_comments(text: str) -> str:
    """Remove Luau comments (block and line) but keep line numbers stable."""
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return re.sub(r"--[^\n]*", "", text)


def read(path: Path) -> str:
    return strip_comments(path.read_text())


def members_defined(path: Path, module_name: str) -> set:
    text = read(path)
    found = set()
    # function Name.Member(  /  Name.Member = ...
    for m in re.finditer(r"^\s*function\s+%s[.:](\w+)\s*\(" % re.escape(module_name), text, re.M):
        found.add(m.group(1))
    for m in re.finditer(r"^\s*%s\.(\w+)\s*=" % re.escape(module_name), text, re.M):
        found.add(m.group(1))
    return found


def check_table_calls(table_name: str, folder: Path, search_root: Path):
    modules = {p.stem: p for p in folder.glob("*.luau")}
    defined = {name: members_defined(path, name) for name, path in modules.items()}
    for file in search_root.rglob("*.luau"):
        text = read(file)
        for m in re.finditer(r"\b%s\.(\w+)\.(\w+)" % table_name, text):
            module, member = m.group(1), m.group(2)
            line = text.count("\n", 0, m.start()) + 1
            where = f"{file.relative_to(ROOT)}:{line}"
            if module not in modules:
                problems.append(f"{where}: {table_name}.{module} does not exist")
            elif member not in defined[module]:
                problems.append(f"{where}: {table_name}.{module}.{member} is not defined in {module}.luau")


check_table_calls("Services", SRC / "server" / "Services", SRC / "server")
check_table_calls("Controllers", SRC / "client" / "Controllers", SRC / "client")

# Remotes
net_text = read(SRC / "shared" / "Util" / "Net.luau")
events_block = net_text.split("local EVENTS = {", 1)[1].split("\n}", 1)[0]
functions_block = net_text.split("local FUNCTIONS = {", 1)[1].split("\n}", 1)[0]
events = set(re.findall(r'"(\w+)"', events_block))
functions = set(re.findall(r'"(\w+)"', functions_block))
for file in SRC.rglob("*.luau"):
    text = read(file)
    for kind, names in (("Event", events), ("Function", functions)):
        for m in re.finditer(r'Net\.%s\("(\w+)"\)' % kind, text):
            if m.group(1) not in names:
                line = text.count("\n", 0, m.start()) + 1
                problems.append(f"{file.relative_to(ROOT)}:{line}: Net.{kind}(\"{m.group(1)}\") is not declared in Net.luau")

# Screens
screens = set()
for p in (SRC / "client" / "UI" / "Screens").glob("*.luau"):
    m = re.search(r'\.Name\s*=\s*"(\w+)"', read(p))
    if m:
        screens.add(m.group(1))
for file in SRC.rglob("*.luau"):
    text = read(file)
    patterns = [r'UIController\.(?:Open|Toggle)\("(\w+)"', r'Net\.Event\("UI_Open"\)\s*:\s*FireClient\(\s*\w+\s*,\s*"(\w+)"', r'uiOpen\s*:\s*FireClient\(\s*\w+\s*,\s*"(\w+)"']
    for pattern in patterns:
        for m in re.finditer(pattern, text):
            if m.group(1) not in screens:
                line = text.count("\n", 0, m.start()) + 1
                problems.append(f"{file.relative_to(ROOT)}:{line}: screen \"{m.group(1)}\" has no module in UI/Screens")

# Interactable kinds
mapdata = read(SRC / "shared" / "Map" / "MapData.luau")
map_kinds = set(re.findall(r'Kind\s*=\s*"(\w+)"', mapdata.split("MapData.Interactables", 1)[1]))
registered = set()
for file in (SRC / "server").rglob("*.luau"):
    registered |= set(re.findall(r'Register\("(\w+)"', read(file)))
for kind in sorted(map_kinds - registered):
    problems.append(f"MapData interactable kind \"{kind}\" has no InteractionService.Register handler")
for kind in sorted(registered - map_kinds):
    problems.append(f"Handler registered for kind \"{kind}\" but no MapData interactable uses it")

if problems:
    print("Cross-reference problems:")
    for p in problems:
        print("  " + p)
    sys.exit(1)
print("Cross-references OK")
