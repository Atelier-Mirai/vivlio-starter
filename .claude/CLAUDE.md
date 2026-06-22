# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Coding Rules
Always apply the ruby-coding-rules skill when working with .rb files.

## What This Project Is

`vivlio-starter` is a Ruby gem (CLI tool `vs`) that wraps Vivliostyle (CSS typesetting engine) to generate publication-quality PDFs and EPUBs from Markdown. Requires Ruby 4.0+. The CLI framework is Samovar.

## Commands

```bash
# Run all tests (excludes page layout integration tests)
rake test

# Run a single test file
ruby -Ilib -Itest test/vivlio_starter/cli/token_resolver_test.rb

# Run page layout integration tests (executes vs build — slow)
rake test:layout

# Rebuild and reinstall the gem locally
rake reinstall

# Lint Ruby code
bundle exec rubocop

# Debug mode for CLI commands
VS_DEBUG=1 vs build --no-clean --log=debug
```

## Architecture

### Entry Points

- `bin/vs` / `bin/vivlio-starter` → `VivlioStarter::CLI.start(argv)` in `lib/vivlio_starter/cli/startup.rb`
- `lib/vivlio_starter/cli/loader.rb` requires all domain modules before Samovar command classes
- `lib/vivlio_starter/cli/samovar/root_command.rb` routes argv to the matching command class

### Configuration (`Common::CONFIG`)

`config/book.yml` is loaded at module load time into `VivlioStarter::CLI::Common::CONFIG`, a frozen `Data` object (Ruby 4.0 style). Supports dot-notation (`CONFIG.book.main_title`) and bracket access. Reload with `Common.reload_configuration!`. Commands that require a project call `Common.ensure_configured!` early; `new`, `doctor`, `help` work without it.

### Chapter / Entry Model

`TokenResolver::Entry` (a `Data.define`) is the canonical representation of a chapter. Naming convention: `{number}-{slug}.md` (e.g., `10-intro.md`). Number ranges determine kind: `00` = preface, `01–89` = chapter, `90–98` = appendix, `99` = postface. `TokenResolver::Resolver` translates loose user input (number, slug, basename, range) into `Entry` arrays.

### Build Pipeline (`vs build`)

Implemented in `lib/vivlio_starter/cli/build/pipeline.rb` as `UnifiedBuildPipeline`. Two modes:

- **`:full`** — 14+ sequential steps: clean → image optimize → Markdown pre-process → index scan → VFM/HTML convert → TOC → Vivliostyle PDF → backlink dedup → cover PDF → merge → outline → colophon adjust → compress → rename
- **`:single`** — abbreviated path for per-chapter preview (steps 6–12, 14 skipped)

### Pre-processing (`lib/vivlio_starter/cli/pre_process/`)

Pipeline run by `MarkdownPreprocessor` per chapter: frontmatter generation, image path normalization, code include from `codes/`, book-card/table-rotate conversion, link-to-footnote transformation, cross-reference resolution (global pass after all chapters).

### Post-processing (`lib/vivlio_starter/cli/post_process/`)

Applied to HTML after Vivliostyle: footnote conversion, heading processor, body class injection, section wrapping, HTML replacement.

### PDF low-level operations (providers)

Low-level PDF operations (hidden nombre stamping, PDF outline/bookmarks) go through `VivlioStarter::Pdf.provider` (`lib/vivlio_starter/cli/pdf/provider.rb`), which selects one of **two implementations**:

- **`StandardProvider`** (`standard_provider.rb`, in this repo, **MIT**, Prawn + CombinePDF) — nombre only; outline is a no-op warning.
- **`EnhancedProvider`** (in a **separate gem `vivlio-starter-pdf`**, HexaPDF) — full nombre + outline.

Selection: `VIVLIO_PDF_PLUGIN=disable` forces standard; otherwise, if `vivlio-starter-pdf` is **gem-installed** (even when absent from the Gemfile — `provider.rb` injects its load paths and picks the newest installed version), the enhanced provider is used. **A developer machine with the plugin installed runs builds through `EnhancedProvider`**, so a fix to `StandardProvider` alone won't change real builds — change both, and `gem build` + bump version + `gem install` the plugin to apply it. Unit-test `StandardProvider` directly (not via `NombreStamper.stamp!`, which routes to whichever provider is active); the plugin has its own test suite.

### Logging

`Common` provides `log_info`, `log_success`, `log_warn`, `log_error`, `log_action`, `log_debug`, `log_summary`, `log_result`. Default level is `warn` (🟡+🔴 always). Pass `--log` to raise to `info`; `--log=debug` for everything.

### Testing

Minitest. Test files live in `test/` mirroring `lib/`. Fixtures in `test/vivlio_starter/fixtures/`. Robustness tests (security, interrupt, YAML safety) in `test/vivlio_starter/robustness/`. Page layout tests in `test/vivlio_starter/page_layout/` run actual `vs build` and are excluded from `rake test`.

When the `vivlio-starter-pdf` plugin is installed (the usual dev setup), `rake test` exercises only the `EnhancedProvider` path. Run **`rake test:standard`** (sets `VIVLIO_PDF_PLUGIN=disable` in a subprocess) to force the MIT `StandardProvider` path without uninstalling the plugin — so standard-mode regressions are caught. `test:release` runs both. Main-repo tests must not depend on AGPL HexaPDF: create PDFs with Prawn and inspect them with pdf-reader (both MIT runtime deps); HexaPDF-using tests guard with a skip.
