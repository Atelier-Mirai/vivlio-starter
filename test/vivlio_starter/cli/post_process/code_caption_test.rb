# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # mark_code_captions! は「段落全体が <strong> ひとつ」かつ「直後がコード
      # ブロック」の <p> にだけ code-caption クラスを付ける。
      #
      # この判定はかつて CSS の `p:has(+ pre)` が隣接だけで行っており、コードを
      # 導入するだけの普通の文章まで巻き込んでいた（本書で 403 件が字下げ・両端
      # 揃え・本文書体を失っていた。意図した対象は 16 件）。巻き込みを再発させ
      # ないことがこのテストの主眼なので、付く例と同じだけ「付かない例」を置く。
      class CodeCaptionTest < Minitest::Test
        # HTML を一時ファイルに書いて判定を適用し、結果文字列を返す。
        def mark(html)
          Tempfile.create(['vs_caption_test_', '.html']) do |f|
            f.write("<html><body>#{html}</body></html>")
            f.flush
            PostProcessCommands.mark_code_captions!(f.path)
            return File.read(f.path, encoding: 'utf-8')
          end
        end

        # =============================================================
        # キャプションとして印を付ける
        # =============================================================

        def test_should_mark_strong_only_paragraph_before_pre
          out = mark('<p><strong>設定例</strong></p><pre><code>x = 1</code></pre>')

          assert_includes out, '<p class="code-caption"><strong>設定例</strong></p>'
        end

        def test_should_mark_strong_only_paragraph_before_language_figure
          out = mark('<p><strong>foo.rb</strong></p>' \
                     '<figure class="language-ruby"><pre><code>x = 1</code></pre></figure>')

          assert_includes out, '<p class="code-caption"><strong>foo.rb</strong></p>'
        end

        # 既存クラスは保つ（相互参照の経路が別のクラスを載せている場合がある）。
        def test_should_keep_existing_classes
          out = mark('<p class="aki"><strong>設定例</strong></p><pre><code>x = 1</code></pre>')

          assert_includes out, 'class="aki code-caption"'
        end

        def test_should_not_duplicate_existing_caption_class
          out = mark('<p class="code-caption"><strong>設定例</strong></p><pre><code>x = 1</code></pre>')

          assert_includes out, 'class="code-caption"'
          refute_includes out, 'code-caption code-caption'
        end

        # 左右に並べる囲みの直下では、キャプションとコードを 1 列になるよう包む
        def test_should_wrap_caption_and_code_into_one_column_in_side_by_side
          out = mark('<div class="side-by-side"><pre><code>src</code></pre>' \
                     '<p><strong>CSS の例</strong></p><pre><code>h1 {}</code></pre></div>')
        
          assert_includes out, '<div><p class="code-caption"><strong>CSS の例</strong></p><pre><code>h1 {}</code></pre></div>'
        end
        
        # 囲みの外では包まない（紙面の改ページの判定を変えない）
        def test_should_not_wrap_caption_outside_side_by_side
          out = mark('<p><strong>設定例</strong></p><pre><code>x = 1</code></pre>')
        
          refute_includes out, '<div><p class="code-caption">'
        end

        # =============================================================
        # 巻き込まない（旧 CSS ルール p:has(+ pre) の再発防止）
        # =============================================================

        def test_should_not_mark_plain_sentence_before_code
          out = mark('<p>次のように書きます。</p><pre><code>x = 1</code></pre>')

          refute_includes out, 'code-caption'
        end

        # 地の文に強調が 1 つあるだけの段落。CSS の :only-child では弾けなかった形。
        def test_should_not_mark_sentence_containing_strong_before_code
          out = mark('<p>これは<strong>重要</strong>な設定です。</p><pre><code>x = 1</code></pre>')

          refute_includes out, 'code-caption'
        end

        def test_should_not_mark_strong_only_paragraph_without_following_code
          out = mark('<p><strong>ただの強調</strong></p><p>次の段落です。</p>')

          refute_includes out, 'code-caption'
        end

        # 画像の figure は language- クラスを持たないので対象外。
        def test_should_not_mark_caption_before_image_figure
          out = mark('<p><strong>図の説明</strong></p><figure><img src="a.png"></figure>')

          refute_includes out, 'code-caption'
        end

        # =============================================================
        # 小見出し（strong-heading クラス付与）
        # =============================================================

        # mark_strong_headings! を適用して結果文字列を返す。
        def mark_headings(html)
          Tempfile.create(["vs_heading_test_", ".html"]) do |f|
            f.write("<html><body>#{html}</body></html>")
            f.flush
            PostProcessCommands.mark_strong_headings!(f.path)
            return File.read(f.path, encoding: "utf-8")
          end
        end

        def test_should_mark_strong_only_paragraph_followed_by_text
          out = mark_headings("<p><strong>ビルド時の警告</strong></p><p>次のような警告が出ます。</p>")

          assert_includes out, %(<p class="strong-heading"><strong>ビルド時の警告</strong></p>)
        end

        # コードが続くものは code-caption の担当。二重に印を付けない。
        def test_should_not_mark_strong_heading_before_code
          out = mark_headings("<p><strong>設定例</strong></p><pre><code>x = 1</code></pre>")

          refute_includes out, "strong-heading"
        end

        def test_should_not_mark_sentence_containing_strong_as_heading
          out = mark_headings("<p>これは<strong>重要</strong>な設定です。</p><p>次の段落。</p>")

          refute_includes out, "strong-heading"
        end

        # =============================================================
        # 画像を含む段落（text-wrap: pretty を外す印）
        # =============================================================

        def mark_images(html)
          Tempfile.create(['vs_image_test_', '.html']) do |f|
            f.write("<html><body>#{html}</body></html>")
            f.flush
            PostProcessCommands.mark_inline_image_blocks!(f.path)
            return File.read(f.path, encoding: 'utf-8')
          end
        end

        # 行の中の画像（インライン数式）を含む段落・リスト項目に印を付ける。既存のクラスは保つ
        def test_should_mark_blocks_containing_inline_images
          out = mark_images('<p class="aki">式 <img class="vs-math-inline" src="a.svg"> です。</p>' \
                            '<ul><li>項目 <img src="b.svg"></li></ul>')

          assert_includes out, '<p class="aki vs-inline-image">'
          assert_includes out, '<li class="vs-inline-image">'
        end

        # 図の画像は段落の行の中にないので印を付けない。画像のない段落も対象外
        def test_should_not_mark_blocks_without_inline_images
          out = mark_images('<li><figure><img src="c.webp"><figcaption>図</figcaption></figure></li>' \
                            '<p>画像のない段落です。</p>')

          refute_includes out, 'vs-inline-image'
        end
      end
    end
  end
end
