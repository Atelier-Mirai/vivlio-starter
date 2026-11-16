# frozen_string_literal: true

# ================================================================
# scripts/html_contract_doc.rb — 契約 HTML の一覧を Markdown で書き出す
# ================================================================
# 使い方:
#   ruby scripts/html_contract_doc.rb [--out FILE]
#
#   --out FILE   書き出す先（既定: 標準出力）
#
# 契約 HTML の正典は lib/vivlio_starter/cli/html_contract.rb の表である
# （theme-contract-spec.md §2.1）。テーマを作る人向けの文書（マニュアルの章）は、手で
# 一覧を写さず、この出力から作る。写すと、表を直したときに文書だけが古いまま残る。
# ================================================================

require 'optparse'

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(ROOT, 'lib'))
require 'vivlio_starter/cli/html_contract'

Contract = VivlioStarter::CLI::HtmlContract

STAGES = { contract: '契約 HTML', target: '出力先の変換' }.freeze

options = {}
OptionParser.new do |o|
  o.banner = 'usage: ruby scripts/html_contract_doc.rb [--out FILE]'
  o.on('--out FILE') { options[:out] = it }
end.parse!

# --- Phase: クラス（分類ごとの表） --------------------------------------------
# テーマのオプションのクラスは、同梱の standard の theme.yml の body_class: から引く
theme_entries = Contract.theme_option_classes.map do
  Contract::ClassEntry.new(name: it, category: :theme_option, level: :theme, stage: :contract)
end
entries = Contract::CLASSES.values + theme_entries + Contract::PATTERNS.map(&:last)
class_sections = Contract::CATEGORIES.filter_map do |key, category|
  rows = entries.select { it.category == key }
  next if rows.empty?

  lines = rows.map { "| `#{it.name}` | #{Contract::LEVELS.fetch(it.level)} | #{STAGES.fetch(it.stage)} |" }
  <<~MD
    ### #{category[:label]}（§#{category[:section]}）

    付ける処理: #{category[:added_by]}

    | クラス | 水準 | 付く段 |
    | :--- | :--- | :--- |
    #{lines.join("\n")}
  MD
end

# --- Phase: Prism・role・属性 -------------------------------------------------
prism = Contract::PRISM_TOKENS.sort.map { "`#{it}`" }.join('・')
roles = Contract::PAGE_ROLES.map { |kind, it| "| `#{kind}` | `#{it[:role]}` | #{it[:element]} |" }
attributes = Contract::GUARANTEED_ATTRIBUTES.map { |name, note| "| `#{name}` | #{note} |" }

document = <<~MD
  # 契約 HTML の一覧

  `lib/vivlio_starter/cli/html_contract.rb` から書き出した一覧（`ruby scripts/html_contract_doc.rb`）。
  水準の意味と、契約を変えるときの決まりは `theme-contract-spec.md` §2.1・§2.8 による。

  - **保証**: 契約の版が同じ間は変えない。テーマの CSS が選んでよい
  - **テーマ**: テーマが `theme.yml` で宣言したクラス。そのテーマの中でだけ意味を持つ
  - **内部**: テーマは選ばない。予告なく変わる
  - 付く段が「出力先の変換」のクラスは、契約 HTML には現れず、PDF・EPUB・Kindle の写しで付く

  ## クラス

  #{class_sections.join("\n")}
  ### Prism のトークン（§2.4）

  `span.token` と組で付く。CSS で選んでよいのは次の種類: #{prism}

  ## role

  | ページの種類 | `role` | 付ける要素 |
  | :--- | :--- | :--- |
  #{roles.join("\n")}

  ほかに保証する値: `doc-noteref`（脚注の参照）・`doc-footnote`（脚注の本体）。

  ## 属性

  | 属性 | 中身 |
  | :--- | :--- |
  #{attributes.join("\n")}

  ここに無い `data-*` 属性（`data-vs-*` を含む）は内部とする。
MD

if options[:out]
  File.write(options[:out], document)
else
  puts document
end
