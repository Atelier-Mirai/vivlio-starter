# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/svg_font_embedder.rb
# ================================================================
# 責務:
#   `<img>` から参照される合成 SVG に、その SVG が使う字だけを絞った
#   @font-face（data: URI）を持たせる。
#
# なぜ要るのか:
#   showcase / mermaid の生成 SVG はファイルへ書き出して `<img src="...svg">` で
#   参照する。これは**独立文書**なので、本文 HTML の @font-face も CSS 変数も届かず、
#   相対パスの外部フォントも読めない（実測で確認済み）。結果、指定した書体は解決されず
#   OS の既定和文フォント（macOS なら Hiragino）へフォールバックし、Chromium が
#   それを **Type 3 フォント**として PDF へ埋め込む。Type 3 は技術書典等の入稿で不可。
#
#   全章ビルドの実測（2026-08-07）では、`techbook: true` でも残っていた Type 3 の
#   全件がこの経路だった（showcase 14 件・mermaid 18 件）。
#
# なぜサブセットなのか:
#   和文フォントは 2〜4MB あり、丸ごと data: URI にすると SVG 1 枚が数 MB 太る。
#   図中に出る字だけに絞れば 8 文字で 3.3KB 程度に収まり、実質太らない。
#   サブセット化は ttfunk（Prawn 経由で既に入っている MIT ライブラリ）で行う。
#
# 使い分け:
#   - mermaid: SVG が書体名を名指ししているので、**同名**の @font-face を注げば解決する
#   - showcase: font-family が汎用名（sans-serif）なので、専用ファミリ名を別途与える
#
# 詳細と実測は `type3-font-embedding-notes.md`。
# ================================================================

require 'ttfunk'
require 'ttfunk/subset'
require_relative '../common'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 生成 SVG へサブセットフォントを埋め込むユーティリティ
      module SvgFontEmbedder
        module_function

        # SVG の <text> に現れる字を重複なく集める。
        # @param svg [String] SVG 全文
        # @return [Array<String>] 空白を除いた 1 文字の配列
        def characters_in(svg)
          svg.to_s.scan(%r{<text[^>]*>(.*?)</text>}m)
             .flatten.join.gsub(/<[^>]+>/, '')
             .then { unescape(it) }
             .chars.uniq.reject { it.match?(/\s/) }
        end

        # 指定した字だけを含む @font-face の <style> を組み立てる。
        # @param chars [Array<String>] 埋め込む字
        # @param family [String] CSS 上で名乗るファミリ名
        # @param font_path [String, nil] TTF の実体（省略時は書籍の見出し書体を解決）
        # @return [String, nil] <style> 要素。埋め込めないときは nil（呼び出し側は従来動作へ）
        def font_face_style(chars, family:, font_path: nil)
          return nil if chars.empty?

          data = subset(chars, font_path || heading_font_path)
          return nil unless data

          # 埋め込むのは 1 面だけ（ウェイト指定なし＝400 扱い）。図のラベルが太字を
          # 要求すると faux-bold が合成され Type 3 になるので、独立文書のここでも
          # 合成を止める。本文側の body ルールはこの SVG に届かない。
          %(<style>@font-face{font-family:"#{family}";) +
            %(src:url("data:font/ttf;base64,#{[data].pack('m0')}") format("truetype");}) +
            %(svg{font-synthesis-weight:none}</style>)
        end

        # 複数の書体ぶんの @font-face を持つ <style> を組み立てる。
        #
        # 著者が `images/` へ置いた図版は、生成 SVG と違って**何の書体を何面使うか
        # 決め打ちできない**——1 枚の中にゴシックのラベルと等幅の座標値が同居しうるし、
        # 太字も混ざる。そこで図が実際に名指ししている書体を集め、面ごとに埋める。
        #
        # @param chars [Array<String>] 埋め込む字
        # @param families [Array<String>] CSS 上で名乗るファミリ名
        # @param default_family [String, nil] font-family の指定が無い字の受け皿。
        #   独立文書では未指定＝ブラウザ既定（serif）＝OS フォントなので、ここを空けると
        #   指定を書き忘れた字だけが Type 3 で残る。
        # @return [String, nil] <style> 要素。1 面も埋め込めなければ nil
        def font_faces_style(chars, families:, default_family: nil)
          return nil if chars.empty?

          faces = Array(families).compact.uniq.flat_map { face_rules(chars, it) }
          return nil if faces.empty?

          # 合成禁止は独立文書にも要る。1 面しか埋まらなかった書体に太字を要求されると
          # faux-bold が合成され、それがまた Type 3 になる（notes §5.2）。
          base = if default_family
                   %(svg{font-family:"#{default_family}";font-synthesis-weight:none})
                 else
                   'svg{font-synthesis-weight:none}'
                 end
          "<style>#{faces.join}#{base}</style>"
        end

        # 書体 1 つぶんの @font-face 宣言（面ごとに 1 つ）。実体が無ければ空配列。
        def face_rules(chars, family)
          face_paths(family).filter_map do |weight, path|
            data = subset(chars, path)
            next unless data

            descriptor = weight ? "font-weight:#{weight};" : ''
            %(@font-face{font-family:"#{family}";#{descriptor}) +
              %(src:url("data:font/ttf;base64,#{[data].pack('m0')}") format("truetype");})
          end
        end

        # 書体 1 つぶんの、埋め込むべき字面。
        #
        # Regular と Bold が別ファイルで見つかったときは **400 と 700 を別々に埋める**。
        # 生成 SVG は 1 面で足りていた（ラベルの太さが揃っているため）が、著者の図版は
        # 本文と同じように太字を混ぜる。1 面しか渡さないと、合成が起きるか
        # `font-synthesis-weight:none` で止めた結果すべて細く出るかのどちらかになる。
        #
        # @return [Hash{Integer, nil => String}] ウェイト => TTF のパス（1 面なら鍵は nil）
        def face_paths(family)
          regular = font_path(family, weight: :regular)
          return {} unless regular

          bold = font_path(family, weight: :bold)
          regular == bold ? { nil => regular } : { 400 => regular, 700 => bold }
        end

        # SVG のルート直下へ <style> を差し込む。
        # @return [String] 差し込み済みの SVG（style が nil ならそのまま返す）
        def inject(svg, style)
          return svg if style.nil? || style.empty?

          svg.sub(/(<svg[^>]*>)/) { "#{::Regexp.last_match(1)}#{style}" }
        end

        # 書籍の見出し書体（太字優先）の実体。ディレクトリ名の規則は FontManager.slug_for と同じ。
        #
        # 置き場もファイル名も 2 通りある——同梱書体は `fonts/<slug>/` に
        # `*-Bold.ttf` / `*-Regular.ttf`、Google Fonts は `fonts/google/<slug>/` に
        # `<Slug>-700.ttf`（400 はウェイト無し）という FontManager#readable_filename_from の
        # 規則で置かれる。**両方を探すこと。** 同梱側しか見ないと、著者が Google Fonts の
        # 書体を指定した瞬間にサブセットを埋め込めず、SVG が OS の和文フォントへ落ちて
        # Type 3 が再発する（`type3-font-embedding-notes.md` §5）。
        # @return [String, nil]
        def heading_font_path = font_path(configured_heading_font, weight: :bold)

        # 本文書体の実体（数式の中の日本語に使う）。
        #
        # 見出し書体を埋めると、`面積 = √(s(s−a)…)` の「面積」だけ**周りの本文と違う書体**に
        # なる（本書なら本文が明朝・見出しがゴシック）。図のラベルは見出し相当でよいが、
        # 数式の中の日本語は本文の続きなので、本文書体・Regular を埋める。
        # @return [String, nil]
        def body_font_path = font_path(configured_body_font, weight: :regular)

        # 書体名から TTF の実体を探す。置き場もファイル名の規則も同梱と Google で違う（notes §5.1）。
        def font_path(name, weight:)
          dir = bundled_font_dir(name)
          (dir && bundled_font_path(dir, weight)) ||
            google_font_path(File.join(Common.stylesheets_dir, 'fonts', 'google', slug_for(name)), weight)
        end

        # 同梱書体の置き場。**slug と一致するとは限らない。**
        #
        # `HackGen35 Console NF` は `fonts/hackgen35/` に置かれている——page-settings.css の
        # @font-face が実ファイルを直に指しているだけで、Google Fonts 側の slug 規則には
        # 従っていないためである。slug で引けなければ中身のファイル名から引き当てる。
        # ここを外すとコード書体だけサブセットを作れず、等幅で組んだ図が OS フォントへ
        # 落ちて Type 3 が残る。
        # @return [String, nil]
        def bundled_font_dir(name)
          root = File.join(Common.stylesheets_dir, 'fonts')
          by_slug = File.join(root, slug_for(name))
          return by_slug if Dir.exist?(by_slug)

          key = comparable(name)
          Dir.glob(File.join(root, '*')).find do |dir|
            next false unless File.directory?(dir) && File.basename(dir) != 'google'

            comparable(File.basename(dir)) == key || bundled_faces_named?(dir, key)
          end
        end

        # ディレクトリの中に、その書体名の字面が入っているか。
        # ファイル名は `ZenKakuGothicNew-Bold.ttf` のように「詰めた書体名 + 字面」なので、
        # 末尾の字面を落として突き合わせる。
        def bundled_faces_named?(dir, key)
          Dir.glob(File.join(dir, '*.ttf')).any? do |file|
            comparable(File.basename(file, '.ttf').sub(/-[^-]*\z/, '')) == key
          end
        end

        # 書体名の比較用の形（大小・空白・記号の違いを潰す）。
        def comparable(name) = name.to_s.downcase.gsub(/[^a-z0-9]/, '')

        # Google Fonts の置き場に使うディレクトリ名（FontManager.slug_for と同じ規則）。
        def slug_for(name) = name.to_s.gsub(/[^A-Za-z0-9]+/, '_')

        # 同梱書体: 求める字面があればそれ、無ければ辞書順で最初の 1 本。
        def bundled_font_path(dir, weight = :bold)
          preferred = weight == :bold ? '*Bold.ttf' : '*Regular.ttf'
          Dir.glob(File.join(dir, preferred)).first || Dir.glob(File.join(dir, '*.ttf')).min
        end

        # Google Fonts: 太さはファイル名末尾のウェイト数値で表される（400 は数値なし＝0 扱い）。
        # 見出し相当は最も太い面、本文相当は最も細い面を選ぶ。
        def google_font_path(dir, weight = :bold)
          files = Dir.glob(File.join(dir, '*.ttf'))
          return nil if files.empty?

          files.public_send(weight == :bold ? :max_by : :min_by) do |file|
            File.basename(file)[/-(\d{3})\.ttf\z/, 1].to_i
          end
        end

        # book.yml の見出し書体名（未設定・プロジェクト外では同梱既定）。
        def configured_heading_font
          name = Common.configured? ? Common::CONFIG.typography.heading.font.to_s.strip : ''
          name.empty? ? DEFAULT_FONT : name
        end

        # book.yml の本文書体名（未設定・プロジェクト外では同梱既定）。
        def configured_body_font
          name = Common.configured? ? Common::CONFIG.typography.body.font.to_s.strip : ''
          name.empty? ? DEFAULT_BODY_FONT : name
        end

        # book.yml のコード書体名（未設定・プロジェクト外では同梱既定）。
        # 図の中の等幅——座標値・コマンド名・キー表記——の受け皿になる。
        def configured_code_font
          name = Common.configured? ? Common::CONFIG.typography.code.font.to_s.strip : ''
          name.empty? ? DEFAULT_CODE_FONT : name
        end

        DEFAULT_FONT = 'Zen Kaku Gothic New'
        DEFAULT_BODY_FONT = 'Zen Old Mincho'
        DEFAULT_CODE_FONT = 'HackGen35 Console NF'

        # 指定の字だけを含む TTF を作る。フォントが読めない場合は nil。
        def subset(chars, path)
          return nil unless path && File.file?(path)

          subset = TTFunk::Subset.for(TTFunk::File.open(path), :unicode)
          chars.each { subset.use(it.ord) }
          subset.encode
        rescue StandardError => e
          Common.log_debug("[svg-font] サブセットを作れませんでした: #{path} (#{e.message})")
          nil
        end

        # SVG のテキストノードに現れる実体参照を戻す（サブセットの対象文字を取り違えないため）。
        def unescape(text)
          text.gsub('&lt;', '<').gsub('&gt;', '>').gsub('&quot;', '"')
              .gsub('&#39;', "'").gsub('&amp;', '&')
        end
      end
    end
  end
end
