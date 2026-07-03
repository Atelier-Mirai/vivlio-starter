# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/metrics/runner.rb
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
require_relative 'cache'
require_relative 'parallel_runner'
require_relative 'consistency'
require_relative 'sentence_collector'
require_relative 'sentence_endings'
require_relative 'content_words'
require_relative 'kanji_levels'
require_relative '../token_resolver'

module VivlioStarter
  module CLI
    module Metrics
      # metrics コマンドの実行を制御する
      class Runner
        ChapterAnalysis = Data.define(:chapter, :basic, :vocab, :readability)
        PlaceholderChapter = Data.define(:path, :title, :chapter_num, :chars)

        # キャッシュの構造バージョン。読解難度の特徴量導入や MATTR 追加など
        # 互換性を破る変更時にインクリメントし、旧バージョンのキャッシュを無効化する。
        CACHE_SCHEMA_VERSION = 4

        # 「見直したい長い文」として挙げる下限文字数と最大件数。
        LONG_SENTENCE_MIN = 80
        LONG_SENTENCE_TOP = 5

        # 頻出内容語ランキングの表示件数。
        CONTENT_WORD_TOP = 15

        def initialize(targets, options = {})
          @targets = Array(targets)
          @options = options
          @config = ConfigLoader.new
          @warning_checker = WarningChecker.new(@config)
          @formatter = Formatter.new(@config)
          @chapter_parser = ChapterParser.new(@warning_checker)
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
          output_chapter_count(all_analyses)
          output_final_summary(final_basic, final_vocab, final_readability)

          # --all のときだけ、推敲用の参考資料（A–G）を続けて出力する。
          output_advice(all_analyses) if options[:all]

          0
        end

        private

        attr_reader :targets, :options, :config, :warning_checker, :formatter,
                    :chapter_parser, :cache, :parallel_runner,
                    :analysis_buffer, :analysis_mutex

        def aggregate_summary_from_analyses(analyses)
          basics = analyses.map(&:basic)
          vocabularies = analyses.map(&:vocab)

          basic = aggregate_basic_stats(basics)
          vocab = aggregate_vocabulary_stats(vocabularies)
          readability = aggregate_readability(analyses)

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
          hira_char_count = vocabularies.sum(&:hira_char_count)
          kata_char_count = vocabularies.sum(&:kata_char_count)
          alpha_char_count = vocabularies.sum(&:alpha_char_count)

          merged_tokens = vocabularies.each_with_object(Hash.new(0)) do |vocab, acc|
            vocab.tokens_map.each { |token, count| acc[token] += count }
          end

          unique_tokens = merged_tokens.size
          avg_word_length = total_tokens.positive? ? total_word_length.to_f / total_tokens : 0.0
          ttr = total_tokens.positive? ? unique_tokens.to_f / total_tokens : 0.0
          kanji_ratio = total_char_count.positive? ? (kanji_char_count.to_f / total_char_count) * 100 : 0.0
          # MATTR は文書長に頑健なので、全体は章ごと MATTR の語数加重平均で代表させる
          # （頻度マップからは語順を復元できず全体を再走査できないため）。
          mattr = total_tokens.positive? ? vocabularies.sum { it.mattr * it.total_tokens } / total_tokens : 0.0

          Metrics::VocabularyStats.new(
            kanji_ratio:,
            avg_word_length:,
            ttr:,
            mattr:,
            total_tokens:,
            unique_tokens:,
            kanji_char_count:,
            hira_char_count:,
            kata_char_count:,
            alpha_char_count:,
            total_char_count:,
            total_word_length:,
            tokens_map: merged_tokens
          )
        end

        # 章ごとの特徴量を合算してから全体 RS を一度だけ算出する
        # （各 l* は平均値なので、章 RS の平均では全体 RS にならない）。
        def aggregate_readability(analyses)
          features = Readability.aggregate(analyses.map { it.readability.features })
          build_readability(features)
        end

        # 特徴量から ReadabilityScore（スコア＋ラベル）を構築する。
        def build_readability(features)
          score = Readability.score(features)
          label = Readability.label(score, config.readability_thresholds)
          Metrics::ReadabilityScore.new(score:, label:, features:)
        end

        # ================================================================
        # Phase 2: 章別解析（キャッシュ + 並列処理）
        # ================================================================

        # 章を解析し進捗を表示する
        def analyze_chapters_with_progress(files)
          results = []
          mutex = Mutex.new

          parallel_runner.parallel_each_with_progress(files, on_complete: lambda { |_file, chapter|
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
            mattr: 0.0,
            total_tokens: 0,
            unique_tokens: 0,
            kanji_char_count: 0,
            hira_char_count: 0,
            kata_char_count: 0,
            alpha_char_count: 0,
            total_char_count: 0,
            total_word_length: 0,
            tokens_map: {}
          )
          readability = build_readability(Metrics::ReadabilityFeatures.zero)
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
          analyzer = Analyzer.new(content, readability: config.readability_thresholds,
                                           mattr_window: config.mattr_window)
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
            'schema_version' => CACHE_SCHEMA_VERSION,
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
            'mattr' => vocab.mattr,
            'total_tokens' => vocab.total_tokens,
            'unique_tokens' => vocab.unique_tokens,
            'kanji_char_count' => vocab.kanji_char_count,
            'hira_char_count' => vocab.hira_char_count,
            'kata_char_count' => vocab.kata_char_count,
            'alpha_char_count' => vocab.alpha_char_count,
            'total_char_count' => vocab.total_char_count,
            'total_word_length' => vocab.total_word_length,
            'tokens_map' => vocab.tokens_map.to_h
          }
        end

        def readability_to_hash(readability)
          {
            'score' => readability.score,
            'label' => readability.label,
            'features' => readability.features.to_h.transform_keys(&:to_s)
          }
        end

        def rebuild_analysis_from_cache(data)
          return nil unless data
          return nil unless data['schema_version'] == CACHE_SCHEMA_VERSION

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
            mattr: data['mattr'] || 0.0,
            total_tokens: data['total_tokens'],
            unique_tokens: data['unique_tokens'],
            kanji_char_count: data['kanji_char_count'],
            hira_char_count: data['hira_char_count'] || 0,
            kata_char_count: data['kata_char_count'] || 0,
            alpha_char_count: data['alpha_char_count'] || 0,
            total_char_count: data['total_char_count'],
            total_word_length: data['total_word_length'],
            tokens_map: data['tokens_map'] || {}
          )
        end

        def rebuild_readability(data)
          return nil unless data

          features = rebuild_readability_features(data['features'])
          Metrics::ReadabilityScore.new(score: data['score'], label: data['label'], features:)
        end

        # キャッシュの特徴量ハッシュから ReadabilityFeatures を復元する。
        def rebuild_readability_features(data)
          return Metrics::ReadabilityFeatures.zero unless data.is_a?(Hash)

          fields = Metrics::ReadabilityFeatures.members.to_h { [it, data[it.to_s] || 0] }
          Metrics::ReadabilityFeatures.new(**fields)
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

        # catalog.yml から有効章を解決する（パーサは TokenResolver に一本化。
        # 仕様: docs/specs/catalog-parser-unification-spec.md §3.3）。
        # metrics は統計ツールのため catalog 破損でもハード停止せず、書ける範囲で答える
        # （catalog 不在/空 → 全 Markdown へフォールバック、破損 → warn + フォールバック）。
        def resolve_from_catalog
          entries = TokenResolver::Resolver.new.resolve
          return glob_all_chapters if entries.empty?

          entries.select(&:exists?).map(&:path)
        rescue StandardError => e
          Common.log_warn("catalog.yml の読み込みに失敗したため、全 Markdown ファイルを対象にします: #{e.message}")
          glob_all_chapters
        end

        # 全章ファイルを列挙する（カタログがない場合のフォールバック）
        def glob_all_chapters
          Dir.glob(File.join(Common::CONTENTS_DIR, '*.md'))
             .reject { it.include?('_') }
        end

        # ターゲットからパスを解決する（明示指定時はカタログ外も許可）
        def resolve_target_paths
          resolver = TokenResolver::Resolver.new
          entries = resolver.resolve(targets)
          entries.select(&:exists?).map(&:path)
        end

        # ================================================================
        # フィルタリング
        # ================================================================

        # オプションに応じてフィルタリングする（--warn 時のみ警告章に絞る）
        def analysis_visible?(analysis)
          if options[:warn]
            chapter_num = analysis.chapter.chapter_num
            return false if warning_checker.excluded_chapter?(chapter_num)

            return warning_checker.has_warning?(chapter_num, analysis.chapter.chars, analysis.chapter.sections)
          end

          true
        end

        # 節まで展開するか判定する（--sections / --warn、または章を明示指定したとき）
        def show_sections?
          return true if options[:sections]
          return true if options[:warn]

          targets.any?
        end

        # 章別リストの直後に「合計◯章／平均◯文字」を出力する。
        def output_chapter_count(analyses)
          total_chars = analyses.sum { it.chapter.chars }
          puts ''
          puts formatter.format_chapter_count_summary(analyses.size, total_chars)
        end

        def output_final_summary(basic, vocab, readability)
          puts ''
          puts formatter.format_basic_info(basic)
          puts ''
          puts formatter.format_sentence_structure(basic)
          puts ''
          puts formatter.format_detailed_analysis(vocab, readability)
        end

        # 推敲用の参考資料（A–G）をまとめて出力する（--all / 構造化出力で使用）。
        def output_advice(analyses)
          output_consistency(analyses)

          body_sentences = collect_body_sentences(analyses)
          output_long_sentences(body_sentences)
          output_sentence_rhythm(body_sentences)
          output_content_words(analyses)
          output_kanji_levels(body_sentences)
        end

        # 章間のばらつき（漢字比率・平均文長）を表示する。
        def output_consistency(analyses)
          metrics = build_consistency_metrics(analyses)
          return if metrics.empty?

          puts ''
          puts formatter.format_consistency(metrics)
        end

        # 章間のばらつき指標を組み立てる。除外章と本文のない章は比較対象から外し、
        # 2 章以上そろったときだけ算出する（そろわなければ空配列）。
        def build_consistency_metrics(analyses)
          body = analyses.reject { excluded_or_empty?(it) }
          return [] if body.size < 2

          [
            Consistency.build(metric_label: '漢字比率', unit: '%', high_label: '高め', low_label: '低め',
                              entries: body.map { [chapter_num_label(it.chapter), it.vocab.kanji_ratio] }),
            Consistency.build(metric_label: '平均文長', unit: '字', high_label: '長め', low_label: '短め',
                              entries: body.map { [chapter_num_label(it.chapter), it.basic.avg_sentence_len] })
          ]
        end

        def excluded_or_empty?(analysis)
          warning_checker.excluded_chapter?(analysis.chapter.chapter_num) || analysis.basic.sentences.zero?
        end

        def chapter_num_label(chapter) = format('第%02d章', chapter.chapter_num)

        # 本文の章（除外章・本文なし章を除く）から、位置つきの文を順序どおり集める。
        def collect_body_sentences(analyses)
          collector = SentenceCollector.new
          analyses.reject { excluded_or_empty?(it) }
                  .flat_map { collect_chapter_sentences(collector, it) }
        end

        def collect_chapter_sentences(collector, analysis)
          collector.collect(File.read(analysis.chapter.path, encoding: 'UTF-8'), analysis.chapter.chapter_num)
        rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError, Errno::ENOENT
          []
        end

        # 本文中で特に長い文（下限以上）の上位を、位置つきで表示する。
        def output_long_sentences(sentences)
          longest = select_long_sentences(sentences)
          return if longest.empty?

          puts ''
          puts formatter.format_long_sentences(longest)
        end

        # 下限以上の長文を、長い順に上位まで返す。
        def select_long_sentences(sentences)
          sentences.select { it.length >= LONG_SENTENCE_MIN }.max_by(LONG_SENTENCE_TOP, &:length)
        end

        # 文末表現の内訳と、同一文末が連続する箇所を表示する。
        def output_sentence_rhythm(sentences)
          return if sentences.empty?

          distribution = SentenceEndings.distribution(sentences)
          puts ''
          puts formatter.format_sentence_rhythm(distribution, monotone_runs_for(sentences))
        end

        # 同一文末の連続を、多い順（最悪箇所が先頭）に並べる。同数なら出現順。
        def monotone_runs_for(sentences)
          SentenceEndings.monotone_runs(sentences).sort_by { [-it.count, it.chapter_num, it.line] }
        end

        # 頻出する内容語を品詞ラベルつきで表示する（MeCab 前提。無ければ非表示）。
        def output_content_words(analyses)
          ranked = rank_content_words(analyses)
          return if ranked.empty?

          puts ''
          puts formatter.format_content_words(ranked)
        end

        # 本文の章から内容語を集め、頻度上位を返す。
        def rank_content_words(analyses)
          words = analyses.reject { excluded_or_empty?(it) }.flat_map { content_words_for(it) }
          ContentWords.rank(words, limit: CONTENT_WORD_TOP)
        end

        def content_words_for(analysis)
          Analyzer.new(File.read(analysis.chapter.path, encoding: 'UTF-8')).content_words
        rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError, Errno::ENOENT
          []
        end

        # 本文の漢字をレベル分けし、ルビ候補（中学以上・一般・専門）を表示する。
        def output_kanji_levels(sentences)
          report = KanjiLevels.build_report(sentences)
          return unless report

          puts ''
          puts formatter.format_kanji_levels(report)
        end

        # 対象なしの警告
        def warn_no_targets
          Common.log_warn('対象となる Markdown ファイルが見つかりません。')
          1
        end

        # ================================================================
        # 構造化出力（JSON/YAML）
        # ================================================================

        # 構造化フォーマットで出力する（一括処理）。画面出力と同じ内容を、
        # 章別統計（stats）・全体集計（totals）・推敲用の参考資料（advice）で構成する。
        def output_structured(format, files)
          analyses = parallel_runner.parallel_map(files) { analyze_chapter_with_cache(it) }.compact
          payload = {
            'stats' => analyses.map { analysis_to_stat_hash(it) },
            'totals' => structured_totals(analyses),
            'advice' => structured_advice(analyses)
          }

          case format
          when :json
            require 'json'
            puts JSON.pretty_generate(payload)
          when :yaml
            require 'yaml'
            puts payload.to_yaml
          end
          0
        end

        # 全体集計（基本統計＋語彙＋読解難度）を構造化ハッシュにまとめる。
        def structured_totals(analyses)
          basic = aggregate_basic_stats(analyses.map(&:basic))
          vocab = aggregate_vocabulary_stats(analyses.map(&:vocab))
          readability = aggregate_readability(analyses)

          basic_stats_to_structured_hash(basic).merge(
            'vocabulary' => vocabulary_to_structured_hash(vocab),
            'readability' => { 'score' => readability.score.round(2), 'label' => readability.label }
          )
        end

        def vocabulary_to_structured_hash(vocab)
          {
            'kanji_ratio' => vocab.kanji_ratio.round(2),
            'avg_word_length' => vocab.avg_word_length.round(2),
            'mattr' => vocab.mattr.round(3),
            'ttr' => vocab.ttr.round(3),
            'total_tokens' => vocab.total_tokens,
            'unique_tokens' => vocab.unique_tokens,
            'kanji_char_count' => vocab.kanji_char_count,
            'hira_char_count' => vocab.hira_char_count,
            'kata_char_count' => vocab.kata_char_count,
            'alpha_char_count' => vocab.alpha_char_count,
            'total_char_count' => vocab.total_char_count
          }
        end

        # 推敲用の参考資料（A–G）を構造化ハッシュにまとめる。各項目は対象が
        # なければ空配列 / nil を返し、消費側が扱いやすいよう常にキーを備える。
        def structured_advice(analyses)
          body_sentences = collect_body_sentences(analyses)
          {
            'consistency' => build_consistency_metrics(analyses).map { consistency_to_structured_hash(it) },
            'long_sentences' => select_long_sentences(body_sentences).map { located_sentence_to_structured_hash(it) },
            'sentence_rhythm' => sentence_rhythm_to_structured_hash(body_sentences),
            'content_words' => rank_content_words(analyses).map { { 'word' => it.word, 'pos' => it.pos, 'count' => it.count } },
            'kanji_levels' => kanji_levels_to_structured_hash(body_sentences)
          }
        end

        def consistency_to_structured_hash(metric)
          {
            'label' => metric.label,
            'unit' => metric.unit,
            'mean' => metric.mean.round(2),
            'stdev' => metric.stdev.round(2),
            'high' => metric.high.map { |chapter, value| { 'chapter' => chapter, 'value' => value.round(2) } },
            'low' => metric.low.map { |chapter, value| { 'chapter' => chapter, 'value' => value.round(2) } }
          }
        end

        def located_sentence_to_structured_hash(sentence)
          {
            'chapter_num' => sentence.chapter_num,
            'line' => sentence.line,
            'length' => sentence.length,
            'text' => sentence.text
          }
        end

        def sentence_rhythm_to_structured_hash(sentences)
          return { 'distribution' => {}, 'monotone_runs' => [] } if sentences.empty?

          {
            'distribution' => SentenceEndings.distribution(sentences),
            'monotone_runs' => monotone_runs_for(sentences).map do |run|
              { 'chapter_num' => run.chapter_num, 'line' => run.line, 'label' => run.label, 'count' => run.count }
            end
          }
        end

        def kanji_levels_to_structured_hash(sentences)
          report = KanjiLevels.build_report(sentences)
          return nil unless report

          {
            'ratios' => report.ratios.map { |label, percent| { 'label' => label, 'percent' => percent } },
            'lists' => report.lists.transform_keys(&:to_s).transform_values do |list|
              list.map { |char, count| { 'char' => char, 'count' => count } }
            end,
            'locations' => report.locations.map do |char, places|
              { 'char' => char, 'places' => places.map { |chapter_num, line| { 'chapter_num' => chapter_num, 'line' => line } } }
            end
          }
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
