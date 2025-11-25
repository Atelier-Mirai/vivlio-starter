# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      module Build
        # ------------------------------------------------
        # ChapterConfig: 章設定・番号パースモジュール
        # ------------------------------------------------
        # book.yml の chapters 設定の解析、章番号のパースと展開、
        # ファイル名の正規化などを担当する。
        # ------------------------------------------------
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

            files.each do |file|
              basename = File.basename(file, '.md')
              num = Common.get_chapter_number(basename)
              next unless num

              number_to_files[num.to_i] << basename
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
          # 返り値: ソート済みのファイル名配列（例: ["02-preface.md", "11-install.md", ...]）
          def all_chapter_files
            Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { |f| File.basename(f) }.sort
          end

          # book.yml の chapters 設定を解析し、対象とする章ファイル名のリストを返す
          #
          # 対応形式:
          #   - nil または未指定 → 全章
          #   - "all" → 全章
          #   - "02, 11-13, 91" → 章番号指定（範囲・カンマ区切り）
          #   - [2, 11, 12, 91] → 章番号指定（配列）
          #   - ["11-install", "12-tutorial"] → ファイル名指定（配列）
          #   - 複数行文字列 → ファイル名指定（行ごと）
          #
          # 返り値: ファイル名配列（例: ["02-preface.md", "11-install.md", ...]）
          #         または nil（設定が空の場合）
          def configured_chapters
            cfg = Common::CONFIG['chapters']
            Common.log_info("[Subset] raw chapters config=#{cfg.inspect}") unless cfg.nil?

            # 章番号重複チェック（全形式共通）
            validate_no_duplicate_chapter_numbers!

            # 設定に応じて処理を分岐
            return all_chapter_files if cfg.nil? || (cfg.is_a?(String) && cfg.strip.downcase == 'all')
            return process_string_config(cfg) if cfg.is_a?(String)
            return process_array_config(cfg) if cfg.is_a?(Array)

            nil
          end

          # 章番号の重複を検証し、重複があればエラーを発生させる
          def validate_no_duplicate_chapter_numbers!
            duplicates = detect_duplicate_chapter_numbers
            return unless duplicates.any?

            error_msg = "❌ 同一章番号で複数のファイルが存在します。ファイル名を見直してください:\n"
            duplicates.each do |num, files|
              error_msg += "  章番号 #{num}: #{files.join(', ')}\n"
            end
            Common.log_error(error_msg)
            raise StandardError, error_msg
          end

          # 文字列形式の chapters 設定を処理
          # 番号指定（カンマ区切り・範囲）またはファイル名指定（複数行）に対応
          def process_string_config(str)
            str = str.to_s.strip

            # 番号指定（カンマ区切りまたは範囲）の場合
            if str.include?(',') || str.match?(/\A\d+-\d+\z/)
              return process_number_string(str)
            end

            # ファイル名指定（複数行）の場合
            process_filename_list(str.lines)
          end

          # 番号指定文字列を処理（例: "02, 11-13, 91"）
          def process_number_string(str)
            numbers = parse_chapter_numbers_from_string(str)
            Common.log_info("[Subset] parsed chapter numbers=#{numbers.inspect}")
            convert_numbers_to_filenames(numbers)
          rescue ArgumentError => e
            Common.log_error("❌ chapters 設定エラー: #{e.message}")
            raise StandardError, e.message
          end

          # 配列形式の chapters 設定を処理
          # 全て整数なら番号指定、そうでなければファイル名指定
          def process_array_config(arr)
            if all_integers?(arr)
              # 番号指定の場合
              numbers = arr.map { |n| n.to_s.strip.to_i }.uniq.sort
              Common.log_info("[Subset] chapter numbers from array=#{numbers.inspect}")
              convert_numbers_to_filenames(numbers)
            else
              # ファイル名指定の場合
              process_filename_list(arr)
            end
          end

          # ファイル名リストを正規化
          # contents/ 接頭辞や .md 拡張子の省略を許容
          def process_filename_list(items)
            normalized = Array(items)
                         .map { |s| s.to_s.strip }
                         .reject(&:empty?)
                         .map { |s| normalize_chapter_filename(s) }

            Common.log_info("[Subset] normalized filenames=#{normalized.inspect}") if normalized.any?
            normalized.any? ? normalized : nil
          end

          # 章ファイル名を正規化（contents/ 接頭辞削除、.md 拡張子補完）
          def normalize_chapter_filename(name)
            name = name.sub(%r{\A#{Regexp.escape(Common::CONTENTS_DIR)}/}, '')
            name = "#{name}.md" unless name.end_with?('.md')
            name
          end

          # 章番号配列をファイル名配列に変換
          # 例: [2, 11, 12] → ["02-preface.md", "11-install.md", "12-tutorial.md"]
          # 存在しないファイルはスキップ
          def convert_numbers_to_filenames(numbers)
            return [] unless numbers.is_a?(Array)

            files = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md'))
            number_to_file = {}

            files.each do |file|
              basename = File.basename(file, '.md')
              num = Common.get_chapter_number(basename)
              next unless num

              number_to_file[num.to_i] = "#{basename}.md"
            end

            result = numbers.map { |n| number_to_file[n] }.compact
            Common.log_info("[Subset] converted to filenames=#{result.inspect}")
            result
          end

          # ベース名配列を章番号レンジ＋keepでフィルタ
          #
          # @param basenames [Array<String>] 拡張子なしのベース名配列
          # @param range [Range] 章番号レンジ（例: 11..89, 91..97）
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
end
