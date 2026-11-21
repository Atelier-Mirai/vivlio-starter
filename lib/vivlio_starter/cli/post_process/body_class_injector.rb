# frozen_string_literal: true

require_relative '../common'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # ================================================================
      # Module: BodyClassInjector
      # ----------------------------------------------------------------
      # 【役割】
      # - HTMLファイルの <body> タグにファイルタイプクラスを付与
      #
      # 【処理内容】
      # - ファイル名から chapter/preface/appendix などを判定
      # - <body> を <body class="file_type"> に置換
      # - 最初の本文章には chapter-first クラスを追加（pageカウンタリセット用）
      # ================================================================
      module BodyClassInjector
        # 縦書きの本の body に付けるクラス（契約 HTML の保証のクラス）
        VERTICAL_CLASS = 'vs-vertical'

        module_function

        # 本の軸から付く body のクラス（目次など、ここを通らないページの生成も読む）
        # @return [Array<String>]
        def trait_classes = Common.traits.vertical? ? [VERTICAL_CLASS] : []

        # HTMLファイルの <body> タグにファイルタイプクラスを付与
        # @param html_file [String] HTMLファイルのパス
        # @param entry [TokenResolver::Entry] 章情報を持つ Entry オブジェクト
        # @return [Boolean] 変更があったかどうか
        def inject_body_class(html_file, entry)
          content = File.read(html_file, encoding: 'utf-8')
          file_type = entry.kind.to_s
          classes = [file_type]

          # ヘッダ切替（方式A・P3-3）: chapter.css / appendix.css が simple/image の
          # 両ヘッダを import し、この body クラスで相互排他に有効化する。
          # 注入は literal `<body>` の gsub なので、必ずこの同一注入内で classes に足す
          # （後付けの別パスは `<body class=...>` に一致せず失敗する）。
          header_class = header_mode_class(entry.kind)
          classes << header_class if header_class

          # 最初の本文章には chapter-first クラスを追加
          classes << 'chapter-first' if entry.kind == :chapter && first_main_chapter?(html_file)

          # 組方向（theme-contract-spec.md §2.2）。本の軸なので、横に組む奥付と権利ページにも付ける
          classes.concat(trait_classes)

          class_attr = classes.join(' ')

          # 単純置換で <body> にクラスを付与
          # - 既存 class 属性が無いテンプレ構成を前提に、文字列置換で高速に処理
          updated = content.gsub('<body>', "<body class=\"#{class_attr}\">")

          return if updated == content

          File.write(html_file, updated, encoding: 'utf-8')
          Common.log_info("#{html_file}: <body>→class追加(#{class_attr})")
        end

        # 選ばれたテーマのオプションが付ける body のクラス（theme.yml の body_class:・theme-contract-spec.md §3.3）。
        # standard は章に style の値で vs-header-image・vs-header-simple、付録に vs-header-simple を付ける
        # @param kind [Symbol] entry.kind
        # @return [String, nil]
        def header_mode_class(kind)
          classes = Theme.declared&.body_classes(kind, Common::CONFIG).to_a
          classes.empty? ? nil : classes.join(' ')
        end

        # 最初の本文章かどうかを判定
        # @param html_file [String] HTMLファイルのパス
        # @return [Boolean]
        def first_main_chapter?(html_file)
          basename = File.basename(html_file, '.html')
          first_chapter = detect_first_main_chapter
          return false unless first_chapter

          basename == first_chapter
        end

        # catalog.yml から最初の本文章を検出
        # @return [String, nil] 最初の本文章の basename、または nil
        def detect_first_main_chapter
          @detect_first_main_chapter ||= begin
            require_relative '../build/catalog_loader'
            catalog = Build::CatalogLoader.load_catalog
            chapters = catalog['CHAPTERS']
            return nil if chapters.nil? || chapters.empty?

            # CHAPTERSセクションの最初のエントリを取得
            first_item = chapters.first
            case first_item
            when String
              first_item.sub(/\.md\z/, '')
            when Hash
              # 部タイトルの場合は配下の最初の章を取得
              sub_items = first_item.values.first
              sub_items.is_a?(Array) && sub_items.first ? sub_items.first.to_s.sub(/\.md\z/, '') : nil
            end
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
