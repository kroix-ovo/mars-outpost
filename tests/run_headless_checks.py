"""Run available Godot suites with explicit success/error checks. No packages needed."""
import argparse
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--benchmark", action="store_true")
    args = parser.parse_args()
    project = args.project.resolve()
    simulation = (project / "scripts/simulation/simulation.gd").exists()
    jobs = [("tests/world/run_world.gd", "WORLD_PASS", []),
            ("tests/simulation/run_a1.gd", "A1_PASS", []),
            ("tests/simulation/run_a2.gd", "A2_PASS", []),
            ("tests/world/run_integration.gd", "INTEGRATION_PASS" if simulation else "INTEGRATION_SKIP", [])]
    if simulation:
        jobs.append(("tests/world/run_bridge_regressions.gd", "BRIDGE_PASS", []))
    if args.benchmark:
        jobs.append(("tests/simulation/run_a1.gd", "A1_PASS", ["--", "--benchmark"]))
    commands = [(name, marker, ["--script", name] + extra) for name, marker, extra in jobs if (project / name).exists()]
    commands.append(("main scene", None, ["--quit-after", "30"]))
    for name, marker, extra in commands:
        print("CHECK " + name, flush=True)
        result = subprocess.run([args.godot, "--headless", "--path", str(project)] + extra,
                                capture_output=True, text=True, timeout=120)
        output = result.stdout + result.stderr
        print(output, end="", flush=True)
        if result.returncode or (marker and marker not in output) or any(token in output for token in ("SCRIPT ERROR", "Parse Error", "ERROR:")):
            raise SystemExit(f"HEADLESS_FAIL {name} exit={result.returncode}")
    print("HEADLESS_PASS")


if __name__ == "__main__":
    main()
