# RuboCop 違反サマリー

- 対象ディレクトリ: `lib/vivlio/starter/`
- 実行コマンド: `bundle exec rubocop --parallel --format json lib/vivlio/starter/`
- 集計日時: 2025-12-27 20:00 (UTC+09:00)
- 総違反件数: **722件**（前回 805件 → 83件減少）

## 残存違反一覧

| ファイル | 件数 | 主な違反内容 |
| --- | --- | --- |
| `lib/vivlio/starter/cli/build/outline_extractor.rb` | 55 | Metrics/AbcSize: 11件, Metrics/CyclomaticComplexity: 10件, Metrics/PerceivedComplexity: 9件 |
| `lib/vivlio/starter/cli/post_process.rb` | 43 | Metrics/AbcSize: 9件, Metrics/CyclomaticComplexity: 8件, Metrics/PerceivedComplexity: 8件 |
| `lib/vivlio/starter/cli/doctor.rb` | 27 | Metrics/AbcSize: 6件, Metrics/CyclomaticComplexity: 5件, Metrics/PerceivedComplexity: 4件 |
| `lib/vivlio/starter/cli/post_process/heading_processor.rb` | 21 | Metrics/CyclomaticComplexity: 6件, Naming/PredicateMethod: 5件, Metrics/PerceivedComplexity: 4件 |
| `lib/vivlio/starter/cli/pre_process/frontmatter_generator.rb` | 8 | Metrics/AbcSize: 3件, Layout/LineLength: 2件, Metrics/ModuleLength: 1件 |
| `lib/vivlio/starter/cli/build/pdf_builder.rb` | 31 | Layout/LineLength: 8件, Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 4件 |
| `lib/vivlio/starter/cli/pre_process/image_generator.rb` | 27 | Metrics/AbcSize: 5件, Layout/LineLength: 5件, Metrics/MethodLength: 3件 |
| `lib/vivlio/starter/cli/pre_process/theme_image_resolver.rb` | 27 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 5件, Layout/LineLength: 5件 |
| `lib/vivlio/starter/cli/build/catalog_updater.rb` | 27 | Metrics/CyclomaticComplexity: 5件, Metrics/PerceivedComplexity: 5件, Metrics/AbcSize: 3件 |
| `lib/vivlio/starter/cli/pre_process/css_updater.rb` | 26 | Metrics/AbcSize: 6件, Metrics/CyclomaticComplexity: 4件, Metrics/PerceivedComplexity: 4件 |
| `lib/vivlio/starter/cli/cover.rb` | 24 | Lint/UnusedMethodArgument: 5件, Style/GuardClause: 4件, Metrics/AbcSize: 2件 |
| `lib/vivlio/starter/scaffolder.rb` | 23 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 3件, Style/IfUnlessModifier: 3件 |
| `lib/vivlio/starter/cli/common.rb` | 23 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 5件, Metrics/PerceivedComplexity: 4件 |
| `lib/vivlio/starter/cli/pre_process/markdown_transformer.rb` | 22 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 4件, Metrics/PerceivedComplexity: 4件 |
| `lib/vivlio/starter/cli/build/output_helpers.rb` | 21 | Style/FormatStringToken: 7件, Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 3件 |
| `lib/vivlio/starter/cli/font_manager.rb` | 21 | Metrics/AbcSize: 3件, Layout/FirstArrayElementIndentation: 2件, Metrics/CyclomaticComplexity: 2件 |
| `lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb` | 17 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/build/utilities.rb` | 17 | Naming/PredicateMethod: 4件, Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 3件 |
| `lib/vivlio/starter/cli/pre_process.rb` | 15 | Metrics/AbcSize: 2件, Metrics/CyclomaticComplexity: 2件, Metrics/MethodLength: 2件 |
| `lib/vivlio/starter/cli/build/section_builder.rb` | 14 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 3件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/text_lint.rb` | 14 | Style/IfUnlessModifier: 3件, Metrics/AbcSize: 2件, Metrics/CyclomaticComplexity: 2件 |
| `lib/vivlio/starter/cli/rename.rb` | 13 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 2件, Metrics/ClassLength: 1件 |
| `lib/vivlio/starter/cli/build/pdf_merger.rb` | 11 | Metrics/AbcSize: 2件, Metrics/CyclomaticComplexity: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/clean.rb` | 11 | Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 2件, Metrics/MethodLength: 2件 |
| `lib/vivlio/starter/cli/build/page_numberer.rb` | 11 | Metrics/AbcSize: 2件, Layout/LineLength: 2件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/glossary/add_commands.rb` | 11 | Metrics/AbcSize: 6件, Naming/PredicateMethod: 2件, Metrics/ModuleLength: 1件 |
| `lib/vivlio/starter/cli/glossary/lint_commands.rb` | 10 | Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 2件, Metrics/ModuleLength: 1件 |
| `lib/vivlio/starter/cli/pre_process/markdown_utils.rb` | 10 | Metrics/AbcSize: 2件, Metrics/CyclomaticComplexity: 2件, Metrics/MethodLength: 2件 |
| `lib/vivlio/starter/cli/build/pipeline.rb` | 10 | Metrics/AbcSize: 3件, Metrics/ClassLength: 1件, Layout/LineLength: 1件 |
| `lib/vivlio/starter/cli/create.rb` | 9 | Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/build/catalog_loader.rb` | 9 | Style/IfUnlessModifier: 3件, Metrics/AbcSize: 2件, Metrics/ModuleLength: 1件 |
| `lib/vivlio/starter/cli/glossary/fix_commands.rb` | 8 | Metrics/AbcSize: 3件, Metrics/ModuleLength: 1件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/commands/new.rb` | 8 | Metrics/AbcSize: 2件, Metrics/ModuleLength: 1件, Style/Documentation: 1件 |
| `lib/vivlio/starter/cli/build/image_optimizer.rb` | 7 | Metrics/CyclomaticComplexity: 2件, Layout/LineLength: 2件, Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/pre_process/image_path_normalizer.rb` | 7 | Layout/LineLength: 2件, Style/IfUnlessModifier: 2件, Metrics/ModuleLength: 1件 |
| `lib/vivlio/starter/cli/samovar/new_command.rb` | 6 | Metrics/AbcSize: 2件, Style/IfUnlessModifier: 2件, Style/GuardClause: 1件 |
| `lib/vivlio/starter/cli/samovar/build_command.rb` | 6 | Metrics/AbcSize: 2件, Metrics/ClassLength: 1件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/resize.rb` | 6 | Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/samovar/create_command.rb` | 6 | Style/Documentation: 5件, Naming/PredicateMethod: 1件 |
| `lib/vivlio/starter/cli/post_process/footnote_converter.rb` | 5 | Style/IdenticalConditionalBranches: 2件, Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/glossary/canonicalize_commands.rb` | 5 | Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/build/toc_generator.rb` | 5 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/MethodLength: 1件 |
| `lib/vivlio/starter/cli/post_process/section_wrapper.rb` | 4 | Naming/MethodParameterName: 2件, Metrics/CyclomaticComplexity: 1件, Metrics/PerceivedComplexity: 1件 |
| `lib/vivlio/starter/cli/post_process/html_replacer.rb` | 4 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/MethodLength: 1件 |
| `lib/vivlio/starter/cli/new.rb` | 4 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/MethodLength: 1件 |
| `lib/vivlio/starter/cli/vivliostyle.rb` | 4 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/MethodLength: 1件 |
| `lib/vivlio/starter/cli/entries.rb` | 4 | Lint/RedundantDirGlobSort: 2件, Metrics/ModuleLength: 1件, Style/IfUnlessModifier: 1件 |
| `lib/vivlio/starter/cli/convert.rb` | 4 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/PerceivedComplexity: 1件 |
| `lib/vivlio/starter/cli/build/chapter_config.rb` | 4 | Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/toc.rb` | 3 | Layout/LineLength: 2件, Style/MultipleComparison: 1件 |
| `lib/vivlio/starter/cli/samovar/resize_command.rb` | 3 | Style/Documentation: 3件 |
| `lib/vivlio/starter/cli/samovar/rename_command.rb` | 2 | Naming/PredicateMethod: 1件, Style/Documentation: 1件 |
| `lib/vivlio/starter/cli/samovar/pdf_command.rb` | 1 | Style/Documentation: 1件 |
| `lib/vivlio/starter/cli/samovar/entries_command.rb` | 1 | Naming/PredicateMethod: 1件 |
| `lib/vivlio/starter/cli/samovar/doctor_command.rb` | 1 | Naming/PredicateMethod: 1件 |
| `lib/vivlio/starter/cli/prism_lines.rb` | 1 | Style/ModuleFunction: 1件 |
| `lib/vivlio/starter/cli/post_process/body_class_injector.rb` | 1 | Naming/PredicateMethod: 1件 |
| `lib/vivlio/starter/cli/pdf.rb` | 1 | Metrics/ClassLength: 1件 |
| `lib/vivlio/starter/cli/glossary/shared_helpers.rb` | 1 | Layout/IndentationWidth: 1件 |
| `lib/vivlio/starter/cli/build/token_expander.rb` | 1 | Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli.rb` | 1 | Style/Documentation: 1件 |

## 備考

残存違反の多くは Metrics 系（AbcSize, CyclomaticComplexity, PerceivedComplexity）であり、メソッド分割等の大規模リファクタリングが必要。軽微な自動修正は完了済み。
