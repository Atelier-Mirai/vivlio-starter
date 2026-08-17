# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/resize_command.rb
# ================================================================
# 責務:
#   Samovar CLI の resize 系コマンドを実装する。
#   画像ファイルを WebP 形式に変換・リサイズする。
#
# 提供コマンド:
#   - resize: 画像を WebP へ変換（--high / --medium / --low で品質を選ぶ。既定は標準）
#
# かつてこの欄に resize:high / resize:medium / resize:low と書いてあったが、**そんな
# サブコマンドは登録されていない**（root_command.rb にあるのは 'resize' の 1 つだけ）。
# この記述を信じた `system("vs resize:high …")` が theme_image_resolver に残り、WebP を
# 1 枚も生成しないまま動いていた（2026-08-17 に発覚）。
#
# 依存:
#   - ResizeCommands: 実際のリサイズ処理
#   - ImageMagick: 画像変換エンジン
# ================================================================

require_relative '../resize'
require_relative '../guards'
require_relative 'vs_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      # resize コマンドの Samovar 実装
      class ResizeCommand < VsCommand
        self.description = 'images/ の画像を WebP へ変換・最適化します（--high/--medium/--low で品質変更）'

        options do
          option '-f/--force', '既存ファイルも強制再生成', key: :force
          option '--high', '高品質プリセットを使用', key: :high
          option '--medium', '標準品質プリセットを使用（既定）', key: :medium
          option '--low', '軽量品質プリセットを使用', key: :low
          option '--delete-originals', '変換後に元の PNG/JPG ファイルを削除（確認あり）', default: false, key: :delete_originals
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        one :dir, '対象ディレクトリ', default: 'images', required: false

        def call
          # --help が未定義だと位置引数 dir に「--help」が落ちてしまう（契約テスト CL-01 で検出）
          if options[:help]
            print_usage
            return 0
          end

          # 前提条件の検証（ProjectRoot ◎ / ImagesDir ◎）
          # 既定の images/ 以外を対象にする場合（vs resize <dir>）は ImagesDir を検証しない
          checks = [Guards::ProjectRootCheck.new]
          checks << Guards::ImagesDirCheck.new if resolve_dir == Common::IMAGES_DIR
          guard_failure = Guards.precheck(*checks)
          return guard_failure if guard_failure

          # --medium は既定と同じだが、受け付ける。3 つのプリセットが原稿の表に並んでいるのに
          # 「標準だけはオプションで書けない」のは著者を戸惑わせる（実際に問われた）。
          preset = if options[:high]
                     '高精細'
                   elsif options[:low]
                     '軽量'
                   else
                     '標準'
                   end
          report_result(ResizeCommands.execute_resize_with_preset(preset, resolve_dir, merged_options))
          0
        end

        private

        # 変換の実績を既定ログレベルでも 1 行で報告する。
        # 表示をここで行うのは、同じ関数を vs build の Step 1 も呼ぶため
        # （ドメイン層で報告するとビルド中に対象ディレクトリの数だけ混ざる）。
        def report_result(summary)
          return unless summary.is_a?(ResizeCommands::ResizeSummary)

          VivlioStarter::CLI::Common.log_result(result_message(summary), status: :success)
        end

        # 「0 件生成」は何が起きたか読み取れないため、実績に応じて言い方を変える
        def result_message(summary)
          return "最適化の対象画像はありませんでした: #{resolve_dir}" if summary.none?
          return "画像はすべて最新でした（#{summary.skipped} 件を確認）" if summary.converted.zero?

          skipped_note = summary.skipped.positive? ? "・最新のため据え置き #{summary.skipped} 件" : ''
          "画像を最適化しました（WebP #{summary.converted} 件生成#{skipped_note}）"
        end

        def resolve_dir
          d = dir || 'images'
          # "01-intro" のように images/ プレフィックスなしで指定された場合に補完する
          return d if d == 'images' || d.start_with?('images/') || File.directory?(d)

          with_prefix = File.join('images', d)
          File.directory?(with_prefix) ? with_prefix : d
        end

        def merged_options
          (parent&.options || {}).merge(options || {})
        end

        def print_usage
          puts <<~USAGE
            vs resize - 画像をWebPに変換します

            Usage: vs resize [DIR] [options]

            引数:
              DIR                 対象ディレクトリ（省略時: images/。images/ プレフィックスは省略可）

            オプション:
              -f, --force         既存ファイルも強制再生成
              --high              高品質プリセットを使用
              --medium            標準品質プリセットを使用（既定）
              --low               軽量品質プリセットを使用
              --delete-originals  変換後に元の PNG/JPG ファイルを削除（確認あり）
              -h, --help          このコマンドの使い方を表示

            例:
              vs resize                  # images/ 配下を標準品質で変換
              vs resize 01-intro         # images/01-intro/ のみ変換
              vs resize --high --force   # 高品質で全ファイル再生成
          USAGE
        end
      end
    end
  end
end
