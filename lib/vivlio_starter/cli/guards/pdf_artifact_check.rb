# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Guards
      # 対象 PDF（build 成果物または明示指定されたパス）が存在するかを検証する。
      #
      # パス未指定（nil / 空文字）の場合は検証しない。引数省略時の
      # 「ビルド生成物の自動選択」「sources/ 探索」はドメイン層の責務であり、
      # その解決ロジックを Check 側へ複製しないため。
      class PdfArtifactCheck < BaseCheck
        # @param path [String, nil] 検証する PDF パス（nil なら検証スキップ）
        def initialize(path)
          @path = path.to_s.strip
          super()
        end

        # 拡張子を省いた指定（`vs pdf:pages 97-sample`）は、コマンド本体と同じく
        # `.pdf` を補ってから探す。補わずに調べると、本体なら開けるファイルをここで止めてしまう。
        def validate
          return [] if @path.empty?

          pdf_path = @path.downcase.end_with?('.pdf') ? @path : "#{@path}.pdf"
          return [] if File.file?(pdf_path)

          [error(
            "対象の PDF が見つかりません: #{pdf_path}",
            detail: '対処: vs build で PDF を生成するか、既存 PDF のパスを指定してください'
          )]
        end
      end
    end
  end
end
