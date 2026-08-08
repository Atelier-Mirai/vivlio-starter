# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/config_keys.rb
# ================================================================
# 責務:
#   config/book.yml のキーを 1 箇所で宣言する。既定値・著者が埋めるキー・廃止キーの
#   3 状態をここだけで持ち、Common の既定値スキーマと各種案内はここから導出する。
#
# なぜ 1 表にするか:
#   かつては宣言が 4 箇所（default_config_schema / RETIRED_CONFIG_KEYS /
#   REQUIRED_BOOK_KEYS / 各ドメインの DEFAULT_* 定数）に分かれ、同じ既定値が
#   複数箇所にあった。結果として book.yml とコードで値が食い違い、著者がキーを
#   消した瞬間だけ誰も宣言していない値で動く、という状態が 6 件あった。
#   仕様: config-defaults-design-spec.md
#
# 値の書き方（3 状態のいずれか 1 つだけを与える）:
#   Spec[default: 500]        通常のキー。book.yml に無ければこの値で動く
#   Spec[authored: '著者名']   著者が埋めるキー。既定値は無く、空なら記入例つきで促す
#   Spec[retired: '…']        廃止キー。読まずに移行先を案内する
#
# book.yml との一致は config_keys_test.rb が検査する。scaffold の book.yml に
# 書かれた値と default: がずれたらテストが落ちる——これが無いと、宣言を 1 箇所に
# しても食い違いは再発する。
# ================================================================

module VivlioStarter
  module CLI
    # book.yml のキー宣言。Common から参照する。
    module ConfigKeys
      # キー 1 件の宣言。ハッシュリテラルではなく Data を使うのは、打ち間違いを
      # 即座に落とすため（Spec[defualt: 500] は ArgumentError だが
      # { defualt: 500 } は静かに通り、既定値を持たないキーとして振る舞う）。
      Spec = Data.define(:default, :retired, :authored) do
        def initialize(default: nil, retired: nil, authored: nil) = super

        # 廃止キーか（値は移行先の案内文）
        def retired? = !retired.nil?

        # 著者が埋めるキーか（値は未設定時に見せる記入例）
        def authored? = !authored.nil?
      end

      # ================================================================
      # 現役キー — scaffold の config/book.yml と 1 対 1 に対応する
      # ================================================================
      KEYS = {
      # ------- book -------
      %i[book main_title]                             => Spec[authored: "本のタイトル"],
      %i[book subtitle]                               => Spec[default: ""],
      %i[book subtitle_style]                         => Spec[default: "wave"],
      %i[book series]                                 => Spec[default: ""],
      %i[book release]                                => Spec[default: ""],
      %i[book publisher]                              => Spec[default: ""],
      %i[book contact]                                => Spec[default: ""],
      %i[book author]                                 => Spec[authored: "著者名"],
      %i[book language]                               => Spec[default: "ja"],
      %i[book isbn]                                   => Spec[default: ""],

      # ------- project -------
      %i[project name]                                => Spec[authored: "mybook"],
      %i[project version]                             => Spec[default: "0.1.0"],

      # ------- theme -------
      %i[theme color]                                 => Spec[default: "green"],
      %i[theme preface_color]                         => Spec[default: "teal"],
      %i[theme appendix_color]                        => Spec[default: "cyan"],
      %i[theme style]                                 => Spec[default: "image"],
      %i[theme frontispiece image]                    => Spec[default: "sakura"],
      %i[theme frontispiece edge_inset]               => Spec[default: "5mm"],
      %i[theme frontispiece heading_offset]           => Spec[default: "15mm"],
      %i[theme frontispiece heading_chars]            => Spec[default: 10],
      %i[theme frontispiece lead_chars]               => Spec[default: 24],
      %i[theme ornament image]                        => Spec[default: "sakura"],
      %i[theme ornament heading_chars]                => Spec[default: 14],
      %i[theme markers h3]                            => Spec[default: "♣"],
      %i[theme markers h4]                            => Spec[default: "♦"],

      # ------- page -------
      %i[page use]                                    => Spec[default: "b5_standard"],
      %i[page section_pagebreak]                      => Spec[default: true],
      %i[page chapter_pagebreak]                      => Spec[default: "recto"],

      # ------- typography -------
      %i[typography body font]                        => Spec[default: "Zen Old Mincho"],
      %i[typography heading font]                     => Spec[default: "Zen Kaku Gothic New"],
      %i[typography column font]                      => Spec[default: "Zen Maru Gothic"],
      %i[typography column font_size]                 => Spec[default: "8pt"],
      %i[typography code font]                        => Spec[default: "HackGen35 Console NF"],
      %i[typography folio font]                       => Spec[default: "Zen Kaku Gothic New"],
      %i[typography folio placement]                  => Spec[default: "sides"],

      # ------- output -------
      %i[output targets]                              => Spec[default: "pdf"],
      %i[output include_version]                      => Spec[default: true],
      %i[output pdf_preview close_existing_windows]   => Spec[default: true],
      %i[output pdf_preview window_bounds]            => Spec[default: "{0, 0, 1280, 960}"],
      %i[output cover]                                => Spec[default: "master"],
      %i[output pdf combined]                         => Spec[default: true],
      %i[output pdf compress]                         => Spec[default: false],
      %i[output pdf techbook]                         => Spec[default: true],
      %i[output print_pdf bleed]                      => Spec[default: "3mm"],
      %i[output print_pdf crop_marks]                 => Spec[default: true],
      %i[output print_pdf full_bleed]                 => Spec[default: false],
      %i[output epub embed]                           => Spec[default: true],
      %i[output epub layout]                          => Spec[default: "reflowable"],
      %i[output kindle embed]                         => Spec[default: false],
      %i[output kindle layout]                        => Spec[default: "reflowable"],

      # ------- verify -------
      %i[verify images]                               => Spec[default: true],
      %i[verify bare_urls]                            => Spec[default: true],
      %i[verify external_links]                       => Spec[default: false],
      %i[verify timeout]                              => Spec[default: 10],
      %i[verify max_concurrency]                      => Spec[default: 5],

      # ------- legal -------
      %i[legal disclaimer]                            => Spec[default: "本書は教育目的で作成された入門書であり、情報の提供のみを目的としています。内容の正確性には万全を期しておりますが、技術的な詳細については、専門的な文献もあわせてご参照ください。\n本書の内容を参考にした結果生じた損害や、本書の内容を実行・運用・適用したことによって発生した問題について、著者・発行者および関係者は一切の責任を負いかねます。\n"],
      %i[legal trademark]                             => Spec[default: "本書に登場するシステム名や製品名は、関係各社の商標または登録商標です。\n本書では ™、®、© などのマークは省略しています。\n"],
      %i[legal twemoji]                               => Spec[default: "本書で使用している絵文字画像は Twemoji (https://twemoji.twitter.com) を利用しています。\nCopyright © Twitter, Inc and other contributors. Licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).\n"],

      # ------- index_glossary -------
      %i[index_glossary enabled]                      => Spec[default: true],
      %i[index_glossary use_mecab]                    => Spec[default: true],
      %i[index_glossary timezone]                     => Spec[default: "Asia/Tokyo"],
      %i[index_glossary context_width]                => Spec[default: 40],

      # ------- index -------
      %i[index auto_discovery]                        => Spec[default: true],
      %i[index title]                                 => Spec[default: "索引"],
      %i[index target_terms]                          => Spec[default: "light"],
      %i[index candidate_pool]                        => Spec[default: 3.0],
      %i[index auto_approve]                          => Spec[default: false],
      %i[index common_term_ratio]                     => Spec[default: 0.5],
      %i[index reference_style]                       => Spec[default: "main_and_sub"],
      %i[index max_sub_references]                    => Spec[default: 8],
      %i[index page_range_min]                        => Spec[default: 3],

      # ------- glossary -------
      %i[glossary title]                              => Spec[default: "用語集"],
      %i[glossary require_definition]                 => Spec[default: false],
      %i[glossary max_definition_length]              => Spec[default: 500],

      # ------- metrics -------
      %i[metrics use]                                 => Spec[default: "standard"],
      %i[metrics compact chapter min]                 => Spec[default: 800],
      %i[metrics compact chapter ideal]               => Spec[default: [1100, 3400]],
      %i[metrics compact chapter max]                 => Spec[default: 4200],
      %i[metrics compact section min]                 => Spec[default: 400],
      %i[metrics compact section ideal]               => Spec[default: [1000, 2800]],
      %i[metrics compact section max]                 => Spec[default: 4000],
      %i[metrics handy chapter min]                   => Spec[default: 2900],
      %i[metrics handy chapter ideal]                 => Spec[default: [3400, 5700]],
      %i[metrics handy chapter max]                   => Spec[default: 6800],
      %i[metrics handy section min]                   => Spec[default: 400],
      %i[metrics handy section ideal]                 => Spec[default: [1000, 2800]],
      %i[metrics handy section max]                   => Spec[default: 4000],
      %i[metrics standard chapter min]                => Spec[default: 4200],
      %i[metrics standard chapter ideal]              => Spec[default: [4800, 8500]],
      %i[metrics standard chapter max]                => Spec[default: 9700],
      %i[metrics standard section min]                => Spec[default: 400],
      %i[metrics standard section ideal]              => Spec[default: [1000, 2800]],
      %i[metrics standard section max]                => Spec[default: 4000],
      %i[metrics commercial chapter min]              => Spec[default: 6400],
      %i[metrics commercial chapter ideal]            => Spec[default: [7800, 14600]],
      %i[metrics commercial chapter max]              => Spec[default: 17800],
      %i[metrics commercial section min]              => Spec[default: 400],
      %i[metrics commercial section ideal]            => Spec[default: [1000, 2800]],
      %i[metrics commercial section max]              => Spec[default: 4000],
      %i[metrics heavy chapter min]                   => Spec[default: 9200],
      %i[metrics heavy chapter ideal]                 => Spec[default: [11000, 16000]],
      %i[metrics heavy chapter max]                   => Spec[default: 19600],
      %i[metrics heavy section min]                   => Spec[default: 400],
      %i[metrics heavy section ideal]                 => Spec[default: [1000, 2800]],
      %i[metrics heavy section max]                   => Spec[default: 4000],
      %i[metrics author_custom chapter min]           => Spec[default: 6400],
      %i[metrics author_custom chapter ideal]         => Spec[default: [7800, 14600]],
      %i[metrics author_custom chapter max]           => Spec[default: 17800],
      %i[metrics author_custom section min]           => Spec[default: 400],
      %i[metrics author_custom section ideal]         => Spec[default: [1000, 2800]],
      %i[metrics author_custom section max]           => Spec[default: 4000],
      %i[metrics exclude_chapters]                    => Spec[default: [0, "90-98", 99]],
      %i[metrics kanji_ratio min]                     => Spec[default: 20],
      %i[metrics kanji_ratio ideal]                   => Spec[default: [25, 35]],
      %i[metrics kanji_ratio max]                     => Spec[default: 45],
      %i[metrics word_length min]                     => Spec[default: 1.5],
      %i[metrics word_length ideal]                   => Spec[default: [2.0, 2.5]],
      %i[metrics word_length max]                     => Spec[default: 3.0],
      %i[metrics readability standard]                => Spec[default: 40],
      %i[metrics readability easy]                    => Spec[default: 60],
      %i[metrics labels too_short]                    => Spec[default: "加筆検討"],
      %i[metrics labels just_right]                   => Spec[default: "丁度良い"],
      %i[metrics labels too_long]                     => Spec[default: "やや長い"],
      %i[metrics labels monotonous]                   => Spec[default: "表現が単調"],
      %i[metrics labels too_complex]                  => Spec[default: "やや難解"],

      # ------- lint -------
      %i[lint disabled_rules]                         => Spec[default: ["arabic-kanji-numbers"]],
      %i[lint sentence_length_max]                    => Spec[default: 100],
      %i[lint trim_long_vowel]                        => Spec[default: true],
      %i[lint allow_space_around_code]                => Spec[default: true],
      %i[lint allow_space_between_ja_en]              => Spec[default: true],

      # ------- spellcheck -------
      %i[spellcheck extra_dictionaries]               => Spec[default: nil],
      %i[spellcheck check_code_blocks]                => Spec[default: false],

      # ------- pdf_read -------
      %i[pdf_read text_area top_margin]               => Spec[default: 18],
      %i[pdf_read text_area bottom_margin]            => Spec[default: 20],
      %i[pdf_read text_area inner_margin]             => Spec[default: 15],
      %i[pdf_read text_area outer_margin]             => Spec[default: 12],
      %i[pdf_read page_separator]                     => Spec[default: false],
      %i[pdf_read ocr mode]                           => Spec[default: "auto"],
      %i[pdf_read ocr languages]                      => Spec[default: ["japanese"]],
      %i[pdf_read ocr dpi]                            => Spec[default: 300],
      %i[pdf_read ocr psm]                            => Spec[default: 3],
      %i[pdf_read ocr inline_image_text]              => Spec[default: "include"],
      }.freeze

      # ================================================================
      # 廃止キー — 読まずに移行先を案内する
      # ================================================================
      # 値は「代わりにどうするか」。著者が読んで行動できる文言にすること
      # （警告は具体的な修正案とセットにする、が本プロジェクトの流儀）。
      # 廃止したら book.yml と scaffold からもキーを消し、ここへ 1 行足す。
      RETIRED = {
      %i[index auto_approve_threshold]           => Spec[retired: "索引語数はスコアの絶対値ではなく index.target_terms（本文の分量から導く目安語数）で決めます"],
      %i[index review_threshold]                 => Spec[retired: "同上。レビュー対象は目安語数と index.candidate_pool で決まります"],
      %i[index high_candidates_ratio]            => Spec[retired: "推奨候補／一般候補の分割は目安語数が決めるため、比率の指定は不要です"],
      %i[metrics mattr_window]                   => Spec[retired: "語彙多様度を測る窓幅は算出方法そのもので、変えると章どうしを比べられなくなるため固定しました"],
      %i[spellcheck extra_words]                 => Spec[retired: "除外したい語は config/spellcheck_allowlist.yml に書きます（vs lint --register で一括登録もできます）"],
      %i[spellcheck ignore_words]                => Spec[retired: "同上。指摘したくない語の窓口は config/spellcheck_allowlist.yml に一本化しました"],
      %i[index_glossary library]                 => Spec[retired: "書き出し先・取り込み元は vs index:export mybook.yml のように引数で指定します（既定は index_library.yml）"],
      %i[index_glossary smart_context_cutting]   => Spec[retired: "文脈の切り出しは常に形態素境界を考慮します（切りたくない理由がないため選択肢をなくしました）"],
      %i[preflight allowed_classes]              => Spec[retired: "そのクラスの CSS を stylesheets/ に書けば既知クラスとして扱われます（CSS を書くことが登録です）"],
      %i[vfm hard_line_breaks]                   => Spec[retired: "原稿中の改行は常に改行として組みます。章ごとに変えたい場合はその章のフロントマターに vfm: { hardLineBreaks: false } と書きます"],
      %i[lint config]                            => Spec[retired: "校正ルールは config/.textlintrc.yml を直接編集します（book.yml には文体の選択だけを置きます）"],
      %i[lint disabled_terms]                    => Spec[retired: "指摘したくない語句は config/textlint_allowlist.yml に書きます"],
      %i[index backlink_dedup]                   => Spec[retired: "バックリンクの重複排除は常に行ないます（切っても浮くのは 0.8 秒で、用語の出現箇所すべてにダガー印が付きます）"],
      %i[glossary backlink_dedup]                => Spec[retired: "同上。用語集のバックリンクも常に重複排除します"],
      %i[directories]                            => Spec[retired: "contents/ や stylesheets/ の名前は変更できません"],
      %i[cache]                                  => Spec[retired: "キャッシュは常に .cache/vs に置き、常に有効です"],
      %i[commands]                               => Spec[retired: "vfm コマンドの名前は変更できません"],
      %i[vivliostyle]                            => Spec[retired: "vivliostyle の進行表示は常に抑制します（reading_progression は元から読んでいません）"],
      %i[book title]                             => Spec[retired: "書名は book.main_title に書きます（title は初期実装の名残で、main_title が空のときだけ使われていました）"],
      %i[metrics clause_length]                  => Spec[retired: "節の長さの基準は使っていません（宣言だけが残っていました）"],      }.freeze

      # 現役キーと廃止キーを合わせた全宣言
      ALL = KEYS.merge(RETIRED).freeze

      module_function

      # 既定値スキーマ（Common.default_config_schema の実体）。
      # 葉キーの宣言から入れ子ハッシュを組み立て直す。default: を持たないキー
      # （authored:）は nil——著者が埋めるまで値は無い。
      def default_schema
        KEYS.each_with_object({}) do |(path, spec), tree|
          *parents, leaf = path
          node = parents.reduce(tree) { |h, key| h[key] ||= {} }
          node[leaf] = spec.default
        end
      end

      # 著者が埋めるキーと、未設定時に見せる記入例。
      # @return [Hash{Array<Symbol> => String}]
      def authored_examples
        KEYS.select { |_, spec| spec.authored? }.transform_values(&:authored)
      end

      # 廃止キーと移行先の案内。
      # @return [Hash{Array<Symbol> => String}]
      def retirement_notices
        RETIRED.transform_values(&:retired)
      end
    end
  end
end
