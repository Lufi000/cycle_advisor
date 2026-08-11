# Assistant Profile Harness

这个 harness 用来回归“AI 助手是否真的根据用户档案回答”。

当前推荐入口是 Promptfoo：

```sh
npm run eval:profile:example
```

评分真实/线上捕获答案时，把答案写成 `tools/assistant_profile_harness_answers.example.json` 同样的结构，然后运行：

```sh
PROMPTFOO_PROFILE_ANSWERS=/path/to/answers.json npm run eval:profile
```

直接调用当前 BFF/LLM 评分：

```sh
PROMPTFOO_BFF_URL=https://your-bff.example.com/v1/chat/completions \
PROMPTFOO_APP_TOKEN=your-app-token \
npm run eval:profile:live
```

如果本机已有 `Sources/Core/Secrets.swift`，也可以直接读取本机密钥文件：

```sh
PROMPTFOO_USE_SWIFT_SECRETS=1 npm run eval:profile:live
```

可选参数：

```sh
PROMPTFOO_MODEL=deepseek-chat
PROMPTFOO_TEMPERATURE=0
PROMPTFOO_MAX_TOKENS=700
```

Promptfoo 配置在仓库根目录的 `promptfooconfig.profile.yaml`，断言逻辑在 `tools/promptfoo_profile_assert.js`。

下面的 Python 脚本是轻量备用入口，不依赖 Node/Promptfoo。

## 用法

列出用例：

```sh
python3 tools/assistant_profile_harness.py --list
```

输出给模型/人工测试用的问题包：

```sh
python3 tools/assistant_profile_harness.py --prompt-pack
```

生成空答案模板：

```sh
python3 tools/assistant_profile_harness.py --template > /tmp/assistant_answers.json
```

把真实或模拟回答填进 JSON 后评分：

```sh
python3 tools/assistant_profile_harness.py --answers /tmp/assistant_answers.json
```

## 评分重点

- `must_include_any`：每组至少命中一个词，代表回答确实使用了相关画像。
- `must_avoid`：命中即扣分，代表回答和画像冲突、误用历史信息，或出现不希望的医疗措辞。
- `passed`：所有 include 组都命中，且没有 avoid 命中。

这不是替代人工评审的最终裁判，而是用来防止 prompt 改动后退化成泛泛建议。
