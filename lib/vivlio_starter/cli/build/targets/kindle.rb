# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/targets/kindle.rb
# ================================================================
# 責務:
#   出力先の宣言: Kindle（Amazon 向け。中間の EPUB を KPF へ変換する）
# ================================================================

require_relative '../output_target'
require_relative 'epub'
require_relative '../transforms/kindle/decorate_talk'
require_relative '../transforms/kindle/transcode_webp_images'
require_relative '../transforms/kindle/strip_webp_inline_styles'
require_relative '../transforms/kindle/mark_body'
require_relative '../transforms/kindle/restore_h3_markers'
require_relative '../transforms/kindle/constrain_layout_images'
require_relative '../transforms/kindle/compose_pictures'
require_relative '../transforms/kindle/textify_simple_math'
require_relative '../transforms/kindle/rasterize_display_math'
require_relative '../transforms/kindle/convert_math_units'
require_relative '../transforms/kindle/keep_cell_math_inline'
require_relative '../transforms/kindle/align_code_cells'
require_relative '../transforms/kindle/inject_code_line_numbers'
require_relative '../transforms/kindle/decorate_admonitions'
require_relative '../transforms/kindle/decorate_list_markers'
require_relative '../transforms/kindle/layout_index_columns'
require_relative '../transforms/kindle/replace_rotate_tables'
require_relative '../finalizers/author_priority'
require_relative '../finalizers/variant_glyph_fonts'
require_relative '../finalizers/inversion_report'

module VivlioStarter
  module CLI
    module Build
      # Kindle だけで走る変換の並び。
      # Kindle（KFX）は WebP・CSS Grid・position: absolute・外部の CSS の画像の大きさを解さず、
      # ::before の内容も出さない。そこで body.vs-kindle の印の下で、WebP → JPEG・画像の style 属性での
      # 制約・数式の px 化・コードの行番号やラベルの実体の字での注入を行う。クリーンな EPUB には
      # どれも当てない。
      # CSS で済むもの（book-card・img-text の画像の上限など）は stylesheets/targets/kindle*.css に置き、
      # ここには要素の書き換えが要るものだけを並べる（epub-kindle-layout-spec.md）。
      KINDLE_TRANSFORMS = [
        # 会話文のアイコンの <img> を外すのは、WebP の変換より先に行う（外される画像を
        # 変換して、使わない _epub_assets を作らないため）
        Transforms::Kindle::DecorateTalk,
        # 残った <img> の WebP を JPEG・PNG へ変換する（<img> の出入りが決まった後＝扉絵・絵文字の処理の後）
        Transforms::Kindle::TranscodeWebpImages,
        # インラインの <style> の中の WebP の url()（Techbook の Type 3 対策の印）を外す（RSC-007 を避ける）
        Transforms::Kindle::StripWebpInlineStyles,
        Transforms::Kindle::MarkBody,
        Transforms::Kindle::RestoreH3Markers,
        Transforms::Kindle::ConstrainLayoutImages,
        Transforms::Kindle::ComposePictures,
        # 単純なインライン数式を先に字へ直す（字の大きさに従う）。残った複雑な式には、
        # 後の ConvertMathUnits が px の予備を効かせる（この順が要点）
        Transforms::Kindle::TextifySimpleMath,
        # ディスプレイ数式は PNG で送る（字へ直さない）。Σ・∫ を含む大きな式を独立した行に組むのが
        # ディスプレイ数式の意図なので、組版を保つ。ConvertMathUnits より前に置き、差し替えた
        # <img> にも px の予備が効くようにする
        Transforms::Kindle::RasterizeDisplayMath,
        Transforms::Kindle::ConvertMathUnits,
        Transforms::Kindle::KeepCellMathInline,
        Transforms::Kindle::AlignCodeCells,
        Transforms::Kindle::InjectCodeLineNumbers,
        Transforms::Kindle::DecorateAdmonitions,
        Transforms::Kindle::DecorateListMarkers,
        Transforms::Kindle::LayoutIndexColumns,
        # 回転した表を PDF のページの画像へ差し替える（KFX は transform も position: absolute も
        # 解さない）。PDF の枝の成果物を待つ点だけが、ほかの段と違う
        Transforms::Kindle::ReplaceRotateTables
      ].freeze

      # Kindle。EPUB と同じ変換の後ろに Kindle だけの段を足し、CSS は値に解いた平らな形で渡す
      # （KFX は @layer の囲みを中身ごと捨て、var()・calc() の宣言も捨てる）。
      OutputTarget.register(
        OutputTarget.new(
          id: :kindle,
          branch: :epub,
          workspace: Common::BUILD_KINDLE_DIR,
          body_classes: [Transforms::Shared::MarkBody::BODY_CLASS, Transforms::Kindle::MarkBody::BODY_CLASS],
          transforms: [*SHARED_EPUB_TRANSFORMS, *KINDLE_TRANSFORMS].freeze,
          css_form: :flat_literal,
          finalizers: [
            # custom.css の宣言を、平らな CSS でも PDF と同じに勝たせる。判定の後に CSS を書き直すので、
            # 異体字の規則を CSS の末尾へ足す VariantGlyphFonts より前に置く
            Finalizers::AuthorPriority,
            # 異体字セレクタ付きの字を 1 字書体で出す（KFX はセレクタを読まない）。
            # ほかの書き換えでテキストノードが動き終わった後に置く
            Finalizers::VariantGlyphFonts,
            # 層を外すと勝ち負けが変わる組を --log=debug で一覧にする
            Finalizers::InversionReport
          ],
          assets: OutputTarget::Assets.new(images: :jpeg_png, svg: false),
          packager: :vivliostyle_epub_to_kpf
        )
      )
    end
  end
end
