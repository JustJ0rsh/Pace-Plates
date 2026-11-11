"""Write a host-fixture PersistenceController exposing only the production legacyModelTypes list."""
from pathlib import Path
import re

def write_shim(root: Path, out_dir: Path) -> Path:
    source = (root / 'WorkingOut/Data/PersistenceController.swift').read_text()
    match = re.search(r'static var legacyModelTypes: \[any PersistentModel\.Type\] \{.*?\n    \}', source, re.S)
    assert match, 'PersistenceController.legacyModelTypes not found'
    shim = out_dir / 'PersistenceControllerShim.swift'
    shim.write_text('import SwiftData\n\n// Host fixture: copied verbatim from PersistenceController.swift.\n'
                    'enum PersistenceController {\n    ' + match.group(0) + '\n}\n')
    return shim
