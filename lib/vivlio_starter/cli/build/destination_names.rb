# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/destination_names.rb
# ================================================================
# 責務:
#   仕上がった PDF のリンク先の名前（named destinations）を短い名前に付け替える。
#
# なぜ付け替えるのか（改善案 #81）:
#   vivliostyle はリンク先の名前に、ビルド時の URL をそのまま埋め込む
#   （`viv-id-http:003a:002f:002flocalhost:003a13000:002fvivliostyle:002f:002ecache:002fvs:002fbuild:002fpdf:002f44-build:002ehtml:0023fn1`）。
#   PDF の実装上限の目安（名前は 127 バイトまで）を超えて印刷所の検査に掛かるおそれがあり、
#   ビルドした場所のパスも配布物に残る。
#
# なぜ仕上げの直前なのか:
#   途中の工程は、この長い名前を手がかりに使う。backlink dedup はアンカー ID を、
#   閲覧用 PDF の結合は前付・奥付の開始ページ（`_titlepage` など）を名前から引く
#   （PdfPageMapExtractor）。付け替えは、それらが済んだ成果物にだけ行う。
#
# 書き換えるもの:
#   文書カタログの `/Dests` の見出し語と、それを指すリンク（`/Dest`・`/A` の `/D`）。
#   名前としても文字列（`u:…`）としても現れうるので、両方の形を同じ短い名前へ写す。
#   qpdf の JSON で構造を保ったまま差分更新する（QpdfJson）。ページの中身には触れない。
#
# 一時ファイルで書き換えて、オブジェクトストリームを作り直す:
#   qpdf の JSON 更新はオブジェクトストリームの中の更新を捨てることがあり、QpdfJson.read は
#   読む前にストリームを外す（qpdf_json.rb の説明・改善案 #95。2026-09-30 の全章ビルドで、
#   ページのリンク 5,404 件のうち 1,504 件が元の名前のまま残り、リンクが切れた）。
#   仕上がった成果物は外したままにせず作り直して戻すので、ここでは外した一時ファイルで
#   読み書きする。書き換えるものが無ければ、元のファイルには触れない。
#
# 組んでいない章へのリンク:
#   単章ビルド・直接ビルドでは、PDF に含まれない章へのリンクを vivliostyle が
#   `http://localhost:13000/vivliostyle/.cache/vs/build/pdf/41-book-yml.html#…` を開く
#   外部リンクとして書く。開けないうえビルドした場所のパスが残るので、飛び先（`/A`）を外す。
#   リンクの領域は枠のないまま残り、クリックしても何も起きない（全章ビルドでは 0 件）。
# ================================================================

require 'fileutils'

require_relative 'qpdf_json'

module VivlioStarter
  module CLI
    module Build
      module DestinationNames
        # vivliostyle が付けるリンク先の名前の頭
        VIVLIOSTYLE_PREFIX = 'viv-id-'

        # 付け替え後の名前の頭（vs1, vs2, …）
        SHORT_PREFIX = 'vs'

        # vivliostyle がビルド中に立てるサーバーのアドレス（qpdf の JSON の文字列表現）
        LOCAL_SERVER_URI = %r{\Au:https?://localhost(?::\d+)?/vivliostyle/}

        module_function

        # PDF のリンク先の名前を短い名前に付け替え、組んでいない章へのリンクの飛び先を外す。
        # どちらも無ければ何もしない。名前は元の名前の並び順で振るので、同じ原稿なら毎回同じ名前になる。
        #
        # @param pdf_path [String] 付け替える PDF（成功時に上書きされる）
        # @return [Integer] 付け替えた名前の数
        def shorten!(pdf_path)
          flat = "#{pdf_path}.flat.pdf"
          return 0 unless qpdf(pdf_path, flat, '--object-streams=disable')

          header, objects, = QpdfJson.read(flat)
          return 0 unless objects

          renames = short_names(objects)
          unlinked = 0
          updates = objects.each_with_object({}) do |(key, object), changed|
            next unless object.is_a?(Hash) && object.key?('value')

            value = rename(object['value'], renames)
            if local_link?(value, objects)
              value = value.except('/A')
              unlinked += 1
            end
            changed[key] = { 'value' => value } unless value == object['value']
          end
          return 0 if updates.empty? || !QpdfJson.apply!(flat, header, updates)
          return 0 unless qpdf(flat, pdf_path, '--object-streams=generate')

          Common.log_info("[pdf] リンク先の名前 #{renames.size} 件を短い名前に付け替え、" \
                          "PDF に含まれない章へのリンク #{unlinked} 件の飛び先を外しました: #{File.basename(pdf_path)}")
          renames.size
        ensure
          FileUtils.rm_f(flat) if flat
        end

        # vivliostyle の名前 → 短い名前。すでに短い名前（vsN）があれば続きの番号から振る
        # （付け替え済みの PDF にもう一度かけても、既存の名前と重ならないように）。
        def short_names(objects)
          taken = 0
          objects.each_value do |object|
            walk_texts(object) { |text| taken = [taken, text[%r{\A(?:/|u:)#{SHORT_PREFIX}(\d+)\z}o, 1].to_i].max }
          end
          collect_names(objects).sort.each_with_index.to_h { |name, index| [name, "#{SHORT_PREFIX}#{taken + index + 1}"] }
        end

        # qpdf で PDF を書き直す。失敗したら書き出し先を残さない。
        def qpdf(input, output, *options)
          return true if system('qpdf', input, output, *options, out: File::NULL, err: File::NULL)

          FileUtils.rm_f(output)
          Common.log_warn("[pdf] リンク先の名前を付け替えられませんでした（qpdf が失敗）: #{File.basename(input)}")
          false
        end

        # ビルド中のサーバーを開く外部リンクか。飛び先の動作は直接の辞書でも間接参照でもありうる。
        def local_link?(value, objects)
          return false unless value.is_a?(Hash) && value['/Subtype'] == '/Link'

          action = value['/A']
          action = objects.dig("obj:#{action}", 'value') if action.is_a?(String)
          action.is_a?(Hash) && action['/S'] == '/URI' && action['/URI'].to_s.match?(LOCAL_SERVER_URI)
        end

        # PDF 全体から vivliostyle の名前（頭の `/` や `u:` を除いた本体）を集める。
        # `/Dests` の見出し語だけでなく参照側も拾うので、見出し語が無い参照も同じ規則で写る。
        def collect_names(objects)
          found = Set.new
          objects.each_value { walk(it) { |text| found << text } }
          found
        end

        # JSON の値を巡り、vivliostyle の名前の本体を渡す。
        def walk(value, &block)
          walk_texts(value) { |text| (body = name_body(text)) && block.call(body) }
        end

        # JSON の値を巡り、辞書の見出し語と文字列（名前・文字列・参照）をすべて渡す。
        def walk_texts(value, &block)
          case value
          when Hash
            value.each do |key, child|
              block.call(key)
              walk_texts(child, &block)
            end
          when Array then value.each { walk_texts(it, &block) }
          when String then block.call(value)
          end
        end

        # qpdf の JSON では名前は `/名前`、文字列は `u:文字列` と書かれる。
        # vivliostyle の名前ならその本体を、そうでなければ nil を返す。
        def name_body(text)
          body = if text.start_with?('/') then text[1..]
                 elsif text.start_with?('u:') then text[2..]
                 end
          body if body&.start_with?(VIVLIOSTYLE_PREFIX)
        end

        # 値の中の vivliostyle の名前を、同じ形（名前／文字列）のまま短い名前へ置き換える。
        def rename(value, renames)
          case value
          when Hash then value.to_h { |key, child| [rename_text(key, renames), rename(child, renames)] }
          when Array then value.map { rename(it, renames) }
          when String then rename_text(value, renames)
          else value
          end
        end

        def rename_text(text, renames)
          body = name_body(text)
          return text unless body

          "#{text.delete_suffix(body)}#{renames.fetch(body)}"
        end
      end
    end
  end
end
