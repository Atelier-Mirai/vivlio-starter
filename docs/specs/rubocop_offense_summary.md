# RuboCop 違反サマリー

- 対象ディレクトリ: `lib/vivlio/starter/`
- 実行コマンド: `bundle exec rubocop --parallel --format json lib/vivlio/starter/`
- 集計日時: 2026-04-12 (UTC+09:00)
- 総違反件数: **1595件**（前回 632件 → 963件増加）
- 検査ファイル数: 118件

## 残存違反一覧

| ファイル | 件数 | 主な違反内容 |
| --- | --- | --- |
| `lib/vivlio/starter/cli/pdf/pdf_read_command.rb` | 110 | Style/StringLiterals: 64件, Style/RedundantRegexpEscape: 8件, Metrics/AbcSize: 7件 |
| `lib/vivlio/starter/cli/create.rb` | 99 | Layout/HashAlignment: 24件, Lint/AmbiguousOperatorPrecedence: 20件, Metrics/AbcSize: 8件 |
| `lib/vivlio/starter/cli/pdf/mecab_newline_cleaner.rb` | 73 | Style/StringLiterals: 29件, Style/RedundantFreeze: 9件, Lint/UselessConstantScoping: 5件 |
| `lib/vivlio/starter/cli/common.rb` | 59 | Layout/TrailingWhitespace: 9件, Layout/EmptyLineAfterGuardClause: 8件, Metrics/AbcSize: 5件 |
| `lib/vivlio/starter/cli/index/unified_index_manager.rb` | 55 | Metrics/CyclomaticComplexity: 10件, Metrics/AbcSize: 9件, Metrics/PerceivedComplexity: 7件 |
| `lib/vivlio/starter/cli/build/outline_extractor.rb` | 50 | Metrics/AbcSize: 12件, Metrics/CyclomaticComplexity: 10件, Metrics/PerceivedComplexity: 8件 |
| `lib/vivlio/starter/cli/build/pipeline.rb` | 48 | Layout/LineLength: 11件, Metrics/AbcSize: 10件, Layout/ExtraSpacing: 6件 |
| `lib/vivlio/starter/cli/post_process.rb` | 43 | Metrics/AbcSize: 10件, Metrics/CyclomaticComplexity: 8件, Metrics/PerceivedComplexity: 8件 |
| `lib/vivlio/starter/cli/samovar/build_command.rb` | 42 | Layout/TrailingWhitespace: 20件, Metrics/AbcSize: 6件, Metrics/MethodLength: 3件 |
| `lib/vivlio/starter/cli/textlint_formatter.rb` | 36 | Style/PerlBackrefs: 14件, Style/RedundantRegexpEscape: 8件, Style/RegexpLiteral: 5件 |
| `lib/vivlio/starter/cli/token_resolver.rb` | 35 | Style/PerlBackrefs: 9件, Layout/HashAlignment: 5件, Metrics/AbcSize: 3件 |
| `lib/vivlio/starter/cli/build/pdf_merger.rb` | 35 | Layout/TrailingWhitespace: 8件, Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 4件 |
| `lib/vivlio/starter/cli/pre_process/css_updater.rb` | 31 | Metrics/AbcSize: 7件, Metrics/CyclomaticComplexity: 5件, Metrics/PerceivedComplexity: 5件 |
| `lib/vivlio/starter/cli/index/review_markdown_generator.rb` | 31 | Metrics/AbcSize: 6件, Metrics/CyclomaticComplexity: 5件, Metrics/PerceivedComplexity: 4件 |
| `lib/vivlio/starter/cli/index/index_match_scanner.rb` | 31 | Metrics/AbcSize: 6件, Layout/LineLength: 4件, Style/RegexpLiteral: 2件 |
| `lib/vivlio/starter/cli/import/markdown_converter.rb` | 31 | Style/RegexpLiteral: 11件, Layout/HashAlignment: 10件, Style/StringConcatenation: 3件 |
| `lib/vivlio/starter/cli/pre_process/data_render/query_stream_parser.rb` | 30 | Style/PerlBackrefs: 14件, Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 2件 |
| `lib/vivlio/starter/cli/doctor.rb` | 29 | Metrics/AbcSize: 7件, Layout/LineLength: 7件, Metrics/CyclomaticComplexity: 4件 |
| `lib/vivlio/starter/cli/pre_process/image_generator.rb` | 27 | Metrics/AbcSize: 5件, Layout/LineLength: 5件, Metrics/MethodLength: 3件 |
| `lib/vivlio/starter/cli/post_process/heading_processor.rb` | 24 | Metrics/CyclomaticComplexity: 6件, Naming/PredicateMethod: 5件, Metrics/AbcSize: 4件 |
| `lib/vivlio/starter/cli/cover.rb` | 24 | Metrics/AbcSize: 4件, Lint/AmbiguousOperatorPrecedence: 4件, Metrics/CyclomaticComplexity: 3件 |
| `lib/vivlio/starter/scaffolder.rb` | 23 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 3件, Style/IfUnlessModifier: 3件 |
| `lib/vivlio/starter/cli/new.rb` | 23 | Metrics/AbcSize: 5件, Layout/MultilineMethodCallIndentation: 5件, Layout/HashAlignment: 3件 |
| `lib/vivlio/starter/cli/pre_process/markdown_transformer.rb` | 22 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 4件, Metrics/PerceivedComplexity: 4件 |
| `lib/vivlio/starter/cli/index/index_candidate_extractor.rb` | 22 | Metrics/AbcSize: 5件, Layout/MultilineMethodCallIndentation: 4件, Metrics/CyclomaticComplexity: 3件 |
| `lib/vivlio/starter/cli/import/yaml_processor.rb` | 21 | Style/YAMLFileRead: 3件, Layout/HashAlignment: 3件, Metrics/AbcSize: 3件 |
| `lib/vivlio/starter/cli/pre_process/theme_image_resolver.rb` | 21 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 5件, Metrics/PerceivedComplexity: 4件 |
| `lib/vivlio/starter/cli/font_manager.rb` | 21 | Metrics/AbcSize: 3件, Layout/FirstArrayElementIndentation: 2件, Metrics/CyclomaticComplexity: 2件 |
| `lib/vivlio/starter/cli/import.rb` | 20 | Style/IfUnlessModifier: 4件, Style/StringLiterals: 3件, Metrics/CyclomaticComplexity: 2件 |
| `lib/vivlio/starter/cli/pre_process/link_image_validator.rb` | 19 | Metrics/AbcSize: 4件, Style/NumericPredicate: 4件, Metrics/MethodLength: 2件 |
| `lib/vivlio/starter/cli/clean.rb` | 19 | Layout/IndentationConsistency: 6件, Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 2件 |
| `lib/vivlio/starter/cli/rename.rb` | 18 | Metrics/AbcSize: 5件, Metrics/MethodLength: 2件, Lint/UselessAssignment: 2件 |
| `lib/vivlio/starter/cli/metrics/runner.rb` | 17 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 3件, Metrics/PerceivedComplexity: 3件 |
| `lib/vivlio/starter/cli/build/pdf_builder.rb` | 17 | Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 3件, Metrics/MethodLength: 3件 |
| `lib/vivlio/starter/cli/build/output_helpers.rb` | 17 | Style/RedundantFreeze: 3件, Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 3件 |
| `lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb` | 16 | Metrics/AbcSize: 6件, Metrics/CyclomaticComplexity: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/lint.rb` | 16 | Metrics/AbcSize: 5件, Metrics/CyclomaticComplexity: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/index/unified_terms_manager.rb` | 15 | Metrics/AbcSize: 4件, Metrics/CyclomaticComplexity: 3件, Metrics/PerceivedComplexity: 3件 |
| `lib/vivlio/starter/cli/pre_process/frontmatter_generator.rb` | 14 | Style/SingleArgumentDig: 5件, Metrics/AbcSize: 4件, Layout/LineLength: 2件 |
| `lib/vivlio/starter/cli/pre_process/data_render/template_compiler.rb` | 14 | Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/build/catalog_updater.rb` | 14 | Metrics/AbcSize: 4件, Style/StringConcatenation: 2件, Metrics/CyclomaticComplexity: 2件 |
| `lib/vivlio/starter/cli/build/section_builder.rb` | 13 | Metrics/AbcSize: 4件, Metrics/PerceivedComplexity: 3件, Metrics/CyclomaticComplexity: 2件 |
| `lib/vivlio/starter/cli/index/unified_page_builder.rb` | 12 | Metrics/AbcSize: 3件, Metrics/CyclomaticComplexity: 3件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/build/page_mapping_extractor.rb` | 12 | Style/ItBlockParameter: 3件, Style/StringLiterals: 2件, Metrics/AbcSize: 2件 |
| `lib/vivlio/starter/cli/pre_process.rb` | 11 | Style/ArgumentsForwarding: 2件, Metrics/ModuleLength: 1件, Style/GuardClause: 1件 |
| `lib/vivlio/starter/cli/build/image_optimizer.rb` | 11 | Style/SingleArgumentDig: 3件, Layout/LineLength: 3件, Metrics/CyclomaticComplexity: 2件 |
| `lib/vivlio/starter/cli/build/epub_builder.rb` | 10 | Metrics/AbcSize: 2件, Metrics/MethodLength: 2件, Metrics/PerceivedComplexity: 2件 |
| `lib/vivlio/starter/cli/index/review_queue_manager.rb` | 10 | Metrics/AbcSize: 2件, Naming/PredicateMethod: 2件, Metrics/ClassLength: 1件 |
| `lib/vivlio/starter/cli/pre_process/markdown_utils.rb` | 10 | Metrics/AbcSize: 2件, Metrics/CyclomaticComplexity: 2件, Metrics/MethodLength: 2件 |
| `lib/vivlio/starter/cli/pdf/standard_provider.rb` | 9 | Lint/UnusedMethodArgument: 3件, Naming/MethodParameterName: 2件, Lint/EmptyBlock: 1件 |
| `lib/vivlio/starter/cli/build/catalog_loader.rb` | 9 | Style/IfUnlessModifier: 3件, Metrics/AbcSize: 2件, Metrics/ModuleLength: 1件 |
| `lib/vivlio/starter/cli/build/toc_generator.rb` | 9 | Metrics/AbcSize: 2件, Metrics/CyclomaticComplexity: 2件, Metrics/MethodLength: 2件 |
| `lib/vivlio/starter/cli/lint/spell_checker.rb` | 8 | Style/FormatStringToken: 5件, Metrics/AbcSize: 2件, Naming/PredicateMethod: 1件 |
| `lib/vivlio/starter/cli/pre_process/data_render/singularize.rb` | 7 | Style/PerlBackrefs: 5件, Layout/ExtraSpacing: 2件 |
| `lib/vivlio/starter/cli/resize.rb` | 7 | Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/samovar/index_command.rb` | 7 | Layout/TrailingWhitespace: 3件, Metrics/AbcSize: 2件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/pre_process/image_path_normalizer.rb` | 7 | Layout/LineLength: 2件, Style/IfUnlessModifier: 2件, Metrics/ModuleLength: 1件 |
| `lib/vivlio/starter/cli/metrics/live_display.rb` | 7 | Style/ItBlockParameter: 2件, Metrics/ClassLength: 1件, Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/metrics/formatter.rb` | 7 | Lint/AmbiguousOperatorPrecedence: 2件, Metrics/ClassLength: 1件, Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/lint/dict_manager.rb` | 7 | Metrics/AbcSize: 2件, Style/ItBlockParameter: 1件, Style/RedundantRegexpEscape: 1件 |
| `lib/vivlio/starter/cli/build/chapter_config.rb` | 6 | Metrics/AbcSize: 3件, Metrics/ModuleLength: 1件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/build/nombre_stamper.rb` | 6 | Layout/CommentIndentation: 2件, Naming/MethodParameterName: 2件, Style/Documentation: 1件 |
| `lib/vivlio/starter/cli/lint/tokenizer.rb` | 6 | Lint/RedundantRequireStatement: 1件, Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/entries.rb` | 5 | Lint/RedundantDirGlobSort: 2件, Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/build/backlink_deduplicator.rb` | 5 | Lint/RedundantRequireStatement: 1件, Metrics/ClassLength: 1件, Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/build/utilities.rb` | 5 | Naming/PredicateMethod: 2件, Metrics/ModuleLength: 1件, Layout/EmptyLinesAroundModuleBody: 1件 |
| `lib/vivlio/starter/cli/metrics/analyzer.rb` | 5 | Metrics/AbcSize: 2件, Metrics/ClassLength: 1件, Style/SymbolProc: 1件 |
| `lib/vivlio/starter/cli/vivliostyle.rb` | 4 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/MethodLength: 1件 |
| `lib/vivlio/starter/cli/index/yomi_inferrer.rb` | 4 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/PerceivedComplexity: 1件 |
| `lib/vivlio/starter/cli/metrics/cache.rb` | 4 | Lint/NonAtomicFileOperation: 2件, Style/YAMLFileRead: 1件, Lint/UnusedMethodArgument: 1件 |
| `lib/vivlio/starter/cli/build/part_title_generator.rb` | 4 | Lint/RedundantDirGlobSort: 1件, Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件 |
| `lib/vivlio/starter/cli/post_process/section_wrapper.rb` | 4 | Naming/MethodParameterName: 2件, Metrics/CyclomaticComplexity: 1件, Metrics/PerceivedComplexity: 1件 |
| `lib/vivlio/starter/cli/post_process/html_replacer.rb` | 4 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Metrics/MethodLength: 1件 |
| `lib/vivlio/starter/cli/post_process/body_class_injector.rb` | 4 | Style/IfUnlessModifier: 1件, Metrics/CyclomaticComplexity: 1件, Naming/MemoizedInstanceVariableName: 1件 |
| `lib/vivlio/starter/cli/samovar/help_command.rb` | 3 | Style/FormatStringToken: 2件, Layout/TrailingWhitespace: 1件 |
| `lib/vivlio/starter/cli/import/image_processor.rb` | 3 | Metrics/ModuleLength: 1件, Naming/PredicateMethod: 1件, Lint/UselessAccessModifier: 1件 |
| `lib/vivlio/starter/cli/toc.rb` | 3 | Metrics/AbcSize: 1件, Style/MultipleComparison: 1件, Layout/LineLength: 1件 |
| `lib/vivlio/starter/cli/startup.rb` | 3 | Style/Documentation: 1件, Lint/RescueException: 1件, Style/IfUnlessModifier: 1件 |
| `lib/vivlio/starter/cli/pre_process/cross_reference_processor.rb` | 3 | Metrics/AbcSize: 1件, Metrics/CyclomaticComplexity: 1件, Lint/RedundantSafeNavigation: 1件 |
| `lib/vivlio/starter/cli/metrics/config_loader.rb` | 3 | Metrics/ClassLength: 1件, Style/WordArray: 1件, Style/YAMLFileRead: 1件 |
| `lib/vivlio/starter/cli/metrics/parallel_runner.rb` | 3 | Metrics/AbcSize: 2件, Style/ComparableClamp: 1件 |
| `lib/vivlio/starter/cli/samovar/root_command.rb` | 2 | Metrics/AbcSize: 1件, Lint/UselessConstantScoping: 1件 |
| `lib/vivlio/starter/cli/samovar/import_command.rb` | 2 | Metrics/AbcSize: 1件, Style/GuardClause: 1件 |
| `lib/vivlio/starter/cli/samovar/pdf_command.rb` | 2 | Metrics/AbcSize: 1件, Lint/DuplicateBranch: 1件 |
| `lib/vivlio/starter/cli/samovar/cover_command.rb` | 2 | Metrics/CyclomaticComplexity: 1件, Style/RedundantParentheses: 1件 |
| `lib/vivlio/starter/cli/post_process/footnote_converter.rb` | 2 | Metrics/ModuleLength: 1件, Metrics/AbcSize: 1件 |
| `lib/vivlio/starter/cli/index/scoring_engine.rb` | 2 | Naming/MethodParameterName: 2件 |
| `lib/vivlio/starter/cli/index/hierarchical_index.rb` | 2 | Naming/AccessorMethodName: 1件, Style/SymbolProc: 1件 |
| `lib/vivlio/starter/cli/convert.rb` | 2 | Metrics/AbcSize: 1件, Layout/TrailingEmptyLines: 1件 |
| `lib/vivlio/starter/cli/build/backlink_dedup_orchestrator.rb` | 2 | Metrics/AbcSize: 1件, Lint/UnusedMethodArgument: 1件 |
| `lib/vivlio/starter/cli/pdf/provider.rb` | 1 | Style/Documentation: 1件 |
| `lib/vivlio/starter/cli/samovar/resize_command.rb` | 1 | Layout/EmptyLinesAroundModuleBody: 1件 |
| `lib/vivlio/starter/cli/pdf.rb` | 1 | Metrics/ClassLength: 1件 |
| `lib/vivlio/starter/cli/metrics/catalog_loader.rb` | 1 | Style/YAMLFileRead: 1件 |
| `lib/vivlio/starter/cli/index.rb` | 1 | Metrics/AbcSize: 1件 |

## 備考

前回（2025-12-27）から963件増加。新規追加ファイル（`cli/pdf/`, `cli/index/`, `cli/import/`, `cli/metrics/`, `cli/lint/` 配下など）が検査対象に加わったことが主因。既存ファイルの違反数は概ね横ばいまたは微減。

残存違反の多くは Metrics 系（AbcSize, CyclomaticComplexity, PerceivedComplexity）および Style 系（StringLiterals, PerlBackrefs, RegexpLiteral）であり、メソッド分割・スタイル統一等のリファクタリングが必要。
