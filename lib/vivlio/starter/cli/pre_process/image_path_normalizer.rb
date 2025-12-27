# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/pre_process/image_path_normalizer.rb
# ================================================================
# 責務:
#   Markdown 内の画像パスを正規化し、存在しない画像にはプレースホルダーを生成する。
#
# 処理内容:
#   - 相対パス → images/ 配下のパスに正規化
#   - 存在しない画像 → SVG プレースホルダーの data URI に置換
#   - WebP 優先: .png/.jpg があっても .webp を優先参照
#
# プレースホルダー:
#   - 「Vivlio Starter」ロゴと「画像準備中」メッセージを表示
#   - ファイル名を表示して不足画像を特定しやすくする
# ================================================================

require 'cgi'
require_relative '../common'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # 画像パス正規化・プレースホルダー生成モジュール
        module ImagePathNormalizer
          NO_IMAGE_PLACEHOLDER_SVG = <<~SVG.freeze
            <svg width="600" height="400" viewBox="0 0 600 400" fill="none" xmlns="http://www.w3.org/2000/svg">
              <defs>
                    <linearGradient id="vivlioTextGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                  <stop offset="0%" style="stop-color:#4a86e8;stop-opacity:1" />
                  <stop offset="100%" style="stop-color:#1c4587;stop-opacity:1" />
                </linearGradient>
                <linearGradient id="starterTextGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                  <stop offset="0%" style="stop-color:#6aa84f;stop-opacity:1" />
                  <stop offset="100%" style="stop-color:#38761d;stop-opacity:1" />
                </linearGradient>
                <linearGradient id="backgroundGradient" x1="0%" y1="0%" x2="0%" y2="100%">
                  <stop offset="0%" style="stop-color:#E0F2F7;stop-opacity:1" />
                  <stop offset="100%" style="stop-color:#E8F5E9;stop-opacity:1" />
                </linearGradient>
              </defs>

              <rect x="0" y="0" width="600" height="400" fill="url(#backgroundGradient)" />

              <text#{' '}
                x="300"#{' '}
                y="140"#{' '}
                font-family="Arial, sans-serif"#{' '}
                font-size="72"#{' '}
                font-weight="bold"
                text-anchor="middle"
                dominant-baseline="middle"
              >
                <tspan fill="url(#vivlioTextGradient)">filename.webp</tspan>
              </text>

              <text#{' '}
                x="300"#{' '}
                y="260"#{' '}
                font-family="Arial, sans-serif"#{' '}
                font-size="72"#{' '}
                font-weight="bold"
                text-anchor="middle"
                dominant-baseline="middle"
              >
                <tspan fill="url(#starterTextGradient)">No Image</tspan>
              </text>
            </svg>
          SVG

          module_function

          # Markdown 内の画像リンクを生成規約に合わせて正規化する
          def fix_image_paths(content, filename)
            chapter_dir = filename.sub(/\.md$/, '')

            lines = content.lines
            in_code_block = false

            transformed_lines = lines.each_with_index.map do |line, idx|
              line_number = idx + 1
              stripped = line.lstrip

              # フェンス付きコードブロック (``` ～ ``` ) 内はそのまま残す
              if stripped.start_with?('```')
                in_code_block = !in_code_block
                line
              elsif in_code_block
                line
              else
                line.gsub(%r{!\[(.*?)\]\((?!https?://)([^)]+)\)}) do
                  alt_text = ::Regexp.last_match(1)
                  image_path = ::Regexp.last_match(2)

                  # すでに images/ から始まる場合はそのまま。相対パスは images/<章ディレクトリ>/ に正規化
                  normalized = if image_path.start_with?('images/')
                                 image_path
                               else
                                 "images/#{chapter_dir}/#{image_path}"
                               end

                  # 生成物ポリシーに合わせて拡張子を .webp に寄せる（png/jpg のみ対象）
                  normalized = normalized.sub(/\.(png|jpe?g)\z/i, '.webp')

                  original_image_name = File.basename(image_path)
                  resolved_placeholder_or_path(alt_text, normalized, filename, line_number, original_image_name)
                end
              end
            end

            transformed_lines.join
          end

          # 既存画像なら元のパスを、無い場合はプレースホルダーを返す
          def resolved_placeholder_or_path(alt_text, normalized_path, source_filename = nil, line_number = nil, original_image_name = nil)
            return "![#{alt_text}](#{normalized_path})" if image_exists_for?(normalized_path)

            image_name = original_image_name || File.basename(normalized_path)

            if source_filename && line_number
              # 1行目: ファイル名と行番号、元の画像名、代替画像使用の案内
              # 先頭にスペースを入れて、⚠️ の後ろが常に2スペースになるように調整
              message = " #{source_filename}:#{line_number} - 画像 '#{image_name}' が見つかりません（代替画像を使用します）"
              Common.log_warn(message)

              # 2行目: 1行目の「画像」と同じ位置にそろえて、実際に参照した画像パスを表示
              indent_width = message.index('画像') || 0
              Common.log_warn("#{' ' * indent_width}画像の場所: #{normalized_path}")
            else
              # 位置情報が取れない場合のフォールバック
              Common.log_warn("画像 '#{image_name}' が見つかりません（代替画像を使用します）")
              Common.log_warn("画像の場所: #{normalized_path}")
            end

            placeholder_path = placeholder_image_path(normalized_path)
            "![#{alt_text}](#{placeholder_path})"
          end

          # 画像ディレクトリ内の拡張子違いを含めて存在を確認する
          def image_exists_for?(normalized_path)
            relative_path = normalized_path.sub(%r{\Aimages/}, '')
            base_path = File.expand_path(relative_path, Common::IMAGES_DIR)

            # SVGの場合は直接チェック
            if base_path.end_with?('.svg')
              return File.exist?(base_path)
            end

            # その他の画像形式は拡張子違いをチェック
            base_without_ext = base_path.sub(/\.webp\z/i, '')
            %w[.webp .png .jpg .jpeg].any? do |ext|
              File.exist?("#{base_without_ext}#{ext}")
            end
          end

          # プレースホルダーSVGを使用してデータURIを生成する
          def placeholder_image_path(missing_image_path = nil)
            return 'data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%2F%3E' unless missing_image_path

            begin
              filename = File.basename(missing_image_path)
              replacement = sanitize_placeholder_text(filename)
              svg_with_filename = NO_IMAGE_PLACEHOLDER_SVG.gsub('filename.webp', replacement)
              svg_to_data_uri(svg_with_filename)
            rescue StandardError => e
              Common.log_warn("プレースホルダー画像の生成に失敗しました: #{e.class}: #{e.message}")
              'data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%2F%3E'
            end
          end

          # プレースホルダーに差し込むファイル名をサニタイズする
          def sanitize_placeholder_text(filename)
            text = filename.to_s.strip
            text = 'missing image' if text.empty?
            CGI.escapeHTML(text)
          end

          # SVGコンテンツをURLエンコードした data URI に変換する
          def svg_to_data_uri(svg_content)
            escaped = CGI.escape(svg_content.encode('utf-8'))
            escaped = escaped.gsub('+', '%20')
            "data:image/svg+xml;charset=utf-8,#{escaped}"
          end
        end
      end
    end
  end
end
