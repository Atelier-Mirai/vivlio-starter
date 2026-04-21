#!/usr/bin/env ruby
# frozen_string_literal: true

# SVG ファイルの全座標値をスケールし、viewBox をキリのいい数値に整えるスクリプト。
#
# 使い方:
#   ruby scale_svg.rb <input.svg> <scale> [pad_x] [pad_y]
#
# 例:
#   ruby scale_svg.rb contents/logos/vivlio_starter_logo_outline.svg 1.14402 0 0.82
#
# 処理内容:
#   - SVG 内の全 path/rect/circle/line/polyline/polygon の座標属性を scale 倍
#   - linearGradient の座標属性を scale 倍
#   - text/tspan の x/y/font-size を scale 倍
#   - g/use の transform を scale 倍（translate の値を scale 倍し、既存 scale を乗算）
#   - viewBox を "0 0 W H" に更新（W = 元W * scale + pad_x*2, H = 元H * scale + pad_y*2）
#   - 外側ラッパー <g transform="translate(...) scale(...)"> があれば除去して座標に吸収
#
# 注意: このスクリプトは現在の「scaleラッパー方式」から「直接数値方式」への移行用です。

require 'nokogiri'
require 'bigdecimal'

# 数値を丸める（小数点以下4桁）
def r(v)
  v.round(4)
end

# "translate(tx, ty) scale(s)" 形式の transform を解析
def parse_transform(str)
  return {} if str.nil? || str.empty?

  result = {}
  if (m = str.match(/translate\(\s*([-\d.]+)[,\s]+([-\d.]+)\s*\)/))
    result[:tx] = m[1].to_f
    result[:ty] = m[2].to_f
  end
  if (m = str.match(/scale\(\s*([-\d.]+)\s*\)/))
    result[:scale] = m[1].to_f
  end
  result
end

# path の d 属性内の数値を scale 倍（座標値のみ、コマンド文字は保持）
def scale_path_d(d, scale)
  # 数値トークンをすべて scale 倍する
  d.gsub(/([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)/) do
    r($1.to_f * scale).to_s
  end
end

# 属性値の数値を scale 倍
def scale_attr(node, attr, scale)
  return unless node[attr]
  node[attr] = r(node[attr].to_f * scale).to_s
end

# スペース/カンマ区切りの数値リストを scale 倍
def scale_points(str, scale)
  str.gsub(/([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)/) do
    r($1.to_f * scale).to_s
  end
end

def process_svg(input_path, scale, pad_x, pad_y)
  doc = Nokogiri::XML(File.read(input_path)) { |c| c.noblanks }
  svg = doc.at_css('svg')

  # --- viewBox の更新 ---
  vb = svg['viewBox']&.split(/[\s,]+/)&.map(&:to_f)
  raise "viewBox が見つかりません: #{input_path}" unless vb

  orig_w, orig_h = vb[2], vb[3]
  new_w = r(orig_w * scale + pad_x * 2)
  new_h = r(orig_h * scale + pad_y * 2)
  svg['viewBox'] = "0 0 #{new_w} #{new_h}"

  # --- 外側ラッパー <g> の除去 ---
  # translate(pad_x, pad_y) scale(scale) のラッパーがあれば除去して子を昇格
  svg.children.each do |child|
    next unless child.name == 'g'
    t = parse_transform(child['transform'])
    next unless t[:scale] && (t[:scale] - scale).abs < 0.001

    # このラッパーを除去し、子ノードを svg 直下に移動
    child.children.each { |c| child.before(c) }
    child.remove
    break
  end

  # --- 全要素の座標を scale 倍 ---
  doc.traverse do |node|
    next unless node.is_a?(Nokogiri::XML::Element)

    case node.name
    when 'path'
      node['d'] = scale_path_d(node['d'], scale) if node['d']

    when 'rect'
      %w[x y width height rx ry].each { |a| scale_attr(node, a, scale) }

    when 'circle'
      %w[cx cy r].each { |a| scale_attr(node, a, scale) }

    when 'ellipse'
      %w[cx cy rx ry].each { |a| scale_attr(node, a, scale) }

    when 'line'
      %w[x1 y1 x2 y2].each { |a| scale_attr(node, a, scale) }

    when 'polyline', 'polygon'
      node['points'] = scale_points(node['points'], scale) if node['points']

    when 'text', 'tspan'
      %w[x y dx dy].each { |a| scale_attr(node, a, scale) }
      scale_attr(node, 'font-size', scale)

    when 'linearGradient', 'radialGradient'
      %w[x1 y1 x2 y2 cx cy r fx fy].each { |a| scale_attr(node, a, scale) }

    when 'g', 'use', 'symbol'
      next unless node['transform']
      t = parse_transform(node['transform'])
      parts = []
      if t[:tx] || t[:ty]
        tx = r((t[:tx] || 0) * scale + pad_x)
        ty = r((t[:ty] || 0) * scale + pad_y)
        parts << "translate(#{tx}, #{ty})"
      end
      parts << "scale(#{t[:scale]})" if t[:scale]
      node['transform'] = parts.join(' ')
    end
  end

  # pad_x/pad_y を translate に反映（ラッパー除去後の最上位 g に適用）
  # ※ ラッパーを除去した場合、pad は viewBox 側で吸収済みなので追加 translate 不要

  doc.to_xml(indent: 2)
end

# --- メイン ---
if ARGV.length < 2
  puts "使い方: ruby scale_svg.rb <input.svg> <scale> [pad_x] [pad_y]"
  exit 1
end

input  = ARGV[0]
scale  = ARGV[1].to_f
pad_x  = (ARGV[2] || 0).to_f
pad_y  = (ARGV[3] || 0).to_f

output = process_svg(input, scale, pad_x, pad_y)

# 上書き保存（バックアップは .bak に）
File.write("#{input}.bak", File.read(input))
File.write(input, output)

puts "完了: #{input}"
puts "  scale=#{scale}, pad_x=#{pad_x}, pad_y=#{pad_y}"
puts "  バックアップ: #{input}.bak"
