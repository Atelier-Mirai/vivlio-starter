# frozen_string_literal: true

source 'https://rubygems.org'

# Dependencies are defined in the gemspec to keep a single source of truth.
gemspec

# query-stream は公開済みバージョンを使用
gem 'query-stream', '~> 1.3'

# strscan を単一バージョンへ固定する（テスト flaky の恒久対策）。
# Ruby 4.0 環境では strscan が default gem（3.1.6 = stdlib 実体）と通常 gem（3.1.8 等）で
# 同居し、実行途中に別バージョンが activate されると C 拡張が二重初期化されて
# StringScanner のクラス同一性が壊れ、Kramdown が
# "wrong argument type StringScanner (expected StringScanner)" で散発的に落ちる。
# Bundler の起動時に 1 バージョンだけを確定 activate させ、全 require を同一ファイルへ解決する。
gem 'strscan', '~> 3.1'

# vivlio-starter-pdf（AGPL の Enhanced プラグイン）は rubygems.org で公開済み（>= 1.1.1）。
# MIT 本体の bundle へ AGPL を取り込まないため Gemfile には含めず、`gem install vivlio-starter-pdf`
# 済みなら provider.rb が自動検出して Enhanced モードに切り替える。
# プラグイン本体をローカル開発する場合のみ、次行を有効化する:
# gem 'vivlio-starter-pdf', path: '../vivlio-starter-pdf'
