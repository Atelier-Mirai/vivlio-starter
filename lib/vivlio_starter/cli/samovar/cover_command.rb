# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/cover_command.rb
# ================================================================
# 責務:
#   Samovar CLI の cover コマンドを実装する。
#   カバー画像生成ロジック (CoverCommands) を呼び出す。
#   分冊の本では vs build と同じく巻を選べる（multivolume-spec.md §4.8）:
#     --volume <id|name> … その巻の表紙 / --volume all … 全巻の表紙 / 何も付けない … 合本の表紙
# ================================================================

require_relative '../cover'
require_relative '../guards'
require_relative 'vs_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      # cover コマンドの Samovar 実装
      class CoverCommand < VsCommand
        self.description = '表紙・裏表紙の画像を生成します（book.yml の判型と output.targets に従う）'

        options do
          option '--volume <name>', '分冊の巻の表紙を作る（巻の id か name。all で全巻の表紙を作る）', key: :volume
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if options[:help]

          # 前提条件の検証（ProjectRoot ◎ / ImagesDir ○）
          guard_failure = Guards.precheck(
            Guards::ProjectRootCheck.new,
            Guards::RelaxedCheck.new(Guards::ImagesDirCheck.new)
          )
          return guard_failure if guard_failure

          volumes = selected_volumes
          if volumes.empty?
            CoverCommands.execute_generate(self)
          else
            volumes.each { generate_for(it) }
          end
          0
        rescue Build::Volumes::SelectionError => e
          Common.log_error(e.message, detail: e.detail)
          1
        end

        private

        # 表紙を作る巻。何も付けなければ空（合本の表紙を book.yml の値で作る）
        def selected_volumes
          case options[:volume]
          in nil then []
          in Build::Volumes::ALL
            # 巻の無い本は、書き方を案内して止める
            Build::Volumes.list.tap { Build::Volumes.find!(Build::Volumes::ALL) if it.empty? }
          in token then [Build::Volumes.find!(token)]
          end
        end

        # 巻の値（書名・表紙など）を book.yml に重ねて表紙を作り、book.yml の値へ戻す。
        # 表紙が読むのは CONFIG だけなので、vs build と違い全巻を同じプロセスで続けて作れる
        def generate_for(volume)
          Common.log_action("#{volume.name}（#{volume.id}）の表紙を作ります")
          book_config = Common::CONFIG
          Build::Volumes.select!(volume)
          Build::Volumes.apply_config!(volume)
          CoverCommands.execute_generate(self)
        ensure
          Build::Volumes.select!(nil)
          Common.install_configuration!(book_config) if book_config
        end
      end
    end
  end
end
