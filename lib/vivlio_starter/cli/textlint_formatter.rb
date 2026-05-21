# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/textlint_formatter.rb
# ================================================================
# 責務:
#   textlint の stylish 出力を日本語話者向けに再整形する。
#
# 処理内容:
#   - 列番号の除去（行番号のみ表示）
#   - ✓ error / error ラベルの除去
#   - ルール名を (ルール名) 形式で末尾に統一
#   - 冗長な中間説明（助詞リスト・Total ブロック等）の除去
#   - 英語メッセージの日本語翻訳（sentence-length 等）
#   - 補足説明のインデント整理
#   - ファイルパスの相対パス化
#
# 用途:
#   - LintCommands から呼び出される
#   - 日本語ユーザー向けの lint 出力改善
# ================================================================

module VivlioStarter
  module CLI
    # textlint stylish 出力の再整形フォーマッター
    class TextlintFormatter
      # パース済みエラーエントリ
      LintEntry = Data.define(:line, :fixable, :message, :details, :rule)

      # エラーメッセージの日本語マッピング（既存の translate_output 用）
      MESSAGE_TRANSLATIONS = {
        'Disallow to use "!"' => '感嘆符「!」は使用しないでください',
        'Disallow to use "！"' => '感嘆符「！」は使用しないでください',
        'Disallow to use "?"' => '疑問符「?」は使用しないでください',
        'Disallow to use "？"' => '疑問符「？」は使用しないでください'
      }.freeze

      # エラー開始行のパターン: "  行:列  [✓] error  メッセージ  ルール名"
      ERROR_LINE_PATTERN = /\A\s+(\d+):(\d+)\s+(✓\s+)?error\s+(.+)\z/

      # ファイルパスヘッダー行のパターン
      FILE_HEADER_PATTERN = %r{\A(/\S+\.md)\s*\z}

      # 除去対象の冗長行パターン
      NOISE_PATTERNS = [
        /\A次の助詞が連続しているため/,
        /\A\s*-\s+"[^"]+"\s*\z/,
        /\AOver\s+\d+\s+characters/,
        /\ATotal:\s*\z/,
        /\A(である|ですます)\s*:\s*\d+\s*\z/,
        %r{\A解説:\s*https?://},
        /\A\s*Try to run:/i,
        /\A\s*=>\s*/,
        /\AThis pair of marks is called/,
        /\A✖\s+\d+\s+problem/,
        /\A✓\s+\d+\s+fixable/
      ].freeze

      # sentence-length 英語→日本語翻訳パターン
      SENTENCE_LENGTH_PATTERN = /Line\s+\d+\s+sentence\s+length\((\d+)\)\s+exceeds\s+the\s+maximum\s+sentence\s+length\s+of\s+(\d+)\./

      # --- Public API ---

      # textlint stylish 出力を再整形する
      # @param output [String, nil] textlint の生出力
      # @return [String, nil] 整形済み出力
      def self.reformat_output(output)
        return output if output.nil? || output.empty?

        Reformatter.new(output).call
      end

      # 個別メッセージの日本語翻訳（既存互換）
      def self.translate_output(output)
        return output if output.nil? || output.empty?

        translated = output.dup
        MESSAGE_TRANSLATIONS.each { translated.gsub!(it.first, it.last) }
        translated
      end

      # stylish 出力の再整形エンジン
      class Reformatter
        # インデント幅: 行番号表示幅に合わせた補足行のインデント
        DETAIL_INDENT = '         '

        def initialize(raw_output)
          @raw_output = raw_output
        end

        # 再整形済み文字列を返す
        # stylish 形式として認識できない場合は元の出力をそのまま返す
        def call
          lines = @raw_output.lines.map(&:chomp)
          entries = parse(lines)
          return @raw_output unless entries.any? { it[:type] == :entry }

          format_entries(entries)
        end

        private

        # --- Phase: Parse --- textlint stylish 出力を構造化データに変換
        def parse(lines)
          result = []
          current_entry = nil
          continuation_lines = []

          lines.each do |line|
            case line
            in FILE_HEADER_PATTERN
              # ファイルヘッダー: 前のエントリを確定してからヘッダーを追加
              flush_entry(result, current_entry, continuation_lines) if current_entry
              current_entry = nil
              continuation_lines = []
              result << { type: :header, path: ::Regexp.last_match(1) }
            in ERROR_LINE_PATTERN
              # 新しいエラー行: 前のエントリを確定
              flush_entry(result, current_entry, continuation_lines) if current_entry
              current_entry = { line: ::Regexp.last_match(1).to_i, fixable: !::Regexp.last_match(3).nil?,
                                raw_message: ::Regexp.last_match(4).strip }
              continuation_lines = []
            in /\A\s*\z/
              # 空行: 無視（ただしエントリ間の区切りとして認識）
              next
            in /\A[✖✓]\s+\d+\s+(problem|fixable)/
              # textlint サマリ行: 無視
              next
            else
              # 継続行: 現在のエントリに追加
              continuation_lines << line.strip if current_entry
            end
          end

          # 最後のエントリを確定
          flush_entry(result, current_entry, continuation_lines) if current_entry
          result
        end

        # パース中のエントリと継続行から LintEntry を生成して result に追加
        def flush_entry(result, entry_data, continuation_lines)
          message, rule = extract_rule(entry_data[:raw_message], continuation_lines)
          details = clean_details(continuation_lines, rule)
          message = translate_message(message)
          details = details.map { translate_message(it) }

          result << {
            type: :entry,
            entry: LintEntry.new(
              line: entry_data[:line],
              fixable: entry_data[:fixable],
              message: message.strip,
              details: details,
              rule: rule
            )
          }
        end

        # メッセージ末尾または継続行末尾からルール名を抽出
        # 継続行を末尾から逆順に走査し、最初に見つかったルール名を返す
        def extract_rule(message, continuation_lines)
          # 継続行を末尾から逆順に走査
          continuation_lines.size.times do |i|
            idx = continuation_lines.size - 1 - i
            line = continuation_lines[idx].strip

            # ルール名のみの行（例: "prh", "ja-spacing/ja-space-between-half-and-full-width"）
            if line =~ %r{\A([\w-]+(?:/[\w-]+)*)\s*\z} && rule_like?(::Regexp.last_match(1))
              continuation_lines.delete_at(idx)
              return [message, ::Regexp.last_match(1)]
            end

            # 行末に空白区切りでルール名が付いている場合
            if line =~ %r{^(.+?)\s{2,}([\w-]+(?:/[\w-]+)*)$}
              continuation_lines[idx] = ::Regexp.last_match(1).strip
              return [message, ::Regexp.last_match(2)]
            end

            # ノイズ行はスキップして前の行を探索し続ける
            next if noise_line?(line)

            # ルール名もノイズでもない通常の継続行に到達 → ルールなし
            break
          end

          # メッセージ行末にルール名が空白区切りで付いている場合
          if message =~ %r{^(.+?)\s{2,}([\w-]+(?:/[\w-]+)*)$}
            return [::Regexp.last_match(1).strip,
                    ::Regexp.last_match(2)]
          end

          [message, nil]
        end

        # ルール名らしい文字列かどうか判定（日本語を含まないこと）
        def rule_like?(str) = str.match?(%r{\A[a-zA-Z][\w-]*(/[\w-]+)*\z}) && !str.match?(/[ぁ-んァ-ヶ一-龥]/)

        # 継続行から冗長な行を除去する
        def clean_details(lines, rule)
          lines
            .reject { noise_line?(it) }
            .reject { it.strip == rule }
            .map { it.sub(/\A【dict\d+】\s*/, '') }
            .reject(&:empty?)
        end

        # 冗長行パターンにマッチするか判定
        def noise_line?(line) = NOISE_PATTERNS.any? { it.match?(line.strip) }

        # 英語メッセージを日本語に翻訳し、冗長なラベルを除去する
        def translate_message(msg)
          # 【dictN】 ラベル除去
          msg = msg.sub(/\A【dict\d+】\s*/, '')

          # sentence-length
          msg = msg.gsub(SENTENCE_LENGTH_PATTERN) do
            "文の長さ (#{::Regexp.last_match(1)}) が最大文長の #{::Regexp.last_match(2)} を超えています。"
          end

          # unmatched-pair: Cannot find a pairing character for X.
          msg = msg.gsub(/Cannot find a pairing character for (.+)\./) do
            "#{::Regexp.last_match(1)} のペアとなる文字が見つかりません。"
          end

          # unmatched-pair: You should close this sentence with X.
          msg = msg.gsub(/You should close this sentence with (.+)\./) { "#{::Regexp.last_match(1)} で閉じてください。" }

          # Disallow to use 系
          MESSAGE_TRANSLATIONS.each { msg = msg.gsub(it.first, it.last) }

          msg
        end

        # --- Phase: Format --- 構造化データを整形済み文字列に変換
        def format_entries(parsed)
          lines = []

          parsed.each do |item|
            case item
            in { type: :header, path: String => path }
              # ファイルパスを相対パス化（2つ目以降は空行で区切る）
              relative = path.sub(%r{.*/contents/}, 'contents/')
              lines << '' unless lines.empty?
              lines << "📄 #{relative}"
            in { type: :entry, entry: LintEntry => e }
              lines.concat(format_single_entry(e))
            end
          end

          "#{lines.join("\n")}\n"
        end

        # 単一エントリを整形済み行の配列に変換
        def format_single_entry(entry)
          rule_suffix = entry.rule ? " (#{entry.rule})" : ''
          line_prefix = format('%5d', entry.line)

          # unmatched-pair の主メッセージと補足を結合
          message, details = merge_unmatched_pair(entry.message, entry.details)

          if details.empty?
            # 詳細なし: 1行で完結
            ["#{line_prefix}  #{message}#{rule_suffix}"]
          else
            # 詳細あり: 主メッセージ + インデント付き補足行
            result = ["#{line_prefix}  #{message}"]
            details.each_with_index do |detail, idx|
              suffix = idx == details.size - 1 ? rule_suffix : ''
              result << "#{DETAIL_INDENT}#{detail}#{suffix}"
            end
            result
          end
        end

        # unmatched-pair: 主メッセージと「閉じてください」を1行に結合
        def merge_unmatched_pair(message, details)
          return [message, details] unless message.include?('ペアとなる文字が見つかりません。')

          close_detail = details.find { it.include?('で閉じてください。') }
          return [message, details] unless close_detail

          merged = "#{message}#{close_detail}"
          remaining = details.reject { it.include?('で閉じてください。') }
          [merged, remaining]
        end
      end
    end
  end
end
