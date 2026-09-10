# frozen_string_literal: true

require 'digest'
require 'fileutils'
require_relative '../pre_process/svg_font_embedder'
require_relative 'derived_image'

module VivlioStarter
  module CLI
    module Build
      # ------------------------------------------------
      # DerivedSvg: 著者の SVG 図版へ、PDF 用に書体を抱かせた複製を作る
      # ------------------------------------------------
      # `<img src="…svg">` は**独立文書**なので、本文 HTML の @font-face も CSS 変数も
      # 相対パスの外部フォントも届かない。`font-family` に何を書いても解決されず、
      # OS 既定の和文フォント（macOS なら Hiragino）へ落ちて、Chromium がそれを
      # **Type 3 フォント**として PDF へ埋め込む。Type 3 は技術書典等の入稿で不可。
      #
      # showcase / mermaid の生成 SVG は 2026-08-07 に `SvgFontEmbedder` で塞いだが、
      # **著者が `images/` へ置いた図版は素通りのままだった**。実測（2026-09-10・本書
      # 22 章の組み上がり PDF）では、`font-family: sans-serif` で組まれた図 1 枚だけで
      # `HiraKakuProN-W3` の Type 3 が 17 件出ていた。ここはその経路を塞ぐ。
      #
      # **素材には触れない。** 派生は `.cache/vs/derived/svg/` にだけ作り、各ターゲットが
      # ステージングした HTML だけがそこを指す（`image-format-per-target-spec.md` §3.1）。
      #
      # **PDF 専用ではない。** EPUB もこの派生をそのまま配る——`<img>` 参照の SVG が
      # 独立文書である事情はリーダーでも同じで、しかも EPUB は本文書体を埋め込まない
      # （`EpubBuilder#embed_fonts?` は false）ため、図が拠れる書体は図自身が持つものしかない。
      # ラスタライズして逃げる手は使えない。librsvg は data: URI の @font-face を読まず
      # （実測: 埋め込み前後の PNG がバイト一致）、**焼いた機械の OS 書体**が焼き付いて
      # 成果物が再現しなくなる。Kindle だけは KFX が SVG を扱えないので、そこで初めて焼く。
      #
      # 生成 SVG と違って、著者の図版は**何の書体を何面使うか決め打ちできない**。
      # 1 枚の中にゴシックのラベルと等幅の座標値が同居しうるし、太字も混ざる。
      # そこで図が名指ししている書体を集め、汎用名しか無いものは書籍の書体へ寄せる。
      #
      # 詳細と実測は `type3-font-embedding-notes.md`。
      # ------------------------------------------------
      module DerivedSvg
        Embedder = PreProcessCommands::SvgFontEmbedder

        # 派生の置き場。**ターゲットをまたいで共有する**——PDF も EPUB も同じ 1 枚を指す。
        # `DerivedImage` のラスタ派生が `derived/pdf/` に閉じているのは、あちらが PDF の
        # 都合（WebP を格納できない）で形式を変えるからで、こちらは形式を変えない。
        DERIVED_DIR = "#{DerivedImage::DERIVED_ROOT}/svg".freeze

        # 派生の版。書体の寄せ方を変えたら上げる（既存の派生を捨てさせるため）。
        SCHEMA = 'v1'

        # 作り直しの要否を見る目印。SVG は XML で、宣言より前には何も置けないので、
        # ファイル先頭ではなくルート（`<svg>`）の直下へ差し込む。
        MARKER_NAME = 'vs-svg-font'

        # 汎用ファミリ名。これしか無いスタックは書籍の書体へ寄せる。
        GENERIC_FAMILIES = %w[
          serif sans-serif monospace cursive fantasy system-ui
          ui-serif ui-sans-serif ui-monospace ui-rounded math emoji fangsong
        ].freeze

        # `<style>…</style>`（中は CSS）
        STYLE_BLOCK_RE = %r{(<style[^>]*>)(.*?)(</style>)}m
        # `style="…"`（中は CSS）
        STYLE_ATTR_RE = /(\bstyle\s*=\s*)(["'])(.*?)\2/
        # `font-family="…"`（プレゼンテーション属性。値はフォントスタックそのもの）
        FAMILY_ATTR_RE = /(\bfont-family\s*=\s*)(["'])(.*?)\2/
        # CSS の font-family 宣言 1 つ
        CSS_DECL_RE = /(font-family\s*:\s*)([^;}]+)/

        module_function

        # 素材群ぶんの派生をまとめて用意する。
        #
        # 文字を持たない SVG（純粋な図形）は対象に入らない——書体が要らないので
        # 素材のまま運べばよく、複製すればステージングが太るだけである。
        # @param sources [Array<String>] 素材パス
        # @return [Hash{String => String}] 素材パス => 派生パス（作れたものだけ）
        def prepare_all(sources)
          mapping = Array(sources).uniq.select { svg?(it) }.filter_map { |source|
            derived = prepare(source)
            [source, derived] if derived
          }.to_h
          Common.log_info("[stage] SVG に書体を埋め込みました: #{mapping.size} 件") unless mapping.empty?
          mapping
        end

        # 1 件ぶんの派生を用意し、派生パスを返す（要らない・作れないときは nil）。
        #
        # 失敗しても組版は止めない。素材のまま組まれ、Type 3 は残るが本は出る——
        # 生成 SVG 側と同じ倒れ方に揃えてある。
        def prepare(source)
          # --- Phase: 埋め込む必要があるか ---
          svg = File.read(source, encoding: 'utf-8')
          chars = Embedder.characters_in(svg)
          return nil if chars.empty?
          # 生成 SVG（showcase / mermaid）は既に自分で書体を抱えている。二重に埋めない。
          return nil if svg.include?('data:font/')

          # --- Phase: 使える派生があれば作り直さない ---
          dest = derived_path(source)
          marker = "<!--#{MARKER_NAME} #{fingerprint(svg)}-->"
          return dest if fresh?(dest, marker)

          # --- Phase: 書体を実体のあるものへ寄せ、その字だけを埋める ---
          rewritten, families = resolve_families(svg)
          default = default_family(svg)
          style = Embedder.font_faces_style(chars, families: families + [default], default_family: default)
          return nil unless style

          embedded = Embedder.inject(rewritten, "#{marker}#{style}")
          # `<svg>` が見つからず差し込めなかった（壊れた SVG）。素材のまま運ぶ。
          return nil if embedded == rewritten

          FileUtils.mkdir_p(File.dirname(dest))
          File.write(dest, embedded, encoding: 'utf-8')
          dest
        rescue StandardError => e
          Common.log_warn("SVG への書体埋め込みを見送りました（素材のまま組みます）: #{source} (#{e.message})")
          nil
        end

        # 図が名指ししている書体を、実体のあるものへ寄せる。
        #
        # 値の区切り方が場所によって違う——`<style>` の中と `style="…"` の中は CSS
        # （`;` や `}` で切れる）、`font-family="…"` はプレゼンテーション属性
        # （引用符で切れる）。同じ正規表現では両方を正しく取れないので別々に扱う。
        #
        # @return [Array(String, Array<String>)] 書き換え後の SVG と、埋め込むべき書体名
        def resolve_families(svg)
          used = []

          # 内側でも gsub を回すため、置換に使う値は**先に**取り出しておく
          # （後から Regexp.last_match を引くと内側のマッチに差し替わっている）。
          rewritten = svg.gsub(STYLE_BLOCK_RE) do
            open_tag, body, close_tag = Regexp.last_match.captures
            "#{open_tag}#{rewrite_css(body, used, quote: '"')}#{close_tag}"
          end

          rewritten = rewritten.gsub(STYLE_ATTR_RE) do
            prefix, delimiter, value = Regexp.last_match.captures
            "#{prefix}#{delimiter}#{rewrite_css(value, used, quote: other_quote(delimiter))}#{delimiter}"
          end

          rewritten = rewritten.gsub(FAMILY_ATTR_RE) do
            prefix, delimiter, stack = Regexp.last_match.captures
            "#{prefix}#{delimiter}#{preferred_stack(stack, used, quote: other_quote(delimiter))}#{delimiter}"
          end

          [rewritten, used.uniq]
        end

        # CSS の font-family 宣言をまとめて寄せる。
        def rewrite_css(text, used, quote:)
          text.gsub(CSS_DECL_RE) do
            prefix, stack = Regexp.last_match.captures
            "#{prefix}#{preferred_stack(stack, used, quote:)}"
          end
        end

        # フォントスタックの先頭を、実体のある書体にする。
        #
        # 著者が名指しした書体が手元にあるなら**並べ替えない**——意図した書体で組むのが
        # 正しく、こちらが差し出がましく先頭へ割り込む理由がない。寄せるのは、汎用名しか
        # 無いか、書いてある名前の実体がどこにも無いときだけである。
        def preferred_stack(stack, used, quote:)
          names = stack.split(',').map { it.strip.gsub(/\A["']|["']\z/, '') }.reject(&:empty?)
          named = names.find { !generic?(it) && !Embedder.face_paths(it).empty? }
          if named
            used << named
            return stack
          end

          fallback = book_font_for(names)
          return stack if Embedder.face_paths(fallback).empty?

          used << fallback
          "#{quoted(fallback, quote)}, #{stack.strip}"
        end

        # 汎用名から、書籍のどの書体へ寄せるかを決める。
        #
        # 判断がつかないものは見出し書体にする。図のラベルは本文の続きではなく見出しの側で、
        # showcase / mermaid も見出し書体で組んでいるため、図どうしで書体が揃う。
        def book_font_for(names)
          lower = names.map(&:downcase)
          return Embedder.configured_code_font if lower.any? { it.include?('monospace') }
          return Embedder.configured_body_font if lower.any? { it.end_with?('serif') && !it.include?('sans') }

          Embedder.configured_heading_font
        end

        # font-family の指定が無い字の受け皿。
        #
        # ルートの `<svg>` が font-family を持つ図では置かない——注入するのは CSS 規則で、
        # プレゼンテーション属性より強い。著者がルートに書いた指定を上書きしてしまう。
        def default_family(svg)
          svg[/<svg[^>]*>/].to_s.match?(/\bfont-family\s*=/) ? nil : Embedder.configured_heading_font
        end

        # CSS のファミリ名は識別子の並びなら引用符が要らない。引用符を足すのはそれで
        # 書けない名前だけで、属性の中では区切り記号と衝突しない側を選ぶ。
        def quoted(name, quote)
          name.match?(/\A[A-Za-z][A-Za-z0-9 ]*\z/) ? name : "#{quote}#{name}#{quote}"
        end

        def other_quote(delimiter) = delimiter == '"' ? "'" : '"'

        def generic?(name) = GENERIC_FAMILIES.include?(name.downcase)

        def svg?(path) = File.file?(path) && File.extname(path).casecmp?('.svg')

        # 素材のパス構造を派生側にも残す（`DerivedImage.derived_base` と同じ流儀）。
        # ハッシュ名にすると、どの図が効いているかを人が追えなくなる。
        def derived_path(source)
          relative = source.sub(%r{\A\./}, '').delete_prefix('/')
          File.join(DERIVED_DIR, relative)
        end

        # 作り直しの判定に使う指紋。
        #
        # 素材の中身だけでなく**書体の設定も鍵に入れる**。著者が `typography.*.font` を
        # 変えたのに古い書体を抱えた派生が残ると、直したはずの書体が紙面に出ないうえ、
        # 「対策が効いている」ように見えて検証まで歪む（notes §5.1 の showcase と同じ取りこぼし）。
        def fingerprint(svg)
          payload = [SCHEMA, svg, Embedder.configured_heading_font,
                     Embedder.configured_body_font, Embedder.configured_code_font].join('|')
          Digest::SHA256.hexdigest(payload)[0, 16]
        end

        # 目印はルート直下にあるので、先頭だけ読めば足りる。
        def fresh?(dest, marker)
          File.file?(dest) && File.binread(dest, 8192).to_s.include?(marker)
        end
      end
    end
  end
end
