#!/usr/bin/env python3
"""Compile the actual Foundation-only form helpers with focused Swift assertions.

The helpers currently live alongside SwiftUI views. Extract their complete enum
declarations into a temporary file so this checks production code, without an
iOS simulator or a second copy of either implementation.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def declaration(relative_path: str, name: str) -> str:
    source = (ROOT / relative_path).read_text()
    start = source.index(f"enum {name} {{")
    end = source.index("\n}\n", start) + 3
    return source[start:end]


checks = r'''
let cases: [(String, Double?)] = [("",nil),("  ",nil),("0",0),("0.0",0),("1800",1800),("1,5",1.5),("1e-7",0.0000001)]
for (text,value) in cases {
    let actual = try CoachEntryNumber.optional(text)
    precondition(actual == value, "Incorrect blank, zero, decimal, or scientific input")
}
for text in ["-1","nan","inf","1e999","1e-999","1.2.3"] {
    do { _ = try CoachEntryNumber.optional(text); fatalError("Accepted invalid input: \(text)") }
    catch { }
}
let original = 0.0000001
let roundtrip = try CoachEntryNumber.optional(CoachEntryNumber.input(original))
precondition(roundtrip == original, "Editing must preserve stored precision")
print("Coach entry parser checks passed: 14")

precondition(CoachMeasurementUnits.kilograms(100, unit: "stone") == nil)
precondition(CoachMeasurementUnits.kilometers(1, unit: "furlong") == nil)
precondition(CoachMeasurementUnits.centimeters(32, unit: "yards") == nil)
precondition(abs(CoachMeasurementUnits.kilograms(100, unit: "lbs")! - 45.359237) < 0.000001)
precondition(CoachMeasurementUnits.kilograms(80, unit: "kilograms") == 80)
precondition(CoachMeasurementUnits.kilometers(1, unit: "miles") == 1.609344)
precondition(CoachMeasurementUnits.centimeters(10, unit: "in") == 25.4)
precondition(CoachMeasurementUnits.kilograms(.infinity, unit: "kg") == nil)
print("Coach measurement unit checks passed: 8")
'''

source = "import Foundation\nenum CoachRepositoryError: Error { case invalidValue(String) }\n"
source += declaration("WorkingOut/Features/Coach/CoachCheckInView.swift", "CoachEntryNumber")
source += declaration("WorkingOut/Features/Coach/CoachBodyProgressView.swift", "CoachMeasurementUnits")
source += checks
with tempfile.TemporaryDirectory(prefix="coach-entry-checks-") as temporary:
    directory = Path(temporary)
    main = directory / "main.swift"
    binary = directory / "coach-entry-checks"
    main.write_text(source)
    subprocess.run(["swiftc", str(main), "-o", str(binary)], check=True, cwd=ROOT)
    subprocess.run([str(binary)], check=True, cwd=ROOT)
