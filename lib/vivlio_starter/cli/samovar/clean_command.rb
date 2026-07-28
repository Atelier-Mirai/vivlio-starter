# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/clean_command.rb
# ================================================================
# 責務:
#   Samovar CLI の clean コマンドを実装する。
#   ビルド生成物・キャッシュ・カバー画像の削除を行う。
#
# 主要オプション:
#   - (なし): 中間生成物を削除、最終 PDF は保持
#   - --purge: 最終 PDF も含めてすべて削除
#   - --cache: キャッシュのみ削除
#   - --cover: カバー画像のみ削除（マスターは保持）
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
          option '--purge/-P', '生成物（PDF含む）をすべて削除します', default: false, key: :purge
          option '--cache/-C', 'キャッシュのみを削除します', default: false, key: :cache
          option '--cover', '生成されたカバー画像のみを削除します', default: false, key: :cover
          option '--generated-images', '生成された扉絵/装飾などの画像を削除します', default: false, key: :generated_images
          option '--index-dictionaries', '索引・用語集辞書データを削除します（確認あり）', default: false, key: :index_dictionaries
          option '--all', 'index-dictionaries を除くすべての削除オプションをまとめて実行します', default: false, key: :all
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
        # 表示をここで行うのは、同じ execute_clean を vs build の Step 0 も呼ぶため
        # （ドメイン層で報告するとビルドのたびに混ざる）。
        def report_result(summary)
          if summary.none?
            VivlioStarter::CLI::Common.log_result('削除対象はありませんでした', status: :success)
            return
          end

          VivlioStarter::CLI::Common.log_result("削除しました（#{breakdown(summary)}）", status: :success)
        end

        # 実績のあったカテゴリだけを並べる（「キャッシュ 3 件・生成物 12 件」）
        def breakdown(summary)
          {
            'キャッシュ' => summary.cache,
            '生成物' => summary.artifacts,
            'カバー画像' => summary.cover,
            '生成画像' => summary.generated_images,
            '辞書' => summary.dictionaries
          }.filter_map { |label, count| "#{label} #{count} 件" if count.positive? }.join('・')
        end
      end
    end
  end
end
