# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      module Build
        # ------------------------------------------------
        # ImageOptimizer: 画像最適化モジュール
        # ------------------------------------------------
        # WebP変換、リサイズ、テーマ画像の準備を担当する。
        # ------------------------------------------------
        module ImageOptimizer
          module_function

          # Step 2: 画像最適化（WebP 変換/リサイズ）
          def optimize_images!(preset = nil)
            p = preset&.to_sym || :medium
            preset_task = { high: 'resize:high', low: 'resize:low' }[p] || 'resize:medium'

            Common.log_action("[Step 1] 画像の最適化（WebP 変換/リサイズ）を実行します… preset=#{p}")
            dirs = [Common::IMAGES_DIR, File.join(Common::STYLESHEETS_DIR, 'images')]
            dirs.each do |d|
              if Dir.exist?(d)
                Common.log_info("[Step 1] 対象ディレクトリ: #{d}（preset: #{p}）")
                case preset_task
                when 'resize:high'
                  ResizeCommands.execute_resize_high(d)
                when 'resize:low'
                  ResizeCommands.execute_resize_low(d)
                else
                  ResizeCommands.execute_resize_medium(d)
                end
              else
                Common.log_info("[Step 1] スキップ（存在しません）: #{d}")
              end
            end
            Common.log_success('[Step 1] 画像最適化が完了しました')
          end

          # Step 3: frontispiece / ornament の事前生成
          def prepare_theme_images!
            Common.log_action('[Step 2] frontispiece / ornament の準備を開始します…')

            cfg = Common::CONFIG
            theme_cfg = cfg.dig(:theme)
            unless theme_cfg
              Common.log_info('[Step 2] theme 設定が存在しないためスキップします')
              return
            end

            # CSS更新のためにfrontmatter生成を実行（HTMLファイルは生成しない）
            require_relative '../pre_process/frontmatter_generator'
            require_relative '../pre_process/css_updater'
            Vivlio::Starter::CLI::PreProcessCommands::FrontmatterGenerator.update_css_only!(cfg)

            frontispiece_entry = theme_cfg.dig(:frontispiece)
            ornament_entry = theme_cfg.dig(:ornament)

            # String の場合はそのまま、Data オブジェクトの場合は :image を取得
            frontispiece_source = frontispiece_entry.is_a?(String) ? frontispiece_entry : frontispiece_entry&.dig(:image)
            ornament_source = ornament_entry

            generated_any = false

            if frontispiece_source && !frontispiece_source.to_s.strip.empty?
              path = Vivlio::Starter::CLI::PreProcessCommands.resolve_frontispiece_path(frontispiece_source, allow_generation: true)
              Common.log_success("[Step 2] frontispiece を準備しました: #{path}")
              generated_any = true
            else
              Common.log_info('[Step 2] frontispiece 設定なし（既定画像を使用）')
            end

            if ornament_source && !ornament_source.to_s.strip.empty?
              path = Vivlio::Starter::CLI::PreProcessCommands.resolve_ornament_path(ornament_source, allow_generation: true)
              Common.log_success("[Step 2] ornament を準備しました: #{path}")
              generated_any = true
            else
              Common.log_info('[Step 2] ornament 設定なし（既定画像を使用）')
            end

            Common.log_info('[Step 2] 追加生成は不要でした') unless generated_any
          rescue StandardError => e
            Common.log_warn("[Step 2] frontispiece / ornament 準備中にエラーが発生しました: #{e.message}")
          end
        end
      end
    end
  end
end
