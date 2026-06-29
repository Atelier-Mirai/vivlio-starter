# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/textlint_formatter.rb
# ================================================================
# 責務:
#   textlint --format json の出力を、ルール（メッセージ先頭行）単位に集約して整形する。
#   同じ指摘を 1 行へ畳み、book.yml の lint.disabled_rules / disabled_terms による
#   個別無効化も適用する（スペルチェック側 SpellChecker.aggregate と体裁を揃える）。
#
# 用途:
#   - LintCommands（vs lint の textlint 集約表示）から呼び出される
# ================================================================

require 'json'

module VivlioStarter
  module CLI
    # textlint --format json 出力の集約フォーマッター
    class TextlintFormatter
      # 集約表示で出現行を並べる最大件数（超過分は … で省略）
      MAX_SHOWN_LINES = 10

      # --- Public API ---

      # textlint --format json の出力を、メッセージ（先頭行）＋ルール単位で集約する。
      # スペルチェック側（SpellChecker.aggregate）と同様、同じ指摘を 1 行へ畳んで見やすくする。
      # @param json_string [String] textlint --format json の生出力
      # @param base_dir [String] ファイルパスの相対化基準
      # @param disabled_rules [Array<String>] 無効化するルール ID（短縮名・完全名の両対応）
      # @param disabled_terms [Array<String>] 無効化する指摘語（"X => Y" 表記揺れ系。先頭行に含めば除外）
      # @param trim_long_vowel [Boolean] true なら「X => Xー」（末尾長音を足す）系の指摘を抑止
      # @return [Hash, nil] { files: [{ path:, rows: }], total:, fixable: } / JSON 解釈失敗時 nil
      #   rows: [{ count:, label:, lines: }]（出現数の多い順。label は "[ルール] 指摘先頭行"）
      def self.aggregate_json(json_string, base_dir: Dir.pwd, disabled_rules: [], disabled_terms: [],
                              trim_long_vowel: false)
        data = JSON.parse(json_string.to_s)
        return nil unless data.is_a?(Array)

        drules = Array(disabled_rules).map(&:to_s)
        dterms = Array(disabled_terms).map(&:to_s).reject(&:empty?)
        total = 0
        fixable = 0
        files = data.filter_map do |file|
          messages = Array(file['messages']).reject { |m| disabled_message?(m, drules, dterms, trim_long_vowel) }
          next if messages.empty?

          total += messages.size
          fixable += messages.count { |m| m['fix'] }
          { path: relative_md_path(file['filePath'], base_dir), rows: aggregate_messages(messages) }
        end
        { files: files, total: total, fixable: fixable }
      rescue JSON::ParserError
        nil
      end

      # book.yml の lint.disabled_rules / disabled_terms / trim_long_vowel に該当する指摘か
      def self.disabled_message?(message, disabled_rules, disabled_terms, trim_long_vowel = false)
        rule = message['ruleId'].to_s
        return true if disabled_rules.include?(rule) || disabled_rules.include?(short_rule(rule))

        head = message_head(message['message'])
        return true if disabled_terms.any? { |t| head.include?(t) }

        trim_long_vowel && long_vowel_addition?(head)
      end

      # 「X => Xー」（末尾に長音記号を足すだけ）の表記揺れ指摘か。
      # 技術者向けに「サーバ／パラメータ／フィルタ」等の末尾長音を省く文体を選べるようにする。
      def self.long_vowel_addition?(head)
        m = head.match(/\A(.+?)\s*=>\s*(.+)\z/)
        return false unless m

        m[2].strip == "#{m[1].strip}ー"
      end

      # メッセージが出現ごとに変動する（行番号・文字数を含む等）ルールの、集約用の要約ラベル。
      # これらは個別メッセージを使わず 1 つにまとめる（件数と出現行だけ見られれば十分）。
      RULE_SUMMARIES = {
        'sentence-length' => '一文が長すぎます（最大文長を超過）'
      }.freeze

      # メッセージ配列を [集約見出し, ルール] 単位で集約する。
      # 通常はメッセージ先頭行ごと（prh の置換などは別グループ）だが、出現ごとに数値が変わる
      # ルール（sentence-length 等）は要約ラベル＋数字マスクで 1 つに畳む。
      def self.aggregate_messages(messages)
        messages.group_by { |m| [grouping_head(m['message'], m['ruleId']), short_rule(m['ruleId'])] }
                .map do |(head, rule), items|
          lines = items.filter_map { it['line'] }.uniq.sort
          shown = lines.first(MAX_SHOWN_LINES).join(', ')
          shown += ', …' if lines.size > MAX_SHOWN_LINES
          { count: items.size, label: "[#{rule}] #{head}", lines: shown }
        end.sort_by { |row| -row[:count] }
      end

      # 集約見出し：出現ごとに数値が変わるルール（sentence-length 等）は要約ラベルで 1 つに畳み、
      # それ以外は先頭行そのまま（"一つ => 1つ" の数字など、意味のある数値を保つ）。
      def self.grouping_head(message, rule_id)
        RULE_SUMMARIES[short_rule(rule_id)] || message_head(message)
      end

      # メッセージの先頭行（actionable な指摘部分。prh の置換や ja-spacing の本文）
      def self.message_head(message) = message.to_s.lines.first.to_s.strip

      # ルール ID を短縮（"ja-spacing/ja-space-around-code" → "ja-space-around-code"）
      def self.short_rule(rule_id) = rule_id.to_s.split('/').last.to_s

      # textlint の絶対パスを base_dir 相対へ
      def self.relative_md_path(path, base_dir)
        rel = path.to_s.sub(%r{\A#{Regexp.escape(base_dir.to_s)}/?}, '')
        rel.empty? ? path.to_s : rel
      end
    end
  end
end
