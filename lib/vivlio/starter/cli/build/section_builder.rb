# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/build/section_builder.rb
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

module Vivlio
  module Starter
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
          def chapter_order_from(basenames, base_dir = '.')
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

          # 章ごとの処理に計時を付与して実行
          def time_step_for_chapter(chapter, step)
            label = "#{chapter} / #{step}"
            start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            begin
              Common.with_current_step_label(label) do
                yield if block_given?
              end
            ensure
              finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              elapsed = finish - start
              Common.log_action("[Timer] #{label} : #{format('%.2f', elapsed)}s")
            end
            elapsed
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

          # 章HTMLの最新性をチェックし、必要なら再生成
          # _titlepage/_legalpage/_colophon/_part{N} は .cache/vs/ から参照する
          def ensure_chapter_html_up_to_date!(basename, extra_sources: [])
            html_path = File.join('.', "#{basename}.html")
            cached = TokenResolver::Resolver::CACHED_SYSTEM_FILES.include?(basename) || basename.match?(/\A_part\d+\z/)
            dir = cached ? Common::CACHE_DIR : Common::CONTENTS_DIR
            md_path = File.join(dir, "#{basename}.md")
            sources = [md_path, *Array(extra_sources)].compact

            needs_regeneration = !File.exist?(html_path)
            unless needs_regeneration
              html_mtime = begin
                File.mtime(html_path)
              rescue StandardError
                Time.at(0)
              end
              latest_source_mtime = sources.select { |src| File.exist?(src) }
                                           .map do |src|
                File.mtime(src)
              rescue StandardError
                Time.at(0)
              end
                                           .max
              needs_regeneration = latest_source_mtime && latest_source_mtime > html_mtime
            end

            return unless needs_regeneration

            Common.log_info("[HTML] 再生成します: #{basename}.html")
            preprocess_single_chapter!(basename)
            convert_single_chapter!(basename)
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

          # Step 4: セクション（前書き/本文/付録/後書き）をビルド（HTML生成）
          # 注: このメソッドは後方互換性のため維持するが、UnifiedBuildPipeline では
          #     preprocess_sections! と convert_sections_html! に分割して呼び出すことを推奨
          def build_sections_html!(keep = nil)
            preprocess_sections!(keep)
            convert_sections_html!(keep)
          end
        end
      end
    end
  end
end
