# frozen_string_literal: true

require 'etc'

module Vivlio
  module Starter
    module CLI
      module Build
        # ------------------------------------------------
        # SectionBuilder: セクションHTML生成モジュール
        # ------------------------------------------------
        # 本文、付録、後書きのHTML生成を担当する。
        # 並列処理、キャッシュ管理、章順序の管理を含む。
        # ------------------------------------------------
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

            sort_key = lambda do |bn|
              number = Common.get_chapter_number(bn)
              number ? [number.to_i, bn] : [Float::INFINITY, bn]
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

          # 付録を奇数（右）開始にするための空白HTMLを生成
          def ensure_appendices_guard_html(base_dir = '.')
            path = File.join(base_dir, '90-appendices-guard.html')
            width, height = Build::Utilities.page_size_strings_from_config
            html = <<~HTML
              <!doctype html>
              <html>
              <head>
                <meta charset="utf-8">
                <title>Appendices Guard</title>
                <style>
                  @page {
                    size: #{width} #{height};
                  }
                </style>
              </head>
              <body></body>
              </html>
            HTML
            File.write(path, html, encoding: 'utf-8')
            path
          end

          # 章ごとの処理に計時を付与して実行
          def time_step_for_chapter(chapter, step)
            label = "#{chapter} / #{step}"
            start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            elapsed = nil
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
          def ensure_chapter_html_up_to_date!(basename, extra_sources: [])
            html_path = File.join('.', "#{basename}.html")
            md_path = File.join(Common::CONTENTS_DIR, "#{basename}.md")
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
            %w[pre_process convert post_process].each do |task|
              Vivlio::Starter::ThorCLI.start([task, basename])
            end
          end

          # Step 4: セクション（前書き/本文/付録/後書き）をビルド（HTML生成）
          # catalog.yml で指定された章のみを対象とする
          def build_sections_html!(keep = nil)
            Common.log_action('[Step 4] セクション（前書き/本文/付録/後書き）をビルドします…')

            # catalog.yml から対象章を取得（keep パラメータをそのまま使用）
            chapter_targets = if keep&.any?
                                Array(keep).map { |s| File.basename(s.to_s, '.md') }.sort
                              else
                                # keep が空の場合は contents/ 内の全章をビルド
                                Dir[File.join(Common::CONTENTS_DIR, '*.md')]
                                  .map { |p| File.basename(p, '.md') }
                                  .reject { |bn| bn.start_with?('_') } # 特殊ページは除外
                                  .sort
                              end

            if chapter_targets.empty?
              Common.log_warn('[Step 4] 章が見つかりません。Step 4 をスキップします。')
              return
            end

            Common.log_info("[Step 4] 対象: #{chapter_targets.join(', ')}")

            # 並列度（未設定時は min(4, n_cores) を既定に）
            concurrency = (ENV['VIVLIO_BUILD_CONCURRENCY'] || '').to_i
            if concurrency <= 0
              n_cores = Etc.respond_to?(:nprocessors) ? Etc.nprocessors : 2
              concurrency = [n_cores, 4].min
              concurrency = 1 if concurrency <= 0
              Common.log_info("[Step 4] 並列度を自動設定: concurrency=#{concurrency} (cores=#{n_cores})")
            end

            if concurrency == 1
              chapter_targets.each do |target|
                %w[pre_process convert post_process].each do |tn|
                  time_step_for_chapter(target, tn) do
                    Vivlio::Starter::ThorCLI.start([tn, target])
                  end
                end
              end
              return
            end

            Common.log_info("[Step 4] 並列実行を開始します（concurrency=#{concurrency}、対象=#{chapter_targets.size}）")
            parallel_each(chapter_targets, concurrency: concurrency) do |target|
              %w[pre_process convert post_process].each do |tn|
                time_step_for_chapter(target, tn) do
                  Vivlio::Starter::ThorCLI.start([tn, target])
                end
              end
            end
          end
        end
      end
    end
  end
end
