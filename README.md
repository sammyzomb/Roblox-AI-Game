# Roblox AI Game

> **PROJECT GOVERNANCE / 開發規則**
>
> 此專案由 **Product Owner（sammyzomb）決定方向與優先順序**，**Claude Code 擔任主開發**，負責程式修改與整合到候選分支。
> ChatGPT 改為**顧問／審查**角色：提供意見與審查，但不派工、不把關、不決定能否合併。
> 開始工作前，所有協作者都必須先閱讀：
> - `STATUS.md`（目前進度、分工、候選分支）
> - `README.md`
> - `docs/AI_RULES.md`
> - `docs/ARCHITECTURE.md`
>
> **禁止直接修改 `main`。** 合併到 `main` 需經 Product Owner 同意。

Collaborative Roblox game project developed through GitHub with human direction and AI-assisted development.

## Team Roles

- Product Owner: sammyzomb — direction, priorities, Studio testing, final acceptance
- Claude Code: Primary Developer — all code changes and integration into the candidate branch
- Cursor: Secondary Developer — read-only checks on the assigned candidate branch
- ChatGPT: Advisor / Reviewer — design discussion and review opinions (advisory only)
- Grok: Independent Reviewer and creative planning roles

## Workflow

No AI agent should develop features directly on `main`.

- Current candidate branch: see `STATUS.md` (now `candidate/v1`).
- Claude Code works on the candidate branch or task branches and integrates them there.
- Merging into `main` requires Product Owner approval.

See `docs/AI_RULES.md` for collaboration rules.
