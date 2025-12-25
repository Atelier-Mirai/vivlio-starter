# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/post_process/html_replacer.rb
# ================================================================
# 責務:
#   config/post_replace_list.yml の置換ルールを HTML に適用する。
#
# 置換ルール形式:
#   - f: 検索パターン（正規表現）
#   - r: 置換文字列（$1〜$9 でキャプチャ参照）
#
# 用途:
#   - 特殊文字の変換（例: 〈〉→《》）
#   - クラス追加（例: <p> に特定クラスを付与）
#   - カスタム記法の展開
# ================================================================

require_relative '../common'

module Vivlio
  module Starter
    module CLI
      module PostProcessCommands
        # YAML 置換ルール適用モジュール
        module HtmlReplacer
          module_function

          # YAML置換ルールを適用してHTMLファイルを更新
          def process_html_file(html_file, replace_rules)
            return { changed: false, replacements: 0 } unless replace_rules&.any?

            content = File.read(html_file, encoding: 'utf-8')
            replacements = 0
            
            replace_rules.each do |rule|
              pattern_str = rule['f']
              replacement_str = rule['r']
              next unless pattern_str && replacement_str

              begin
                regex = Regexp.new(pattern_str, Regexp::MULTILINE)
                content = content.gsub(regex) do
                  match_data = ::Regexp.last_match
                  result = replacement_str.dup
                  (1..9).each do |i|
                    result.gsub!("$#{i}", match_data[i].to_s)
                  end
                  replacements += 1
                  result
                end
              rescue RegexpError => e
                Common.log_warn("不正な正規表現: #{pattern_str} - #{e.message}")
              end
            end

            if replacements.positive?
              File.write(html_file, content, encoding: 'utf-8')
              { changed: true, replacements: replacements }
            else
              { changed: false, replacements: 0 }
            end
          rescue StandardError => e
            Common.log_error("置換処理に失敗: #{html_file} - #{e.message}")
            { changed: false, replacements: 0 }
          end
        end
      end
    end
  end
end
