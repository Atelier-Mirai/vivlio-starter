# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/talk_avatar_generator.rb
# ================================================================
# 責務:
#   会話文の「簡易アバター」（話者色を地に、表示名の頭 1 文字を白抜き）を
#   自動生成する（talk-auto-avatar-spec.md §2）。話者の initial: で 1〜2 文字を
#   指定されたら、その字を円に収まる大きさで描く（talk-avatar-initial-spec.md）。
#
# なぜ必要か:
#   アバターの絵を用意すること自体が執筆の障壁になりやすい。単色地＋1 文字でも
#   話者の識別という目的には十分機能する（PDF 実測で確認）。画像が用意できたら
#   `avatar: haruka.webp` へ差し替えればよい。
#
# フォント:
#   同梱の Noto Sans JP Bold（見出しの既定書体）を使う。CJK もラテンも描画でき、
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

        # 1 文字を中央に置くときの文字サイズ。2 文字のときもこれを上限にする。
        POINTSIZE = 200

        # 2 文字を収める箱（一辺 EDGE の画像の中央）。角が中心から約 168px で、
        # 丸抜きの半径 200px の内側に縁の太さぶんの余白を残す。
        # 試作（2026-10-11）で、漢字 2 字が 136〜138pt・欧字 2 字が 200pt になり、
        # どれも欠けず余白がそろうことを確かめた幅と高さ。
        FIT_WIDTH = 270
        FIT_HEIGHT = 200

        # 同梱フォント（stylesheets/ からの相対）。
        FONT_REL = 'fonts/Noto_Sans_JP/NotoSansJP-Bold.ttf'

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

          unless tools.available?
            warn_tools_missing(source_filename)
            return nil
          end

          background = background_hex(char)
          foreground = foreground_hex(background)
          pointsize = fit_pointsize(glyph, tools)
          key = cache_key(glyph, background, foreground, pointsize)

          out_dir = File.join(Common::BUILD_HTML_DIR, 'images', REL_BASE)
          return nil unless write_asset!(key, out_dir, glyph:, background:, foreground:, pointsize:, tools:)

          "images/#{REL_BASE}/#{key}.webp"
        end

        # 生成物をワークスペースへ用意する（永続キャッシュ経由）。
        # @return [Boolean] 参照可能な生成物が揃ったか
        def write_asset!(key, out_dir, glyph:, background:, foreground:, pointsize:, tools:)
          GeneratedAssetCache.fetch(REL_BASE, ["#{key}.webp"], out_dir:) do |cache_dir|
            tools.render(File.join(cache_dir, "#{key}.webp"),
                         glyph:, background:, foreground:, pointsize:, font: font_path)
          end
        end

        # アバターに入れる字。initial: があればそれ（1〜2 文字・TalkRegistry で確かめ済み）、
        # 無ければ表示名の 1 文字目。書記素クラスタ単位で取るため、絵文字や結合文字を割らない。
        def avatar_glyph(char)
          return char.initial if char&.initial

          (char&.name.to_s.strip.grapheme_clusters.first || '').to_s
        end

        # 字の大きさ。1 文字はこれまでどおり POINTSIZE で描き、測らない（見た目もキャッシュも変えない）。
        # 2 文字は POINTSIZE で一度測り、FIT_WIDTH × FIT_HEIGHT に収まるよう比例で縮める。
        # 字の寸法は大きさにほぼ比例するので、測るのは 1 回で足りる。漢字と欧字で適した
        # 大きさが違う（漢字 2 字は 200pt で円からはみ出し、欧字 2 字は 200pt で収まる）ため、
        # 決め打ちにせず実際の字の幅から決める（talk-avatar-initial-spec.md §2.2）。
        def fit_pointsize(glyph, tools)
          return POINTSIZE if glyph.grapheme_clusters.size == 1

          width, height = tools.measure(glyph, pointsize: POINTSIZE, font: font_path)
          return POINTSIZE unless width&.positive? && height&.positive?

          scale = [FIT_WIDTH.fdiv(width), FIT_HEIGHT.fdiv(height), 1.0].min
          (POINTSIZE * scale).floor
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
        # 1 文字の大きさは POINTSIZE なので、キーは字を指定できるようになる前と変わらない
        # （既存のキャッシュをそのまま使える）。
        def cache_key(glyph, background, foreground, pointsize = POINTSIZE)
          payload = ['v1', glyph, background, foreground, EDGE, pointsize, FONT_REL].join('|')
          Digest::SHA256.hexdigest(payload)[0, 16]
        end

        # 同梱フォントの実体パス。
        def font_path = File.join(Common.stylesheets_dir, FONT_REL)

        def default_tools = (@default_tools ||= AvatarTools.new)

        # -annotate へ渡す字を逃がす。ImageMagick は頭の @ をファイル名として読んで中身を描き、
        # % を画像の情報の書式（%w は幅）として置き換え、\ で次の字を逃がす。著者が initial: で
        # 字を選べるので、どの字もそのとおり描かれるよう、\ → \\、% → %%、頭の @ → \@ にする
        # （talk-avatar-initial-spec.md §2.3）。
        def magick_text(text) = text.gsub('\\') { '\\\\' }.gsub('%', '%%').sub(/\A@/) { '\\@' }

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

          # 単色地に字を中央配置した正方形画像を書き出す。
          # @return [Boolean] 生成できたか
          def render(path, glyph:, background:, foreground:, pointsize:, font:)
            args = ['magick', '-size', "#{EDGE}x#{EDGE}", "xc:#{background}",
                    '-gravity', 'center', '-fill', foreground]
            args += ['-font', font] if File.exist?(font)
            args += ['-pointsize', pointsize.to_s, '-annotate', '0', TalkAvatarGenerator.magick_text(glyph), path]
            system(*args, out: File::NULL, err: File::NULL) && File.exist?(path)
          rescue StandardError
            false
          end

          # 透明な広い下地に字を描き、余白を削った寸法を測る。
          # @return [Array(Integer, Integer), nil] 幅と高さ（測れなければ nil）
          def measure(glyph, pointsize:, font:)
            args = ['magick', '-size', "#{EDGE * 3}x#{EDGE * 2}", 'xc:none', '-gravity', 'center', '-fill', 'black']
            args += ['-font', font] if File.exist?(font)
            args += ['-pointsize', pointsize.to_s, '-annotate', '0', TalkAvatarGenerator.magick_text(glyph),
                     '-trim', '-format', '%w %h', 'info:']
            out, status = Open3.capture2(*args, err: File::NULL)
            status.success? ? out.split.map(&:to_i) : nil
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
