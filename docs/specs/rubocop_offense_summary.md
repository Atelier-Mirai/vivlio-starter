# RuboCop 違反サマリー

- 対象ディレクトリ: `lib/vivlio/starter/`
- 実行コマンド: `bundle exec rubocop --parallel --format json lib/vivlio/starter/`
- 集計日時: 2026-04-12 (UTC+09:00)
- 総違反件数: **884件**（前回 1595件 → 711件減少）
- 検査ファイル数: 118件

## 自動修正の経緯

| フェーズ | コマンド | 修正件数 |
| --- | --- | --- |
| 安全な自動修正 | `rubocop --autocorrect` | 1021件 |
| 積極的な自動修正 | `rubocop --autocorrect-all` | 119件 |
| 手動修正（構文エラー） | `font_manager.rb` の正規表現デリミタ修正 | 1件 |
| **合計削減** | | **711件** |

## 残存違反一覧

| ファイル | 件数 | 主な違反内容 |
| --- | --- | --- |
| `lib/vivlio/starter/cli/post_process.rb` | 43 | Metrics/AbcSize: 10件, Metrics/CyclomaticComplexity: 8件, Metrics/PerceivedComplexity: 8件 |
| `lib/vivlio/starter/cli/build/outline_extractor.rb` | 42 | Metrics/AbcSize: 12件, Metrics/CyclomaticComplexity: 10件, Metrics/PerceivedComplexity: 8件 |
| `lib/vivlio/starter/cli/index/unified_index_manager.rb` | 36 | Metrics/CyclomaticComplexity: 10件, Metrics/AbcSize: 9件, Metrics/PerceivedComplexity: 7件 |
| `lib/vivlio/starter/cli/create.rb` | 30 | Metrics/AbcSize: 8件, Naming/MethodParameterName: 8件, Metrics/CyclomaticComplexity: 4件 |
| `lib/vivlio/starter/cli/doctor.rb` | 29 | Metrics/AbcSize: 7件, Layout/LineLength: 7件, Metrics/CyclomaticComplexity: 4件 |
| `lib/vivlio/starter/cli/pre_process/css_updater.rb` | 25 | Metrics/AbcSize: 7件, Metrics/CyclomaticComplexity: 5件, Metrics/PerceivedComplexity: 5件 |
| `lib/vivlio/starter/cli/common.rb` | 24 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 4件, Metrics/PerceivedComplexity: 4件 |
| `lib/vivlio/starter/cli/index/review_markdown_generator.rb` | 23 | Metrics/AbcSize: 6件, Metrics/CyclomaticComplexity: 5件, Metrics/PerceivedComplexity: 4件 |
| `lib/vivlio/starter/cli/pdf/mecab_newline_cleaner.rb` | 22 | Metrics/AbcSize: 5件, Lint/UselessConstantScoping: 5件, Metrics/CyclomaticComplexity: 4件 |
| `lib/vivlio/starter/cli/build/pipeline.rb` | 22 | Metrics/AbcSize: 10件, Metrics/CyclomaticComplexity: 3件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/pre_process/theme_image_resolver.rb` | 21 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 5件, Metrics/PerceivedComplexity: 4件 |
| `lib/vivlio/starter/cli/index/index_match_scanner.rb` | 21 | Metrics/AbcSize: 6件, Layout/LineLength: 4件, Metrics/CyclomaticComplexity: 2件 |
| `lib/vivlio/starter/cli/post_process/heading_processor.rb` | 21 | Metrics/CyclomaticComplexity: 6件, Naming/PredicateMethod: 5件, Metrics/AbcSize: 4件 |
| `lib/vivlio/starter/cli/pre_process/markdown_transformer.rb` | 19 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 4件, Metrics/PerceivedComplexity: 4件 |
| `lib/vivlio/starter/cli/pre_process/image_generator.rb` | 19 | Metrics/AbcSize: 5件, Metrics/MethodLength: 3件, Layout/LineLength: 3件 |
| `lib/vivlio/starter/cli/samovar/build_command.rb` | 17 | Metrics/AbcSize: 6件, Metrics/MethodLength: 3件, Metrics/CyclomaticComplexity: 3件 |
| `lib/vivlio/starter/cli/pdf/pdf_read_command.rb` | 16 | Metrics/AbcSize: 7件, Metrics/CyclomaticComplexity: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/font_manager.rb` | 15 | Layout/ArrayAlignment: 3件, Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 2件 |
| `lib/vivlio/starter/cli/index/unified_terms_manager.rb` | 14 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 3件, Metrics/PerceivedComplexity: 3件 |
| `lib/vivlio/starter/cli/build/pdf_merger.rb` | 14 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 3件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/metrics/runner.rb` | 14 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 3件, Metrics/PerceivedComplexity: 3件 |
| `lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb` | 13 | Metrics/AbcSize: 6件, Metrics/CyclomaticComplexity: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/new.rb` | 13 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 2件, Metrics/MethodLength: 2件 |
| `lib/vivlio/starter/scaffolder.rb` | 13 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 3件, Metrics/MethodLength: 2件 |
| `lib/vivlio/starter/cli/build/pdf_builder.rb` | 13 | Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 3件, Metrics/MethodLength: 3件 |
| `lib/vivlio/starter/cli/pre_process/data_render/query_stream_parser.rb` | 12 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/lint.rb` | 12 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/build/section_builder.rb` | 12 | Metrics/AbcSize: 4件, Metrics/PerceivedComplexity: 3件, Metrics/CyclomaticComplexity: 2件 |
| `lib/vivlio/starter/cli/import/yaml_processor.rb` | 12 | Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 3件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/cover.rb` | 12 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 3件, Metrics/MethodLength: 2件 |
| `lib/vivlio/starter/cli/pre_process/link_image_validator.rb` | 11 | Metrics/AbcSize: 4件, Metrics/MethodLength: 2件, Metrics/ModuleLength: 1件 |
| `lib/vivlio/starter/cli/index/unified_page_builder.rb` | 11 | Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 3件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/rename.rb` | 11 | Metrics/AbcSize: 5件, Metrics/MethodLength: 2件, Metrics/ClassLength: 1件 |
| `lib/vivlio/starter/cli/index/index_candidate_extractor.rb` | 11 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/clean.rb` | 11 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 2件, Metrics/MethodLength: 2件 |
| `lib/vivlio/starter/cli/token_resolver.rb` | 10 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 3件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/pre_process/markdown_utils.rb` | 10 | Metrics/AbcSize: 2件, Metrics/CyclomaticComplexity: 2件, Metrics/MethodLength: 2件 |
| `lib/vivlio/starter/cli/build/output_helpers.rb` | 10 | Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 3件, Metrics/PerceivedComplexity: 3件 |
| `lib/vivlio/starter/cli/build/toc_generator.rb` | 9 | Metrics/AbcSize: 2件, Metrics/CyclomaticComplexity: 2件, Metrics/MethodLength: 2件 |
| `lib/vivlio/starter/cli/build/epub_builder.rb` | 8 | Metrics/AbcSize: 2件, Metrics/MethodLength: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/pre_process/data_render/template_compiler.rb` | 8 | Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/pre_process/frontmatter_generator.rb` | 8 | Metrics/AbcSize: 4件, Metrics/ModuleLength: 1件, Layout/LineLength: 1件 |
| `lib/vivlio/starter/cli/build/catalog_updater.rb` | 8 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 2件, Metrics/ModuleLength: 1件 |
| `lib/vivlio/starter/cli/lint/spell_checker.rb` | 8 | Style/FormatStringToken: 5件, Metrics/AbcSize: 2件, Naming/PredicateMethod: 1件 |
| `lib/vivlio/starter/cli/index/review_queue_manager.rb` | 8 | Metrics/AbcSize: 2件, Naming/PredicateMethod: 2件, Metrics/ClassLength: 1件 |
| `lib/vivlio/starter/cli/build/page_mapping_extractor.rb` | 7 | Style/ItBlockParameter: 3件, Metrics/AbcSize: 2件, Metrics/ClassLength: 1件 |
| `lib/vivlio/starter/cli/textlint_formatter.rb` | 7 | Metrics/AbcSize: 2件, Layout/LineLength: 1件, Metrics/ClassLength: 1件 |
| `lib/vivlio/starter/cli/pre_process.rb` | 6 | Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/pdf/standard_provider.rb` | 6 | Naming/MethodParameterName: 2件, Lint/EmptyBlock: 1件, Naming/PredicateMethod: 1件 |
| `lib/vivlio/starter/cli/resize.rb` | 6 | Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/import.rb` | 6 | Metrics/CyclomaticComplexity: 2件, Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/build/chapter_config.rb` | 6 | Metrics/AbcSize: 3件, Metrics/ModuleLength: 1件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/build/image_optimizer.rb` | 6 | Metrics/CyclomaticComplexity: 2件, Metrics/AbcSize: 1件, Metrics/MethodLength: 1件 |
| `lib/vivlio/starter/cli/import/markdown_converter.rb` | 5 | Metrics/AbcSize: 2件, Metrics/ModuleLength: 1件, Style/StringConcatenation: 1件 |
| `lib/vivlio/starter/cli/build/nombre_stamper.rb` | 4 | Naming/MethodParameterName: 2件, Style/Documentation: 1件, Lint/DuplicateBranch: 1件 |
| `lib/vivlio/starter/cli/pre_process/image_path_normalizer.rb` | 4 | Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件, Metrics/MethodLength: 1件 |
| `lib/vivlio/starter/cli/lint/dict_manager.rb` | 4 | Metrics/AbcSize: 2件, Metrics/CyclomaticComplexity: 1件, Metrics/PerceivedComplexity: 1件 |
| `lib/vivlio/starter/cli/vivliostyle.rb` | 4 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/MethodLength: 1件 |
| `lib/vivlio/starter/cli/build/catalog_loader.rb` | 4 | Metrics/AbcSize: 2件, Metrics/ModuleLength: 1件, Lint/DuplicateBranch: 1件 |
| `lib/vivlio/starter/cli/post_process/section_wrapper.rb` | 4 | Naming/MethodParameterName: 2件, Metrics/CyclomaticComplexity: 1件, Metrics/PerceivedComplexity: 1件 |
| `lib/vivlio/starter/cli/post_process/html_replacer.rb` | 4 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/MethodLength: 1件 |
| `lib/vivlio/starter/cli/build/utilities.rb` | 4 | Naming/PredicateMethod: 2件, Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/build/backlink_deduplicator.rb` | 3 | Metrics/ClassLength: 1件, Metrics/AbcSize: 1件, Naming/MethodParameterName: 1件 |
| `lib/vivlio/starter/cli/samovar/index_command.rb` | 3 | Metrics/AbcSize: 2件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/build/part_title_generator.rb` | 3 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/PerceivedComplexity: 1件 |
| `lib/vivlio/starter/cli/metrics/parallel_runner.rb` | 3 | Metrics/AbcSize: 2件, Style/ComparableClamp: 1件 |
| `lib/vivlio/starter/cli/metrics/formatter.rb` | 3 | Metrics/ClassLength: 1件, Metrics/AbcSize: 1件, Naming/PredicatePrefix: 1件 |
| `lib/vivlio/starter/cli/index/yomi_inferrer.rb` | 3 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/PerceivedComplexity: 1件 |
| `lib/vivlio/starter/cli/metrics/analyzer.rb` | 3 | Metrics/AbcSize: 2件, Metrics/ClassLength: 1件 |
| `lib/vivlio/starter/cli/lint/tokenizer.rb` | 3 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/PerceivedComplexity: 1件 |
| `lib/vivlio/starter/cli/samovar/help_command.rb` | 2 | Style/FormatStringToken: 2件 |
| `lib/vivlio/starter/cli/import/image_processor.rb` | 2 | Metrics/ModuleLength: 1件, Naming/PredicateMethod: 1件 |
| `lib/vivlio/starter/cli/toc.rb` | 2 | Metrics/AbcSize: 1件, Layout/LineLength: 1件 |
| `lib/vivlio/starter/cli/index/scoring_engine.rb` | 2 | Naming/MethodParameterName: 2件 |
| `lib/vivlio/starter/cli/startup.rb` | 2 | Style/Documentation: 1件, Lint/RescueException: 1件 |
| `lib/vivlio/starter/cli/samovar/root_command.rb` | 2 | Metrics/AbcSize: 1件, Lint/UselessConstantScoping: 1件 |
| `lib/vivlio/starter/cli/metrics/live_display.rb` | 2 | Metrics/ClassLength: 1件, Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/samovar/pdf_command.rb` | 2 | Metrics/AbcSize: 1件, Lint/DuplicateBranch: 1件 |
| `lib/vivlio/starter/cli/post_process/body_class_injector.rb` | 2 | Metrics/CyclomaticComplexity: 1件, Lint/NoReturnInBeginEndBlocks: 1件 |
| `lib/vivlio/starter/cli/post_process/footnote_converter.rb` | 2 | Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/samovar/import_command.rb` | 1 | Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/samovar/cover_command.rb` | 1 | Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/pre_process/data_render/singularize.rb` | 1 | Layout/LineLength: 1件 |
| `lib/vivlio/starter/cli/pdf/provider.rb` | 1 | Style/Documentation: 1件 |
| `lib/vivlio/starter/cli/pdf.rb` | 1 | Metrics/ClassLength: 1件 |
| `lib/vivlio/starter/cli/metrics/config_loader.rb` | 1 | Metrics/ClassLength: 1件 |
| `lib/vivlio/starter/cli/metrics/cache.rb` | 1 | Lint/UnusedMethodArgument: 1件 |
| `lib/vivlio/starter/cli/index/hierarchical_index.rb` | 1 | Naming/AccessorMethodName: 1件 |
| `lib/vivlio/starter/cli/index.rb` | 1 | Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/entries.rb` | 1 | Metrics/ModuleLength: 1件 |
| `lib/vivlio/starter/cli/convert.rb` | 1 | Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/build/backlink_dedup_orchestrator.rb` | 1 | Metrics/AbcSize: 1件 |

## 備考

自動修正（`--autocorrect` + `--autocorrect-all`）で1595件から884件に削減。残存違反の大半は Metrics 系（AbcSize, CyclomaticComplexity, PerceivedComplexity）であり、メソッド分割等の手動リファクタリングが必要。

なお `--autocorrect-all` 実行時に `font_manager.rb` の正規表現デリミタ変換（`/.../` → `%r{...}`）で `{` `}` の対応が崩れる構文エラーが発生したため、手動で `%r|...|` に修正済み。
