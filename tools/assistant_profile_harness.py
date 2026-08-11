#!/usr/bin/env python3
"""Offline harness for checking whether assistant answers use user profiles well.

Usage:
  python3 tools/assistant_profile_harness.py --list
  python3 tools/assistant_profile_harness.py --template
  python3 tools/assistant_profile_harness.py --answers path/to/answers.json

Answers JSON format:
{
  "diet_lactose_sensitive_luteal": "answer text...",
  "exercise_yoga_runner_menstrual_cramps": "answer text..."
}
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CASES_PATH = ROOT / "tools" / "assistant_profile_harness_cases.json"


def load_cases() -> list[dict[str, Any]]:
    data = json.loads(CASES_PATH.read_text(encoding="utf-8"))
    return data["cases"]


def contains_any(text: str, terms: list[str]) -> bool:
    return any(term.lower() in text.lower() for term in terms)


def score_answer(case: dict[str, Any], answer: str) -> dict[str, Any]:
    include_groups = case.get("must_include_any", [])
    avoid_terms = case.get("must_avoid", [])

    include_results = [
        {
            "terms": group,
            "passed": contains_any(answer, group),
        }
        for group in include_groups
    ]
    avoid_hits = [term for term in avoid_terms if term.lower() in answer.lower()]

    include_passed = sum(1 for result in include_results if result["passed"])
    include_total = len(include_results)
    avoid_penalty = len(avoid_hits)
    score = max(0, round((include_passed / max(1, include_total)) * 100 - avoid_penalty * 12))

    return {
        "id": case["id"],
        "title": case["title"],
        "score": score,
        "passed": include_passed == include_total and not avoid_hits,
        "include_results": include_results,
        "avoid_hits": avoid_hits,
    }


def print_case_list(cases: list[dict[str, Any]]) -> None:
    for case in cases:
        print(f"{case['id']}: {case['title']}")


def print_template(cases: list[dict[str, Any]]) -> None:
    print(json.dumps({case["id"]: "" for case in cases}, ensure_ascii=False, indent=2))


def print_prompt_pack(cases: list[dict[str, Any]]) -> None:
    for case in cases:
        print(f"\n## {case['id']} - {case['title']}")
        print("用户问题：")
        print(case["question"])
        print("\n用户画像/状态重点：")
        for note in case["profile_notes"]:
            print(f"- {note}")
        print("\n人工验收重点：")
        print(case["notes"])


def evaluate(answers_path: Path, cases: list[dict[str, Any]]) -> int:
    answers = json.loads(answers_path.read_text(encoding="utf-8"))
    results = []
    for case in cases:
        answer = answers.get(case["id"], "")
        results.append(score_answer(case, answer))

    failures = 0
    for result in results:
        status = "PASS" if result["passed"] else "FAIL"
        print(f"{status} {result['id']} score={result['score']}")
        for include in result["include_results"]:
            marker = "ok" if include["passed"] else "missing"
            print(f"  include/{marker}: {' | '.join(include['terms'])}")
        if result["avoid_hits"]:
            print(f"  avoid/hit: {', '.join(result['avoid_hits'])}")
        if not result["passed"]:
            failures += 1

    avg = round(sum(result["score"] for result in results) / max(1, len(results)))
    print(f"\nAverage score: {avg}")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true", help="List harness cases.")
    parser.add_argument("--template", action="store_true", help="Print blank answers JSON.")
    parser.add_argument("--prompt-pack", action="store_true", help="Print cases for manual/LLM answer generation.")
    parser.add_argument("--answers", type=Path, help="Evaluate answers JSON.")
    args = parser.parse_args()

    cases = load_cases()
    if args.list:
        print_case_list(cases)
        return 0
    if args.template:
        print_template(cases)
        return 0
    if args.prompt_pack:
        print_prompt_pack(cases)
        return 0
    if args.answers:
        return evaluate(args.answers, cases)

    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
