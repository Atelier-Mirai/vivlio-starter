# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/metrics/runner.rb
# ================================================================
# 責務:
#   metrics コマンドの実行フローを制御する。
#
# 機能:
#   - catalog.yml に基づく章フィルタリング
#   - サマリ即時出力 + ローディング表示 + 逐次出力
#   - キャッシュ機構による高速化
#   - 並列処理による章解析
#
# Ruby 4.0+ 構文:
#   - it パラメータ
#   - エンドレスメソッド
# ================================================================

require_relative 'analyzer'
require_relative 'config_loader'
require_relative 'formatter'
require_relative 'chapter_parser'
require_relative 'catalog_loader'
require_relative 'cache'
require_relative 'parallel_runner'

module Vivlio
  module Starter
    module CLI
      module Metrics
        # metrics コマンドの実行を制御する
        class Runner
          ChapterAnalysis = Data.define(:chapter, :basic, :vocab, :readability)
          PlaceholderChapter = Data.define(:path, :title, :chapter_num, :chars)

          def initialize(targets, options = {})
            @targets = Array(targets)
            @options = options
            @config = ConfigLoader.new
            @warning_checker = WarningChecker.new(@config)
            @formatter = Formatter.new(@config)
            @chapter_parser = ChapterParser.new(@warning_checker)
            @catalog_loader = CatalogLoader.new
            @cache = Cache.new
            @parallel_runner = ParallelRunner.new
            @analysis_buffer = {}
            @analysis_mutex = Mutex.new
          end

          # メトリクス分析を実行する
          def call
            files = resolve_files
            return warn_no_targets if files.empty?

            # JSON/YAML 出力は一括処理
            return output_structured(:json, files) if options[:json]
            return output_structured(:yaml, files) if options[:yaml]

            puts '📚 章別の解析結果'
            puts ''

            placeholders = build_placeholder_chapters(files)
            max_chars = [placeholders.map(&:chars).max || 1, 1].max
            file_order = files.each_with_index.to_h
            pending = {}
            next_display_index = 0

            all_analyses = analyze_chapters_with_progress(files) do |analysis|
              index = file_order[analysis.chapter.path]
              next unless index

              pending[index] = { analysis:, visible: analysis_visible?(analysis) }

              while pending.key?(next_display_index)
                entry = pending.delete(next_display_index)
                output_chapter_line(entry[:analysis].chapter, max_chars) if entry[:visible]
                next_display_index += 1
              end
            end

            visible_analyses = all_analyses.select { analysis_visible?(it) }
            if visible_analyses.empty?
              puts '（対象章がありません）'
              return warn_no_targets
            end

            final_basic, final_vocab, final_readability = aggregate_summary_from_analyses(all_analyses)
            output_final_summary(final_basic, final_vocab, final_readability)

            0
          end

          private

          attr_reader :targets, :options, :config, :warning_checker, :formatter,
                      :chapter_parser, :catalog_loader, :cache, :parallel_runner,
                      :analysis_buffer, :analysis_mutex

          def aggregate_summary_from_analyses(analyses)
            basics = analyses.map(&:basic)
            vocabularies = analyses.map(&:vocab)

            basic = aggregate_basic_stats(basics)
            vocab = aggregate_vocabulary_stats(vocabularies)
            readability = aggregate_readability(basic, vocab)

            [basic, vocab, readability]
          end

          def aggregate_basic_stats(basics)
            total_sentences = basics.sum(&:sentences)
            total_clauses = basics.sum(&:clauses)
            sentence_char_sum = basics.sum { it.avg_sentence_len * it.sentences }
            clause_char_sum = basics.sum { it.avg_clause_len * it.clauses }

            Metrics::BasicStats.new(
              chars: basics.sum(&:chars),
              chars_no_newline: basics.sum(&:chars_no_newline),
              lines: basics.sum(&:lines),
              sentences: total_sentences,
              avg_sentence_len: total_sentences.positive? ? sentence_char_sum / total_sentences : 0.0,
              clauses: total_clauses,
              avg_clause_len: total_clauses.positive? ? clause_char_sum / total_clauses : 0.0,
              commas: basics.sum(&:commas)
            )
          end

          def aggregate_vocabulary_stats(vocabularies)
            total_tokens = vocabularies.sum(&:total_tokens)
            total_word_length = vocabularies.sum(&:total_word_length)
            total_char_count = vocabularies.sum(&:total_char_count)
            kanji_char_count = vocabularies.sum(&:kanji_char_count)

            merged_tokens = vocabularies.each_with_object(Hash.new(0)) do |vocab, acc|
              vocab.tokens_map.each { |token, count| acc[token] += count }
            end

            unique_tokens = merged_tokens.size
            avg_word_length = total_tokens.positive? ? total_word_length.to_f / total_tokens : 0.0
            ttr = total_tokens.positive? ? unique_tokens.to_f / total_tokens : 0.0
            kanji_ratio = total_char_count.positive? ? (kanji_char_count.to_f / total_char_count) * 100 : 0.0

            Metrics::VocabularyStats.new(
              kanji_ratio:,
              avg_word_length:,
              ttr:,
              total_tokens:,
              unique_tokens:,
              kanji_char_count:,
              total_char_count:,
              total_word_length:,
              tokens_map: merged_tokens
            )
          end

          def aggregate_readability(basic, vocab)
            thresholds = config.readability_thresholds
            score = (basic.avg_sentence_len * 0.5) + (vocab.kanji_ratio * 0.5)

            label = if score <= thresholds[:easy]
                      'Easy'
                    elsif score <= thresholds[:standard]
                      'Standard'
                    else
                      'Professional'
                    end

            Metrics::ReadabilityScore.new(score:, label:)
          end

          # ================================================================
          # Phase 2: 章別解析（キャッシュ + 並列処理）
          # ================================================================

          # 章を解析し進捗を表示する
          def analyze_chapters_with_progress(files)
            results = []
            mutex = Mutex.new

            parallel_runner.parallel_each_with_progress(files, on_complete: ->(file, chapter) {
              mutex.synchronize do
                results << chapter
                yield chapter if block_given?
              end
            }) do |file|
              analyze_chapter_with_cache(file)
            end

            # ファイル順にソート
            file_order = files.each_with_index.to_h
            results.sort_by { file_order[it.chapter.path] || Float::INFINITY }
          end

          # キャッシュを活用して章を解析する
          def analyze_chapter_with_cache(file)
            existing = analysis_mutex.synchronize { analysis_buffer[file] }
            return existing if existing

            if (cached = load_cached_analysis(file))
              return cached
            end

            analysis = compute_chapter_analysis(file)
            cache.write(File.basename(file, '.md'), analysis_to_cache_hash(analysis), source_path: file)
            analysis_mutex.synchronize { analysis_buffer[file] = analysis }

            analysis
          rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
            chapter = chapter_parser.send(:blank_chapter, file)
            basic = Metrics::BasicStats.new(
              chars: 0,
              chars_no_newline: 0,
              lines: 0,
              sentences: 0,
              avg_sentence_len: 0.0,
              clauses: 0,
              avg_clause_len: 0.0,
              commas: 0
            )
            vocab = Metrics::VocabularyStats.new(
              kanji_ratio: 0.0,
              avg_word_length: 0.0,
              ttr: 0.0,
              total_tokens: 0,
              unique_tokens: 0,
              kanji_char_count: 0,
              total_char_count: 0,
              total_word_length: 0,
              tokens_map: {}
            )
            readability = Metrics::ReadabilityScore.new(score: 0.0, label: 'Easy')
            ChapterAnalysis.new(chapter:, basic:, vocab:, readability:)
          end

          def load_cached_analysis(file)
            basename = File.basename(file, '.md')
            cached = cache.read(basename, file)
            analysis = rebuild_analysis_from_cache(cached&.data)
            analysis_mutex.synchronize { analysis_buffer[file] = analysis } if analysis
            analysis
          end

          def compute_chapter_analysis(file)
            content = File.read(file, encoding: 'UTF-8')
            chapter = chapter_parser.parse_content(file, content)
            analyzer = Analyzer.new(content, readability: config.readability_thresholds)
            basic = analyzer.basic_stats
            vocab = analyzer.vocabulary_stats
            readability = analyzer.readability

            ChapterAnalysis.new(chapter:, basic:, vocab:, readability:)
          end

          # キャッシュデータから ChapterMetrics を再構築する
          def rebuild_chapter_from_cache(data)
            sections = (data['sections'] || []).map do |sec|
              SectionMetrics.new(
                title: sec['title'],
                chars: sec['chars'],
                warning: sec['warning']
              )
            end

            ChapterMetrics.new(
              path: data['path'],
              title: data['title'],
              chapter_num: data['chapter_num'],
              chars: data['chars'],
              sections:,
              warning: data['warning']
            )
          end

          # 解析結果をキャッシュ用ハッシュに変換する
          def analysis_to_cache_hash(analysis)
            chapter = analysis.chapter
            {
              'path' => chapter.path,
              'title' => chapter.title,
              'chapter_num' => chapter.chapter_num,
              'chars' => chapter.chars,
              'warning' => chapter.warning,
              'sections' => chapter.sections.map do |sec|
                { 'title' => sec.title, 'chars' => sec.chars, 'warning' => sec.warning }
              end,
              'basic_stats' => basic_stats_to_hash(analysis.basic),
              'vocabulary_stats' => vocabulary_stats_to_hash(analysis.vocab),
              'readability' => readability_to_hash(analysis.readability)
            }
          end

          def basic_stats_to_hash(basic)
            {
              'chars' => basic.chars,
              'chars_without_newline' => basic.chars_no_newline,
              'lines' => basic.lines,
              'sentences' => basic.sentences,
              'avg_sentence_chars' => basic.avg_sentence_len,
              'clauses' => basic.clauses,
              'avg_clause_chars' => basic.avg_clause_len,
              'commas' => basic.commas
            }
          end

          def vocabulary_stats_to_hash(vocab)
            {
              'kanji_ratio' => vocab.kanji_ratio,
              'avg_word_length' => vocab.avg_word_length,
              'ttr' => vocab.ttr,
              'total_tokens' => vocab.total_tokens,
              'unique_tokens' => vocab.unique_tokens,
              'kanji_char_count' => vocab.kanji_char_count,
              'total_char_count' => vocab.total_char_count,
              'total_word_length' => vocab.total_word_length,
              'tokens_map' => vocab.tokens_map.to_h
            }
          end

          def readability_to_hash(readability)
            {
              'score' => readability.score,
              'label' => readability.label
            }
          end

          def rebuild_analysis_from_cache(data)
            return nil unless data

            chapter = rebuild_chapter_from_cache(data)
            basic = rebuild_basic_stats(data['basic_stats'])
            vocab = rebuild_vocabulary_stats(data['vocabulary_stats'])
            readability = rebuild_readability(data['readability'])

            return nil unless [chapter, basic, vocab, readability].all?

            ChapterAnalysis.new(chapter:, basic:, vocab:, readability:)
          end

          def rebuild_basic_stats(data)
            return nil unless data

            Metrics::BasicStats.new(
              chars: data['chars'],
              chars_no_newline: data['chars_without_newline'],
              lines: data['lines'],
              sentences: data['sentences'],
              avg_sentence_len: data['avg_sentence_chars'],
              clauses: data['clauses'],
              avg_clause_len: data['avg_clause_chars'],
              commas: data['commas']
            )
          end

          def rebuild_vocabulary_stats(data)
            return nil unless data

            Metrics::VocabularyStats.new(
              kanji_ratio: data['kanji_ratio'],
              avg_word_length: data['avg_word_length'],
              ttr: data['ttr'],
              total_tokens: data['total_tokens'],
              unique_tokens: data['unique_tokens'],
              kanji_char_count: data['kanji_char_count'],
              total_char_count: data['total_char_count'],
              total_word_length: data['total_word_length'],
              tokens_map: data['tokens_map'] || {}
            )
          end

          def rebuild_readability(data)
            return nil unless data

            Metrics::ReadabilityScore.new(score: data['score'], label: data['label'])
          end

          def build_placeholder_chapters(files)
            files.map { light_scan_placeholder(it) }
          end

          def light_scan_placeholder(file)
            content = File.read(file, encoding: 'UTF-8')
            chars = content.delete("\r\n").length
            PlaceholderChapter.new(
              path: file,
              title: extract_placeholder_title(content, file),
              chapter_num: extract_placeholder_chapter_num(file),
              chars:
            )
          rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
            PlaceholderChapter.new(
              path: file,
              title: File.basename(file, '.md'),
              chapter_num: extract_placeholder_chapter_num(file),
              chars: 0
            )
          end

          def extract_placeholder_title(content, file)
            match = content.match(ChapterParser::H1_PATTERN)
            match ? match[1].strip : File.basename(file, '.md')
          end

          def extract_placeholder_chapter_num(file)
            basename = File.basename(file, '.md')
            match = basename.match(ChapterParser::CHAPTER_NUM_PATTERN)
            match ? match[1].to_i : 0
          end

          def output_chapter_line(chapter, max_chars)
            puts formatter.format_chapter_line(chapter, max_chars, show_sections?)
          end

          # ================================================================
          # ファイル解決
          # ================================================================

          # ファイルを解決する
          def resolve_files
            paths = if targets.empty?
                      resolve_from_catalog
                    else
                      resolve_target_paths
                    end

            paths.select { File.exist?(it) }.sort
          end

          # catalog.yml から有効章を解決する
          def resolve_from_catalog
            enabled = catalog_loader.enabled_chapters

            if enabled.any?
              enabled.map { File.join(Common::CONTENTS_DIR, "#{it}.md") }
            else
              glob_all_chapters
            end
          end

          # 全章ファイルを列挙する（カタログがない場合のフォールバック）
          def glob_all_chapters
            Dir.glob(File.join(Common::CONTENTS_DIR, '*.md'))
               .reject { it.include?('_') }
          end

          # ターゲットからパスを解決する（明示指定時はカタログ外も許可）
          def resolve_target_paths
            normalized = Common.normalize_tokens(targets)
            normalized.flat_map { find_chapter_files(it) }
          end

          # 章番号からファイルを検索する
          def find_chapter_files(token)
            pattern = File.join(Common::CONTENTS_DIR, "#{token}*.md")
            Dir.glob(pattern)
          end

          # ================================================================
          # フィルタリング
          # ================================================================

          # オプションに応じてフィルタリングする
          def analysis_visible?(analysis)
            return true if options[:all]
            if options[:warn]
              chapter_num = analysis.chapter.chapter_num
              return false if warning_checker.excluded_chapter?(chapter_num)

              return warning_checker.has_warning?(chapter_num, analysis.chapter.chars, analysis.chapter.sections)
            end

            true
          end

          # 節を表示するか判定する
          def show_sections?
            return true if options[:all]
            return true if options[:warn]

            targets.any?
          end

          def output_final_summary(basic, vocab, readability)
            puts ''
            puts formatter.format_basic_info(basic)
            puts ''
            puts formatter.format_sentence_structure(basic)
            puts ''
            puts formatter.format_detailed_analysis(vocab, readability)
          end

          # 対象なしの警告
          def warn_no_targets
            Common.log_warn('対象となる Markdown ファイルが見つかりません。')
            1
          end

          # ================================================================
          # 構造化出力（JSON/YAML）
          # ================================================================

          # 構造化フォーマットで出力する（一括処理）
          def output_structured(format, files)
            analyses = parallel_runner.parallel_map(files) { analyze_chapter_with_cache(it) }.compact
            stats = analyses.map { analysis_to_stat_hash(it) }
            totals_basic = aggregate_basic_stats(analyses.map(&:basic))
            totals = basic_stats_to_structured_hash(totals_basic)

            case format
            when :json
              require 'json'
              puts JSON.pretty_generate({ 'stats' => stats, 'totals' => totals })
            when :yaml
              require 'yaml'
              puts({ 'stats' => stats, 'totals' => totals }.to_yaml)
            end
            0
          end

          def analysis_to_stat_hash(analysis)
            basic = analysis.basic
            chapter = analysis.chapter

            basic_stats_to_structured_hash(basic).merge('path' => chapter.path)
          end

          def basic_stats_to_structured_hash(basic)
            {
              'lines' => basic.lines,
              'chars' => basic.chars,
              'chars_without_newline' => basic.chars_no_newline,
              'sentences' => basic.sentences,
              'avg_sentence_chars' => basic.avg_sentence_len,
              'commas' => basic.commas,
              'clauses' => basic.clauses,
              'avg_clause_chars' => basic.avg_clause_len
            }
          end
        end
      end
    end
  end
end
