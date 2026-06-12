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

        def validate
          return [] if @path.empty?
          return [] if File.file?(@path)

          [error(
            "対象の PDF が見つかりません: #{@path}",
            detail: '対処: vs build で PDF を生成するか、既存 PDF のパスを指定してください'
          )]
        end
      end
    end
  end
end
