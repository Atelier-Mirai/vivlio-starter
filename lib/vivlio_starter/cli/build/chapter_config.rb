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

        # 章番号の重複をチェック（同一番号で複数ファイルが存在する場合）
        # 返り値: { 章番号 => [ファイル名配列] } の Hash（重複がある番号のみ）
        def detect_duplicate_chapter_numbers
          files = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md'))
          number_to_files = Hash.new { |h, k| h[k] = [] }
          resolver = TokenResolver::Resolver.new

          files.each do |file|
            basename = File.basename(file, '.md')
            entry = resolver.resolve_file(basename)
            next unless entry.number

            number_to_files[entry.number.to_i] << basename
          end

          # 重複があるもののみ返す
          number_to_files.select { |_num, files_list| files_list.size > 1 }
        end

        # 配列が全て整数（または整数文字列）かチェック
        def all_integers?(arr)
          return false unless arr.is_a?(Array)

          arr.all? do |item|
            item.to_s.strip.match?(/\A\d+\z/)
          end
        end

        # contents ディレクトリ内の全 .md ファイルのベース名を取得
        # 返り値: ソート済みのファイル名配列（例: ["00-preface.md", "11-install.md", ...]）
        def all_chapter_files
          Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { |f| File.basename(f) }.sort
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

        # 章番号の重複を検証し、重複があればエラーを発生させる
        def validate_no_duplicate_chapter_numbers!
          duplicates = detect_duplicate_chapter_numbers
          return unless duplicates.any?

          error_msg = "同一章番号で複数のファイルが存在します。ファイル名を見直してください:\n"
          duplicates.each do |num, files|
            error_msg += "  章番号 #{num}: #{files.join(', ')}\n"
          end
          Common.log_error(error_msg)
          raise StandardError, error_msg
        end

        # 章番号配列をファイル名配列に変換
        # 例: [0, 11, 12] → ["00-preface.md", "11-install.md", "12-tutorial.md"]
        # 存在しないファイルはスキップ
        def convert_numbers_to_filenames(numbers)
          return [] unless numbers.is_a?(Array)

          files = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md'))
          number_to_file = {}
          resolver = TokenResolver::Resolver.new

          files.each do |file|
            basename = File.basename(file, '.md')
            entry = resolver.resolve_file(basename)
            next unless entry.number

            number_to_file[entry.number.to_i] = "#{basename}.md"
          end

          result = numbers.map { |n| number_to_file[n] }.compact
          Common.log_info("[Subset] converted to filenames=#{result.inspect}")
          result
        end

        # ベース名配列を章番号レンジ＋keepでフィルタ
        # 注: _toc.html などアンダースコア始まりのファイルは \A(\d+)- パターンにマッチしないため自動的に除外される
        #
        # @param basenames [Array<String>] 拡張子なしのベース名配列
        # @param range [Range] 章番号レンジ（例: 1..89, 90..98）
        # @param keep_numbers [Array<Integer>, nil] 許可する章番号配列
        # @return [Array<String>] フィルタ済みベース名配列
        def filter_basenames_by_range(basenames, range, keep_numbers = nil)
          keep_set = keep_numbers.respond_to?(:include?) ? keep_numbers : nil
          Array(basenames)
            .map(&:to_s)
            .grep(/\A(\d+)-/)
            .select do |bn|
              n = bn[/\A(\d+)-/, 1].to_i
              in_range = range.include?(n)
              allowed  = keep_set ? keep_set.include?(n) : true
              in_range && allowed
            end
            .uniq
            .sort
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
