# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/clean_command.rb
# ================================================================
# 責務:
#   Samovar CLI の clean コマンドを実装する。
#   キャッシュとビルドの生成物の削除を行う。
#
# 主要オプション:
#   - (なし): キャッシュ（.cache/）を削除
#   - --purge: キャッシュに加えて、ルート直下の生成物（PDF・EPUB など）も削除
#   - --index-dictionaries: 索引・用語集の辞書だけを削除（確認あり）
#
# 依存:
#   - CleanCommands: 実際の削除処理
# ================================================================

require_relative '../clean'
require_relative '../guards'
require_relative 'vs_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      # clean コマンドの Samovar 実装
      class CleanCommand < VsCommand
        self.description = '生成物やキャッシュを削除します'

        options do
          option '--purge/-P', 'キャッシュに加えて、プロジェクト直下の PDF・EPUB などの生成物も削除します',
                 default: false, key: :purge
          option '--index-dictionaries', '索引・用語集の辞書だけを削除します（確認あり）', default: false, key: :index_dictionaries
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if options[:help]

          # 前提条件の検証（precondition-guard-spec.md: clean は ProjectRoot ○）
          guard_failure = Guards.precheck(Guards::RelaxedCheck.new(Guards::ProjectRootCheck.new))
          return guard_failure if guard_failure

          report_result(CleanCommands.execute_clean(options.dup))
          0
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          VivlioStarter::CLI::Common.log_warn("clean コマンド実行中にエラー: #{e.message}")
          1
        end

        private

        # 削除の実績を既定ログレベルでも 1 行で報告する。
        # 実行して無音だと「効いたのか分からない」ため、何も無かった場合も黙らない。
        # 表示はコマンド層の責務とし、ドメイン層（CleanCommands）は件数を返すだけにする。
        # 辞書の削除を確認で断ったときは「削除しませんでした」と答える（対象が無かったのではない）。
        def report_result(summary)
          if summary.none?
            message = summary.declined ? '削除しませんでした' : '削除対象はありませんでした'
            VivlioStarter::CLI::Common.log_result(message, status: :success)
            return
          end

          declined = summary.declined ? '。辞書は削除しませんでした' : ''
          VivlioStarter::CLI::Common.log_result("削除しました（#{breakdown(summary)}）#{declined}", status: :success)
        end

        # 実績のあったカテゴリだけを並べる（「キャッシュ 3 件・生成物 12 件」）
        def breakdown(summary)
          {
            'キャッシュ' => summary.cache,
            '生成物' => summary.artifacts,
            '辞書' => summary.dictionaries
          }.filter_map { |label, count| "#{label} #{count} 件" if count.positive? }.join('・')
        end
      end
    end
  end
end
