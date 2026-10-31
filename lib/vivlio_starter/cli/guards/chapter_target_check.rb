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
      # なので、一部を黙って捨ててよい場面がない。
      #
      # **範囲（`00-11`）は、その番号の間にある章を指す**（改善案 #113）。間の欠けた番号は
      # 著者が名指しした章ではないので責めない（TokenResolver が落とす）。止めるのは、
      # 範囲に章が 1 つも無いときだけ。
      #
      # 検証は指定 1 つずつ行う。範囲は複数の章に展開されるため、まとめて解決すると
      # 「どの指定が悪かったか」を著者へ返せなくなる。
      class ChapterTargetCheck < BaseCheck
        # 範囲が何章に広がったかを知らせる 1 行（💡）を返す。範囲は打った字面から
        # 何章になるかが読めないので、組む前に見せる（改善案 #113）。
        # 範囲に章が無いときは validate が止めるので、ここでは行を作らない。
        # @param targets [Array<String>] CLI が受け取った章指定
        # @param verb [String] 「ビルド」「点検」など、章に対してすること
        # @param scope [Symbol] :catalog（catalog.yml の章だけ）／:contents（原稿があれば含める）
        # @return [Array<String>]
        def self.range_notices(targets, verb:, scope: :catalog)
          return [] if Array(targets).empty?

          resolver = TokenResolver::Resolver.new
          resolver.split_tokens(targets).select { TokenResolver::Resolver.range_token?(it) }.filter_map do |piece|
            entries = resolver.resolve([piece])
            used = entries.select { usable?(it, scope) }
            next if used.empty?

            drafts = entries.reject { usable?(it, scope) }.select(&:exists?).map(&:basename)
            dropped = drafts.empty? ? '' : "（#{drafts.join(', ')} は catalog.yml に無いので外しました）"
            "💡 #{piece} のうち、原稿のある #{used.size} 章（#{used.map(&:basename).join(', ')}）を#{verb}します#{dropped}"
          end
        end

        # その章を対象に含めるか。build・preflight は catalog.yml に登録した章だけを組む。
        # lint・metrics は読んで分析するだけなので、登録していない原稿も含める
        # （`_toc` などのシステムページの名前も通し、有無はコマンドに任せる）
        def self.usable?(entry, scope)
          entry.in_catalog? || (scope == :contents && (entry.exists? || entry.number.nil?))
        end

        # @param targets [Array<String>] CLI が受け取った章指定（空ならフルビルド）
        # @param scope [Symbol] :catalog（build・preflight）／:contents（lint・metrics）
        def initialize(targets, scope: :catalog)
          super()
          @targets = Array(targets).map(&:to_s).reject { it.strip.empty? }
          @scope = scope
        end

        def validate
          return [] if @targets.empty?

          unresolved = resolver.split_tokens(@targets).filter_map { unresolved_labels_for(it) }
          return [] if unresolved.empty?

          by_reason = unresolved.group_by { it[:reason] }
          [missing_violation(by_reason[:missing]),
           uncataloged_violation(by_reason[:uncataloged]),
           *Array(by_reason[:empty_range]).map { empty_range_violation(it) }].compact
        end

        private

        def resolver = @resolver ||= TokenResolver::Resolver.new

        # 1 つの指定を解決し、通らなかったものを { label:, reason:, ... } にして返す。
        # 通ったものは nil。
        def unresolved_labels_for(token)
          entries = resolver.resolve([token])
          return unresolved_range(token, entries) if TokenResolver::Resolver.range_token?(token)

          bad = entries.reject { usable?(it) || left_to_duplicate_checks?(it) }
          return nil if bad.empty?

          # contents/ に実在するのに未登録なら、直し方は「catalog.yml へ追加」になる。
          # 「そんな章はありません」と言ってしまうと、著者は在るファイルを探し続ける。
          reason = bad.all? { it.exists? } ? :uncataloged : :missing
          suggestion = reason == :missing ? suggestion_for(token) : nil
          { label: token, reason:, suggestion: }
        end

        # 範囲は、章が 1 つも無いときだけ止める。範囲の中の草稿は組まないが、それだけしか
        # 無いなら、登録すれば組めることを言う
        def unresolved_range(token, entries)
          return nil if entries.any? { usable?(it) || left_to_duplicate_checks?(it) }

          { label: token, reason: :empty_range, drafts: entries.select(&:exists?).map(&:basename) }
        end

        def usable?(entry) = self.class.usable?(entry, @scope)

        # 番号・名前の重なった章を指す指定は解決されないが、DuplicateNumberCheck・DuplicateSlugCheck が
        # 直すコマンドを添えて止めるので、ここでは数えない
        def left_to_duplicate_checks?(entry)
          !entry.valid? && duplicated_names.include?(entry.slug.to_s.downcase)
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

        # 範囲の手前と後ろで、いちばん近い章（無ければ省く）
        def chapters_near(token)
          first, last = token.scan(/\d+/).map(&:to_i).minmax
          numbered = catalog_entries.sort_by { it.number.to_i }
          [numbered.reverse.find { it.number.to_i < first }, numbered.find { it.number.to_i > last }]
            .compact.map(&:basename)
        end

        def duplicated_names
          @duplicated_names ||= DuplicateNumberCheck.new.duplicated_numbers + DuplicateSlugCheck.new.duplicated_slugs
        end

        # catalog.yml に載っている本文・付録等（システムページは番号を持たない）
        def catalog_entries
          @catalog_entries ||= resolver.resolve.select(&:number)
        end

        def catalog_basenames = catalog_entries.map(&:basename)

        def missing_violation(missing)
          return nil if missing.nil?

          error("指定した章が見つかりません: #{missing.map { it[:label] }.join(', ')}",
                detail: ["#{Common::CONTENTS_DIR}/ に該当する原稿がありません。",
                         *suggestion_lines(missing),
                         '対処: 章の綴りは config/catalog.yml で確認できます（番号だけでも指定できます）',
                         *volume_hint])
        end

        # 分冊の本では、巻の指定の書き間違いかもしれないので、巻の書き方を添える
        def volume_hint
          ids = Build::Volumes.list.map(&:id)
          return [] if ids.empty?

          ["巻を指定するなら、巻の id を 1 語だけ書きます: #{ids.join('、')}、all（全巻）"]
        end

        # 候補は before → after の形で見せる。そのまま打ち直せる並びにする。
        def suggestion_lines(missing)
          suggested = missing.select { it[:suggestion] }
          return [] if suggested.empty?

          ['もしかして:', *suggested.map { "  #{it[:label]} → #{it[:suggestion]}" }]
        end

        def uncataloged_violation(uncataloged)
          return nil if uncataloged.nil?

          labels = uncataloged.map { it[:label] }
          error("指定した章が config/catalog.yml に登録されていません: #{labels.join(', ')}",
                detail: ['原稿はありますが、catalog.yml に無い章は組む順番が決まりません。',
                         "対処: config/catalog.yml へ #{labels.join(', ')} を追加してください" \
                         '（草稿のまま外しておきたいなら、指定せずに vs build してください）'])
        end

        # 範囲に、組める章が 1 つも無い。草稿だけがあるなら登録を、何も無いなら近い章を示す
        def empty_range_violation(range)
          token = range[:label]
          drafts = range[:drafts]
          return empty_range_with_drafts(token, drafts) if drafts.any?

          near = chapters_near(token)
          error("#{token} に章がありません",
                detail: [*("近い章: #{near.join(', ')}" if near.any?),
                         '対処: 章の番号は config/catalog.yml で確認できます'])
        end

        def empty_range_with_drafts(token, drafts)
          error("#{token} に、config/catalog.yml に登録した章がありません",
                detail: ["#{drafts.join(', ')} は原稿がありますが、catalog.yml に無い章は組む順番が決まりません。",
                         "対処: config/catalog.yml へ #{drafts.join(', ')} を追加してください"])
        end
      end
    end
  end
end
