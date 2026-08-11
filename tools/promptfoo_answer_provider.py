#!/usr/bin/env python3
"""Promptfoo provider for profile-grounded assistant evals.

Default mode reads pre-generated assistant answers from JSON.
Set PROMPTFOO_PROFILE_ANSWERS to a JSON file shaped like:
{
  "case_id": "assistant answer"
}

Live mode calls the Cycle Advisor BFF:
  PROMPTFOO_PROFILE_PROVIDER=live
  PROMPTFOO_BFF_URL=https://.../v1/chat/completions
  PROMPTFOO_APP_TOKEN=...
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Optional
import re


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ANSWERS = ROOT / "tools" / "assistant_profile_harness_answers.example.json"
CASES_PATH = ROOT / "tools" / "assistant_profile_harness_cases.json"
SWIFT_SECRETS_PATH = ROOT / "Sources" / "Core" / "Secrets.swift"
DEFAULT_MODEL = "deepseek-chat"


def load_context() -> dict[str, Any]:
    for arg in reversed(sys.argv[1:]):
        try:
            parsed = json.loads(arg)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            return parsed
    return {}


def load_prompt_text() -> str:
    arg_text = "\n".join(arg for arg in sys.argv[1:] if not arg.lstrip().startswith("{"))
    stdin_text = "" if sys.stdin.isatty() else sys.stdin.read()
    return f"{arg_text}\n{stdin_text}"


def case_id_from_prompt(prompt_text: str) -> Optional[str]:
    for case in load_cases():
        if case.get("question") and case["question"] in prompt_text:
            return case.get("id")
    return None


def load_cases() -> list[dict[str, Any]]:
    try:
        cases = json.loads(CASES_PATH.read_text(encoding="utf-8"))["cases"]
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        return []
    return [case for case in cases if isinstance(case, dict)]


def case_by_id(case_id: str) -> Optional[dict[str, Any]]:
    for case in load_cases():
        if case.get("id") == case_id:
            return case
    return None


def build_live_system_prompt(case: dict[str, Any]) -> str:
    profile_notes = "\n".join(f"- {note}" for note in case.get("profile_notes", []))
    return f"""你是月经周期生活方式顾问"周期助理"，语气温暖体贴，但要简洁、具体、可执行。

规则：
- 提供生活方式建议，含具体做法/份量/时间；不做医学诊断或治疗承诺。
- 禁用「治疗」「诊断」「医嘱」等医疗措辞。
- 回答前优先看：当前周期阶段/当前症状 > 用户这次问题 > 用户个人画像 > 历史参考。
- 当问题与饮食、运动、睡眠、症状、周期规律相关时，必须至少引用 1 条相关画像信息。
- 若画像中有禁忌/偏好，建议必须避开冲突方案，并主动给出匹配替代选项。
- 若画像中有用户常做运动，优先把建议改写成用户熟悉的运动形式。
- 若用户有咖啡因影响睡眠，下午/晚上加餐必须避开咖啡、奶茶、浓茶、可可和巧克力，优先给无咖啡因替代。
- 若当前症状包含疼痛/痉挛/疲劳，运动建议必须明确写出“低强度”或“降低强度”，并说明今天先不跑步/不做高强度。
- 如果用户画像/状态重点含有“咖啡因”，回答必须明确出现“咖啡因”，并说明下午/晚上避开含咖啡因选择。
- 只有当用户画像/状态重点明确含有“历史”或“非当前状态”时，才使用“历史记录”措辞；这种情况下第一段必须写清楚“不代表你现在有这些症状”。
- 如果用户画像/状态重点没有“历史”或“非当前状态”，不要使用“历史记录”开头。
- 输出纯文本，不输出 JSON。

用户画像/状态重点：
{profile_notes}
"""


def call_live_bff(case: dict[str, Any]) -> str:
    bff_url = os.environ.get("PROMPTFOO_BFF_URL")
    app_token = os.environ.get("PROMPTFOO_APP_TOKEN")
    if os.environ.get("PROMPTFOO_USE_SWIFT_SECRETS") == "1":
        swift_secrets = load_swift_secrets()
        bff_url = bff_url or swift_secrets.get("baseURL")
        app_token = app_token or swift_secrets.get("appToken")
    if not bff_url or not app_token:
        raise RuntimeError("Live mode requires PROMPTFOO_BFF_URL/PROMPTFOO_APP_TOKEN or PROMPTFOO_USE_SWIFT_SECRETS=1")

    payload = {
        "model": os.environ.get("PROMPTFOO_MODEL", DEFAULT_MODEL),
        "messages": [
            {"role": "system", "content": build_live_system_prompt(case)},
            {"role": "user", "content": case.get("question", "")},
        ],
        "stream": False,
        "temperature": float(os.environ.get("PROMPTFOO_TEMPERATURE", "0")),
        "max_tokens": int(os.environ.get("PROMPTFOO_MAX_TOKENS", "700")),
    }
    if os.environ.get("PROMPTFOO_LIVE_HTTP_CLIENT", "curl") == "curl":
        response_data = call_bff_with_curl(bff_url, app_token, payload)
    else:
        response_data = call_bff_with_urllib(bff_url, app_token, payload)

    choices = response_data.get("choices") or []
    if not choices:
        raise RuntimeError(f"BFF response has no choices: {response_data}")
    message = choices[0].get("message") or {}
    content = message.get("content")
    if not isinstance(content, str) or not content.strip():
        raise RuntimeError(f"BFF response has empty content: {response_data}")
    return content.strip()


def call_bff_with_urllib(bff_url: str, app_token: str, payload: dict[str, Any]) -> dict[str, Any]:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        bff_url,
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-App-Token": app_token,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            response_data = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"BFF HTTP {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"BFF request failed: {exc}") from exc
    return response_data


def call_bff_with_curl(bff_url: str, app_token: str, payload: dict[str, Any]) -> dict[str, Any]:
    data = json.dumps(payload, ensure_ascii=False)
    cmd = [
        "curl",
        "-sS",
        "--fail-with-body",
        "--max-time",
        os.environ.get("PROMPTFOO_BFF_TIMEOUT_SECONDS", "120"),
        "-X",
        "POST",
        "-H",
        "Content-Type: application/json",
        "-H",
        f"X-App-Token: {app_token}",
        "--data-binary",
        "@-",
        bff_url,
    ]
    result = subprocess.run(
        cmd,
        input=data,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip()
        stdout = result.stdout.strip()
        detail = stdout or stderr or f"curl exited {result.returncode}"
        raise RuntimeError(f"BFF curl request failed: {detail}")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"BFF returned invalid JSON: {result.stdout[:500]}") from exc


def load_swift_secrets() -> dict[str, str]:
    try:
        text = SWIFT_SECRETS_PATH.read_text(encoding="utf-8")
    except FileNotFoundError:
        return {}

    secrets: dict[str, str] = {}
    for key in ("baseURL", "appToken"):
        match = re.search(rf"static\s+let\s+{key}\s*=\s*\"([^\"]+)\"", text)
        if match:
            secrets[key] = match.group(1)
    return secrets


def main() -> int:
    context = load_context()
    vars_ = context.get("vars", {})
    case_id = vars_.get("id") or case_id_from_prompt(load_prompt_text())
    if not case_id:
        print("Missing promptfoo vars.id", file=sys.stderr)
        return 1

    if os.environ.get("PROMPTFOO_PROFILE_PROVIDER") == "live":
        case = case_by_id(case_id)
        if not case:
            print(f"No case found for id: {case_id}", file=sys.stderr)
            return 1
        try:
            print(call_live_bff(case))
        except RuntimeError as exc:
            print(str(exc), file=sys.stderr)
            return 1
        return 0

    answers_path = Path(os.environ.get("PROMPTFOO_PROFILE_ANSWERS", DEFAULT_ANSWERS))
    try:
        answers = json.loads(answers_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        print(f"Answers file not found: {answers_path}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"Invalid answers JSON {answers_path}: {exc}", file=sys.stderr)
        return 1

    answer = answers.get(case_id)
    if not isinstance(answer, str) or not answer.strip():
        print(f"No answer found for case id: {case_id}", file=sys.stderr)
        return 1

    print(answer)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
