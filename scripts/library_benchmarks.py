#!/usr/bin/env python3
"""Summarize and compare AniShelf library benchmark runs (docs-ai 026).

  library_benchmarks.py summarize RUN_DIR [MODE ITERATIONS]
      Reads RUN_DIR/<size>.xcresult bundles and writes RUN_DIR/summary.json. MODE is
      `full` (the default, 10 iterations) or `quick` (`make bench-quick`).
  library_benchmarks.py compare BASELINE.json CANDIDATE.json
      Prints per-metric medians and flags changes beyond the noise thresholds.
  library_benchmarks.py save-baseline BASELINE.json CANDIDATE.json
      Merges the candidate's results into the baseline, so a partial run replaces only the
      tests and sizes it measured.

Numbers are only comparable on the same machine and simulator, and in the same mode:
quick runs build without whole-module optimization, so they keep their own baseline.
"""

import json
import os
import statistics
import subprocess
import sys
from pathlib import Path

# A change is flagged only when it exceeds both the relative and the absolute threshold.
# The absolute floors keep frame quantization (~16.7 ms at 60 Hz) and one-off late frames
# from reading as regressions.
RELATIVE_THRESHOLD = 0.15
ABSOLUTE_FLOORS = {
    "s": 0.005,
    "ms per s": 5.0,
    "hitches": 1.0,
}


# Every included test must report all of its metrics for every iteration
# (`LibraryBenchmarkTests.measureOptions`; full runs use 10, quick runs record their own). Partial runs may omit whole tests, never single
# metrics or iterations: a missing metric would hide a regression and erase its baseline.
EXPECTED_ITERATIONS = 10
SELECTION = ["Duration (SelectionUpdate)", "Duration (SelectionUpdateCommit)"]
HITCHES = ["Hitch Count", "Hitch Time Ratio"]
EXPECTED_METRICS = {
    "testSelectionToggleList": SELECTION,
    "testSelectionToggleGrid": SELECTION,
    "testScrollList": HITCHES,
    "testScrollGrid": HITCHES,
    "testScrollGallery": HITCHES,
    "testCategorySwitchList": ["Duration (DisplayUpdate)", "Duration (DisplayUpdateCommit)", *HITCHES],
    "testCategorySwitchGrid": ["Duration (DisplayUpdate)", "Duration (DisplayUpdateCommit)", *HITCHES],
    "testBatchFavoriteList": ["Duration (BatchAction)", "Duration (BatchActionCommit)"],
}


def incomplete_results(summary):
    """Describes every included test whose metrics or iterations are incomplete."""
    expected_iterations = summary.get("iterations", EXPECTED_ITERATIONS)
    problems = [f"{name}: {result}" for name, result in summary.get("failed_tests", [])]
    if not summary["results"]:
        problems.append("no test ran or reported measurements")
    for size, tests in sorted(summary["results"].items(), key=lambda item: int(item[0])):
        for test, metrics in sorted(tests.items()):
            expected = EXPECTED_METRICS.get(test)
            if expected is None:
                problems.append(f"{size}/{test}: no expected metric set; add it to EXPECTED_METRICS")
                continue
            for metric in expected:
                count = len(metrics.get(metric, {}).get("values", []))
                if count != expected_iterations:
                    problems.append(f"{size}/{test}: {metric} has {count} of {expected_iterations} iterations")
    return problems


def require_complete(summary, action):
    problems = incomplete_results(summary)
    if problems:
        details = "\n  ".join(problems)
        sys.exit(f"Refusing to {action}: run {summary['run']} is incomplete.\n  {details}")


def read_results(bundle, kind):
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(bundle), "--compact"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return json.loads(output)


def test_name(identifier):
    return identifier.split("/")[-1].removesuffix("()")


def executed_tests(bundle):
    """Every test case the bundle ran, with its result, whether or not it reported metrics."""
    cases = []

    def walk(node):
        if node.get("nodeType") == "Test Case":
            cases.append((test_name(node["nodeIdentifier"]), node.get("result")))
        for child in node.get("children", []):
            walk(child)

    for node in read_results(bundle, "tests")["testNodes"]:
        walk(node)
    return cases


def summarize(run_dir, mode="full", iterations=EXPECTED_ITERATIONS):
    run_dir = Path(run_dir).resolve()  # `latest` is a symlink; record the run's real name.
    bundles = sorted(run_dir.glob("*.xcresult"), key=lambda path: int(path.stem))
    if not bundles:
        sys.exit(f"No .xcresult bundles in {run_dir}")
    results = {}
    failed_tests = []
    device = None
    for bundle in bundles:
        size = bundle.stem
        # Register every test that ran, so one without measurements reads as incomplete,
        # not as omitted from a partial run.
        for name, result in executed_tests(bundle):
            results.setdefault(size, {}).setdefault(name, {})
            if result != "Passed":
                failed_tests.append((f"{size}/{name}", result))
        for test in read_results(bundle, "metrics"):
            name = test_name(test["testIdentifier"])
            results.setdefault(size, {}).setdefault(name, {})
            for run in test["testRuns"]:
                device = device or run["device"]["deviceName"]
                for metric in run["metrics"]:
                    values = metric["measurements"]
                    results.setdefault(size, {}).setdefault(name, {})[metric["displayName"]] = {
                        "unit": metric["unitOfMeasurement"],
                        "median": statistics.median(values),
                        "min": min(values),
                        "max": max(values),
                        "values": values,
                    }
    # The 15-minute load average roughly covers a one-size run. Host load inflates every
    # metric, so compare uses it to warn when runs are not comparable. Provenance is kept per
    # test because a baseline can merge tests from several runs.
    provenance = {
        "device": device,
        "mode": mode,
        "run": run_dir.name,
        "load_average_15m": round(os.getloadavg()[2], 1),
    }
    summary = {
        **provenance,
        "iterations": iterations,
        "results": results,
        "failed_tests": failed_tests,
        "provenance": {size: {test: provenance for test in tests} for size, tests in results.items()},
    }
    path = run_dir / "summary.json"
    path.write_text(json.dumps(summary, indent=2, sort_keys=True))
    print_summary(summary)
    print(f"\nWrote {path}")
    problems = incomplete_results(summary)
    if problems:
        print("\nIncomplete results; this run cannot be compared or saved as a baseline:")
        for problem in problems:
            print(f"  {problem}")


def format_value(value, unit):
    if unit == "s":
        return f"{value * 1000:.1f} ms"
    return f"{value:.1f} {unit}"


def print_summary(summary):
    print(f"Device: {summary['device']}, {summary.get('mode', 'full')} mode")
    for size, tests in sorted(summary["results"].items(), key=lambda item: int(item[0])):
        print(f"\n{size} entries")
        for test, metrics in sorted(tests.items()):
            for metric, data in sorted(metrics.items()):
                print(f"  {test:28} {metric:32} {format_value(data['median'], data['unit']):>14}")


def provenance_of(summary, size, test):
    """The run that produced one test's results; summaries before provenance use the top level."""
    recorded = summary.get("provenance", {}).get(size, {}).get(test)
    if recorded:
        return recorded
    return {"mode": "full", **{key: summary.get(key) for key in ("device", "mode", "run", "load_average_15m") if key in summary}}


def is_heavier_load(candidate_load, baseline_load):
    return candidate_load is not None and (baseline_load is None or candidate_load > baseline_load * 1.5 + 1)


def compare(baseline_path, candidate_path):
    baseline_path = Path(baseline_path)
    candidate = json.loads(Path(candidate_path).read_text())
    if not baseline_path.exists():
        print(f"No baseline at {baseline_path}; save one with `make bench-baseline` (quick runs: `make bench-quick-baseline`).")
        return
    baseline = json.loads(baseline_path.read_text())
    require_complete(candidate, "compare")
    candidate_load = candidate.get("load_average_15m")
    print(f"Candidate {candidate['run']} on {candidate['device']}, host load (15 min) {candidate_load}")
    regressions = improvements = 0
    warned_runs = set()
    for size, tests in sorted(candidate["results"].items(), key=lambda item: int(item[0])):
        print(f"\n{size} entries")
        for test, metrics in sorted(tests.items()):
            source = provenance_of(baseline, size, test) if test in baseline["results"].get(size, {}) else None
            if source and source["run"] not in warned_runs:
                warned_runs.add(source["run"])
                load = source.get("load_average_15m")
                print(f"  (baseline run {source['run']} on {source['device']}, host load {load if load is not None else 'unknown'})")
                if source["device"] != candidate["device"]:
                    print(f"  Warning: that baseline ran on {source['device']}, not {candidate['device']}.")
                if source.get("mode", "full") != candidate.get("mode", "full"):
                    print("  Warning: that baseline ran in a different mode; quick and full builds are not comparable.")
                if is_heavier_load(candidate_load, load):
                    print("  Warning: the candidate ran under more host load, which inflates every metric. Rerun on a quieter machine before trusting regressions.")
            for metric, data in sorted(metrics.items()):
                old = baseline["results"].get(size, {}).get(test, {}).get(metric)
                new_value = data["median"]
                unit = data["unit"]
                if old is None:
                    print(f"  {test:28} {metric:32} {format_value(new_value, unit):>14}  (new)")
                    continue
                old_value = old["median"]
                difference = new_value - old_value
                # A zero baseline (no hitches) makes any change infinitely relative, so only the
                # absolute floor decides.
                relative = difference / old_value if old_value else float("inf") if difference else 0
                floor = ABSOLUTE_FLOORS.get(unit, 0)
                flag = ""
                if abs(difference) > floor and abs(relative) > RELATIVE_THRESHOLD:
                    if difference > 0:
                        flag = "  REGRESSION"
                        regressions += 1
                    else:
                        flag = "  improved"
                        improvements += 1
                change = f"{relative:+7.1%}" if abs(relative) != float("inf") else "   from 0"
                print(
                    f"  {test:28} {metric:32} {format_value(old_value, unit):>14} -> "
                    f"{format_value(new_value, unit):>14}  {change}{flag}"
                )
    print(f"\n{regressions} regression(s), {improvements} improvement(s) beyond the noise thresholds.")


def save_baseline(baseline_path, candidate_path):
    baseline_path = Path(baseline_path)
    candidate = json.loads(Path(candidate_path).read_text())
    require_complete(candidate, "save the baseline")
    baseline = json.loads(baseline_path.read_text()) if baseline_path.exists() else {"results": {}}
    # One device and mode per baseline: merging another device's or mode's partial run would
    # mix incomparable results under one label.
    candidate_source = (candidate["device"], candidate.get("mode", "full"))
    retained_sources = {
        (source["device"], source.get("mode", "full"))
        for size, tests in baseline["results"].items()
        for test in tests
        for source in [provenance_of(baseline, size, test)]
    }
    if retained_sources - {candidate_source}:
        held = ", ".join(f"{device} ({mode})" for device, mode in sorted(retained_sources))
        sys.exit(
            f"The baseline holds results from {held}, not {candidate_source[0]} ({candidate_source[1]}). "
            f"Delete {baseline_path} to start a new baseline."
        )
    provenance = baseline.setdefault("provenance", {})
    # Pin the provenance of results kept from summaries that predate per-test provenance.
    for size, tests in baseline["results"].items():
        for test in tests:
            provenance.setdefault(size, {}).setdefault(test, provenance_of(baseline, size, test))
    replaced = 0
    for size, tests in candidate["results"].items():
        for test, metrics in tests.items():
            baseline["results"].setdefault(size, {})[test] = metrics
            provenance.setdefault(size, {})[test] = provenance_of(candidate, size, test)
            replaced += 1
    # Run and load live per test now; the top level keeps only the single device.
    baseline.pop("run", None)
    baseline.pop("load_average_15m", None)
    baseline["device"] = candidate["device"]
    baseline["mode"] = candidate.get("mode", "full")
    baseline_path.write_text(json.dumps(baseline, indent=2, sort_keys=True))
    print(f"Saved {replaced} test result(s) from {candidate['run']} into {baseline_path}.")


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "summarize":
        summarize(sys.argv[2])
    elif len(sys.argv) == 5 and sys.argv[1] == "summarize" and sys.argv[3] in ("full", "quick"):
        summarize(sys.argv[2], sys.argv[3], int(sys.argv[4]))
    elif len(sys.argv) == 4 and sys.argv[1] == "compare":
        compare(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "save-baseline":
        save_baseline(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
