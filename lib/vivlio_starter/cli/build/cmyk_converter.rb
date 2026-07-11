# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative 'print_geometry'

module VivlioStarter
  module CLI
    module Build
      # ================================================================
      # Build::CmykConverter — 表紙 CMYK カラーマネジメント（cover-cmyk spec）
      # ================================================================
      # RGB の表紙 PDF を Japan Color 2001 Coated ICC で CMYK 変換し、出力インテントを
      # 埋め込んだ PDF/X-1a:2001 として書き出す。従来の素朴な `magick -colorspace CMYK`
      # （ICC なし・出力インテントなし＝くすみ・ビューア解釈不一致）を置き換える。
      #
      # 役割分担:
      #   - 色変換＋PDF/X-1a 化: Ghostscript（ICC 知覚的レンダリング＋出力インテント埋込）。
      #   - ジオメトリ（TrimBox/BleedBox）確定: Build::PrintGeometry.finalize_boxes!
      #     （qpdf・構造保存）。gs は pdfwrite で TrimBox を MediaBox にリセットしてしまい、
      #     CombinePDF の再保存は OutputIntent を落とすため、qpdf 差分更新で箱だけ書く。
      #
      # ICC 入手: @vivliostyle/cli（必須依存）が推移的に持つ press-ready 同梱の
      #   JapanColor2001Coated.icc を利用する（gem への ICC 再配布は不要）。
      #   設定キー `output.print_pdf.icc_profile` でユーザー指定パスも許可する。
      #
      # gs は AGPL だが CLI としてサブプロセス起動するだけ（本体 MIT・圧縮でも既に使用）。
      # ================================================================
      module CmykConverter
        module_function

        # press-ready 同梱 ICC の node_modules 相対パス（@vivliostyle/cli の推移的依存で常在）
        PRESS_READY_ICC = 'node_modules/press-ready/assets/JapanColor2001Coated.icc'

        # 出力インテントの条件識別子・出力条件（Japan Color 2001 Coated）
        OUTPUT_CONDITION = 'Japan Color 2001 Coated'

        # ICC ベースの CMYK 変換が可能か（ICC が解決できるか）。
        def available? = !icc_profile_path.nil?

        # 使用する ICC プロファイルの絶対パスを解決する。
        # 優先順: 設定キー output.print_pdf.icc_profile（ユーザー指定）→ press-ready 同梱。
        # いずれも無ければ nil（呼び出し側は従来の素朴 CMYK へフォールバック）。
        # メモ化しないのは、解決が cwd 相対（node_modules 探索）で安価なため
        # （プロセス内で cwd を跨ぐテストの汚染を避ける・ビルド毎の呼び出しは数回）。
        def icc_profile_path
          configured = Common::CONFIG&.dig(:output, :print_pdf, :icc_profile)
          if configured && !configured.to_s.strip.empty?
            path = File.expand_path(configured.to_s)
            return path if File.exist?(path)

            Common.log_warn("指定された ICC プロファイルが見つかりません: #{configured}")
          end

          bundled = File.expand_path(PRESS_READY_ICC)
          File.exist?(bundled) ? bundled : nil
        end

        # RGB 表紙 PDF を CMYK PDF/X-1a:2001（Japan Color 2001 Coated 出力インテント）へ
        # 変換し、TrimBox/BleedBox を確定する。成功時は pdf_path を上書きする。
        #
        # @param pdf_path [String] RGB 表紙 PDF（全紙サイズ・トンボ付き）。上書きされる。
        # @param bleed_mm [Numeric] 塗り足し幅（mm）
        # @param crop_offset_mm [Numeric] トンボ代（mm・塗り足しの外側）
        # @param title [String] PDF/X 文書タイトル（DOCINFO 用）
        # @return [Boolean] 変換に成功したか（ICC 不在・gs 失敗時は false）
        def to_pdfx!(pdf_path, bleed_mm:, crop_offset_mm:, title: 'Cover')
          icc = icc_profile_path
          return false unless icc && File.exist?(pdf_path)

          converted = Dir.mktmpdir('cmyk-pdfx') do |tmp|
            defs = File.join(tmp, 'PDFX_def.ps')
            File.write(defs, pdfx_def_ps(icc, title))
            out = File.join(tmp, 'out.pdf')
            next false unless run_gs_pdfx!(pdf_path, out, icc, defs)

            FileUtils.mv(out, pdf_path)
            true
          end
          return false unless converted

          # gs は箱を MediaBox にリセットするため、qpdf（構造保存）で TrimBox/BleedBox を確定。
          Build::PrintGeometry.finalize_boxes!(pdf_path, bleed_mm:, crop_offset_mm:)
          true
        rescue StandardError => e
          Common.log_warn("[cover cmyk] PDF/X-1a 変換に失敗しました: #{e.message}")
          false
        end

        # gs で RGB→CMYK＋PDF/X-1a 化を実行する。
        # --permit-file-read で SAFER を維持したまま ICC の読み取りだけ許可する
        # （gs 10.x の SAFER 既定では ICC 読み取りが拒否されるため。press-ready 4.x が
        # gs 10.x で失敗するのと同じ落とし穴を回避）。
        def run_gs_pdfx!(input, output, icc, defs)
          cmd = [
            'gs', '-dBATCH', '-dNOPAUSE', '-dPDFX=1', '-dNOOUTERSAVE',
            "--permit-file-read=#{icc}",
            '-sDEVICE=pdfwrite', '-sColorConversionStrategy=CMYK',
            "-sOutputICCProfile=#{icc}",
            '-o', output, defs, input
          ]
          system(*cmd, out: File::NULL, err: File::NULL) && File.exist?(output) && File.size(output).positive?
        end

        # PDF/X-1a:2001 の出力インテント定義（ICC を stream 埋込・CMYK=4 成分）。
        # gs 同梱 PDFX_def.ps を最小化したもの。-dPDFX=1 と併用する。
        def pdfx_def_ps(icc, title)
          <<~PS
            %!
            systemdict /PDFX known {systemdict /PDFX get}{1} ifelse
            dup 1 eq {
              [ /GTS_PDFXVersion (PDF/X-1a:2001) /Title (#{ps_escape(title)}) /Trapped /False /DOCINFO pdfmark
            } if pop
            /ICCProfile (#{ps_escape(icc)}) def
            [/_objdef {icc_PDFX} /type /stream /OBJ pdfmark
            [{icc_PDFX} << /N 4 >> /PUT pdfmark
            [{icc_PDFX} ICCProfile (r) file /PUT pdfmark
            [/_objdef {OutputIntent_PDFX} /type /dict /OBJ pdfmark
            [{OutputIntent_PDFX} <<
              /Type /OutputIntent /S /GTS_PDFX
              /OutputCondition (#{ps_escape(OUTPUT_CONDITION)})
              /OutputConditionIdentifier (#{ps_escape(OUTPUT_CONDITION)})
              /RegistryName (http://www.color.org)
              /DestOutputProfile {icc_PDFX}
            >> /PUT pdfmark
            [{Catalog} << /OutputIntents [ {OutputIntent_PDFX} ] >> /PUT pdfmark
          PS
        end

        # PostScript 文字列リテラル用のエスケープ（\ ( ) を順にエスケープ）。
        def ps_escape(str) = str.to_s.gsub('\\', '\\\\\\\\').gsub('(', '\\(').gsub(')', '\\)')
      end
    end
  end
end
