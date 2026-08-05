# frozen_string_literal: true

# 打ち間違いの候補出しに使う。Ruby の default gem なので gemspec への追加は要らず、
# `ruby --disable-did_you_mean` 下でも明示 require なら読める（あのフラグが切るのは
# 例外へフックする側であって、綴り比較そのものではない）。
require 'did_you_mean'

module VivlioStarter
  module CLI
    module Guards
      # CLI に並べた章指定（`vs build 11-install abc`）がすべて解決できるかを検証する。
      #
      # **解決できない指定が 1 つでもあれば、何もせずに止める。**
      # 解決できたぶんだけ処理を進めると、`vs build 11-install abc` が「11-install だけ
      # 組んで成功」で終わる——著者は 2 章ぶんできたつもりでいるのに、成果物にも
      # 終了コードにも食い違いが出ない。CLI 引数は設定ファイルと違って「今打った指示」
      # なので、一部を黙って捨ててよい場面がない。`vs lint` の作法に揃えている。
      #
      # 検証は指定 1 つずつ行う。範囲（`11-13`）は複数の章に展開されるため、
      # まとめて解決すると「どの指定が悪かったか」を著者へ返せなくなる。
      class ChapterTargetCheck < BaseCheck
        # @param targets [Array<String>] CLI が受け取った章指定（空ならフルビルド）
        def initialize(targets)
          super()
          @targets = Array(targets).map(&:to_s).reject { it.strip.empty? }
        end

        def validate
          return [] if @targets.empty?

          unresolved = @targets.filter_map { unresolved_labels_for(it) }
          return [] if unresolved.empty?

          missing, uncataloged = unresolved.partition { it[:reason] == :missing }
          [missing_violation(missing), uncataloged_violation(uncataloged)].compact
        end

        private

        # 1 つの指定を解決し、通らなかったものを { label:, reason:, suggestion: } にして返す。
        # 通ったものは nil。
        def unresolved_labels_for(token)
          entries = TokenResolver::Resolver.new.resolve([token])
          bad = entries.reject(&:in_catalog?)
          return nil if bad.empty?

          # contents/ に実在するのに未登録なら、直し方は「catalog.yml へ追加」になる。
          # 「そんな章はありません」と言ってしまうと、著者は在るファイルを探し続ける。
          reason = bad.all? { it.exists? } ? :uncataloged : :missing
          # 候補を出すのは単一指定のときだけ。範囲（11-13）に章名を差し出しても意味がない
          suggestion = reason == :missing && entries.size <= 1 ? suggestion_for(token) : nil
          { label: label_for(token, entries, bad), reason:, suggestion: }
        end

        # 打ち間違いに添える「もしかして」を 1 件だけ返す。無ければ nil。
        #
        # **1 件に絞るのが肝心**——候補を並べると著者は結局 catalog.yml を見に行くので、
        # それなら候補を出さずに catalog.yml へ案内するのと変わらない。
        #
        # 綴りが近いものを先に見て、無ければ番号だけで拾う。番号は著者が
        # 「第 41 章」を指したことの強い証拠で、綴りが遠くても（`41-nonexistent`）
        # 意図は読める。逆順にすると `43-cover` を差し置いて `41-book-yml` が出る。
        def suggestion_for(token)
          near = DidYouMean::SpellChecker.new(dictionary: catalog_basenames).correct(token).first
          return near if near

          number = token[/\A(\d+)/, 1]
          return nil unless number

          prefix = "#{format('%02d', number.to_i)}-"
          catalog_basenames.find { it.start_with?(prefix) }
        end

        # catalog.yml に載っている本文・付録等の basename（システムページは番号を持たない）
        def catalog_basenames
          @catalog_basenames ||= TokenResolver::Resolver.new.resolve.select(&:number).map(&:basename)
        end

        # 範囲指定はどの番号が欠けているかまで言う。`11-13` とだけ返すと、
        # 実在する 11・12 まで無いかのように読める。
        def label_for(token, entries, bad)
          return token if entries.size <= 1

          "#{token} のうち第 #{bad.map { it.number.to_i }.sort.join('・')} 章"
        end

        def missing_violation(missing)
          return nil if missing.empty?

          error("指定した章が見つかりません: #{missing.map { it[:label] }.join(', ')}",
                detail: ["#{Common::CONTENTS_DIR}/ に該当する原稿がありません。",
                         *suggestion_lines(missing),
                         '対処: 章の綴りは config/catalog.yml で確認できます（番号だけでも指定できます）'])
        end

        # 候補は before → after の形で見せる。そのまま打ち直せる並びにする。
        def suggestion_lines(missing)
          suggested = missing.select { it[:suggestion] }
          return [] if suggested.empty?

          ['もしかして:', *suggested.map { "  #{it[:label]} → #{it[:suggestion]}" }]
        end

        def uncataloged_violation(uncataloged)
          return nil if uncataloged.empty?

          labels = uncataloged.map { it[:label] }
          error("指定した章が config/catalog.yml に登録されていません: #{labels.join(', ')}",
                detail: ["原稿はありますが、catalog.yml に無い章は組む順番が決まりません。",
                         "対処: config/catalog.yml へ #{labels.join(', ')} を追加してください" \
                         '（草稿のまま外しておきたいなら、指定せずに vs build してください）'])
        end
      end
    end
  end
end
