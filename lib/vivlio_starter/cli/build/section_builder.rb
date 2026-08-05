# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/section_builder.rb
# ================================================================
# 責務:
#   本文・付録・後書きの HTML を生成する。
#   並列処理でビルド時間を短縮する。
#
# 処理内容:
#   - contents/*.md → *.html の変換
#   - 前処理（frontmatter）→ 変換（VFM）→ 後処理（heading等）
#   - 並列処理（CPU コア数に応じたスレッド数）
#
# 章構成:
#   - PREFACE (00): 前書き
#   - MAIN (01-89): 本文
#   - APPENDICES (90-98): 付録
#   - POSTFACE (99): 後書き
#
# 依存:
#   - PreProcessCommands: Markdown 前処理
#   - ConvertCommands: VFM 変換
#   - PostProcessCommands: HTML 後処理
# ================================================================

require 'etc'

module VivlioStarter
  module CLI
    module Build
      # セクション HTML 生成モジュール
      module SectionBuilder
        # 章レンジ（定数）- 新仕様に合わせて更新
        PREFACE_RANGE  = (0..0)
        MAIN_RANGE     = (1..89)
        APPX_RANGE     = (90..98)
        POSTFACE_RANGE = (99..99)

        module_function

        # 章順序を取得（ベース名配列から）
        # 中間 HTML はワークスペースの html/ に置かれる（P4 §3.4-1）
        def chapter_order_from(basenames, base_dir = Common::BUILD_HTML_DIR)
          basenames = Array(basenames).map { |bn| bn.to_s.strip }.reject(&:empty?).uniq
          return [] if basenames.empty?

          resolver = TokenResolver::Resolver.new
          sort_key = lambda do |bn|
            entry = resolver.resolve_file(bn)
            entry.number ? [entry.number.to_i, bn] : [Float::INFINITY, bn]
          end

          html_basenames = Dir.glob(File.join(base_dir, '*.html'))
                              .map { |path| File.basename(path, '.html') }
                              .uniq
                              .sort_by { |bn| sort_key.call(bn) }

          ordered = html_basenames.select { |bn| basenames.include?(bn) }

          remaining = basenames - ordered
          remaining_sorted = remaining.sort_by { |bn| sort_key.call(bn) }

          ordered + remaining_sorted
        end


        # 簡易スレッドプールで並列実行
        def parallel_each(items, concurrency: 1, &)
          list = Array(items)
          effective_concurrency = concurrency.to_i
          effective_concurrency = 1 if effective_concurrency <= 0
          Common.log_info("[parallel_each] concurrency=#{effective_concurrency}")
          return list.each(&) if effective_concurrency <= 1

          q = Queue.new
          list.each { |it| q << it }
          sentinel = Object.new
          effective_concurrency.times { q << sentinel }
          workers = Array.new(effective_concurrency) do
            Thread.new do
              loop do
                it = q.pop
                break if it.equal?(sentinel)

                yield(it)
              end
            end
          end
          workers.each(&:join)
        end

        # 単一章の前処理
        def preprocess_single_chapter!(basename)
          PreProcessCommands.execute_pre_process({}, [basename])
        end

        # 単一章の変換（HTML生成）
        def convert_single_chapter!(basename)
          ConvertCommands.execute_convert({}, [basename])
          PostProcessCommands.execute_post_process({}, [basename])
        end

        # セクション（前書き/本文/付録/後書き）の前処理を一括実行
        # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil] Entry 配列または basename 配列
        def preprocess_sections!(entries_or_keep = nil)
          Common.log_action('[Step 3] セクションの前処理（Markdown 修正）を実行します…')
          targets = resolve_targets(entries_or_keep)
          return if targets.empty?

          concurrency = determine_concurrency
          if concurrency == 1
            targets.each { |target| preprocess_single_chapter!(target) }
          else
            parallel_each(targets, concurrency: concurrency) { |target| preprocess_single_chapter!(target) }
          end

          # 全章の前処理完了後に1回だけクロスリファレンス処理を実行する
          PreProcessCommands.execute_cross_references(targets)
        end

        # セクション（前書き/本文/付録/後書き）の変換を一括実行
        # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil] Entry 配列または basename 配列
        def convert_sections_html!(entries_or_keep = nil)
          Common.log_action('[Step 4b] セクションの変換（HTML 生成）を実行します…')
          targets = resolve_targets(entries_or_keep)
          return if targets.empty?

          # 並列処理前に章の表示順を確定させる。
          # HeadingProcessor の @main_chapter_order はモジュールレベルのキャッシュなので、
          # 並列スレッドが不完全な HTML リストでキャッシュを作る前に正しい順序を注入する。
          main_tokens = targets.select { |t| t.match?(/\A\d{2}-/) && t[/\A(\d{2})/, 1].to_i.between?(1, 89) }
          PostProcessCommands::HeadingProcessor.chapter_tokens_override = main_tokens unless main_tokens.empty?

          concurrency = determine_concurrency
          if concurrency == 1
            targets.each { |target| convert_single_chapter!(target) }
          else
            parallel_each(targets, concurrency: concurrency) { |target| convert_single_chapter!(target) }
          end
        end

        # 対象章を解決（Entry 配列または basename 配列から basename 配列を返す）
        # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil]
        # @return [Array<String>] basename 配列
        def resolve_targets(entries_or_keep = nil)
          raw = Array(entries_or_keep).compact
          if raw.any?
            # Entry オブジェクトかどうかを判定
            if raw.first.respond_to?(:basename)
              raw.map(&:basename).sort
            else
              raw.map { |s| File.basename(s.to_s, '.md') }.sort
            end
          else
            Dir[File.join(Common::CONTENTS_DIR, '*.md')]
              .map { |p| File.basename(p, '.md') }
              .reject { |bn| bn.start_with?('_') }
              .sort
          end
        end

        # 並列度を決定
        def determine_concurrency
          concurrency = (ENV['VIVLIO_BUILD_CONCURRENCY'] || '').to_i
          if concurrency <= 0
            n_cores = Etc.respond_to?(:nprocessors) ? Etc.nprocessors : 2
            concurrency = [n_cores, 4].min
            concurrency = 1 if concurrency <= 0
          end
          concurrency
        end

      end
    end
  end
end
