# frozen_string_literal: true

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

        # 1 つの指定を解決し、通らなかったものを { label:, reason: } にして返す。
        # 通ったものは nil。
        def unresolved_labels_for(token)
          entries = TokenResolver::Resolver.new.resolve([token])
          bad = entries.reject(&:in_catalog?)
          return nil if bad.empty?

          # contents/ に実在するのに未登録なら、直し方は「catalog.yml へ追加」になる。
          # 「そんな章はありません」と言ってしまうと、著者は在るファイルを探し続ける。
          reason = bad.all? { it.exists? } ? :uncataloged : :missing
          { label: label_for(token, entries, bad), reason: }
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
                         '対処: 章の綴りは config/catalog.yml で確認できます（番号だけでも指定できます）'])
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
