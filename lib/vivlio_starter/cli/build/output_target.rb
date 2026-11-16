# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/output_target.rb
# ================================================================
# 責務:
#   出力先の宣言の型と登録表（v2-architecture-spec.md §4.1）
# ================================================================

module VivlioStarter
  module CLI
    module Build
      # 出力先（閲覧用 PDF・入稿用 PDF・EPUB・Kindle）の宣言。
      #
      # 出力先は「HTML の変換の並びと CSS の形」に、素材の方針と梱包の方法を加えた形で表す。
      # 各出力先の値は build/targets/<名前>.rb に書く。「Kindle で何を変えているか」は、
      # targets/kindle.rb の並びと stylesheets/targets/kindle*.css の二つを読めば分かる。
      #
      # Build::Targets（output.targets の解決結果。どの出力先を作るか）とは別のものである。
      #
      # @!attribute id [Symbol] :pdf / :print_pdf / :epub / :kindle
      # @!attribute branch [Symbol] :pdf / :epub（どちらの枝で走るか）
      # @!attribute workspace [String] 出力先の HTML と CSS を置くディレクトリ
      # @!attribute body_classes [Array<String>] body に足すクラス（transforms の MarkBody の段が付ける）
      # @!attribute transforms [Array<Module>] 1 ページの HTML だけを見て書き換える段の並び
      # @!attribute css_form [Symbol] :layered / :flat / :flat_literal（css-layer-restructure-spec.md §4）
      # @!attribute finalizers [Array<Module>] 本の全部のページと CSS を見る段の並び（変換の後・梱包の前）
      # @!attribute assets [OutputTarget::Assets] 素材の方針
      # @!attribute packager [Symbol] 梱包の方法
      #   （:vivliostyle_pdf / :print_pdf / :vivliostyle_epub / :vivliostyle_epub_to_kpf）
      OutputTarget = Data.define(:id, :branch, :workspace, :body_classes, :transforms, :css_form, :finalizers,
                                 :assets, :packager) do
        # 出力先の宣言を登録する（build/targets/*.rb が読み込みのときに呼ぶ）
        def self.register(target) = registry[target.id] = target

        # @param id [Symbol] 出力先の名前
        # @return [OutputTarget]
        def self.for(id) = registry.fetch(id) { raise ArgumentError, "知らない出力先です: #{id.inspect}" }

        def self.registry = (@registry ||= {})
      end

      # 素材の方針。
      # @!attribute images [Symbol] 画像の形式
      #   （:as_is そのまま / :webp WebP へ寄せる / :jpeg_png JPEG と PNG だけ）
      # @!attribute svg [Boolean] SVG を同梱できるか
      OutputTarget::Assets = Data.define(:images, :svg)
    end
  end
end
