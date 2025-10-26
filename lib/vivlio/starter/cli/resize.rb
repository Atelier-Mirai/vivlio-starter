# frozen_string_literal: true

require 'fileutils'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: resize（画像リサイズ/変換）
      # ------------------------------------------------
      # - 目的: 画像を WebP に変換（高精細/標準/軽量のプリセット）
      # - 提供コマンド: resize, resize:high, resize:medium, resize:low
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module ResizeCommands
        module_function

        RESIZE_DESC = {
          high: {
            short: '画像を高品質WebPに変換します',
            long: <<~DESC
              画像を高品質WebPに変換します（quality=90, max_px=2000）。

              対象: .png, .jpg, .jpeg
              出力: 同ディレクトリに .webp

              引数:
                DIR    対象ディレクトリ（省略時は images/）

              使用例:
                vs resize:high
                vs resize:high assets/images
            DESC
          },
          medium: {
            short: '画像を標準品質WebPに変換します',
            long: <<~DESC
              画像を標準品質WebPに変換します（quality=85, max_px=1600）。

              対象: .png, .jpg, .jpeg
              出力: 同ディレクトリに .webp

              引数:
                DIR    対象ディレクトリ（省略時は images/）

              使用例:
                vs resize:medium
                vs resize:medium assets/images
            DESC
          },
          low: {
            short: '画像を軽量品質WebPに変換します',
            long: <<~DESC
              画像を軽量品質WebPに変換します（quality=75, max_px=1200）。

              対象: .png, .jpg, .jpeg
              出力: 同ディレクトリに .webp

              引数:
                DIR    対象ディレクトリ（省略時は images/）

              使用例:
                vs resize:low
                vs resize:low assets/images
            DESC
          },
          default: {
            short: '画像をWebPに変換します（標準品質）',
            long: <<~DESC
              画像をWebPに変換します（標準品質が既定）。

              対象: .png, .jpg, .jpeg
              出力: 同ディレクトリに .webp

              引数:
                DIR    対象ディレクトリ（省略時は images/）

              オプション:
                --force   既存ファイルも強制再生成
                --high    高品質プリセットを使用
                --low     軽量品質プリセットを使用

              使用例:
                vs resize
                vs resize assets/images
                vs resize --high
                vs resize --force
            DESC
          }
        }.freeze

        def included(base)
          base.class_eval do
            # Thor エイリアス: Rake風のコマンド名に対応
            map 'resize:high'   => :resize_high
            map 'resize:low'    => :resize_low
            map 'resize:medium' => :resize_medium
            desc 'resize:high [DIR]', RESIZE_DESC[:high][:short]
            long_desc RESIZE_DESC[:high][:long]
            # ================================================================
            # Command: resize:high（高精細 WebP 変換）
            # ------------------------------------------------
            # - 概要: 高品質プリセット（quality=90, max_px=2000）で WebP 変換
            # - 入力: DIR 配下の .png/.jpg/.jpeg
            # - 出力: 同名 .webp
            # ================================================================
            def resize_high(dir = 'images')
              resize_with_preset('高精細', dir)
            end

            desc 'resize:medium [DIR]', RESIZE_DESC[:medium][:short]
            long_desc RESIZE_DESC[:medium][:long]
            # ================================================================
            # Command: resize:medium（標準 WebP 変換）
            # ------------------------------------------------
            # - 概要: 標準品質プリセット（quality=85, max_px=1600）で WebP 変換
            # - 入力: DIR 配下の .png/.jpg/.jpeg
            # - 出力: 同名 .webp
            # ================================================================
            def resize_medium(dir = 'images')
              resize_with_preset('標準', dir)
            end

            desc 'resize:low [DIR]', RESIZE_DESC[:low][:short]
            long_desc RESIZE_DESC[:low][:long]
            # ================================================================
            # Command: resize:low（軽量 WebP 変換）
            # ------------------------------------------------
            # - 概要: 軽量品質プリセット（quality=75, max_px=1200）で WebP 変換
            # - 入力: DIR 配下の .png/.jpg/.jpeg
            # - 出力: 同名 .webp
            # ================================================================
            def resize_low(dir = 'images')
              resize_with_preset('軽量', dir)
            end

            desc 'resize [DIR]', RESIZE_DESC[:default][:short]
            long_desc RESIZE_DESC[:default][:long]

            method_option :force, type: :boolean, aliases: '-f', desc: '既存ファイルも強制再生成'
            method_option :high,  type: :boolean, desc: '高品質プリセットを使用'
            method_option :low,   type: :boolean, desc: '軽量品質プリセットを使用'
            # ================================================================
            # Command: resize（標準 WebP 変換）
            # ------------------------------------------------
            # - 概要: 標準品質（quality=85, max_px=1600）を既定に WebP 変換
            # - 入力: DIR 配下の .png/.jpg/.jpeg
            # - 出力: 同名 .webp
            # - オプション: --force / --high / --low
            # ================================================================
            def resize(dir = 'images')
              preset = if options[:high]
                         '高精細'
                       elsif options[:low]
                         '軽量'
                       else
                         '標準'
                       end

              ENV['FORCE'] = '1' if options[:force]
              resize_with_preset(preset, dir)
            end

            private

            def resize_with_preset(preset_name, dir)
              ENV['VERBOSE'] = '1' if options[:verbose]

              # プリセット定義
              presets = {
                '高精細' => { quality: 90, method: 6, max_px: 2000 },
                '標準' => { quality: 85, method: 6, max_px: 1600 },
                '軽量' => { quality: 75, method: 6, max_px: 1200 }
              }

              preset = presets[preset_name]
              unless preset
                Common.log_error("未知のプリセットです: #{preset_name}")
                exit(1)
              end

              unless Dir.exist?(dir)
                Common.log_error("ディレクトリが存在しません: #{dir}")
                exit(1)
              end

              # ImageMagick の存在確認
              unless system('which magick >/dev/null 2>&1')
                Common.log_error('Error: ImageMagick (magick) が見つかりません。brew install imagemagick 等で導入してください。')
                exit(1)
              end

              # 対象ファイルの収集
              patterns = %w[png jpg jpeg JPG JPEG PNG]
              files = patterns.flat_map { |ext| Dir.glob(File.join(dir, "**/*.#{ext}")) }.uniq.sort

              if files.empty?
                Common.log_info("対象画像が見つかりませんでした: #{dir}")
                return
              end

              Common.log_action("画像変換を開始: Preset=#{preset_name}, Dir=#{dir}, Files=#{files.size}")

              files.each do |src|
                dst = src.sub(/\.[^.]+\z/, '.webp')

                # スキップ判定（FORCE=1でない場合）
                if ENV['FORCE'].nil? && File.exist?(dst) && File.mtime(dst) >= File.mtime(src)
                  Common.log_info("skip: up-to-date #{dst}")
                  next
                end

                FileUtils.mkdir_p(File.dirname(dst))

                # ImageMagick コマンド実行
                cmd = [
                  'magick', src,
                  '-resize', "#{preset[:max_px]}x#{preset[:max_px]}>",
                  '-strip',
                  '-quality', preset[:quality].to_s,
                  '-define', "webp:method=#{preset[:method]}",
                  dst
                ]

                Common.log_info(cmd.join(' '))
                unless system(*cmd)
                  Common.log_error("変換に失敗しました: #{src}")
                  exit(1)
                end
              end

              Common.log_success('画像変換が完了しました')
            end
          end
        end
      end
    end
  end
end
