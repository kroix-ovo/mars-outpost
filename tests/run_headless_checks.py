"""Run available Godot suites with explicit success/error checks. No packages needed."""
import argparse
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--benchmark", action="store_true")
    parser.add_argument("--quick", action="store_true", help="Run campaign time checks without repeating the long detailed day oracle")
    args = parser.parse_args()
    project = args.project.resolve()
    simulation = (project / "scripts/simulation/simulation.gd").exists()
    jobs = [("tests/world/run_world.gd", "WORLD_PASS", []),
            ("tests/simulation/run_a1.gd", "A1_PASS", []),
            ("tests/simulation/run_a2.gd", "A2_PASS", []),
            ("tests/simulation/run_a3.gd", "A3_PASS", []),
            ("tests/world/run_integration.gd", "INTEGRATION_PASS" if simulation else "INTEGRATION_SKIP", [])]
    if simulation:
        jobs.append(("tests/world/run_bridge_regressions.gd", "BRIDGE_PASS", []))
        jobs.append(("tests/crew_ui/run_crew_ui.gd", "85/85 checks passed", []))
        jobs.append(("tests/crew_ui/run_a3_compatibility.gd", "A3_CREW_PASS", []))
        jobs.append(("tests/crew_ui/run_tutorial_mission.gd", "TUTORIAL_PASS", []))
        jobs.append(("tests/frontend/run_frontend.gd", "FRONTEND_PASS", []))
        jobs.append(("tests/world/run_camera_controls.gd", "CAMERA_CONTROLS_PASS", []))
    if simulation:
        jobs.append(("tests/simulation/run_repair_farm.gd", "REPAIR_FARM_PASS", []))
        jobs.append(("tests/simulation/run_dust_storm.gd", "DUST_STORM_PASS", []))
        jobs.append(("tests/simulation/run_radiation.gd", "RADIATION_PASS", []))
    if args.benchmark:
        jobs.append(("tests/simulation/run_a1.gd", "A1_PASS", ["--", "--benchmark"]))
    if (project / "tests/campaign/run_foundation.gd").exists():
        jobs.append(("tests/campaign/run_foundation.gd", "CAMPAIGN_FOUNDATION_PASS", []))
    if (project / "tests/campaign/run_time.gd").exists():
        # Includes a full 86,400-tick detailed oracle day, so it needs a longer limit.
        jobs.append(("tests/campaign/run_time.gd", "CAMPAIGN_TIME_QUICK_OK" if args.quick else "CAMPAIGN_TIME_PASS", ["--", "--quick"] if args.quick else []))
    commands = [(name, marker, ["--script", name] + extra) for name, marker, extra in jobs if (project / name).exists()]
    # The main scene is the title screen; the colony scene also boots on its own.
    commands.append(("main scene (title)", None, ["--quit-after", "30"]))
    commands.append(("colony scene", None, ["res://scenes/world/main.tscn", "--quit-after", "30"]))
    for name, marker, extra in commands:
        print("CHECK " + name, flush=True)
        result = subprocess.run([args.godot, "--headless", "--path", str(project)] + extra,
                                capture_output=True, text=True, timeout=1800 if name == "tests/campaign/run_time.gd" else 120)
        output = result.stdout + result.stderr
        print(output, end="", flush=True)
        if result.returncode or (marker and marker not in output) or any(token in output for token in ("SCRIPT ERROR", "Parse Error", "ERROR:")):
            raise SystemExit(f"HEADLESS_FAIL {name} exit={result.returncode}")
    print("HEADLESS_PASS")


if __name__ == "__main__":
    main()
