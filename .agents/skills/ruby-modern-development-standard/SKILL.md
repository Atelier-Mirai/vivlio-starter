---
name: ruby-modern-development-standard
description: vivlio-starter専用のRuby 4.0+ / Samovar開発標準。ユーザーがRuby実装・バグ修正・リファクタ・テスト変更・CLI（vs/vivlio-starter）挙動変更・README同期更新を依頼したら必ず使う。明示指定がなくても、.rb / .gemspec / Gemfile / Rakefile / bin/vs / bin/vivlio-starter に関わる作業ではこのスキルを優先して適用する。
---

# Ruby Modern Development Standard (vivlio-starter)

## Goal
Keep changes safe, minimal, and readable while using modern Ruby 4.0+ style in this repository.

## Core rules
1. Change only the requested scope (files/functions explicitly mentioned by the user).
2. Do not mix bug fixes and unrelated refactoring in the same patch unless explicitly requested.
3. Ask before destructive changes (public API signature changes, file moves/deletes, dependency changes, test expectation rewrites).
4. If requirements are ambiguous, ask a clarifying question before implementation.

## Ruby style guidance
- Prefer Ruby 4.0+ idioms where appropriate (`it`, pattern matching, endless methods, `Data.define`).
- Avoid over-abstraction and unnecessary wrapper/helper methods.
- Keep logic readable as a coherent flow; optimize for human readability over mechanical micro-rules.
- Add method comments only for methods created or modified in the current task.

## Project-specific guidance
- This project is a Ruby CLI (Samovar) with commands like `vs` / `vivlio-starter`.
- For CLI-facing behavior changes, verify help and command behavior at least for affected commands.
- When behavior changes user-facing docs, update `README.md` in the same task.

## Validation checklist
Run the relevant checks after changes:
1. `bundle exec rake test`
2. `bundle exec rubocop` (when Ruby code style or structure changed)
3. For CLI changes, run:
   - `bundle exec vs help`
   - affected command `--help` or target command execution

## Response checklist
- Summarize changed files and why.
- Report any scope-external issues as suggestions only (do not edit without approval).
- Explicitly list unresolved questions or assumptions.
