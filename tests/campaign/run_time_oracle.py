"""Full detailed-oracle evidence for package 2 (long: tens of minutes on many cores).

    python tests/campaign/run_time_oracle.py --godot <godot console binary> [--workers 12]

The aggregate (replay) run writes one checkpoint per segment. Each segment is then replayed
by a separate one-second oracle process that starts from the aggregate checkpoint and must
reproduce the next checkpoint byte for byte. Because every comparison is exact, the segments
chain: together they show the whole horizon equals uninterrupted detailed stepping.
"""
import argparse
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

CHAINS = [("week", 1, 7), ("first_shipment", 5, 36)]  # name, days per segment, segments
SCRIPT = "tests/campaign/run_time_oracle.gd"


def godot(args, project, extra):
    result = subprocess.run([args.godot, "--headless", "--path", str(project), "--script", SCRIPT, "--"] + extra,
                            capture_output=True, text=True)
    output = result.stdout + result.stderr
    lines = [line for line in output.splitlines() if line.startswith("TIME_ORACLE")]
    bad = result.returncode != 0 or any(token in output for token in ("SCRIPT ERROR", "Parse Error", "ERROR:"))
    return bad, lines, output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--workers", type=int, default=12)
    parser.add_argument("--only", choices=[name for name, _, _ in CHAINS])
    args = parser.parse_args()
    project = args.project.resolve()
    failed = False
    for name, days, segments in CHAINS:
        if args.only and args.only != name:
            continue
        directory = "build/campaign_time_oracle/" + name
        started = time.time()
        bad, lines, output = godot(args, project, ["--produce", directory, str(days), str(segments)])
        print("\n".join(lines), flush=True)
        if bad:
            print(output)
            raise SystemExit("TIME_ORACLE_CHAIN_FAIL %s produce" % name)
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            jobs = [pool.submit(godot, args, project, ["--verify", directory, str(index)]) for index in range(segments)]
            matched = 0
            for index, job in enumerate(jobs):
                bad, lines, output = job.result()
                print("\n".join(lines), flush=True)
                if bad or not any(line.startswith("TIME_ORACLE_MATCH index=%d " % index) for line in lines):
                    print(output)
                    failed = True
                else:
                    matched += 1
        print("TIME_ORACLE_CHAIN_%s %s simulated_days=%d segments=%d matched=%d wall_s=%.0f" % (
            "FAIL" if matched != segments else "PASS", name, days * segments, segments, matched, time.time() - started), flush=True)
    if failed:
        raise SystemExit("TIME_ORACLE_FAIL")
    print("TIME_ORACLE_PASS")


if __name__ == "__main__":
    main()
