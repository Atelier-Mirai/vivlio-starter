# frozen_string_literal: true

require_relative 'lib/vivlio_starter/version'

Gem::Specification.new do |spec|
  spec.name          = 'vivlio-starter'
  spec.version       = VivlioStarter::VERSION
  spec.authors       = ['Atelier Mirai']
  spec.email         = ['contact@atelier-mirai.net']

  spec.summary       = 'Markdown で書いた原稿から高品質な PDF・EPUB・Kindle を生成する電子書籍執筆システム'
  spec.description   = '組版エンジンに CSS 組版の Vivliostyle を採用した、執筆から入稿までを一貫して支える電子書籍執筆システムです。章ファイルの作成・改名といった原稿管理、textlint と独自ルールによる日本語校正・英語スペルチェック、索引と用語集の候補の抽出、分量と読みやすさのメトリクス、画像の最適化と表紙の生成、入稿前の検査（Type 3 フォント・本の書体にない字・組めない数式）、そして前処理（QueryStream 展開・クロスリファレンス）から後処理（PDF しおり・表紙結合・圧縮）までを、30 のコマンドで行います。出力は閲覧用 PDF、トンボと塗り足しを備えた印刷入稿用 PDF、Kobo / Apple Books 向けのクリーン EPUB、Amazon Kindle 向けの KPF。上下巻などの分冊と合本を組めるほか、導入スクリプトによる環境の構築、vs upgrade による本体・雛形・外部ツールの一括更新、Re:VIEW Starter プロジェクトの取り込み、PDF から Markdown への読み取りも備えています。'
  spec.homepage      = 'https://github.com/Atelier-Mirai/vivlio-starter'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.4'
  # gem の依存では表せない前提。rubygems.org の gem ページに表示される。
  spec.requirements = ['Node.js 22.12 以上', 'macOS と Homebrew（外部ツールの自動インストールに使用）']

  # 配布するのは bin/ と lib/ のうち git が管理するファイルだけ
  spec.files = `git ls-files -z bin lib`.split("\x0")
  spec.files += %w[README.md LICENSE THIRD-PARTY-LICENSES.md CONTENT-LICENSE.md]
  spec.bindir        = 'bin'
  spec.executables   = %w[vivlio-starter vs]
  spec.require_paths = ['lib']

  # 実行時の依存
  spec.add_dependency 'query-stream', '~> 1.5'
  spec.add_dependency 'kramdown', '~> 2.4'
  spec.add_dependency 'mini_magick', '>= 4.12'
  spec.add_dependency 'nokogiri', '~> 1.16'
  spec.add_dependency 'pdf-reader', '~> 2.12'
  spec.add_dependency 'prawn', '~> 2.5'
  spec.add_dependency 'samovar', '~> 2.1'
  # @qr:URL の QR コード生成（pure Ruby・MIT。ネイティブ拡張なし）
  spec.add_dependency 'rqrcode', '~> 3.2'
  # 書体ファイルの解析（SVG への書体の埋め込み・異体字・外字・字の送りの計測）
  spec.add_dependency 'ttfunk', '~> 1.8'

  # 索引の読みの推測・交ぜ書きの第 2 層・よく使う言葉の集計に使う。MeCab 本体は任意で、なければこれらの機能だけが動かない
  spec.add_dependency 'natto', '~> 1.2'

  # 開発時の依存
  spec.add_development_dependency 'rake', '~> 13.2'
  spec.add_development_dependency 'rubocop', '>= 1.65'
  spec.add_development_dependency 'minitest', '>= 5.22'
  # Object#stub は、Minitest 6 ではこの gem が提供する
  spec.add_development_dependency 'minitest-mock', '~> 5.27'
  spec.metadata['rubygems_mfa_required'] = 'false'
  # rubygems.org の gem ページに表示するリンク
  spec.metadata['changelog_uri'] = 'https://github.com/Atelier-Mirai/vivlio-starter/blob/master/CHANGELOG.md'
  spec.metadata['source_code_uri'] = 'https://github.com/Atelier-Mirai/vivlio-starter'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/Atelier-Mirai/vivlio-starter/issues'
end
