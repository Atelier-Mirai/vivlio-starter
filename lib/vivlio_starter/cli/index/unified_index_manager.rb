# frozen_string_literal: true

# ================================================================
# Class: UnifiedIndexManager
# ----------------------------------------------------------------
# 責務:
#   索引・用語集生成プロセス全体を統括するマネージャー
#   仕様書 index_glossary_spec.md に準拠
#
# 主要メソッド:
#   - auto_process!: 全自動候補抽出 → _index_glossary_review.md 生成
#   - apply_markdown_review!: Markdownから承認・リジェクトを適用
#   - build_index!: 索引ページを生成（内部用）
# ================================================================

require_relative '../common'
require_relative '../index_markup'
require_relative '../build/catalog_loader'
require_relative '../pre_process/issue_registry'
require_relative 'unified_terms_manager'
require_relative 'review_queue_manager'
require_relative 'review_markdown_generator'
require_relative 'index_candidate_extractor'
require_relative 'index_match_scanner'
# IndexCommands.without_excluded_chapters（索引の対象から外す章）。index.rb は
# このファイルをメソッドの中で読むので、ここから読んでも循環しない
require_relative '../index'
require_relative 'manuscript_markup'
require_relative 'code_block_stripper'
require_relative 'unified_page_builder'
require_relative 'index_plan_reporter'
require_relative 'term_ranking'
require_relative 'term_spread'
require_relative 'main_reference_suggester'
require_relative '../token_resolver'
require_relative 'yomi_inferrer'

module VivlioStarter
  module CLI
    # IndexCommands モジュール内のクラスへのエイリアス
    IndexCandidateExtractor = IndexCommands::IndexCandidateExtractor
    IndexMatchScanner = IndexCommands::IndexMatchScanner
    CodeBlockStripper = IndexCommands::CodeBlockStripper
    UnifiedPageBuilder = IndexCommands::UnifiedPageBuilder
    YomiInferrer = IndexCommands::YomiInferrer

    class UnifiedIndexManager
      # R9: [用語]（読みなし）記法で ASCII 可視文字のみ 2 文字以下の語は登録しない。
      # 単位 [eV] [Hz] やフラグ解説 [g] が索引語として誤登録されるのを防ぐ
      # （[g] は pattern /\bg\b/ となり本文中の英字 g 全部にタグが付く）。
      # 意図的に登録したい場合は読み付き [eV|いーぶい] を使う。
      #
      # 綴りの定義元は IndexMarkup（vs lint の L-1 も同じ値を見る）。同じ「2 文字」が
      # 2 箇所に別々の定数として立つのを避ける（markdown-notation-collision-spec.md §9）。
      ASCII_SHORT_TERM_PATTERN = IndexMarkup::SHORT_ASCII_TERM

      attr_reader :terms_manager, :queue_manager, :markdown_generator

      # @param input [IO] 棄却するときの問い合わせ（§3.1.3）の答えを読む先。テストで差し替える
      def initialize(input: $stdin)
        @input = input
        @terms_manager = UnifiedTermsManager.new
        @queue_manager = ReviewQueueManager.new
        @markdown_generator = ReviewMarkdownGenerator.new
        @config = load_index_config
        @glossary_config = load_glossary_config
      end

      # 索引の下見（`vs index:plan`）。現況と候補の分布を表示するだけで、
      # 辞書もレビューファイルも書かない。表示は auto_process! と同一にする
      # ——見え方が実行ごとに変わると、下見の意味がなくなる（§6.2）。
      # @param chapters [Array<String>] 対象章のリスト
      def plan!(chapters)
        Common.log_action('索引の現況を確認しています...')
        candidates = @config.fetch(:auto_discovery, true) ? extract_candidates(chapters) : []
        # auto_process! と同じく「選べる候補」だけを渡す。生の候補には登録済みの語も
        # 棄却済みの語も混ざっており、そのまま出すと下見だけが多く見え、しかも
        # 著者が自分で外した語を推奨してしまう（実測: 2,880 件 対 2,644 件）。
        selectable, = selectable_candidates(candidates)
        build_plan_reporter(chapters, selectable, extractor: @extractor).render
        0
      end

      # 全自動索引候補抽出 → _index_review.md 生成
      # @param chapters [Array<String>] 対象章のリスト
      def auto_process!(chapters)
        auto_discovery = @config.fetch(:auto_discovery, true)

        Common.log_action('索引の自動処理を開始します...')

        # R8: 辞書へ書いた登録内容を種別ごとに集め、既定ログレベルで要約表示する
        dictionary_writes = {}

        # 1. 手動登録の語のうち、辞書に無い語を登録する
        fresh_terms = fresh_manual_terms(extract_manual_markup_terms(chapters))
        if fresh_terms.any?
          added = @terms_manager.merge_terms!(fresh_terms, flags: 'i', source: 'manual_markup')
          dictionary_writes['手動登録'] = added if added.any?
        end

        # auto_discovery が無効の場合、自動候補抽出をスキップ
        unless auto_discovery
          @terms_manager.record_scanned_chapters!(chapters)
          report_dictionary_writes(dictionary_writes)
          Common.log_info('auto_discovery: false のため、自動候補抽出をスキップします')
          Common.log_info('手動登録の語のみが索引に反映されます')
          return
        end

        # 2. 候補抽出
        candidates = extract_candidates(chapters)
        Common.log_info("候補抽出: #{candidates.size}件")

        # 3. 既に辞書にある語とリジェクト済みの語を落とす（＝選べる候補だけ残す）。
        #    使っていない語のうち原稿に出てくる語は、説明文を添えて候補に戻す（§3.3.2）
        selectable, rejected_count_in_candidates = selectable_candidates(candidates)
        selectable = with_returning_unused_terms(selectable, chapters)

        # 4. 登録語と同じ土俵で並べ、推奨候補／一般候補／見直し候補に分ける。
        #    スコアの絶対値では切らない——閾値は書籍の規模で意味が変わるうえ、
        #    「目安に達しているから推奨は 0 件」という誤った判断を生む（§3.4-1）。
        bands = build_bands(@terms_manager.index_terms, selectable, current_estimate(chapters), @extractor)
        by_name = selectable.to_h { [it['term'], it] }
        high_candidates = review_entries(bands&.recommended, by_name)
        low_candidates = review_entries(bands&.general, by_name)
        high_candidates, low_candidates = with_suggested_main([high_candidates, low_candidates], chapters)

        # 5. 自動承認は既定で行わない。旧既定（スコア 300 以上を無条件登録）が
        #    「頻出の一般語ばかりが辞書に入る」現状を作った張本人である。
        auto_approved = @config[:auto_approve] == true ? high_candidates : []
        if auto_approved.any?
          added = @terms_manager.merge_terms!(auto_approved, flags: 'i', source: 'auto_extracted')
          dictionary_writes['自動承認'] = added if added.any?
        end

        # 6. 登録済み用語（索引＋用語集すべて）に文脈を付与
        terms_with_context = enrich_terms_with_context(
          @terms_manager.load_terms.reject { it['flags'].to_s.empty? }, chapters,
          scores: candidate_scores_by_name(selectable, candidates)
        )

        # 7. リジェクト済み用語に文脈とスコアを付与
        # candidatesからスコアを復元できるように渡す
        rejected_with_context = enrich_rejected_with_context(candidates)

        # 8. _index_review.md を生成。原稿に出てこない語は 5 節にまとめる（§3.3.1）
        present_terms, absent_terms = terms_with_context.partition { Array(it['contexts']).any? }
        present_rejected, absent_rejected = rejected_with_context.partition { Array(it['contexts']).any? }
        # 索引ライブラリから取り込んだ使っていない語・棄却した語は、原稿に出てこない間は
        # 5 節に並べない。この本で片付ける語ではなく、ライブラリを重ねるほど本に固有の語が
        # 埋もれるため（index-library-reserve-spec.md §3.3）
        absent_unused = absent_unused_terms(chapters)
        from_library = ->(item) { item['source'] == 'imported' }
        @markdown_generator.generate!(
          terms: present_terms,
          high_candidates: high_candidates,
          low_candidates: low_candidates,
          rejected: present_rejected,
          absent: absent_entries(absent_terms, absent_unused.reject(&from_library), absent_rejected.reject(&from_library)),
          absent_imported: absent_unused.count(&from_library) + absent_rejected.count(&from_library)
        )

        # 9. 走査した章集合を辞書へ記録（R7: ビルド時の章追加検知に使う）
        @terms_manager.record_scanned_chapters!(chapters)

        # 10. 結果レポート
        # 目安の語数や候補の分布は出さない（`vs index:plan` の役目）。auto の後に著者が
        # することはレビューファイルを開くことなので、件数と次の手順だけを告げる。
        # 以前は `index-term-selection-spec.md` §6.3 に従って plan と同じ画面を出していたが、
        # 30 行近い表の後に肝心の案内が埋もれていた（改善案 #99）
        report_dictionary_writes(dictionary_writes)
        report_auto_results(auto_approved, high_candidates, low_candidates,
                            rejected_count_in_candidates, present_rejected.size)
      end

      # Markdownから承認・リジェクトを適用
      # 仕様: vs index:apply は辞書を更新するだけで、索引ページの生成は行わない
      # （生成はビルドパイプラインの責務）
      def apply_markdown_review!
        unless @markdown_generator.exists?
          Common.log_warn('_index_glossary_review.md が見つかりません')
          Common.log_info('先に vs index:auto を実行してください')
          return
        end

        # 節の見出しが変わった（index-glossary-registration-spec.md §4.1）。古い形式のまま
        # 読むと、節の境目を見失って棄却した語の欄を登録済みとして読み違えるので、止める
        unless @markdown_generator.current_format?
          Common.log_error("#{ReviewMarkdownGenerator::REVIEW_FILE} が古い形式です",
                           detail: 'vs index:auto で作り直してから、もう一度 vs index:apply を実行してください')
          return
        end

        # --- Phase: 索引処理 ---
        index_approved = @markdown_generator.parse_index_approved
        index_rejected = @markdown_generator.parse_index_rejected

        # --- Phase: 用語集処理 ---
        glossary_approved = @markdown_generator.parse_glossary_approved
        glossary_rejected = @markdown_generator.parse_glossary_rejected

        # --- Phase: 共通処理 ---
        both_rejected = @markdown_generator.parse_rejected
        unreject = @markdown_generator.parse_unreject
        yomi_changes = @markdown_generator.parse_yomi_changes
        main_references = @markdown_generator.parse_main_references

        changes_made = false
        index_count = 0
        glossary_count = 0
        # [-i] / [-g] でフラグを全部失い、terms から消えた語（除外リストへ送る対象）
        dropped_i = []
        dropped_g = []

        # --- Phase: 記録ごと消す（[DELETE]・§3.3.3） ---
        # 原稿に印の残る語は、外してよいか確かめる。断られた語は消さない
        deleted = @markdown_generator.parse_deleted
        declined_delete = confirm_markup_removal(deleted, action: '削除')
        (deleted - declined_delete.to_a).each do |term|
          delete_record!(term)
          changes_made = true
        end

        # --- Phase: 索引承認 ---
        if index_approved.any?
          @terms_manager.merge_terms!(index_approved, flags: 'i', source: 'auto_extracted')
          index_count = index_approved.size
          changes_made = true
        end

        # --- Phase: 用語集承認 ---
        if glossary_approved.any?
          validate_glossary_definitions!(glossary_approved)
          @terms_manager.merge_terms!(glossary_approved, flags: 'g', source: 'review')
          glossary_count = glossary_approved.size
          changes_made = true
        end

        # 載せると決めた語は、棄却した語の一覧に残さない（4 節・5 節のどちらで印を付けても）
        rejected_names = @queue_manager.load_rejected_terms.to_set
        (index_approved + glossary_approved).map { it['term'] }.uniq.each do |term|
          @queue_manager.unreject_term_by_name!(term) if rejected_names.include?(term)
        end

        # [ig] → [i] に変更された場合: g フラグを除去
        glossary_approved_names = glossary_approved.map { it['term'] }
        index_only = index_approved.reject { glossary_approved_names.include?(it['term']) }
        index_only.each do |term|
          next unless @terms_manager.glossary_term_names.include?(term['term'])

          @terms_manager.remove_flag!(term['term'], 'g')
          Common.log_info("用語集フラグを除去しました（索引のみ）: #{term['term']}")
          changes_made = true
        end

        # --- Phase: 棄却する語の、原稿の印（§3.1.3） ---
        # 辞書から消える語に原稿の印があれば、外してよいか確かめる。断られた語は棄却しない
        # ——印を残したまま棄却すると、辞書と原稿が食い違う
        declined = confirm_markup_removal(leaving_terms(index_rejected, glossary_rejected, both_rejected))
        if declined.any?
          index_rejected = index_rejected.reject { declined.include?(it['term']) }
          glossary_rejected = glossary_rejected.reject { declined.include?(it['term']) }
          both_rejected = both_rejected.reject { declined.include?(it['term']) }
        end

        # --- Phase: 索引のみリジェクト（[-i]） ---
        # `[-i]` は「索引から外す／**用語集には残す**」なので、除外リストへは書かない。
        # 書くと terms と rejected の両方に載る矛盾が生まれ、次回の apply で
        # Section 4 同期がその語を定義文ごと消す（`index-apply-rejected-consistency-spec.md` §1）。
        # 例外は `i` しか持たない語で、フラグが空になり terms から消える——
        # 残す先が無いので、このときだけ除外リストへ送る（＝ `[r]` と同じ扱い）。
        if index_rejected.any?
          dropped_i = index_rejected.filter_map { @terms_manager.remove_flag!(it['term'], 'i') }
          @queue_manager.save_rejected_terms(dropped_i) if dropped_i.any?
          changes_made = true
        end

        # --- Phase: 用語集のみリジェクト（[-g]） ---
        if glossary_rejected.any?
          dropped_g = glossary_rejected.filter_map { @terms_manager.remove_flag!(it['term'], 'g') }
          @queue_manager.save_rejected_terms(dropped_g) if dropped_g.any?
          changes_made = true
        end

        # --- Phase: 両方リジェクト（[r]） ---
        # 著者が明示的に消すと書いた唯一の経路。定義文を持つ語は黙って消さない（§3.4）。
        if both_rejected.any?
          both_rejected.each { remove_term_aloud!(it['term']) }
          @queue_manager.save_rejected_terms(both_rejected)
          changes_made = true
        end

        # --- Phase: リジェクト解除 + 直接登録 ---
        if unreject.any?
          unreject.each do |entry|
            @queue_manager.unreject_term_by_name!(entry['term'])
            flag = entry['flag'] || 'i'
            term_data = { 'term' => entry['term'], 'yomi' => entry['yomi'] }
            flags = case flag
                    when 'i', 'x' then 'i'
                    when 'g' then 'g'
                    when 'ig', 'gi' then 'ig'
                    else 'i'
                    end
            @terms_manager.merge_terms!([term_data], flags:, source: 'unreject')
            index_count += 1 if flags.include?('i')
            glossary_count += 1 if flags.include?('g')
            Common.log_info("リジェクト解除 → [#{flag}] 登録: #{entry['term']}")
          end
          changes_made = true
        end

        # --- Phase: 読み変更 ---
        if yomi_changes.any?
          @terms_manager.update_yomi!(yomi_changes)
          changes_made = true
        end

        # --- Phase: 主要参照 ---
        changes_made = true if apply_main_references!(main_references)

        # --- Phase: 孤立データ除去 ---
        index_approved_names = index_approved.map { it['term'] }
        glossary_approved_names_all = glossary_approved.map { it['term'] }
        unreject_index_names = unreject.select { %w[i x ig gi].include?(it['flag']) }.map { it['term'] }
        unreject_glossary_names = unreject.select { %w[g ig gi].include?(it['flag']) }.map { it['term'] }

        # 明示的にリジェクトされた用語は孤立除去の対象外
        # （[-i] で i を除去した後に残る g を誤って除去しないため）
        # 原稿の印を残して棄却をやめた語も、ここに含めて登録を保つ
        explicitly_rejected = ((index_rejected + glossary_rejected + both_rejected).map { it['term'] } +
                               declined.to_a + declined_delete.to_a).uniq

        # 外すのは、レビューファイルに行があって印の無い語だけ。行の無い語は著者が
        # 判断していないので触らない——表示しない登録語（脚注参照やカラーコードの形をした
        # 自動抽出の語）まで、apply のたびにフラグを外していた
        # （index-glossary-registration-spec.md §3.1.4）
        listed = @markdown_generator.listed_term_names

        # 索引フラグの孤立除去
        stale_index = (@terms_manager.index_term_names - index_approved_names - unreject_index_names -
                       explicitly_rejected) & listed
        # [ ] で外したとき、説明文のある語は使っていない語として残す（§3.3.2）
        stale_index.each do |term_name|
          @terms_manager.remove_flag!(term_name, 'i', keep_unused: true)
          Common.log_info("索引フラグを除去: #{term_name}")
          changes_made = true
        end

        # 用語集フラグの孤立除去
        stale_glossary = (@terms_manager.glossary_term_names - glossary_approved_names_all - unreject_glossary_names -
                          explicitly_rejected) & listed
        stale_glossary.each do |term_name|
          @terms_manager.remove_flag!(term_name, 'g', keep_unused: true)
          Common.log_info("用語集フラグを除去: #{term_name}")
          changes_made = true
        end

        # --- Phase: 見出し語の綴りの修正（`- 綴り: …`・改善案 #103） ---
        # ほかの印はいまの綴りで書かれているので、すべて反映した後に綴りを直す
        changes_made = true if apply_spelling_changes!(@markdown_generator.parse_spelling_changes)

        # --- Phase: Section 4 同期処理 ---
        rejected_section_all = @markdown_generator.parse_rejected_section_all
        unreject_names = unreject.map { it['term'] }

        confirmed_rejected = rejected_section_all.select { ['', ' '].include?(it['flag']) }
                                                 .reject { unreject_names.include?(it['term']) }

        # 除外リストは「候補に再提示しない語」の記録であって、削除の指示ではない（§2.2）。
        # 登録済みの語がここにも居るなら、それは過去の書き込みが残した矛盾なので、
        # **定義文を持つ terms の側を正として除外リストから落とす**（§2.3・§3.2）。
        # かつては逆に terms から消しており、著者の手書きの定義文が失われていた。
        # この向きなら、既に矛盾を抱えたプロジェクトも次の apply で黙って正しい状態へ寄る。
        resolved = []
        if confirmed_rejected.any?
          confirmed_rejected.each do |entry|
            term_name = entry['term']
            next unless @terms_manager.term_names.include?(term_name)

            @queue_manager.unreject_term_by_name!(term_name)
            Common.log_debug("除外リストの矛盾を解消: #{term_name}（登録済みのため除外リストから外す）")
            resolved << term_name
          end

          # いま外した語を書き戻さない。残りは元から除外リストに居るので実質 no-op。
          still_rejected = confirmed_rejected.reject { resolved.include?(it['term']) }
          @queue_manager.save_rejected_terms(still_rejected) if still_rejected.any?
          changes_made = true if resolved.any?
        end

        if changes_made
          rejected_total = both_rejected.size + dropped_i.size + dropped_g.size
          # 何をどれだけ適用したかを既定ログレベルでも 1 行で報告する
          Common.log_result("辞書を更新しました（索引 #{index_count} 件・用語集 #{glossary_count} 件・" \
                            "棄却 #{rejected_total} 件）", status: :success)
          Common.log_info("読み変更: #{yomi_changes.size}件") if yomi_changes.any?
          Common.log_info('ページ生成は vs build 実行時に行われます')
        else
          Common.log_warn('変更がありませんでした')
          Common.log_info('_index_glossary_review.md でフラグを編集してください')
        end

        # _index_glossary_review.md は残す（再編集の可能性があるため）
        # vs build の clean 処理で削除される
        changes_made
      end

      # 辞書から消える語の名前。`i` だけの語の `[-i]`・`g` だけの語の `[-g]`・`[r]`。
      # `ig` の語の `[-i]` は用語集に残るので含めない（原稿の印は用語集の語として扱われる）
      def leaving_terms(index_rejected, glossary_rejected, both_rejected)
        flags_of = ->(term) { @terms_manager.find_term(term)&.dig('flags').to_s }
        (index_rejected.map { it['term'] }.select { flags_of.(it) == 'i' } +
          glossary_rejected.map { it['term'] }.select { flags_of.(it) == 'g' } +
          both_rejected.map { it['term'] }).uniq
      end

      # 棄却する語に原稿の印があれば、語ごとに確かめる。「はい」なら印を外し、
      # 「いいえ」（Enter だけ・端末でない実行を含む）なら棄却をやめる。
      # @param terms [Array<String>] 辞書から消える語
      # @return [Set<String>] 棄却をやめた語
      # @param action [String] 「棄却」か「削除」
      def confirm_markup_removal(terms, action: '棄却')
        paths = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).sort
        terms.each_with_object(Set[]) do |term, declined|
          places = IndexCommands::ManuscriptMarkup.places(term, paths)
          next if places.empty?

          where = places.size > 1 ? "#{places.first} ほか #{places.size - 1} 箇所に" : "#{places.first} に"
          if Common.confirm?("#{where} [#{term}] と書かれています。原稿の [] を外して#{action}しますか？", input: @input)
            count = IndexCommands::ManuscriptMarkup.strip!(term, paths)
            Common.log_result("原稿の [#{term}] を外しました（#{count} 箇所）", status: :success)
          else
            Common.log_warn("原稿の [#{term}] を残したので、#{action}しませんでした",
                            detail: "#{action}するには、もう一度 vs index:apply を実行して「はい」と答えてください")
            declined << term
          end
        end
      end

      # 見出し語の綴りを直す。新しい綴りが辞書にもうあれば直さずに知らせる。棄却した語の一覧に
      # 新しい綴りがあれば外す（登録と棄却の両方に載らないように）
      # @param changes [Hash{String => String}] いまの綴り → 新しい綴り
      # @return [Boolean] 1 語でも直したか
      def apply_spelling_changes!(changes)
        changes.count do |old_name, new_name|
          case @terms_manager.rename_term!(old_name, new_name)
          when :renamed
            @queue_manager.unreject_term_by_name!(new_name)
            Common.log_result("「#{old_name}」の綴りを「#{new_name}」に直しました", status: :success)
            confirm_manuscript_respelling(old_name, new_name)
            true
          when :taken
            Common.log_warn("「#{old_name}」の綴りを直せませんでした: 「#{new_name}」はすでに辞書にあります",
                            detail: '同じ語なら、どちらかを [DELETE] で消してから、もう一度直してください')
            false
          else false
          end
        end.positive?
      end

      # 原稿に古い綴りが残っていれば、原稿も直すか確かめる。索引の照合は大文字・小文字を
      # 区別し、lint は空白の違いしか見ないので、残したままだと黙って索引から外れる。
      # 「いいえ」（Enter だけ・端末でない実行を含む）なら原稿は触らずに知らせる。
      def confirm_manuscript_respelling(old_name, new_name)
        paths = IndexCommands.without_excluded_chapters(Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).sort)
        places = IndexCommands::ManuscriptMarkup.spelling_places(old_name, new_name, paths)
        return if places.empty?

        written = places.map(&:last).uniq.map { "「#{it}」" }.join
        where = places.size > 1 ? "#{places.first.first} ほか #{places.size - 1} 箇所に" : "#{places.first.first} に"
        if Common.confirm?("原稿の #{where}#{written}があります。原稿も直しますか？", input: @input)
          count = IndexCommands::ManuscriptMarkup.respell!(old_name, new_name, paths)
          Common.log_result("原稿の#{written}を「#{new_name}」に直しました（#{count} 箇所）", status: :success)
        else
          Common.log_warn("原稿の#{written}を残しました（#{places.size} 箇所）",
                          detail: "このままでは索引の「#{new_name}」に載りません。原稿を「#{new_name}」に書き換えてください")
        end
      end

      # 語の記録を辞書・棄却した語の一覧の両方から消す（[DELETE]）。誤って登録した語の
      # ゴミを残さないための操作で、棄却と違って「候補に出さない」という記録も残さない
      def delete_record!(term)
        removed = @terms_manager.remove_term!(term)
        @queue_manager.unreject_term_by_name!(term)
        if removed && !removed['definition'].to_s.strip.empty?
          Common.log_warn("説明文ごと削除しました: #{term}")
        else
          Common.log_info("削除しました: #{term}")
        end
      end

      # 用語を削除する。**定義文を持つ語は黙って消さない**
      # （`index-apply-rejected-consistency-spec.md` §3.4）。
      #
      # 定義文は著者が 1 件ずつ手で書いた資産で、機械が作り直せない。個別の分岐で
      # 経路を塞ぐより、「取り返しのつかない削除は声に出す」という規律のほうが長持ちする
      # ——`remove_term!` を呼ぶ経路が将来また増えても、そこで気づける。
      #
      # @param term_name [String] 削除する用語名
      # @return [Hash, nil] 削除したエントリ
      def remove_term_aloud!(term_name)
        removed = @terms_manager.remove_term!(term_name)
        return removed if removed.nil? || removed['definition'].to_s.strip.empty?

        Common.log_warn("用語集の定義文ごと登録を解除しました: #{term_name}")
        Common.log_warn("  → 戻すには #{ReviewMarkdownGenerator::REVIEW_FILE} の 4 節で " \
                        '[g] を入れて vs index:apply')
        removed
      end

      # 用語集の説明文バリデーション
      # require_definition: true の場合、説明文が空ならエラー
      # max_definition_length を超過している場合は警告
      def validate_glossary_definitions!(terms)
        max_length = @glossary_config[:max_definition_length]

        # 説明文の長さチェック（Markdown装飾を除去した文字数）
        terms.each do |term|
          definition = term['definition'].to_s
          next if definition.strip.empty?

          plain_text = strip_markdown(definition)
          next unless plain_text.length > max_length

          Common.log_warn(
            "用語「#{term['term']}」の説明文が #{max_length} 文字を超過しています " \
            "(#{plain_text.length} 文字)"
          )
        end

        return unless @glossary_config[:require_definition]

        missing = terms.select { it['definition'].to_s.strip.empty? }
        return if missing.empty?

        missing.each do |term|
          Common.log_error("用語「#{term['term']}」に説明文がありません")
        end
        raise "用語集の説明文が必須ですが、#{missing.size}件の用語に説明文がありません"
      end

      # Markdown装飾を除去してプレーンテキストを取得
      def strip_markdown(text)
        text
          .gsub(/\*\*(.+?)\*\*/, '\1')  # **bold**
          .gsub(/\*(.+?)\*/, '\1')      # *italic*
          .gsub(/`(.+?)`/, '\1')        # `code`
          .gsub(/\[(.+?)\]\(.+?\)/, '\1') # [link](url)
          .gsub(/^#+\s*/, '')           # # heading
          .gsub(/^\s*[-*]\s+/, '')      # - list item
          .gsub(/\n+/, ' ')             # newlines to space
          .strip
      end

      # 索引・用語集ページを生成（内部用 - vs build から呼ばれる）
      # @param chapters [Array<String>] 対象章のリスト
      def build_index!(chapters)
        Common.log_action('索引・用語集ページを生成しています...')

        # 本文スキャン（索引タグ付け＋用語集リンク生成）
        scanner = IndexMatchScanner.new(defer_warnings: true)
        scanner.scan_all_chapters!(chapters, read_only: false)

        # UnifiedPageBuilder で索引＋用語集を生成
        builder = UnifiedPageBuilder.new(glossary_config: @glossary_config)

        # 索引ページ生成
        builder.build_index!
        report_reference_style(builder)

        # 用語集ページ生成（glossary_enabled かつ g フラグの用語がある場合）
        # スキャンは辞書を書かない（R1）ためリロード不要
        if glossary_enabled?
          glossary = @terms_manager.glossary_terms
          builder.build_glossary!(glossary)
          warn_unmatched_glossary_terms(glossary, scanner.glossary_backlinks, chapters)
        end

        Common.log_success('索引・用語集ページの生成が完了しました')

        # R7: 索引候補の抽出（vs index:auto）が未実施の章を検出して案内
        warn_unscanned_chapters(chapters)
        # 主要参照が未指定で広く散らばっている語を要約 1 行で促す
        warn_missing_main_references(chapters)

        return unless scanner.config_missing || scanner.no_matches

        IndexCommands.add_post_build_message(IndexCommands::INDEX_TERMS_MISSING_MESSAGE)
        # 画面に 🟡 を出す以上は集計にも載せる（出ているのに「良好」と総括しない）。
        PreProcessCommands::IssueRegistry.record(
          severity: :warn, category: :index,
          message: '索引語辞書がありません（vs index:auto → vs index:apply で作成できます）'
        )
      end

      # 用語集機能が有効か
      def glossary_enabled?
        @glossary_config[:enabled] == true
      end

      # R7: ビルド対象のうち index:auto が未走査の章があれば、ビルド末尾の案内へ積む。
      # 旧辞書（scanned_chapters キーなし）では判定しない——誤警告を避けるため
      # @param chapters [Array<String>] ビルド対象章
      def warn_unscanned_chapters(chapters)
        scanned = @terms_manager.scanned_chapters
        return if scanned.nil?

        unscanned = chapters.map { File.basename(it.to_s, '.md') } - scanned
        return if unscanned.empty?

        IndexCommands.add_post_build_message(
          "🟡 索引候補の抽出が未実施の章があります: #{unscanned.join(', ')} → vs index:auto を実行してください"
        )
        # 章別サマリーへブリッジする。どの章が未走査かは特定できているので章ごとに積む。
        unscanned.each do |chapter|
          PreProcessCommands::IssueRegistry.record(
            chapter: chapter, severity: :warn, category: :index,
            message: '索引候補の抽出が未実施です（vs index:auto を実行してください）'
          )
        end
      end

      # 参照を絞ったことをビルド末尾で報告する（R6・no silent caps）。
      #
      # 索引が短くなった理由が設定にあると分からないと、著者は「索引語が
      # 消えた」と読む。何語をどの設定で絞ったかまで書く。
      # @param builder [UnifiedPageBuilder] 生成を終えたビルダー
      def report_reference_style(builder)
        limitation = builder.reference_limitation
        return unless limitation.any?

        message = if limitation.style == 'main_only'
                    "💡 索引を主要参照のみで組みました（index.reference_style: main_only・#{limitation.size} 語）"
                  else
                    "💡 索引の副次参照を #{limitation.size} 語で #{limitation.limit} 件までに絞りました" \
                    "（index.max_sub_references: #{limitation.limit}）"
                  end
        IndexCommands.add_post_build_message(message)
      end

      # 広く散らばっているのに主要参照が未指定の索引語を促す（R7）。
      #
      # **要約 1 行だけ**にする。実測で該当は 30〜38 語あり、語ごとに 1 行ずつ出すと
      # ビルドログが埋まる。しかもそこから修正には進めない——直す場は
      # レビューファイルなので、導線はそちらへ向ける（語ごとの候補は R2 が出す）。
      #
      # 部分ビルドでは黙る。出現章数の比率は全章を走査したときにしか意味を持たず、
      # 1 章だけを対象にすると全語が「広い」判定になる
      # （warn_unmatched_glossary_terms と同じ立場）。
      # `reference_style: all` で機能を切っている著者にも促さない。
      # @param chapters [Array<String>] ビルド対象章
      def warn_missing_main_references(chapters)
        return if main_reference_disabled?

        build_targets = chapters.map { File.basename(it.to_s, '.md') }
        return unless full_catalog_scope?(build_targets)

        pending = @terms_manager.index_terms.reject { it['main'] }
        return if pending.empty?

        spreads = IndexCommands::TermSpread.measure(pending, chapters)
        wide = IndexCommands::TermSpread.common_terms(spreads, ratio: MAIN_REFERENCE_HINT_RATIO)
        return if wide.empty?

        IndexCommands.add_post_build_message(
          "🟡 主要参照が未指定の索引語が #{wide.size} 語あります（索引が引きにくくなります）\n" \
          '🟡  vs index:auto を実行すると、章の候補付きでレビューファイルに一覧できます'
        )
        # 特定の章の欠陥ではないので chapter は付けない。件数は語ごとではなく
        # **1 件**だけ積む——30 件積むと章別サマリーが索引の話で埋まる。
        PreProcessCommands::IssueRegistry.record(
          severity: :warn, category: :index,
          message: "主要参照が未指定の索引語が #{wide.size} 語あります（vs index:auto で候補を確認できます）"
        )
      end

      # R4: ビルド対象章に 1 回も出現しない用語集語を警告する（掲載自体は維持）。
      # catalog 未登録の原稿に出現があるならその章名を添え、どこにも無ければその旨を伝える。
      # 除外したい場合の判断（-g フラグ）は著者に委ねる——定義は書籍の語彙資産のため。
      #
      # 判定材料は「今回のスキャン結果」なので、章を絞った実行では出現しないのが当然になる
      # （1 章だけを対象にすると用語集語がほぼ全滅して誤検知の山になる）。
      # 全章を走査したときだけ意味を持つ検査なので、部分実行では黙る。
      # 詳細 → preflight-glossary-warning-scope-report.md
      # @param glossary_terms [Array<Hash>] 用語集対象の用語
      # @param glossary_backlinks [Hash{String => Array}] 今回のスキャンで出現した語 → 出現箇所
      # @param chapters [Array<String>] ビルド対象章
      def warn_unmatched_glossary_terms(glossary_terms, glossary_backlinks, chapters)
        build_targets = chapters.map { File.basename(it.to_s, '.md') }
        return unless full_catalog_scope?(build_targets)

        missing = glossary_terms.reject { glossary_backlinks.key?(it['term']) }
        return if missing.empty?

        all_contents = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).to_h do |path|
          [File.basename(path, '.md'), File.read(path, encoding: 'utf-8')]
        end

        missing.each do |term|
          name = term['term']
          found = all_contents.keys.select { all_contents[it].include?(name) }
          outside = found - build_targets
          hint = if outside.any?
                   # 走査は catalog 全章を覆っている（上のガード）ため、ここに来るのは
                   # contents/ にはあるが catalog.yml に載っていない原稿に限られる
                   "catalog 未登録の #{outside.join(', ')} に出現"
                 elsif found.any?
                   "#{found.join(', ')} に文字列出現はあるがリンク化されていません（コード内・タグ内等）"
                 else
                   '原稿のどこにも出現しません（語の変更・削除？）'
                 end
          Common.log_warn("用語集語がビルド対象章に出現しません: #{name}（#{hint}）")
          # 章別サマリーへブリッジする。全章走査時にしか到達しないので（上のガード）
          # ここに来る指摘は「辞書に残った死語」＝原稿とのズレであり、集計に載せる価値がある。
          # 特定の章の欠陥ではないため chapter は付けない（章別サマリーには出ず、
          # 最終行の総括にだけ効く。直し方は上のメッセージが言い切っている）。
          PreProcessCommands::IssueRegistry.record(
            severity: :warn, category: :index,
            message: "用語集語が原稿に出現しません: #{name}"
          )
        end
      end

      # 走査対象が catalog の全章を覆っているか（R4 の前提条件）。
      # catalog を読めない場合は従来どおり検査する（判定材料が無いのに黙るのは危険）。
      # @param build_targets [Array<String>] 走査した章の basename
      def full_catalog_scope?(build_targets)
        catalog = Build::CatalogLoader.load_existing_basenames
        return true if catalog.empty?

        (catalog - build_targets).empty?
      rescue StandardError
        true
      end

      # リジェクト済み候補の一覧表示
      def list_rejected_terms
        @queue_manager.list_rejected_terms
      end

      # リジェクト解除
      # @param term_or_number [String] 用語名または番号
      def unreject_term!(term_or_number)
        @queue_manager.unreject_term!(term_or_number)
      end

      # リジェクト履歴をクリア
      def reset_rejected!
        @queue_manager.reset_rejected!
      end

      private


      # 選べる候補だけを残す。既に辞書にある語とリジェクト済みの語を落とす。
      # @return [Array(Array<Hash>, Integer)] 候補と、リジェクトで落とした件数
      def selectable_candidates(candidates)
        existing = @terms_manager.listed_term_names
        rejected = @queue_manager.load_rejected_terms
        rejected_count = 0

        selectable = candidates.reject do |candidate|
          term = candidate['term']
          next true if existing.include?(term)
          next false unless rejected.include?(term)

          rejected_count += 1
          true
        end

        [selectable, rejected_count]
      end

      # 使っていない語（§3.3.2）のうち、原稿に書き戻された語を候補に加える。抽出の経路が
      # 拾っていない語もあるので、辞書の語として採点して足す。以前の説明文を添えるので、
      # [g] にすれば書き直さずに戻る
      def with_returning_unused_terms(selectable, chapters)
        sources = context_source_chapters(chapters)
        by_name = selectable.to_h { [it['term'], it] }
        returning = @terms_manager.unused_terms.filter_map do |entry|
          contexts = collect_contexts_for_term(entry['term'], sources)
          next if contexts.empty?

          base = by_name.delete(entry['term']) ||
                 { 'term' => entry['term'], 'yomi' => entry['yomi'], 'contexts' => contexts,
                   'score' => @extractor&.score_terms([entry])&.dig(entry['term']) || 0 }
          base.merge('definition' => entry['definition'])
        end
        by_name.values + returning
      end

      # 原稿に出てこない使っていない語
      def absent_unused_terms(chapters)
        sources = context_source_chapters(chapters)
        @terms_manager.unused_terms.select { collect_contexts_for_term(it['term'], sources).empty? }
      end

      # 5 節（原稿に出てこない語）に並べる項目。種類（registered / unused / rejected）を添える
      def absent_entries(registered, unused, rejected)
        registered.map { it.merge('kind' => 'registered') } +
          unused.map { it.merge('kind' => 'unused') } +
          rejected.map { it.merge('kind' => 'rejected') }
      end

      # 表示用のスコア表（用語 → スコア）。辞書には持たないので毎回作る。
      #
      # 登録済みの語は候補から外れている（selectable_candidates が落とす）ので、
      # 候補側のスコアだけでは登録語のスコアが空になる。抽出器に同じ式で
      # 算出させて補う——原稿に出現しない語はここでも取れず、nil のまま残る。
      # @return [Hash{String => Float}]
      def candidate_scores_by_name(selectable, candidates)
        from_candidates = (candidates + selectable).to_h { [it['term'], it['score']] }
        return from_candidates unless @extractor

        @extractor.score_terms(@terms_manager.load_terms).merge(from_candidates)
      end

      # レビューファイルの「主要参照」行を辞書へ反映する。
      #
      # 著者は章トークン（21 / 21,22 / 21-22）で書く。辞書へは basename で持つ
      # ——番号だけだと改番で意味が変わり、スラッグだけだと同名章と衝突する。
      # 解決は TokenResolver（章トークン解釈の正典）に委ねる。
      #
      # 主要参照の欄が空の索引語（`[i]`・`[ig]`）は「付けない」と記録する（`main: []`）。
      # 辞書の `main` が無いのは「まだ決めていない」で、次の `vs index:auto` が推測（`m?`）を
      # 付ける。空の配列と区別しないと、著者が `m?12` を消して「付けない」と決めても、
      # 次の実行で推測が付き直し、そのまま apply すると採用されていた
      # （index-glossary-registration-spec.md §3.1.1・改善案 #101）。
      def apply_main_references!(main_references)
        return false if main_references.empty?

        resolver = TokenResolver::Resolver.new
        changed = false

        main_references.each do |term, tokens|
          entry = @terms_manager.find_term(term) or next

          # 主要参照は索引の機能なので、索引に載らない語（[-igm?21] で外した語など）には
          # 書かれていても記録しない
          next unless entry['flags'].to_s.include?('i')

          chapters = if tokens then resolve_main_chapters(resolver, tokens, term)
                     elsif declinable_main?(entry) then []
                     else next
                     end
          next if !entry['main'].nil? && chapters == Array(entry['main'])

          @terms_manager.merge_terms!([{ 'term' => term, 'main' => chapters }], flags: '')
          log_main_reference_change(term, chapters, entry['main'])
          changed = true
        end

        changed
      end

      # 「主要参照を付けない」を記録できる語か。主要参照は索引の機能なので索引語に限り、
      # 機能を切った本（`index.reference_style: all`）では記録しない
      def declinable_main?(entry) = entry['flags'].to_s.include?('i') && !main_reference_disabled?

      # 主要参照の変化を知らせる。まだ決めていなかった語に「付けない」を記録するのは、
      # 初回の apply で登録語の数だけ起きるので黙る
      def log_main_reference_change(term, chapters, before)
        if chapters.any?
          Common.log_info("主要参照を設定: #{term} → #{chapters.join(', ')}")
        elsif Array(before).any?
          Common.log_info("主要参照を外しました: #{term}")
        end
      end

      # 章トークンを basename へ解決する。解決できないトークンは捨てずに知らせる
      # ——黙って落とすと「書いたのに効かない」になる（警告は具体的な修正案とセットで）。
      def resolve_main_chapters(resolver, tokens, term)
        entries = resolver.resolve(tokens)
        resolved = entries.select(&:valid?).map(&:basename)
        return resolved if resolved.size == tokens.size || resolved.size >= entries.size

        Common.log_warn(
          "「#{term}」の主要参照に解決できない章があります: #{tokens.join(', ')}",
          detail: "指定できるのは章番号（21）・範囲（21-22）・章名（21-markdown-tutorial）です。" \
                  "解決できたのは #{resolved.empty? ? 'なし' : resolved.join(', ')} です"
        )
        resolved
      end

      # 一般語とみなす出現章数の比率（book.yml で調整可）。
      # 「どこから外すべきか」は本の性格で変わるので、つまみとして意味がある。
      def common_term_ratio = @config[:common_term_ratio].to_f

      # 主要参照の指定を促す語の広がり（book.yml のキーにはしない）。
      #
      # つまみにしなかった理由は 2 つある。(1) 著者が 0.33 を 0.4 に変えるべきかを
      # 判断する材料が無い。(2) 唯一の実需だった「警告を止めたい」は
      # `reference_style: all`（主要参照の機能を丸ごと切る）が担うべきで、
      # 比率を 1.0 にして黙らせるのは意図が値から読めない。
      #
      # 値は実測から。本書（27 章・索引語 153 語）で 55 語が該当し、
      # そのうち 53 語に候補を出せた（index-main-reference-spec.md §7.1）。
      MAIN_REFERENCE_HINT_RATIO = 0.33

      # 主要参照の扱いを著者が切っているか（`reference_style: all`）。
      # 切っているなら候補も警告も出さない——使わない機能の未設定を促すのは筋が通らない。
      def main_reference_disabled? = @config[:reference_style].to_s == 'all'

      # 辞書の basename を、著者が読みやすい章トークン（番号）へ落とす
      def chapter_tokens(main) = Array(main).map { it.to_s[/\A\d+/] || it.to_s }

      # 主要参照が未指定の語に候補を添える（R2・対象は R7）。
      #
      # **未指定の語すべてが対象。** 当初は「広く散らばっている語」に絞っていたが、
      # フラグ欄 `[igm33]` で書けるようになり行数が増えないため、絞る理由が消えた。
      # 除くのは「索引に出るページ番号が 1 つしかない語」だけで、その判定は
      # 出現回数を数えている Suggester 側が持つ（実測で該当は 1 語）。
      def suggest_main_references(terms, chapters)
        return {} if main_reference_disabled?

        pending = terms.reject { it['main'] }
        return {} if pending.empty?

        IndexCommands::MainReferenceSuggester.suggest(pending, chapters)
      end

      # 本文の分量から目安語数を得る（帯の境目に使う）
      def current_estimate(chapters)
        prose_chars = IndexCommands::IndexSizeEstimator.prose_chars_of(chapters)
        IndexCommands::IndexSizeEstimator.new(prose_chars).estimate(@config[:target_terms])
      end

      # 帯の並び（TermRanking::Entry）を、レビュー md が扱う候補 Hash へ戻す。
      # 順位の情報は Entry 側にしかないので、並び順はここで保つ。
      def review_entries(entries, by_name)
        return [] if entries.nil?

        entries.filter_map do |entry|
          candidate = by_name[entry.term]
          next unless candidate

          normalize_candidate(candidate).merge('is_new' => true)
        end
      end

      # 表示用の素材を集める。算出はここで済ませ、Reporter は組み立てに徹する。
      # @param chapters [Array<String>] 対象章
      # @param candidates [Array<Hash>] 候補（スコア付き）
      # @return [IndexPlanReporter]
      def build_plan_reporter(chapters, candidates, extractor: nil)
        prose_chars = IndexCommands::IndexSizeEstimator.prose_chars_of(chapters)
        estimator = IndexCommands::IndexSizeEstimator.new(prose_chars)
        estimate = estimator.estimate(@config[:target_terms])
        registered = @terms_manager.index_terms

        plan = IndexCommands::IndexPlanReporter::Plan.new(
          chapters:,
          prose_chars:,
          registration: plan_registration(registered),
          estimate:,
          all_estimates: estimator.all_presets,
          bands: build_bands(registered, candidates, estimate, extractor)
        )
        IndexCommands::IndexPlanReporter.new(plan)
      end

      # plan に出す登録の内訳。主要参照が決まっていない語は、辞書に `main` が無い索引語
      # （`main: []` は「付けない」と決めた語なので数えない。index-glossary-registration-spec.md §3.1.1）
      def plan_registration(index_terms)
        IndexCommands::IndexPlanReporter::Registration.new(
          index: index_terms.size,
          glossary: @terms_manager.glossary_terms.size,
          rejected: @queue_manager.rejected_count,
          undecided_main: main_reference_disabled? ? nil : index_terms.count { it['main'].nil? }
        )
      end

      # 登録語と候補を同じ土俵で並べて帯に分ける。
      # 抽出器が無い（auto_discovery: false）ときは帯を作らない——候補が無いのに
      # 「推奨候補 0 件」と出すと、設定で切っているのか語が無いのか区別できない。
      def build_bands(registered, candidates, estimate, extractor)
        return nil if extractor.nil? || candidates.empty?

        IndexCommands::TermRanking.build(
          registered:,
          registered_scores: extractor.score_terms(registered),
          candidate_scores: candidates.to_h { [it['term'], it['score'].to_f] },
          target: estimate.range.end,
          pool: @config[:candidate_pool].to_f
        )
      end

      # 候補にも主要参照の推測（`[m?95]`）を添え、その章の文脈を先頭に出す。
      #
      # 推測は登録語にしか付けていなかったので、「Re:VIEW Starter」（95 章の章題で 12 回出る）を
      # 候補として採るとき、著者は説明している章を自分で探して書き足すことになった。文脈も
      # 章番号の若い順に 2 件だけ出していたため、前書きと早見表の 1 回ずつが並び、肝心の
      # 95 章は見えなかった（改善案 #99）。登録語と同じ式（MainReferenceSuggester）で推測する。
      # @param bands [Array<Array<Hash>>] 推奨候補・一般候補
      # @return [Array<Array<Hash>>] 同じ並びの帯
      def with_suggested_main(bands, chapters)
        suggestions = suggest_main_references(bands.flatten, chapters)
        bands.map do |band|
          band.map do |candidate|
            main = suggestions[candidate['term']] or next candidate

            candidate.merge('main_tokens' => chapter_tokens(main), 'main_suggested' => true,
                            'contexts' => main_chapter_first(candidate, main))
          end
        end
      end

      # 主要参照の章の文脈を先頭へ。抽出の経路がその章の文脈を拾っていなければ、原稿から作る
      def main_chapter_first(candidate, main)
        contexts = Array(candidate['contexts'])
        own, others = contexts.partition { it['chapter'] == main }
        if own.empty?
          path = resolve_chapter_path(main)
          snippet = path ? extract_surrounding_context(File.read(path, encoding: 'utf-8'), candidate['term']) : ''
          own = [{ 'chapter' => main, 'context' => snippet }] unless snippet.empty?
        end
        own + others
      end

      # 候補の文脈を正規化
      def normalize_candidate(candidate)
        candidate.merge('contexts' => deduplicate_contexts(candidate['contexts']))
      end

      def deduplicate_contexts(contexts)
        return [] unless contexts&.any?

        seen = {}
        contexts.each_with_object([]) do |ctx, result|
          chapter = ctx['chapter'] || ctx[:chapter] || 'unknown'
          context_text = ctx['context'] || ctx[:context] || ''
          key = "#{chapter}|#{context_text}"
          next if seen[key]

          seen[key] = true
          result << { 'chapter' => chapter, 'context' => context_text }
        end
      end

      # 設定を読み込み
      # 共通設定（index_glossary）と個別設定（index）をマージ
      # @return [Hash] index設定
      def load_index_config
        load_shared_config.merge(Common::CONFIG.index.to_h)
      end

      # glossary設定を読み込み
      # 共通設定（index_glossary）と個別設定（glossary）をマージ
      # @return [Hash] glossary設定
      def load_glossary_config
        load_shared_config.merge(Common::CONFIG.glossary.to_h)
      end

      # 共通設定（index_glossary）を読み込み
      # @return [Hash] 共通設定
      def load_shared_config
        Common::CONFIG.index_glossary.to_h
      end

      # 手動登録の用語を抽出
      # @param chapters [Array<String>] 対象章のリスト（ベースネームまたはフルパス）
      # @return [Array<Hash>] 手動登録の用語のリスト
      def extract_manual_markup_terms(chapters)
        terms = []
        yomi_inferrer = YomiInferrer.new
        # R9 でスキップした語 → 出現章のリスト（章ごとに 1 回だけ警告するため集約）
        skipped_short_terms = Hash.new { |h, k| h[k] = [] }

        chapters.each do |chapter|
          # ベースネームの場合はフルパスに変換
          chapter_path = resolve_chapter_path(chapter)
          next unless chapter_path && File.exist?(chapter_path)

          content = File.read(chapter_path, encoding: 'utf-8')
          # コード（フェンス／インライン）を除外してから索引記法を拾う。
          # 素朴な /```...```/ は地の文中のインライン ``` でフェンス対がズレ、
          # コード例の [###] や [00, 90-98, 99] を誤検出するため状態機械方式を使う。
          content_without_code = CodeBlockStripper.strip(content)
          chapter_name = File.basename(chapter_path, '.*')

          # [用語|読み] 形式を検出（コードフェンス除外済みコンテンツから）。
          # 綴りの定義元は IndexMarkup（インライン脚注 ^[A|B] を除外する）。
          content_without_code.scan(IndexMarkup::TERM_WITH_YOMI_PATTERN) do |term, yomi|
            next if term.nil? || term.empty?

            lineno = content_without_code[0...::Regexp.last_match.begin(0)].count("\n") + 1
            context = extract_surrounding_context(content, term)
            terms << {
              'term' => term.strip,
              'yomi' => yomi.strip,
              'explicit_yomi' => true,
              'place' => "#{chapter_name}:#{lineno}",
              'contexts' => [{ 'chapter' => chapter_name, 'context' => context }]
            }
          end

          # [用語] 形式を検出（読みなし、コードフェンス除外済み）。
          # 綴りの定義元は IndexMarkup。パターン側でリンク・画像記法 [text](url) と
          # インライン脚注 ^[本文] を、skip_term? で参照脚注 [^1] を落とす。
          # ここは | を含まない語だけを見る（[用語|読み] は上の走査の担当で、
          # 汎用の TERM_PATTERN に替えると同じ語を二重登録する）。
          # 参照リンクとタスクリストのマーカー（`- [x]`）は、ビルドや lint と同じく
          # IndexMarkup.other_notation? で除く。マーカーの判定は行頭からの並びを見るので、
          # 行ごとに照合する（改善案 #99: 21 章の `- [x]` を単位・記号として警告していた）
          labels = IndexMarkup.link_labels(content_without_code)
          matches = content_without_code.each_line.with_index(1).flat_map do |line, lineno|
            line.to_enum(:scan, IndexMarkup::TERM_ONLY_PATTERN).map { [::Regexp.last_match, lineno] }
          end
          matches.each do |match, lineno|
            term = match[1]
            next if IndexMarkup.skip_term?(term)
            next if IndexMarkup.other_notation?(match, labels)
            next if term.match?(/^https?:/) # URL を除外

            # R9: 単位・記号表記（[eV] [Hz] [g] 等）は登録せず、集約して後で警告
            if term.match?(ASCII_SHORT_TERM_PATTERN)
              skipped_short_terms[term] << chapter_name
              next
            end

            yomi = yomi_inferrer.available? ? yomi_inferrer.infer(term) : term
            context = extract_surrounding_context(content, term)
            terms << {
              'term' => term.strip,
              'yomi' => yomi,
              'place' => "#{chapter_name}:#{lineno}",
              'contexts' => [{ 'chapter' => chapter_name, 'context' => context }]
            }
          end

          # [|] や [||] など、パイプ文字のみで構成される用語を検出
          content_without_code.scan(/\[(\|+)\]/) do |match|
            term = match[0]
            context = extract_surrounding_context(content, term)
            terms << {
              'term' => term,
              'yomi' => term,
              'contexts' => [{ 'chapter' => chapter_name, 'context' => context }]
            }
          end
        end

        warn_skipped_short_terms(skipped_short_terms)

        # 出現ごとに返す（同じ語が何か所にあるかを、棄却した語の知らせに使う）
        terms
      end

      # 手動登録の語のうち、登録してよい語（1 語 1 件）。
      #
      # 原稿の `[語]` は、**辞書に無い語を登録する入口**である。辞書にすでにある語は、
      # 著者がレビューで決めた登録（用語集だけ・主要参照）を変えない——以前は `i` を
      # 足し直し、`[g]` にした語が `ig` へ戻っていた。棄却した語は登録せず、原稿の印を
      # 外すか除外を解くよう知らせる（index-glossary-registration-spec.md §3.1.2・改善案 #100）。
      # @param occurrences [Array<Hash>] extract_manual_markup_terms の戻り（出現ごと）
      # @return [Array<Hash>]
      def fresh_manual_terms(occurrences)
        known = @terms_manager.load_terms.to_h { [it['term'], it] }
        rejected = @queue_manager.load_rejected_terms.to_set

        occurrences.group_by { it['term'] }.filter_map do |term, found|
          places = found.map { it['place'] }.compact.uniq
          # 使っていない語（flags が空）は、原稿に書き戻した語として登録し直す
          if (entry = known[term]) && !entry['flags'].to_s.empty?
            warn_markup_yomi_mismatch(term, entry, found)
            next
          end
          if rejected.include?(term)
            warn_rejected_markup(term, places)
            next
          end
          found.first.except('place', 'explicit_yomi')
        end
      end

      # 原稿に添えた読みが辞書の読みと違う。辞書を正とし、直す場所を案内する
      def warn_markup_yomi_mismatch(term, entry, found)
        written = found.select { it['explicit_yomi'] }.map { it['yomi'] }.uniq - [entry['yomi']]
        return if written.empty?

        Common.log_warn(
          "原稿の [#{term}|#{written.first}] の読みが、辞書の読み（#{entry['yomi']}）と違います（#{found.first['place']}）",
          detail: "辞書の読みを使います。直すときは #{ReviewMarkdownGenerator::REVIEW_FILE} の ( ) を書き換えて vs index:apply を実行してください"
        )
      end

      # 棄却した語に、原稿で印が付いている
      def warn_rejected_markup(term, places)
        shown = places.first(3).join(', ')
        shown += places.size > 3 ? " ほか #{places.size - 3} 箇所に" : " に"
        Common.log_warn(
          "#{shown} [#{term}] がありますが、棄却した語です。索引には載りません",
          detail: "載せるなら #{ReviewMarkdownGenerator::REVIEW_FILE} の 4 節で [i] にして vs index:apply を実行してください。" \
                  "載せないなら、原稿の [] を外してください"
        )
      end

      # R9 でスキップした短い ASCII 語を警告する（警告親切方針: before→after ＋出現箇所）
      # @param skipped [Hash{String => Array<String>}] 語 → 出現章のリスト
      def warn_skipped_short_terms(skipped)
        skipped.each do |term, chapter_names|
          Common.log_warn(
            "[#{term}] は単位・記号表記とみなし索引登録しません（#{chapter_names.uniq.join(', ')}）",
            detail: "索引に載せる場合は読み付きで [#{term}|よみ] と書いてください"
          )
        end
      end

      # 候補を抽出
      # @param chapters [Array<String>] 対象章のリスト
      # @return [Array<Hash>] 候補のリスト
      def extract_candidates(chapters)
        # 帯の算出（build_bands）で登録語のスコア付けに使い回すため保持する
        extractor = @extractor = IndexCandidateExtractor.new
        extractor.extract_from_chapters!(chapters)

        # 読み推測用
        yomi_inferrer = YomiInferrer.new

        # 既存用語の読みを取得（学習済みの読みを優先するため）
        existing_yomi = @terms_manager.load_terms.to_h { |t| [t['term'], t['yomi']] }

        extractor.all_candidates.filter_map do |term|
          # ゴミ用語をフィルタリング
          next nil if garbage_term?(term)

          # 既存の読みを優先、なければ推測
          yomi = existing_yomi[term] || (yomi_inferrer.available? ? yomi_inferrer.infer(term) : term)

          contexts = extractor.term_contexts[term] || []
          normalized_contexts = contexts.map do |ctx|
            {
              'chapter' => ctx[:chapter] || ctx['chapter'],
              'context' => ctx[:context] || ctx['context']
            }
          end

          {
            'term' => term,
            'yomi' => yomi,
            'score' => extractor.term_scores[term] || 0,
            'contexts' => normalized_contexts
          }
        end
      end

      # 登録済み用語に文脈と用語集登録状態を付与
      # R5: 原稿推敲に追従するため、現原稿に無い context を捨て、空になったら複数章ぶん補充する
      # （温存条件は context_live? に集約・R6）
      # @param terms [Array<Hash>] 用語のリスト
      # @param chapters [Array<String>] 対象章のリスト
      # @return [Array<Hash>] 文脈付き用語のリスト
      def enrich_terms_with_context(terms, chapters, scores: {})
        context_sources = context_source_chapters(chapters)
        scanned = chapters.map { File.basename(it.to_s, '.md') }.to_set
        # 一般語（外す印の推奨）と主要参照の推測は、索引の仕組みなので索引に載せている語だけに
        # 当てる。用語集だけの語に当てると、行の印が [-im?00] になって g が消え、そのまま
        # apply すると用語集から外れていた（index-glossary-registration-spec.md §2.1）
        index_terms = terms.select { it['flags'].to_s.include?('i') }
        spreads = IndexCommands::TermSpread.measure(index_terms, chapters)
        common = IndexCommands::TermSpread.common_terms(spreads, ratio: common_term_ratio)
                                          .to_h { [it.term, it] }
        suggestions = suggest_main_references(index_terms, chapters)

        terms.map do |term|
          enriched = term.dup
          flags = term['flags'].to_s

          # スコアは辞書に持たない（出現由来の派生データ）。表示のたびに合流させる。
          # 原稿に出現しない語はスコアが取れない——死語として著者に見せる価値がある。
          enriched['score'] = scores[term['term']]

          # 主要参照はレビューファイルで編集できるよう章トークンとして見せる。
          # 辞書は basename で持つが、著者に見せるのは番号のほうが読みやすい。
          # 未指定の語には候補を添える（R2）。候補は `NEW!` 付きで出し、
          # 機械の推測であることを行の上で分かるようにする。
          if term['main']
            enriched['main_tokens'] = chapter_tokens(term['main'])
          elsif (suggested = suggestions[term['term']])
            enriched['main_tokens'] = chapter_tokens(suggested)
            enriched['main_suggested'] = true
          end

          # 広く散らばりすぎている語は「一般語」として行末に注記し、外す印を推奨する（R5）。
          # 外すか残すかは著者が決めるので、ここでは事実を添えるだけ。
          # 順位で決める「見直し候補」はなくした——著者が選んだ語の 4 割が出て、
          # 機械が当てられなかった語を並べるだけだった（index-glossary-registration-spec.md §5.2）
          if (spread = common[term['term']])
            enriched['common_term'] = true
            enriched['spread_text'] = spread.to_s
          end

          # flags に基づいて索引・用語集の登録状態を反映
          enriched['in_index'] = flags.include?('i')
          enriched['in_glossary'] = flags.include?('g')

          # 文脈は毎回そのときの原稿から拾う。辞書に写しを持たないので古びようがない
          # （旧辞書が contexts を抱えていても読まずに捨てる）。
          enriched['contexts'] = annotate_out_of_scope_contexts(
            collect_contexts_for_term(term['term'], context_sources), scanned
          )

          enriched
        end
      end

      # リジェクト済み用語に文脈とスコアを付与
      # @param candidates [Array<Hash>] 現在の候補リスト（スコア復元用）
      # @return [Array<Hash>] 文脈付きリジェクト用語のリスト
      def enrich_rejected_with_context(candidates = [])
        rejected = @queue_manager.load_rejected_terms_with_metadata
        # 登録語と同じく、索引の対象から外した章（index_glossary.exclude_chapters）は文脈に
        # 使わない。contents/ の全章を見ていたため、97 章（見本）の文が並んでいた（改善案 #99）
        chapters = context_source_chapters([])

        rejected.map do |item|
          enriched = item.dup

          # スコアはいまの候補のものだけを出す。棄却した語のファイルに残るのは外した時点の値で、
          # 数え方を直しても古いまま出ていた（「TeX」が「LaTeX」込みの 285 点・改善案 #99）。
          # いまの候補に無い語（原稿から消えた語など）は、古い値も出さない——
          # 「Step - スコア: 1790.0 - [原稿に出現しません]」と食い違って見えていた
          candidate = candidates.find { it['term'] == item['term'] }
          enriched['score'] = candidate&.dig('score')

          # 文脈は登録済み用語と同じく毎回原稿から拾う（棄却リストの写しは使わない）
          enriched['contexts'] = collect_contexts_for_term(item['term'], chapters)

          enriched
        end
      end

      # context の収集上限（章数）。候補抽出側（IndexCandidateExtractor）の蓄積数
      # `.first(3)` と揃える——レビュー表示は先頭 2 件のためこれで十分
      MAX_CONTEXT_CHAPTERS = 3

      # 用語の文脈を全対象章から収集する（出現する章ごとに 1 件・上限 MAX_CONTEXT_CHAPTERS）
      # 最初の 1 章で打ち切ると複数章で使われる語の使用例が 1 件に痩せるため（報告書 §5.1）
      # @param term [String] 用語
      # @param chapters [Array<String>] 対象章のリスト（ベースネームまたはフルパス）
      # @return [Array<Hash>] 文脈情報のリスト
      def collect_contexts_for_term(term, chapters)
        contexts = []
        chapters.each do |chapter|
          # ベースネームの場合はフルパスに変換
          chapter_path = resolve_chapter_path(chapter)
          next unless chapter_path && File.exist?(chapter_path)

          content = File.read(chapter_path, encoding: 'utf-8')
          next unless content.include?(term)

          context = extract_surrounding_context(content, term)
          next if context.to_s.empty?

          contexts << { 'chapter' => File.basename(chapter_path, '.*'), 'context' => context }
          break if contexts.size >= MAX_CONTEXT_CHAPTERS
        end
        contexts
      end

      # 文脈を拾う章の並び。指定章を先頭に置き、その後ろに残りの章を足す。
      #
      # 章を指定した実行（`vs index:auto 33`）でも、指定章に出てこない用語の文脈欄を
      # 空にしないための順番。空欄は「原稿から消えた語」と見分けが付かず、著者は
      # 索引に残すべきか判断できなくなる。一方で先頭に指定章を置くのは、
      # collect_contexts_for_term が MAX_CONTEXT_CHAPTERS で打ち切るため——いま
      # レビューしている章での使われ方を最優先で見せる。
      # @param chapters [Array<String>] 今回走査する章のリスト
      # @return [Array<String>] 章ベースネームの配列（指定章が先頭）
      def context_source_chapters(chapters)
        scanned = chapters.map { File.basename(it.to_s, '.md') }
        # index_glossary.exclude_chapters の章（記法の見本など）は、文脈の例としても見せない
        others = IndexCommands.without_excluded_chapters(
          Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { File.basename(it, '.md') }.sort
        )
        scanned + (others - scanned)
      end

      # 今回対象外の章から拾った context に表示用マークを付ける（判断材料の誤解防止・§4.3-4）。
      # レビュー md の表示にのみ使われ、apply のパース時に注記は剥がされるため辞書へは戻らない。
      #
      # 「今回走査しなかっただけ」と「catalog に載っていない」は区別する。後者はその章が
      # 本に入らないということで、索引にページ番号が付かない。著者が下す判断も変わる
      # （章を catalog へ戻すか、語を索引から外すか）。ビルド時の警告が
      # 「catalog 未登録の X に出現」と言い分けているのと同じ区別をレビューでも見せる。
      # @param contexts [Array<Hash>] 文脈情報のリスト
      # @param scanned [Set<String>] 今回走査した章のベースネーム
      # @return [Array<Hash>]
      def annotate_out_of_scope_contexts(contexts, scanned)
        contexts.map do |ctx|
          chapter = ctx['chapter'] || ctx[:chapter]
          next ctx if scanned.include?(chapter)

          outside = catalog_basenames && !catalog_basenames.include?(chapter)
          ctx.merge(outside ? { 'outside_catalog' => true } : { 'out_of_scope' => true })
        end
      end

      # catalog.yml に載っている章。読めないときは nil を返す——判定材料が無いのに
      # 「catalog 未登録」と決めつけず、弱いほうの注記（走査対象外）に倒すため。
      def catalog_basenames
        return @catalog_basenames if defined?(@catalog_basenames)

        @catalog_basenames = begin
          Build::CatalogLoader.load_existing_basenames.to_set
        rescue StandardError
          nil
        end
      end

      # 章のパスを解決（ベースネーム → フルパス）
      # @param chapter [String] 章名またはパス
      # @return [String, nil] ファイルパス
      def resolve_chapter_path(chapter)
        return chapter if File.exist?(chapter)

        # contents/ → ワークスペース（前処理済み中間 .md・P4 §3.4-1）の順で探す
        possible_paths = [
          File.join(Common::CONTENTS_DIR, "#{chapter}.md"),
          File.join(Common::BUILD_HTML_DIR, "#{chapter}.md")
        ]

        possible_paths.find { |path| File.exist?(path) }
      end

      # 語の使われ方の抜粋（語を含む 1 文。切り方は ContextSnippet が唯一の定義元）
      def extract_surrounding_context(content, term)
        IndexCommands::ContextSnippet.around(content, term, width: @config[:context_width])
      end

      # 索引候補として除外すべき用語かどうかを判定
      # @param term_text [String] 用語テキスト
      # @return [Boolean] 除外すべきならtrue
      def garbage_term?(term_text)
        return true if term_text.nil? || term_text.empty?

        # Markdown太字記法の一部
        return true if term_text.start_with?('**') || term_text.end_with?('**')

        # カラーコード (#e74c3c, '#e74c3c' など)
        return true if term_text.match?(/^['"]?#[0-9a-fA-F]{3,8}['"]?$/)
        return true if term_text.match?(/^['"]?#[0-9a-fA-F]{3,8}['"]?,\s*['"]?#/)

        # 数字のみ
        return true if term_text.match?(/^\d+$/)

        false
      end

      # R8: auto_process! が辞書へ書いた登録内容を既定ログレベルで必ず表示する。
      # 何も登録しなかった実行では無言（無言＝無変更が成立する）。
      # @param dictionary_writes [Hash{String => Array<String>}] 登録種別 → 追加された語名
      def report_dictionary_writes(dictionary_writes)
        return if dictionary_writes.empty?

        summary = dictionary_writes.map { |kind, names| "#{kind} #{names.size} 語（#{names.join(', ')}）" }.join('・')
        # 絵文字を手書きせず log_result に載せる（他コマンドの結果報告と体系を揃える）
        Common.log_result("辞書を更新しました: #{summary}", status: :success)
      end

      # 結果をレポート（auto_process!用）
      # 総括行（候補数・レビューファイル案内）は既定ログレベルで表示する（R8）。
      # 帯の内訳や目安の語数は出さない（`vs index:plan` の役目）。
      def report_auto_results(auto_approved, high_candidates, low_candidates, rejected_count, rejected_listed = 0)
        approved = auto_approved.any? ? "自動承認 #{auto_approved.size} 語・" : ''
        # 除外済みの件数も載せる。候補の数だけを告げると「外した語はもう出てこない」
        # と読めるが、実際は末尾に一覧があり、そこが戻す唯一の入口である。
        # 数えるのは 4 節に並ぶ語（原稿に出てくる語）だけ。原稿に出てこない語は 5 節へ移るので、
        # 棄却した語の全件を数えると 4 節の見出しの語数と食い違っていた
        listed = rejected_listed.positive? ? "・棄却した語 #{rejected_listed} 語" : ''
        Common.log_summary(
          "レビューファイルを生成しました: #{approved}" \
          "推奨する語 #{high_candidates.size} 語・残りの語 #{low_candidates.size} 語#{listed}",
          detail: "#{ReviewMarkdownGenerator::REVIEW_FILE} を編集後、vs index:apply を実行してください"
        )

        Common.log_info("棄却した語 #{rejected_count} 語を候補から外しました") if rejected_count.positive?
      end
    end
  end
end
