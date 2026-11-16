# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/targets/epub.rb
# ================================================================
# 責務:
#   出力先の宣言: EPUB（Kobo・Apple Books 向けのクリーンな EPUB）
# ================================================================

require_relative '../output_target'
require_relative '../transforms/shared/mark_body'
require_relative '../transforms/shared/strip_inline_footnote_ids'
require_relative '../transforms/shared/rewrite_table_align'
require_relative '../transforms/shared/restore_plain_emoji'
require_relative '../transforms/shared/inject_heading_images'
require_relative '../transforms/shared/localize_showcase_images'
require_relative '../transforms/shared/shrink_side_by_side_figures'
require_relative '../transforms/shared/convert_code_blocks'
require_relative '../transforms/shared/decorate_footnotes'
require_relative '../transforms/shared/post_process_index_glossary'
require_relative '../finalizers/author_priority'
require_relative '../finalizers/inversion_report'

module VivlioStarter
  module CLI
    module Build
      # EPUB と Kindle の両方で走る変換の並び（XHTML として妥当にするための最小の処理）。
      # Kindle の宣言（targets/kindle.rb）は、この並びの後ろに Kindle だけの段を足す。
      SHARED_EPUB_TRANSFORMS = [
        # EPUB のリフローの文脈の印 vs-epub を全部の body に付ける。
        # クリーン EPUB のコードの折り返しなど、PDF を壊さず EPUB だけに効かせる体裁の足場
        Transforms::Shared::MarkBody,
        # 段落内脚注の span の、重複する id を外す（XHTML の id の重複の ERROR を避ける）
        Transforms::Shared::StripInlineFootnoteIds,
        # 表の align 属性を style へ移す（XHTML5 で廃止された属性の ERROR を避ける）
        Transforms::Shared::RewriteTableAlign,
        # 絵文字の画像を、元の絵文字の字へ戻す（EPUB は Type 3 に当たらない。twemoji を同梱せず軽くする）
        Transforms::Shared::RestorePlainEmoji,
        # 扉絵（h1）・節絵（h2）の合成画像を入れる。クリーンは高画質の SVG、Kindle は JPEG
        Transforms::Shared::InjectHeadingImages,
        # 図解注釈（showcase）の参照を SVG から PNG へ差し替える（EPUB は SVG の中の base64 を運べない）
        Transforms::Shared::LocalizeShowcaseImages,
        # 左右に並べる囲み（side-by-side）は上下に積むので、中の図を PDF の片側の幅に抑える
        Transforms::Shared::ShrinkSideBySideFigures,
        # Prism の行番号付きの pre を「1 論理行 = 1 ブロック＋ぶら下げインデント」へ変換する（F 案・
        # epub-code-line-numbers-spec §2.1）。長い行の折り返しでの番号のずれ（クリーン EPUB）と
        # 表のセルに起因する崩れ（Kindle）を同じ構造で解消するため、両方で行う
        Transforms::Shared::ConvertCodeBlocks,
        # 脚注に、番号を実体の字で入れる
        Transforms::Shared::DecorateFootnotes,
        # 索引・用語集を EPUB 用に書き換える（空のリンクに章の短い名前を入れる）。
        # 両方で走る段の最後に置く。この段は「参照先の id が EPUB に実在するか」を照合して
        # 切れたリンクを解除する（RSC-012 の恒常対策）ので、id を消しうる処理が全部終わった後の
        # DOM を見なければならない。以前は先頭に置いており、後から走る InjectHeadingImages が
        # 見出しの中身を合成画像へ差し替えた時点でアンカーが消え、照合をすり抜けた切れたリンクが
        # そのまま残っていた（実測 102 件）
        Transforms::Shared::PostProcessIndexGlossary
      ].freeze

      # クリーンな EPUB。::before の角タブ・var() のテーマ色・WebP を保った、劣化させない EPUB。
      # 層を外した CSS はどのリーダーでも同じに読まれるので、Kindle と同じく平らな CSS を渡す。
      OutputTarget.register(
        OutputTarget.new(
          id: :epub,
          branch: :epub,
          workspace: Common::BUILD_EPUB_DIR,
          body_classes: [Transforms::Shared::MarkBody::BODY_CLASS],
          transforms: SHARED_EPUB_TRANSFORMS,
          css_form: :flat,
          finalizers: [
            # custom.css の宣言を、平らな CSS でも PDF と同じに勝たせる
            Finalizers::AuthorPriority,
            # 層を外すと勝ち負けが変わる組を --log=debug で一覧にする（書き直した後の CSS を見る）
            Finalizers::InversionReport
          ],
          assets: OutputTarget::Assets.new(images: :webp, svg: true),
          packager: :vivliostyle_epub
        )
      )
    end
  end
end
