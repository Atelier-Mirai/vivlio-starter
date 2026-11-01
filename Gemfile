# frozen_string_literal: true

source 'https://rubygems.org'

# 依存は vivlio-starter.gemspec に書く。
gemspec

# gemspec と同じ指定なので、版を変えるときは両方を直す。
# 1.5 以上が要るのは、雛形 templates/_book.md の書誌の行が、値の無い項目の部分だけを
# 消す動きを前提にしているため。1.4 以下では発行年の無い本の書誌が行ごと消える。
gem 'query-stream', '~> 1.5'

# テストが散発的に落ちるのを防ぐため、strscan の版を 1 つに固める。
# strscan は Ruby の標準添付（default gem）と通常の gem で複数の版が同居する。テストの途中で
# 別の版を読み込むと C 拡張が二重に初期化され、Kramdown が
# "wrong argument type StringScanner (expected StringScanner)" で落ちる。
# Bundler が起動時に版を決めれば、どの require も同じファイルを読む。
# 導入した gem の実行では起きないので、gemspec には書かない。
gem 'strscan', '~> 3.1'

# vivlio-starter-pdf（AGPL の Enhanced プラグイン）は、MIT の本体の bundle へ AGPL を
# 持ち込まないよう、ここには書かない。`gem install vivlio-starter-pdf` してあれば、
# provider.rb が見つけて Enhanced モードに切り替える。
# プラグインの作業ツリーを直接使って開発するときだけ、次の行を有効にする。
# gem 'vivlio-starter-pdf', path: '../vivlio-starter-pdf'
