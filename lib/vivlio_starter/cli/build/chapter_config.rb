# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/chapter_config.rb
# ================================================================
# 責務:
#   章番号のパース・展開とファイル名の正規化を行う。
#
# 章番号形式:
#   - 単一: "11" → [11]
#   - 範囲: "11-13" → [11, 12, 13]
#   - カンマ区切り: "11, 13, 15" → [11, 13, 15]
#   - 混合: "11-13, 91" → [11, 12, 13, 91]
#
# ファイル解決:
#   - 章番号からベース名を検索（例: 11 → 11-install.md）
#   - 指定レンジ内の HTML ファイルを収集
#
# 依存:
#   - Common: ディレクトリ定数・ファイル検索
# ================================================================

module VivlioStarter
  module CLI
    module Build
      # 章番号パース・ファイル解決モジュール
      module ChapterConfig
        module_function

        # 範囲指定文字列（"02-12"）を章番号配列に展開
        # 例: "02-12" → [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
        def expand_chapter_range(range_str)
          return [] unless range_str.is_a?(String)

          match = range_str.strip.match(/\A(\d+)-(\d+)\z/)
          return [] unless match

          start_num = match[1].to_i
          end_num = match[2].to_i
          return [] if start_num > end_num

          (start_num..end_num).to_a
        rescue StandardError
          []
        end

        # カンマ区切り文字列から章番号配列を抽出（範囲展開含む）
        # 例: "02, 11-13, 91" → [2, 11, 12, 13, 91]
        def parse_chapter_numbers_from_string(str)
          return [] unless str.is_a?(String)

          parts = str.split(',').map(&:strip).reject(&:empty?)
          numbers = []

          parts.each do |part|
            if part.match?(/\A\d+-\d+\z/)
              # 範囲指定
              numbers.concat(expand_chapter_range(part))
            elsif part.match?(/\A\d+\z/)
              # 単一番号
              numbers << part.to_i
            else
              # 数字でない → ファイル名指定の可能性
              raise ArgumentError, "混在形式は非対応です: '#{part}' は番号指定として無効です。"
            end
          end

          numbers.uniq.sort
        rescue ArgumentError => e
          raise e
        rescue StandardError => e
          Common.log_error("章番号の解析に失敗しました: #{e.message}")
          []
        end

        # 配列が全て整数（または整数文字列）かチェック
        def all_integers?(arr)
          return false unless arr.is_a?(Array)

          arr.all? do |item|
            item.to_s.strip.match?(/\A\d+\z/)
          end
        end

        # catalog.yml から対象とする章ファイル名のリストを返す
        #
        # catalog.yml の PREFACE / CHAPTERS / APPENDICES / POSTFACE から
        # basename を収集し、存在するファイルのみを返す。
        #
        # 返り値: ファイル名配列（例: ["00-preface.md", "11-install.md", ...]）
        #         または空配列
        def configured_chapters
          basenames = CatalogLoader.load_existing_basenames
          Common.log_info("[Catalog] loaded basenames=#{basenames.inspect}")

          # ファイル名配列に変換（.md 付き）
          basenames.map { |bn| "#{bn}.md" }
        rescue StandardError => e
          Common.log_error("catalog.yml の読み込みに失敗しました: #{e.message}")
          raise
        end

        # ディレクトリ内の *.html から、章番号レンジと keep_numbers でフィルタ
        # 注: アンダースコア始まりのファイルは \A(\d+)- パターンにマッチしないため自動的に除外される
        def htmls_for_range(base_dir, range, keep_numbers = nil)
          Dir.glob(File.join(base_dir, '*.html')).select do |path|
            bn = File.basename(path, '.html')
            n = bn[/\A(\d+)-/, 1]&.to_i
            n && range.include?(n) && (keep_numbers.nil? || keep_numbers.include?(n))
          end.sort
        end
      end
    end
  end
end
