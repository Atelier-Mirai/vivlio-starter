# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/talk_avatar_generator.rb
# ================================================================
# 責務:
#   会話文の「簡易アバター」（話者色を地に、表示名の頭 1 文字を白抜き）を
#   自動生成する（talk-auto-avatar-spec.md §2）。
#
# なぜ必要か:
#   アバターの絵を用意すること自体が執筆の障壁になりやすい。単色地＋1 文字でも
#   話者の識別という目的には十分機能する（PDF 実測で確認）。画像が用意できたら
#   `avatar: haruka.webp` へ差し替えればよい。
#
# フォント:
#   同梱の Zen Kaku Gothic New Bold を使う。CJK もラテンも描画できることを実測済みで、
#   gem/雛形に同梱されているため環境差で欠けない。本文フォント設定には追従しない
#   （システムフォント指定時に実体パスを解決できず破綻するため・§5 未決）。
#
# 生成物の扱い:
#   これは**ビルド生成物**であり著者資産ではない。数式 SVG・showcase・mermaid と同じく
#   ワークスペース（BUILD_HTML_DIR/images/）へ出し、参照は消費者 dir 相対
#   （asset_prefix を付けない）。GeneratedAssetCache で内容アドレス永続キャッシュする。
#
# 縮退:
#   magick 不在時は 🟡 を出してアバターなしへ落とす（ビルドは止めない）。
# ================================================================

require 'digest'
require 'open3'
require_relative '../common'
require_relative '../theme_color'
require_relative 'generated_asset_cache'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 簡易アバターの自動生成
      module TalkAvatarGenerator
        # 生成物の出力先サブディレクトリ（images/ 配下）。
        REL_BASE = 'talk-avatars'

        # 生成画像の一辺（px）。表示は 12mm 程度なので印刷解像度に対して十分な余裕がある。
        EDGE = 400

        # 1 文字を中央に置くときの文字サイズ。
        POINTSIZE = 200

        # 同梱フォント（stylesheets/ からの相対）。
        FONT_REL = 'fonts/Zen_Kaku_Gothic_New/ZenKakuGothicNew-Bold.ttf'

        # 地色がこれより明るければ文字を濃色にする（WCAG 相対輝度）。
        # yellow(#f0a000)=0.47 / lime(#65a30d)=0.30 / purple(#7c3aed)=0.14 の実測から、
        # 白抜きが苦しくなる手前の 0.45 を境にする。
        LIGHT_BG_THRESHOLD = 0.45

        LIGHT_TEXT = '#ffffff'
        DARK_TEXT  = '#333333'

        module_function

        # 話者の簡易アバターを生成し、章 HTML から参照するパスを返す。
        # @param char [TalkRegistry::Character] 話者（name と color を使う）
        # @param source_filename [String] 警告に添える原稿ファイル名
        # @param tools [#available?, #render] 外部ツール（テスト差し替え用）
        # @return [String, nil] 参照パス（生成できなければ nil）
        def generate(char, source_filename:, tools: default_tools)
          glyph = avatar_glyph(char)
          return nil if glyph.empty?

          background = background_hex(char)
          foreground = foreground_hex(background)
          key = cache_key(glyph, background, foreground)

          unless tools.available?
            warn_tools_missing(source_filename)
            return nil
          end

          out_dir = File.join(Common::BUILD_HTML_DIR, 'images', REL_BASE)
          return nil unless write_asset!(key, out_dir, glyph:, background:, foreground:, tools:)

          "images/#{REL_BASE}/#{key}.webp"
        end

        # 生成物をワークスペースへ用意する（永続キャッシュ経由）。
        # @return [Boolean] 参照可能な生成物が揃ったか
        def write_asset!(key, out_dir, glyph:, background:, foreground:, tools:)
          GeneratedAssetCache.fetch(REL_BASE, ["#{key}.webp"], out_dir:) do |cache_dir|
            tools.render(File.join(cache_dir, "#{key}.webp"),
                         glyph:, background:, foreground:, font: font_path)
          end
        end

        # 表示名の 1 文字目。書記素クラスタ単位で取るため、絵文字や結合文字を割らない。
        def avatar_glyph(char)
          (char&.name.to_s.strip.grapheme_clusters.first || '').to_s
        end

        # 地色。話者の color 未指定なら本のテーマ色を使う（PDF の --talk-accent 既定と一致）。
        def background_hex(char)
          raw = char&.color
          return ThemeColor.to_hex6(raw) unless raw.to_s.strip.empty?

          theme_hex
        end

        # 本のテーマ色（未設定・プロジェクト外では ThemeColor の既定）。
        def theme_hex
          raw = Common.configured? ? Common::CONFIG.theme.color : nil
          ThemeColor.to_hex6(raw)
        end

        # 地色に載せて読める文字色を選ぶ（明るい地には濃色、暗い地には白）。
        def foreground_hex(background)
          ThemeColor.luminance(background) > LIGHT_BG_THRESHOLD ? DARK_TEXT : LIGHT_TEXT
        end

        # 内容アドレス。文字・色・寸法・フォントが同じなら再生成しない。
        def cache_key(glyph, background, foreground)
          payload = ['v1', glyph, background, foreground, EDGE, POINTSIZE, FONT_REL].join('|')
          Digest::SHA256.hexdigest(payload)[0, 16]
        end

        # 同梱フォントの実体パス。
        def font_path = File.join(Common.stylesheets_dir, FONT_REL)

        def default_tools = (@default_tools ||= AvatarTools.new)

        def warn_tools_missing(source_filename)
          Common.log_warn(
            "[talk] #{source_filename}: ImageMagick が見つからないため簡易アバターを生成できません。" \
            'アバターなしで表示します',
            detail: '→ `vs doctor --fix` で導入できます（brew install imagemagick）'
          )
        end

        # 外部ツール依存をこのクラスへ隔離する（生成ロジックは純粋なまま保つ）。
        class AvatarTools
          def available?
            return @available unless @available.nil?

            @available = system('magick', '-version', out: File::NULL, err: File::NULL) || false
          end

          # 単色地に 1 文字を中央配置した正方形画像を書き出す。
          # @return [Boolean] 生成できたか
          def render(path, glyph:, background:, foreground:, font:)
            args = ['magick', '-size', "#{EDGE}x#{EDGE}", "xc:#{background}",
                    '-gravity', 'center', '-fill', foreground]
            args += ['-font', font] if File.exist?(font)
            args += ['-pointsize', POINTSIZE.to_s, '-annotate', '0', glyph, path]
            system(*args, out: File::NULL, err: File::NULL) && File.exist?(path)
          rescue StandardError
            false
          end
        end
      end
    end
  end
end
