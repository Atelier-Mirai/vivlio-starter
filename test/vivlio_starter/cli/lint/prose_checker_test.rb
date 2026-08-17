# frozen_string_literal: true

# ================================================================
# Test: cli/lint/prose_checker_test.rb
# ================================================================
# テスト対象:
#   textlint では扱えない独自校正ルール（lib/vivlio_starter/cli/lint/prose_checker.rb）
#
# 検証内容（仕様: lint-japanese-prose-rules-spec.md §6）:
#   PC-01: 交ぜ書きを検出し、「誤 => 正」の形で示す
#   PC-02: コードブロック・インラインコードの中は検出しない
#   PC-03: --fix が交ぜ書きを置換し、コード領域と行数を保つ
#   PC-04: 誤検出を避ける制約が効く（囲んだ円／から致します／てしまい進める／行こう配る）
#   PC-05: 「A と同様に X しない」を二通りに読める対比として検出する
#   PC-06: 段落内改行で折り返した文も 1 文として読む
#   PC-07: 「のように」は検出しない（実測 10/10 が誤検出だったため対象から外した）
#   PC-08: 「少ない」を否定と取り違えない
#   PC-09: lint.disabled_rules でルール単位に切れる
#   PC-10: 辞書の修正後の語が、別の交ぜ書きとして再び指摘されない（--fix が収束する）
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/lint/prose_checker'

class TestProseChecker < Minitest::Test
  PC = VivlioStarter::CLI::Lint::ProseChecker
  MazegakiDictionary = VivlioStarter::CLI::Lint::MazegakiDictionary

  # 原稿を一時ファイルへ書いて検査する（check はパスを受け取るため）
  def check(body, disabled_rules: [])
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'chapter.md')
      File.write(path, body)
      PC.check(path, disabled_rules: disabled_rules)
    end
  end

  def labels(findings) = findings.map(&:label)

  # --- 交ぜ書き ---

  # PC-01: 常用漢字になった語・表外漢字の語の双方を拾い、置換先まで示す
  def test_should_detect_mazegaki_with_expected_form
    findings = check("だ円の面積を求めます。\n完ぺきな実装はぜい弱性を隠ぺいしません。\n")

    assert_includes labels(findings), 'だ円 => 楕円'
    assert_includes labels(findings), '完ぺき => 完璧'
    assert_includes labels(findings), 'ぜい弱 => 脆弱'
    assert_includes labels(findings), '隠ぺい => 隠蔽'
    assert(findings.all? { it.rule == PC::MAZEGAKI_RULE })
  end

  # 辞書のすべての語が、素の一文に置いたときに必ず拾えること。
  # 語を足すときに綴りを打ち間違えても、件数のテストでは気づけない
  def test_should_detect_every_word_in_the_dictionary
    plain = MazegakiDictionary::JOYO
            .merge(MazegakiDictionary::HYOGAI)
            .merge(MazegakiDictionary::KANJI_CHOICE)

    plain.each do |wrong, expected|
      findings = check("これは#{wrong}の例です。\n")

      assert_equal ["#{wrong} => #{expected}"], labels(findings), "#{wrong} を拾えていない"
    end
  end

  # PC-02: 記法や綴りを解説する行を壊さないため、コード領域は検査しない
  def test_should_ignore_mazegaki_inside_code
    body = <<~MD
      `だ円` という綴りを説明します。

      ```ruby
      puts 'ぜい弱'
      ```
    MD

    assert_empty check(body)
  end

  # PC-04: 短い綴りは無関係な文にたまたま含まれる。制約を外すと静かに誤検出へ戻る
  def test_should_not_flag_lookalike_phrases
    body = <<~MD
      囲んだ円の内側を塗ります。ここから致しますのでお待ちください。
      読み終えてしまい進めなくなります。あちらへ行こう配る予定です。
      予約すべき乗り換えを調べます。行くべき乗り場が分かりません。
      今日体調を崩したので休みます。今日体験した内容をまとめます。
      あちらへ行こう着いたら連絡します。この処理は動きません動作を見直します。
      とにかく乱暴な書き方です。せっかく乱れた行を直しました。
      引き損なうと聞き損じるが起きます。書き損じの紙は捨てます。
      紙を引き裂くと引き裂かれた跡が残ります。ひざ折りの姿勢をとります。
      この処理は動きません断続的に試します。せながい子が並びました。
      弟子どもを集めます。調子どもう一つでした。様子どもわからないままです。
      これは虫類ではありません。それは虫類の一種でした。
    MD

    assert_empty check(body)
  end

  # 「障がい者」の行は「障がい」にも当たる。1 箇所に 2 件並べず、長いほうを残す
  def test_should_report_only_the_longest_match_in_a_line
    assert_equal ['障がい者 => 障碍者'], labels(check("障がい者手帳を提示します。\n"))
    assert_equal ['障がい => 障碍'], labels(check("障がいのある方に配慮します。\n")), '短い語だけの行はそのまま出る'
  end

  # 「障害者 => 障碍者」は交ぜ書きではないが、同じ用字の選択として同居させている。
  # 「障害」全般へ広げると「システム障害」まで書き換わり、用字の選択でなく誤りになる
  def test_should_limit_the_kanji_choice_to_the_listed_word
    findings = check("障害者手帳を提示します。システム障害が発生し、障害物競走は中止です。\n")

    assert_equal ['障害者 => 障碍者'], labels(findings)
  end

  # 暦の語は複合語のまま持つ。「うるう」だけを登録すると「うるうる」に当たる
  def test_should_detect_calendar_words_as_compounds
    findings = check("うるう年とうるう秒を扱います。目がうるうるしています。\n")

    assert_equal ['うるう年 => 閏年', 'うるう秒 => 閏秒'], labels(findings).sort
  end

  # 制約を付けた語も、本来の用法では必ず拾えること（制約を強くしすぎると黙る）
  def test_should_still_detect_guarded_words_in_their_real_usage
    findings = check(<<~MD)
      2 のべき乗で増えます。きょう体を開けて基板を確認します。
      交渉はこう着状態です。世論をせん動する記事でした。
      かく乱攻撃で整合性のき損が起きます。疲労き裂が入りました。
      ボルトのせん断強さを求めます。日本のは虫類を調べます。
    MD

    assert_includes labels(findings), 'べき乗 => 冪乗'
    assert_includes labels(findings), 'きょう体 => 筐体'
    assert_includes labels(findings), 'こう着 => 膠着'
    assert_includes labels(findings), 'せん動 => 扇動'
    assert_includes labels(findings), 'かく乱 => 攪乱'
    assert_includes labels(findings), 'き損 => 毀損'
    assert_includes labels(findings), 'き裂 => 亀裂'
    assert_includes labels(findings), 'せん断 => 剪断'
    assert_includes labels(findings), 'は虫類 => 爬虫類'
  end

  # 同じ語に 2 つの交ぜ書きがある（新聞は「たんぱく質」、食品表示は「たん白質」）
  def test_should_detect_both_spellings_of_the_same_word
    assert_equal ['たんぱく質 => 蛋白質'], labels(check("高たんぱく質の食品です。\n"))
    assert_equal ['たん白質 => 蛋白質'], labels(check("動物性たん白質を含みます。\n"))
  end

  # PC-10: 「楕円」がまた別の語の交ぜ書きとして挙がると --fix が収束しない
  def test_should_not_flag_the_corrected_forms
    corrected = PC::MAZEGAKI.values.uniq.join('。')

    assert_empty check("#{corrected}。\n")
  end

  # --- 自動修正 ---

  # PC-03: 置換はするが、コード領域と行数には触れない
  def test_should_fix_mazegaki_outside_code_only
    body = <<~MD
      だ円を描きます。

      ```ruby
      puts 'だ円'
      ```

      完ぺきです。
    MD

    fixed = PC.fix_mazegaki(body)

    assert_includes fixed, '楕円を描きます。'
    assert_includes fixed, '完璧です。'
    assert_includes fixed, "puts 'だ円'", 'コードブロックの中は書き換えない'
    assert_equal body.lines.size, fixed.lines.size, '行数を変えてはならない'
  end

  # 直すものが無ければ 1 文字も変えない（原稿の mtime を無用に動かさないため）
  def test_should_leave_clean_text_untouched
    body = "楕円の面積を求めます。\n"

    assert_equal body, PC.fix_mazegaki(body)
  end

  # --- 二通りに読める対比 ---

  # PC-05: 比較の格助詞「と」を伴う形は、否定がどちらに係るか読めない
  def test_should_detect_ambiguous_comparison
    findings = check("Ractor はスレッドと同様にメモリを共有しない。\n")

    assert_equal 1, findings.size
    assert_equal PC::AMBIGUOUS_RULE, findings.first.rule
    assert_includes findings.first.label, 'と同様に'
    assert_equal 1, findings.first.line
  end

  # PC-06: 本書の原稿は 1 文が複数行にまたがる。行で切ると取りこぼす
  def test_should_read_across_soft_wrapped_lines
    body = "Ractor はスレッドと同じように\nメモリを共有しない。\n"

    findings = check(body)

    assert_equal 1, findings.size
    assert_equal 1, findings.first.line, '文の始まった行を指すこと'
  end

  # PC-07: 「のように」は例示・限定・様態に広く使われる。比較だけを切り出せない
  def test_should_not_flag_example_style_expressions
    body = <<~MD
      次のように書いても動作しない場合があります。
      `@titlepage` のように文字が続く場合は展開されません。
      金のように仕事関数が大きい金属では電子が飛び出しません。
    MD

    assert_empty check(body)
  end

  # 箇条書きの項目は独立している。連結すると、隣り合うだけの行で「比較 → 否定」が
  # 成立する（実測 5 件。比較表現を持たない行が前の項目の「と同様の」と繋がっていた）
  def test_should_not_join_separate_list_items
    body = <<~MD
      - 主要参照は先頭の章と同様の書式で書きます
      - 複数章はカンマ区切りで、行数の上限はありません
    MD

    assert_empty check(body)
  end

  # 表も同じ。1 行の中で隣り合うだけのセルを 1 文として読んではいけない
  def test_should_not_join_separate_table_cells
    body = "| EPUB も画像化 | Kindle と同じく PDF を切り出す | 文字が選択できず、拡大で劣化する |\n"

    assert_empty check(body)
  end

  # PC-08: 「少ない」「違いない」は「ない」で終わるが否定ではない
  def test_should_not_treat_adjectives_as_negation
    body = "Ruby と同様に書ける言語は少ない。\n設定は他と同じように動くに違いない。\n"

    assert_empty check(body)
  end

  # 比較が否定より後ろにある場合は対象外（順序が意味を決める）
  def test_should_require_negation_after_the_comparison
    assert_empty check("共有しないことは、スレッドと同様に扱える理由である。\n")
  end

  # --- 無効化 ---

  # 校正について書いた章は自らの例文が指摘される。textlint と同じコメントで抑止できること
  def test_should_honour_vs_lint_disable_comments
    body = <<~MD
      <!-- vs-lint-disable-next-line -->
      だ円は交ぜ書きです。
      完ぺきは交ぜ書きです。

      <!-- vs-lint-disable -->
      Ractor はスレッドと同様に共有しない。
      ばん回もここでは指摘されません。
      <!-- vs-lint-enable -->
    MD

    assert_equal ['完ぺき => 完璧'], labels(check(body))
  end

  # 抑止した行は --fix の置換対象からも外れる（指摘しないものを直すのは筋が通らない）
  def test_should_not_fix_disabled_lines
    body = "<!-- vs-lint-disable-next-line -->\nだ円は交ぜ書きです。\n完ぺきです。\n"

    fixed = PC.fix_mazegaki(body)

    assert_includes fixed, 'だ円は交ぜ書きです。'
    assert_includes fixed, '完璧です。'
  end

  # PC-09: 「表外漢字は開く」方針の著者は交ぜ書きの指摘だけを切りたい
  def test_should_honour_disabled_rules
    body = "だ円について、Ractor はスレッドと同様に共有しない。\n"

    assert(check(body, disabled_rules: ['mazegaki']).all? { it.rule == PC::AMBIGUOUS_RULE })
    assert(check(body, disabled_rules: ['ambiguous-comparison']).all? { it.rule == PC::MAZEGAKI_RULE })
    assert_empty check(body, disabled_rules: %w[mazegaki ambiguous-comparison])
  end

  # --- 除外リスト ---

  # 語単位で黙らせる窓口は config/textlint_allowlist.yml に一本化されている。
  # 辞書は gem 側にあり著者が触れないので、この道が無いと語ごとの拒否ができない
  def test_should_silence_words_listed_in_the_allowlist
    Dir.mktmpdir do |dir|
      list = File.join(dir, 'allow.yml')
      File.write(list, ['かぎ括弧', '/ひな(型|形)/'].to_yaml)
      allowlist = PC.allowlist_from(list)
      path = File.join(dir, 'chapter.md')
      File.write(path, "かぎ括弧とひな型とだ円を使います。\n")

      labels = PC.check(path, allowlist: allowlist).map(&:label)

      assert_equal ['だ円 => 楕円'], labels, '除外した語以外は残ること'
    end
  end

  # 黙らせた語を --fix が書き換えては、著者から見て最も分かりにくい壊れ方になる
  def test_should_not_fix_words_listed_in_the_allowlist
    Dir.mktmpdir do |dir|
      list = File.join(dir, 'allow.yml')
      File.write(list, ['かぎ括弧'].to_yaml)

      fixed = PC.fix_mazegaki("かぎ括弧とだ円を使います。\n", PC.allowlist_from(list))

      assert_equal "かぎ括弧と楕円を使います。\n", fixed
    end
  end

  # 部分一致で黙らせると、「括弧」の 1 行が「かぎ括弧」の指摘まで消してしまう。
  # 本書の除外リストには実際に「括弧」がある（「括弧 => カッコ」を止めるためのもの）
  def test_should_require_the_allowlist_entry_to_cover_the_whole_word
    Dir.mktmpdir do |dir|
      list = File.join(dir, 'allow.yml')
      File.write(list, ['括弧'].to_yaml)
      path = File.join(dir, 'chapter.md')
      File.write(path, "かぎ括弧を使います。\n")

      labels = PC.check(path, allowlist: PC.allowlist_from(list)).map(&:label)

      assert_equal ['かぎ括弧 => 鉤括弧'], labels
    end
  end

  # 除外リストが無い・壊れていても検査は続く（校正が止まるほうが困る）
  def test_should_tolerate_a_missing_allowlist
    assert_empty PC.allowlist_from(nil)
    assert_empty PC.allowlist_from('/nonexistent/allow.yml')
  end

  # --- 表示 ---

  # 著者が lint.disabled_rules へ書く名前を、集約表示からそのまま読み取れること
  def test_should_prefix_labels_with_the_rule_id
    findings = check("だ円を描きます。\nだ円を測ります。\n")
    rows = PC.aggregate(findings)

    assert_equal 1, rows.size, '同じ指摘は 1 行へ畳む'
    assert_equal '[mazegaki] だ円 => 楕円', rows.first[:label]
    assert_equal 2, rows.first[:count]
    assert_equal '1, 2', rows.first[:lines]
  end
end
