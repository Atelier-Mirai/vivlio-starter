# frozen_string_literal: true
#
# **開発時にだけ使うスクリプト**（gem には同梱されるが、実行時には読まれない）。
# mazegaki-source.tsv から「lint に載せてよい語」を絞り込む条件を、本書の原稿で
# 実測しながら確かめる。出荷用データ mazegaki.tsv の生成もこの条件で行う。
#
#   rake mazegaki:build                 # リポジトリのルートから
#
# 条件は上から順に効く。括弧内は本書 200 万字（contents 27・docs 203・ルート 6）
# での検出数で、括弧の後ろが誤検出の数。
#
#   種別が「交ぜ書き」          18,282 語（417 件 / 誤 115）
#     「かな書き」17,439 語は使えない。し→四 7,674 件・する→為る 5,526 件・
#     ため→為 2,083 件。SudachiDict の正規化は検索のための同一視であって、
#     書き言葉の正誤ではない。
#   ① 別語として読める語を落とす   （302 件）
#     見出しを MeCab に単独で食わせ、1 形態素の既知語として読めて、その読みが
#     TSV の読み欄と食い違うなら捨てる。残し＝ノコシ≠ザンシ、動き＝ウゴキ≠ドウキ、
#     思い＝オモイ≠シイ、白く＝シロク≠ハック。**同音異義ではなく同表記異読**で、
#     形態素解析では落とせない。「MeCab が読めない」（ばん石→バンイシ）とは
#     区別する必要があるので、1 形態素の既知語であることを条件に入れている。
#   ② 見出しが全かなの語を落とす
#   ③ 既存 140 語が持つ綴りを落とす  Ruby 側（ガード付き・MeCab 不要）に譲る
#   ④ 行き先が漢字だけの語に限る    （60 件）
#     行き先にひらがなが混じるものは送り仮名・開き閉じの選択であって交ぜ書きの
#     是正ではない。位置づけ→位置付け・はみ出し→食み出し・取りこぼし→取り零し。
#   ⑤ 「御」と こちら／あちら側 を落とす （26 件）
#   ⑥ 漢字 1 字＋かな 1〜2 字の短い語を落とす （5 件 / 誤 0）
#     境界チェックを通しても機能語と衝突する。は種＝「99）は種別が」、
#     合し＝「結合し直した」、上でき＝「事実上できない」、物ごと＝「成果物ごとに」。
#     この長さの語は人が確認した Ruby 側に任せる。「う回」「語い」「り患」は
#     MECAB_ONLY へ、「は種」「合し」は GUARDED へ入れた（2026-08-19）。
#     「そ上」は俎上とも遡上とも読めて行き先が定まらないので採らない。
#
# 残る 5 件は `出どころ → 出所` で、これは正しい検出。
#
$LOAD_PATH.unshift 'lib'
require 'natto'
require 'vivlio_starter/cli/masking'
require 'vivlio_starter/cli/lint/mazegaki_scanner'
M = VivlioStarter::CLI::Masking
S = VivlioStarter::CLI::Lint::MazegakiScanner
mecab = Natto::MeCab.new
FILES = { 'contents' => Dir['contents/*.md'], 'docs' => Dir['docs/**/*.md'], 'ルート' => Dir['*.md'] }.freeze

# **判定は本番と同じコードを使う。** ここで独自に境界判定を書くと、
# 測った数字と実際の lint の振る舞いが静かに食い違う。
# MazegakiScanner の辞書だけ候補で差し替えて、判定はあちらに任せる。
def scan(table)
  S.instance_variable_set(:@table, table)
  S.instance_variable_set(:@max_length, nil)
  hits = Hash.new { |h, k| h[k] = [] }
  FILES.each_value do |files|
    files.each do |path|
      M.each_prose_line(File.read(path, encoding: 'UTF-8')) do |raw, lineno|
        line = raw.tr("\0", ' ')          # NUL を含む行がある。長さは変えない
        protected_line, = M.protect_code(line)
        plain, = M.strip_emphasis(protected_line)
        S.scan(plain).each do |found, _expected, offset, _finish|
          hits[found] << "#{path}:#{lineno}\u3000…#{plain.strip[[offset - 14, 0].max, 34]}…"
        end
      end
    end
  end
  hits
end

rows = File.readlines("#{__dir__}/mazegaki-source.tsv", chomp: true).reject { it.start_with?('#') }.map { it.split("\t", -1) }
def kata(s) = s.tr('ぁ-ゖ', 'ァ-ヶ')
def other_word?(mecab, m, yomi)
  ns = mecab.enum_parse(m).reject { it.surface.to_s.empty? }.to_a
  return false unless ns.size == 1 && ns[0].stat.zero?
  r = ns[0].feature.split(',')[7]
  !r.nil? && r != kata(yomi)
end
mz = rows.select { it[4] == '交ぜ書き' }
filtered = mz.reject { other_word?(mecab, it[0], it[2]) || it[0].match?(/\A[ぁ-ゖー]+\z/) }
# 既存 140 語がすでに持つ綴りは Ruby 側に譲る
require 'vivlio_starter/cli/lint/mazegaki_dictionary'
D = VivlioStarter::CLI::Lint::MazegakiDictionary
own = (D::JOYO.keys + D::HYOGAI.keys + D::KANJI_CHOICE.keys + D::MECAB_ONLY.keys +
       D::GUARDED.keys.map { |re| re.source.gsub(/\(\?<?[!=][^)]*\)/, '') }).to_set
shipped = filtered.reject { own.include?(it[0]) }
# 行き先が漢字だけ＝本来の交ぜ書き。ひらがなが混じるものは送り仮名・開き閉じの選択
kanji_only = shipped.select { it[1].match?(/\A[一-龥々ー]+\z/) }
# 「御」を閉じるかは文体の選択。交ぜ書きの是正ではない
polite = kanji_only.reject { it[1].start_with?('御') || it[0].match?(/\A(こちら|あちら|そちら|どちら)/) }
# 漢字 1 字＋かな 1〜2 字の短い語は、境界チェックを通しても機能語と衝突する
# （は種＝「99）は種別」、合し＝「結合し直した」、上でき＝「事実上できない」）。
# 人が確認した語は Ruby 側（GUARDED / MECAB_ONLY）に置く
short = polite.reject { it[0].size <= 3 && it[0].count('一-龥々') <= 1 }
sets = { '＋御・こちら側を除く' => polite, '＋短い語を除く（出荷案）' => short }

# 出荷用データを書き出す。lib/ に置くのは docs/ が gem に入らないため
# （gemspec の spec.files は {bin,lib}/**/* のみ）。
DEST = File.expand_path('mazegaki.tsv', __dir__)
header = <<~HEAD
  # 交ぜ書き辞書（MeCab がある環境でだけ使う層）
  #
  # SudachiDict の正規化表記から派生したデータ。
  # Copyright (c) 2017-2023 Works Applications Co., Ltd. / Apache License 2.0
  # 帰属表示と改変内容: プロジェクトルートの THIRD-PARTY-LICENSES.md
  # ライセンス全文: プロジェクトルートの LICENSE-APACHE-2.0.txt
  # 元データ・絞り込みの条件と実測値: 同ディレクトリの mazegaki-source.tsv / filter.rb
  #
  # 手で編集しないこと。`rake mazegaki:build` が生成する。
  # 列: 交ぜ書き<TAB>漢字表記
HEAD
body = short.sort_by { it[0] }.map { "#{it[0]}\t#{it[1]}" }.join("\n")
File.write(DEST, header + body + "\n")
puts "\n出荷用データ: #{DEST}（#{short.size} 語）"
sets.each do |label, list|
  t = list.reject { it[0] == it[1] }.group_by { it[0] }.select { |_k, v| v.map { it[1] }.uniq.size == 1 }
          .transform_values { it[0][1] }
  h = scan(t)
  puts "\n#### #{label}: #{t.size} 語（行き先が割れるものを除く）→ 検出 #{h.values.sum(&:size)} 箇所・#{h.size} 語種"
  h.sort_by { -it[1].size }.each { |w, v| puts format('    %-12s→%-12s %3d件  %s', w, t[w], v.size, v.first) }
end
