#!/usr/bin/env python3
"""Cycle Advisor AI 助手验收 runner。

流程：
1. 用 assistant_probe（复用 App 真实 prompt 构建代码）生成每个用例的 system/user prompt；
2. 通过 BFF（默认 https://api.smallbeebee.com/v1/chat/completions）流式调用真实模型；
3. 按用例 acceptance 规则自动断言，输出报告（MD + JSON）。

凭据：
- token：环境变量 PROMPTFOO_APP_TOKEN，否则读取 Sources/Core/Secrets.swift 的 appToken
- BFF：环境变量 PROMPTFOO_BFF_URL，否则读取 Secrets.swift 的 baseURL

用法：
  python3 tools/assistant_acceptance_runner.py --run
  python3 tools/assistant_acceptance_runner.py --evaluate-only
  python3 tools/assistant_acceptance_runner.py --list
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CASES_PATH = ROOT / "tools" / "assistant_acceptance_cases.json"
PROBE_DIR = ROOT / "tools" / "assistant_probe"
PROBE_BIN = PROBE_DIR / "build" / "probe"
BUILD_SCRIPT = PROBE_DIR / "build.sh"
SECRETS_PATH = ROOT / "Sources" / "Core" / "Secrets.swift"
ANSWERS_PATH = ROOT / "tools" / "assistant_acceptance_answers.json"
REPORT_MD_PATH = ROOT / "tools" / "assistant_acceptance_report.md"
REPORT_JSON_PATH = ROOT / "tools" / "assistant_acceptance_report.json"


def read_secrets() -> dict[str, str]:
    if not SECRETS_PATH.exists():
        return {}
    text = SECRETS_PATH.read_text(encoding="utf-8")
    out: dict[str, str] = {}
    m = re.search(r'baseURL\s*=\s*"([^"]+)"', text)
    if m:
        out["baseURL"] = m.group(1)
    m = re.search(r'appToken\s*=\s*"([^"]+)"', text)
    if m:
        out["appToken"] = m.group(1)
    return out


def load_cases() -> list[dict[str, Any]]:
    data = json.loads(CASES_PATH.read_text(encoding="utf-8"))
    return data["cases"]


def contains_any(text: str, terms: list[str]) -> bool:
    return any(t.lower() in text.lower() for t in terms)


def cjk_ratio(text: str) -> float:
    if not text:
        return 0.0
    cjk = sum(1 for ch in text if "\u4e00" <= ch <= "\u9fff")
    return cjk / max(1, len(text))


def ensure_probe() -> Path:
    if PROBE_BIN.exists():
        return PROBE_BIN
    print("probe 未编译，先执行 build.sh ...")
    subprocess.run(["bash", str(BUILD_SCRIPT)], check=True, cwd=ROOT)
    return PROBE_BIN


def probe_prompt(case: dict[str, Any], probe_bin: Path) -> dict[str, Any]:
    spec = {
        "id": case["id"],
        "task": case.get("task", "chat"),
        "mode": case.get("mode", "fast"),
        "language": case.get("language", "zh"),
        "user_message": case.get("user_message", ""),
        "context_preset": case.get("context_preset", "no_health_data"),
        "profile_preset": case.get("profile_preset", "empty"),
        "assistant_reply": case.get("assistant_reply", ""),
    }
    proc = subprocess.run(
        [str(probe_bin)],
        input=json.dumps(spec, ensure_ascii=False).encode("utf-8"),
        capture_output=True,
        cwd=ROOT,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"probe failed for {case['id']}: {proc.stderr.decode(errors='replace')}")
    return json.loads(proc.stdout.decode("utf-8"))


def call_bff(
    bff_url: str,
    token: str,
    system_prompt: str,
    user_message: str,
    *,
    mode: str,
    stream: bool,
    max_tokens: int,
) -> dict[str, Any]:
    model = "deepseek-reasoner" if mode == "deep" else "deepseek-chat"
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ],
        "stream": stream,
        "temperature": 0.70,
        "max_tokens": max_tokens,
    }
    req = urllib.request.Request(
        bff_url,
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-App-Token": token,
        },
        method="POST",
    )
    started = time.monotonic()
    with urllib.request.urlopen(req, timeout=200) as resp:
        if stream:
            content_parts: list[str] = []
            reasoning_parts: list[str] = []
            for raw_line in resp:
                line = raw_line.decode("utf-8", errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if not payload or payload == "[DONE]":
                    continue
                try:
                    obj = json.loads(payload)
                except json.JSONDecodeError:
                    continue
                choice = (obj.get("choices") or [{}])[0]
                delta = choice.get("delta") or {}
                if delta.get("reasoning_content"):
                    reasoning_parts.append(delta["reasoning_content"])
                if delta.get("content"):
                    content_parts.append(delta["content"])
            content = "".join(content_parts)
            reasoning = "".join(reasoning_parts)
        else:
            obj = json.loads(resp.read().decode("utf-8"))
            choice = (obj.get("choices") or [{}])[0]
            msg = choice.get("message") or {}
            content = msg.get("content") or ""
            reasoning = msg.get("reasoning_content") or ""
    elapsed = round(time.monotonic() - started, 2)
    return {"content": content, "reasoning": reasoning, "elapsed_s": elapsed, "model": model}


def clean_json_content(raw: str) -> str:
    s = raw
    if "</think>" in s:
        s = s[s.index("</think>") + len("</think>"):]
    s = s.replace("```json", "").replace("```", "").strip()
    return s


def parse_questions(content: str) -> list[str]:
    cleaned = clean_json_content(content)
    try:
        data = json.loads(cleaned)
    except json.JSONDecodeError:
        return []
    if isinstance(data, list):
        return [str(q).strip() for q in data if str(q).strip()]
    if isinstance(data, dict):
        for key in ("questions", "问题"):
            val = data.get(key)
            if isinstance(val, list):
                return [str(q).strip() for q in val if str(q).strip()]
    return []


def evaluate_case(case: dict[str, Any], answer: dict[str, Any], elapsed: float) -> dict[str, Any]:
    acc = case.get("acceptance", {})
    content = answer.get("content", "")
    reasoning = answer.get("reasoning", "")
    checks: dict[str, Any] = {}
    failures: list[str] = []

    lang = acc.get("language_check")
    if lang == "en":
        passed = cjk_ratio(content) < 0.02
        checks["language_en"] = passed
        if not passed:
            failures.append("language_en")
    elif lang == "zh":
        passed = cjk_ratio(content) > 0.5
        checks["language_zh"] = passed
        if not passed:
            failures.append("language_zh")

    include_groups = acc.get("must_include_any", [])
    include_results = []
    for group in include_groups:
        hit = contains_any(content, group)
        include_results.append({"terms": group, "passed": hit})
        if not hit:
            failures.append("include:" + "|".join(group))
    checks["includes"] = include_results

    avoid_terms = acc.get("must_avoid", [])
    avoid_hits = [t for t in avoid_terms if t.lower() in content.lower()]
    checks["avoid_hits"] = avoid_hits
    for t in avoid_hits:
        failures.append("avoid:" + t)

    q_count = acc.get("expect_question_count")
    if q_count is not None:
        questions = parse_questions(content)
        passed = len(questions) == q_count
        checks["question_count"] = {"expected": q_count, "got": len(questions), "questions": questions}
        if not passed:
            failures.append(f"question_count({len(questions)} != {q_count})")

    if acc.get("expect_reasoning"):
        passed = len(reasoning.strip()) > 0
        checks["reasoning_present"] = passed
        if not passed:
            failures.append("reasoning_missing")

    include_passed = sum(1 for r in include_results if r["passed"])
    include_total = max(1, len(include_results))
    score = max(0, round(include_passed / include_total * 100 - len(avoid_hits) * 12))

    return {
        "id": case["id"],
        "title": case["title"],
        "priority": case.get("priority", "P1"),
        "score": score,
        "passed": not failures,
        "failures": failures,
        "checks": checks,
        "elapsed_s": elapsed,
        "content": content,
        "reasoning": reasoning,
    }


def case_condition_met(case: dict[str, Any]) -> tuple[bool, str]:
    condition = case.get("condition")
    if not condition:
        return True, ""
    if condition == "hour < 12":
        hour = datetime.now().hour
        if hour < 12:
            return True, ""
        return False, f"当前本地时间 {hour} 点，不满足 hour < 12，跳过"
    return True, ""


def run_cases(cases: list[dict[str, Any]], bff_url: str, token: str, stream: bool) -> list[dict[str, Any]]:
    probe_bin = ensure_probe()
    results = []
    for case in cases:
        met, reason = case_condition_met(case)
        if not met:
            print(f"SKIP {case['id']}: {reason}")
            results.append({"id": case["id"], "skipped": True, "reason": reason})
            continue
        cid = case["id"]
        print(f"RUN  {cid} ({case.get('priority', 'P1')}/{case.get('domain', '')}) ...")
        prompt = probe_prompt(case, probe_bin)
        max_tokens = 300 if case.get("task") in ("followup", "suggested") else 800
        try:
            answer = call_bff(
                bff_url,
                token,
                prompt["systemPrompt"],
                prompt["userMessage"],
                mode=case.get("mode", "fast"),
                stream=stream,
                max_tokens=max_tokens,
            )
        except Exception as exc:  # noqa: BLE001
            print(f"  ERROR {cid}: {exc}")
            results.append({"id": cid, "error": str(exc)})
            continue
        result = evaluate_case(case, answer, answer["elapsed_s"])
        status = "PASS" if result["passed"] else "FAIL"
        print(f"  {status} {cid} score={result['score']} {result['failures']}")
        results.append(result)
    return results


def load_answers() -> dict[str, Any]:
    if not ANSWERS_PATH.exists():
        return {}
    return json.loads(ANSWERS_PATH.read_text(encoding="utf-8"))


def save_answers(answers: dict[str, Any]) -> None:
    ANSWERS_PATH.write_text(json.dumps(answers, ensure_ascii=False, indent=2), encoding="utf-8")


def build_report(cases: list[dict[str, Any]], results: list[dict[str, Any]]) -> tuple[dict[str, Any], str]:
    executed = [r for r in results if not r.get("skipped") and "error" not in r]
    errors = [r for r in results if "error" in r]
    skipped = [r for r in results if r.get("skipped")]
    passed = [r for r in executed if r["passed"]]
    failed = [r for r in executed if not r["passed"]]

    summary = {
        "total": len(cases),
        "executed": len(executed),
        "passed": len(passed),
        "failed": len(failed),
        "errors": len(errors),
        "skipped": len(skipped),
        "pass_rate": round(len(passed) / max(1, len(executed)) * 100, 1),
        "avg_score": round(sum(r["score"] for r in executed) / max(1, len(executed)), 1),
        "generated_at": datetime.now().isoformat(timespec="seconds"),
    }

    lines = [
        "# Cycle Advisor AI 助手验收报告",
        "",
        f"- 生成时间：{summary['generated_at']}",
        f"- 用例总数：{summary['total']}；执行：{summary['executed']}；通过：{summary['passed']}；失败：{summary['failed']}；错误：{summary['errors']}；跳过：{summary['skipped']}",
        f"- 自动断言通过率：{summary['pass_rate']}%",
        f"- 平均得分（0-100）：{summary['avg_score']}",
        "",
        "> 自动断言只是粗筛，最终结论需结合人工复核（见各用例 manual_checks）。",
        "",
    ]
    for r in results:
        if r.get("skipped"):
            lines.append(f"## {r['id']} — 跳过")
            lines.append("")
            lines.append(r["reason"])
            lines.append("")
            continue
        if "error" in r:
            lines.append(f"## {r['id']} — 调用失败")
            lines.append("")
            lines.append(f"```\n{r['error']}\n```")
            lines.append("")
            continue
        case = next((c for c in cases if c["id"] == r["id"]), {})
        status = "PASS" if r["passed"] else "FAIL"
        lines.append(f"## {r['id']} — {status}（score={r['score']}，{r['elapsed_s']}s）")
        lines.append("")
        lines.append(case.get("title", ""))
        lines.append("")
        if r["failures"]:
            lines.append("自动断言失败项：")
            lines.append("")
            for f in r["failures"]:
                lines.append(f"- {f}")
            lines.append("")
        manual = case.get("acceptance", {}).get("manual_checks", [])
        if manual:
            lines.append("人工复核要点：")
            lines.append("")
            for m in manual:
                lines.append(f"- [ ] {m}")
            lines.append("")

    report_json = {"summary": summary, "results": results}
    return report_json, "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true", help="列出用例")
    parser.add_argument("--run", action="store_true", help="生成 prompt 并真实调用模型")
    parser.add_argument("--probe-only", action="store_true", help="只生成 prompt，不调用模型（离线验证）")
    parser.add_argument("--evaluate-only", action="store_true", help="仅评估已有 answers 文件")
    parser.add_argument("--no-stream", action="store_true", help="非流式调用（默认流式，与 App 一致）")
    parser.add_argument("--bff-url", default=None, help="BFF 地址（默认读 Secrets.swift）")
    parser.add_argument("--token", default=None, help="X-App-Token（默认读环境变量或 Secrets.swift）")
    parser.add_argument("--answers", type=Path, default=ANSWERS_PATH, help="answers JSON 路径")
    args = parser.parse_args()

    cases = load_cases()
    if args.list:
        for c in cases:
            print(f"{c['id']}: [{c.get('priority', 'P1')}/{c.get('domain', '')}] {c['title']}")
        return 0

    if args.probe_only:
        probe_bin = ensure_probe()
        prompts: dict[str, Any] = {}
        for case in cases:
            met, reason = case_condition_met(case)
            if not met:
                print(f"SKIP {case['id']}: {reason}")
                continue
            print(f"PROBE {case['id']} ...")
            prompts[case["id"]] = probe_prompt(case, probe_bin)
        out = ROOT / "tools" / "assistant_acceptance_prompts.json"
        out.write_text(json.dumps(prompts, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\nprompts 已写入：{out}")
        return 0

    secrets = read_secrets()
    bff_url = args.bff_url or os.environ.get("PROMPTFOO_BFF_URL") or secrets.get("baseURL", "")
    token = args.token or os.environ.get("PROMPTFOO_APP_TOKEN") or secrets.get("appToken", "")
    if not bff_url or not token:
        print("缺少 BFF 地址或 token：请设置 PROMPTFOO_BFF_URL / PROMPTFOO_APP_TOKEN，或提供可用的 Secrets.swift")
        return 2

    if args.run:
        results = run_cases(cases, bff_url, token, stream=not args.no_stream)
        answers: dict[str, Any] = load_answers()
        for r in results:
            if "error" not in r and not r.get("skipped"):
                answers[r["id"]] = {
                    "content": r.get("content", ""),
                    "reasoning": r.get("reasoning", ""),
                    "elapsed_s": r.get("elapsed_s"),
                }
        save_answers(answers)
        report_json, report_md = build_report(cases, results)
    elif args.evaluate_only:
        answers = load_answers()
        results = []
        for case in cases:
            if case["id"] not in answers:
                results.append({"id": case["id"], "skipped": True, "reason": "answers 文件中无该用例"})
                continue
            answer = answers[case["id"]]
            results.append(evaluate_case(case, answer, answer.get("elapsed_s", 0)))
        report_json, report_md = build_report(cases, results)
    else:
        parser.print_help()
        return 0

    REPORT_MD_PATH.write_text(report_md, encoding="utf-8")
    REPORT_JSON_PATH.write_text(json.dumps(report_json, ensure_ascii=False, indent=2), encoding="utf-8")
    print(report_md)
    print(f"\n报告已写入：{REPORT_MD_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
