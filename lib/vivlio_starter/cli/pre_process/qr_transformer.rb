# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/qr_transformer.rb
# ================================================================
# 責務:
#   本文中の `@qr:URL` を QR コードの SVG 画像（ビルド生成物）へ変換する
#   （at-directive-tier1-spec.md §2.5）。
#
# なぜ前処理なのか:
#   置換に画像ファイルの生成が伴うため、ReplacementRules（純粋な文字列置換）では
#   担えない。数式 SVG（math_transformer）と同じ「ビルド生成物」ファミリーとして
#   前処理の独立ステップに置く。
#
# 出力と参照:
#   実体は BUILD_HTML_DIR/images/qr/<hash>.svg、参照は images/qr/<hash>.svg
#   （asset_prefix なし＝消費者 dir 相対。数式 SVG と同形）。
#   BUILD_HTML_DIR/images/ 配下は PDF ミラー・EPUB/Kindle 同梱が丸ごと拾うため、
#   消費側の改修は不要。URL の内容ハッシュを名前にするので、同一 URL は全章で
#   1 ファイルを共有し、再ビルドでも再生成しない（冪等）。
#
# 寸法（vivliostyle-css-pitfalls-notes.md の既知の罠）:
#   rqrcode の as_svg は width/height と viewBox の**どちらか一方**しか出さない。
#   intrinsic size（width/height）が無いと Vivliostyle/EPUB で寸法が崩れ、viewBox が
#   無いと CSS 側の .vs-qr { width: 18mm } で拡縮できない。よって width/height 付きで
#   生成したうえで、同値の viewBox を後から補い両方を備えた SVG にする。
#
# 縮退:
#   rqrcode が無い / 生成に失敗した場合は本文を変えず `@qr:URL` のまま残し、
#   出現位置つきで著者に警告する（[[warning-messages-actionable]]）。
# ================================================================

require 'cgi'
require 'digest'
require 'fileutils'
require_relative '../common'
require_relative '../masking'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # @qr:URL を QR コード SVG の <img> へ変換するモジュール。
      module QrTransformer
        module_function

        # 生成物の出力先（images/ 配下）。
        REL_BASE = 'qr'

        # `@qr:` に続く URL。空白か `)` の手前まで（§1.4）。
        QR_PATTERN = %r{@qr:(https?://[^\s)]+)}

        # QR の 1 モジュール（黒白の 1 マス）の辺長 px。印刷 18mm 角でも読み取れる解像度。
        MODULE_SIZE = 4

        # インラインコード退避用の番兵（本文に現れない NUL 文字）。
        MASK = 0.chr

        # 本文中の @qr:URL をすべて <img class="vs-qr"> へ置換する。
        #
        # @param content [String] 処理対象の Markdown 本文
        # @param source_filename [String] 警告に出す原稿ファイル名
        # @return [String] 置換後の本文（生成不能時は当該箇所を原文のまま残す）
        def transform(content, source_filename:)
          return content unless content.include?('@qr:')
          return warn_gem_missing(content, source_filename) unless available?

          out_dir = File.join(Common::BUILD_HTML_DIR, 'images', REL_BASE)
          replace_in_prose(content) do |line, lineno|
            line.gsub(QR_PATTERN) do
              url = Regexp.last_match(1)
              render_one(url, out_dir) || warn_render_failed(source_filename, lineno, url)
            end
          end
        end

        # コード（フェンス・インラインコード）を避けて各プローズ行を書き換える。
        # Masking.each_prose_line はフェンスだけを判定するため、インラインコード内の
        # 例示（`@qr:https://…`）はここで退避してから戻す。
        def replace_in_prose(content)
          lines = content.lines
          Masking.each_prose_line(content) do |line, lineno|
            spans = []
            masked = line.gsub(/`[^`\n]+`/) do
              spans << Regexp.last_match(0)
              "#{MASK}QR#{spans.size - 1}#{MASK}"
            end
            replaced = yield(masked, lineno)
            lines[lineno - 1] = replaced.gsub(/#{MASK}QR(\d+)#{MASK}/) { spans[Regexp.last_match(1).to_i] }
          end
          lines.join
        end

        # URL 1 件を SVG 化して <img> タグ文字列を返す。生成できなければ nil。
        def render_one(url, out_dir)
          name = "#{Digest::SHA1.hexdigest(url)[0, 12]}.svg"
          path = File.join(out_dir, name)

          unless File.exist?(path)
            svg = build_svg(url)
            return nil unless svg

            FileUtils.mkdir_p(out_dir)
            File.write(path, svg, encoding: 'utf-8')
          end

          %(<img class="vs-qr" src="images/#{REL_BASE}/#{name}" alt="#{CGI.escapeHTML(url)}">)
        end

        # rqrcode で SVG 本体を組み立て、intrinsic size と viewBox の両方を備えさせる。
        def build_svg(url)
          svg = RQRCode::QRCode.new(url).as_svg(use_path: true, module_size: MODULE_SIZE, viewbox: false)
          ensure_viewbox(svg)
        rescue StandardError => e
          Common.log_debug("[qr] SVG 生成に失敗: #{url} - #{e.message}")
          nil
        end

        # width/height しか持たない SVG に同値の viewBox を補う（既にあればそのまま）。
        def ensure_viewbox(svg)
          return svg if svg.nil? || svg.include?('viewBox=')

          width  = svg[/<svg[^>]*\bwidth="([\d.]+)"/, 1]
          height = svg[/<svg[^>]*\bheight="([\d.]+)"/, 1]
          return svg unless width && height

          svg.sub(/<svg\b/, %(<svg viewBox="0 0 #{width} #{height}"))
        end

        # rqrcode が使えるか（gem 未導入の環境でもビルドは止めない）。
        def available?
          return @available unless @available.nil?

          @available = begin
            require 'rqrcode'
            true
          rescue LoadError
            false
          end
        end

        # --- 警告（出現位置つき・修正案つき） ---

        def warn_gem_missing(content, source_filename)
          Common.log_warn(
            "[qr] #{source_filename}: rqrcode が無いため @qr:URL を QR コードにできません（記法のまま出力します）",
            detail: '→ `bundle install`（または `gem install rqrcode`）で導入できます。'
          )
          content
        end

        def warn_render_failed(source_filename, lineno, url)
          Common.log_warn(
            "[qr] #{source_filename}:#{lineno} - QR コードを生成できませんでした（記法のまま残します）",
            detail: "URL: #{url}\n→ URL が長すぎないか・不正な文字を含まないか確認してください。"
          )
          "@qr:#{url}"
        end
      end
    end
  end
end
