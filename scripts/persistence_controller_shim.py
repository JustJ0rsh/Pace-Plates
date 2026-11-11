"""Write a host-fixture PersistenceController exposing only the production legacyModelTypes list.

The host checks cannot compile the app's PersistenceController, so the list is
read from its source. Anything other than a plain array literal of model types
stops the run instead of producing a partial or stale list.
"""
from pathlib import Path
import re

SOURCE = 'WorkingOut/Data/PersistenceController.swift'
DECLARATION = re.compile(r'\bstatic\s+var\s+legacyModelTypes\s*:\s*\[\s*any\s+PersistentModel\.Type\s*\]\s*\{')
ELEMENT = re.compile(r'([A-Z]\w*)\.self')


def legacy_model_types(root: Path) -> list[str]:
    source = (root / SOURCE).read_text()
    declarations = list(DECLARATION.finditer(source))
    if len(declarations) != 1:
        raise SystemExit(f'{SOURCE}: expected one legacyModelTypes declaration, found {len(declarations)}')
    start = declarations[0].end()
    depth, end = 1, start
    while depth and end < len(source):
        depth += {'{': 1, '}': -1}.get(source[end], 0)
        end += 1
    if depth:
        raise SystemExit(f'{SOURCE}: legacyModelTypes body is not closed')
    body = source[start:end - 1].strip()
    if body.startswith('return'):
        body = body[len('return'):].strip()
    names = ELEMENT.findall(body)
    # Rebuilding the literal from the names must reproduce the body exactly, so
    # conditionals, concatenation or helper calls are rejected, never dropped.
    if not names or re.sub(r'[\s,]', '', body) != '[' + ''.join(name + '.self' for name in names) + ']':
        raise SystemExit(f'{SOURCE}: legacyModelTypes is no longer a plain array literal; update {Path(__file__).name}')
    if len(set(names)) != len(names):
        raise SystemExit(f'{SOURCE}: legacyModelTypes lists a model more than once')
    return names


def write_shim(root: Path, out_dir: Path) -> Path:
    names = legacy_model_types(root)
    shim = out_dir / 'PersistenceControllerShim.swift'
    shim.write_text('import SwiftData\n\n// Host fixture generated from ' + SOURCE + '.\n'
                    'enum PersistenceController {\n'
                    '    static var legacyModelTypes: [any PersistentModel.Type] {\n        ['
                    + ', '.join(name + '.self' for name in names) + ']\n    }\n}\n')
    return shim
