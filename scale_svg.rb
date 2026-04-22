#!/usr/bin/env ruby
# frozen_string_literal: true

# SVG の「scaleラッパー方式」を「直接数値方式」に変換するスクリプト。
#
# 対象ファイルの構造:
#   <svg viewBox="0 0 W H">
#     <g transform="translate(tx, ty) scale(s)">
#       ... 元の座標 ...
#     </g>
#   </svg>
#
# 変換後:
#   <svg viewBox="0 0 W H">
#     ... 座標を s 倍 + translate 済みの値に書き換え ...
#   </svg>
#
# 使い方:
#   ruby scale_svg.rb <file.svg>          # 上書き（.bak を作成）
#   ruby scale_svg.rb <file.svg> --dry    # 標準出力のみ（ファイル変更なし）

require 'nokogiri'

DRY = ARGV.include?('--dry')
input_path = ARGV.reject { |a| a.start_with?('--') }.first

unless input_path
  puts "使い方: ruby scale_svg.rb <file.svg> [--dry]"
  exit 1
end

# --- transform 文字列のパース ---
def parse_transform(str)
  return { tx: 0.0, ty: 0.0, scale: nil } if str.nil? || str.strip.empty?

  tx, ty, scale = 0.0, 0.0, nil

  if (m = str.match(/translate\(\s*([-\d.eE+]+)[,\s]+([-\d.eE+]+)\s*\)/))
    tx = m[1].to_f
    ty = m[2].to_f
  end
  if (m = str.match(/scale\(\s*([-\d.eE+]+)\s*\)/))
    scale = m[1].to_f
  end

  { tx: tx, ty: ty, scale: scale }
end

# --- 数値を丸める ---
def r(v)
  # 小数点以下4桁、末尾ゼロ除去
  s = format('%.4f', v)
  s.sub(/\.?0+$/, '')
end

# --- path d 属性の座標変換 ---
# SVG path の d 属性: コマンド文字と数値が混在
# 絶対コマンド(大文字)の座標に tx/ty を加算し scale を掛ける
# 相対コマンド(小文字)は scale のみ
def transform_path_d(d, scale, tx, ty)
  # トークン分割: コマンド文字と数値を分離
  tokens = d.scan(/[MmZzLlHhVvCcSsQqTtAaEe]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/)

  result = []
  i = 0
  while i < tokens.size
    tok = tokens[i]

    if tok =~ /\A[A-Za-z]\z/
      cmd = tok
      result << cmd
      i += 1

      case cmd
      # 絶対コマンド: x,y ペアに tx/ty を加算
      when 'M', 'L', 'T'
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          x = tokens[i].to_f * scale + tx
          y = tokens[i+1].to_f * scale + ty
          result << r(x) << r(y)
          i += 2
        end
      when 'm', 'l', 't'
        # 相対: scale のみ（最初の m は絶対扱いが本来だが簡略化）
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          result << r(tokens[i].to_f * scale)
          i += 1
        end
      when 'H'
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          result << r(tokens[i].to_f * scale + tx)
          i += 1
        end
      when 'h'
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          result << r(tokens[i].to_f * scale)
          i += 1
        end
      when 'V'
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          result << r(tokens[i].to_f * scale + ty)
          i += 1
        end
      when 'v'
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          result << r(tokens[i].to_f * scale)
          i += 1
        end
      when 'C'
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          # 3組の x,y
          3.times do
            result << r(tokens[i].to_f * scale + tx)
            result << r(tokens[i+1].to_f * scale + ty)
            i += 2
          end
        end
      when 'c'
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          6.times { result << r(tokens[i].to_f * scale); i += 1 }
        end
      when 'S', 'Q'
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          2.times do
            result << r(tokens[i].to_f * scale + tx)
            result << r(tokens[i+1].to_f * scale + ty)
            i += 2
          end
        end
      when 's', 'q'
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          4.times { result << r(tokens[i].to_f * scale); i += 1 }
        end
      when 'A'
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          result << r(tokens[i].to_f * scale)     # rx
          result << r(tokens[i+1].to_f * scale)   # ry
          result << tokens[i+2]                    # x-rotation
          result << tokens[i+3]                    # large-arc-flag
          result << tokens[i+4]                    # sweep-flag
          result << r(tokens[i+5].to_f * scale + tx) # x
          result << r(tokens[i+6].to_f * scale + ty) # y
          i += 7
        end
      when 'a'
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          result << r(tokens[i].to_f * scale)
          result << r(tokens[i+1].to_f * scale)
          result << tokens[i+2]
          result << tokens[i+3]
          result << tokens[i+4]
          result << r(tokens[i+5].to_f * scale)
          result << r(tokens[i+6].to_f * scale)
          i += 7
        end
      when 'Z', 'z'
        # no operands
      else
        # 未知コマンド: 数値はそのまま
        while i < tokens.size && tokens[i] !~ /\A[A-Za-z]\z/
          result << tokens[i]
          i += 1
        end
      end
    else
      result << tok
      i += 1
    end
  end

  result.join(' ')
end

# --- 属性値を変換 ---
def scale_coord(val, scale, offset = 0.0)
  r(val.to_f * scale + offset)
end

# --- メイン処理 ---
doc = Nokogiri::XML(File.read(input_path))
svg = doc.at_css('svg')

# 直下の <g> でラッパーを探す
wrapper = svg.children.find do |n|
  n.is_a?(Nokogiri::XML::Element) && n.name == 'g' && n['transform']&.include?('scale')
end

unless wrapper
  puts "ラッパー <g transform='... scale(...)'>  が見つかりません: #{input_path}"
  exit 1
end

t = parse_transform(wrapper['transform'])
scale = t[:scale]
tx    = t[:tx]
ty    = t[:ty]

puts "検出: scale=#{scale}, tx=#{tx}, ty=#{ty}"

# ラッパー内の全要素を変換
wrapper.traverse do |node|
  next unless node.is_a?(Nokogiri::XML::Element)

  case node.name
  when 'path'
    node['d'] = transform_path_d(node['d'], scale, tx, ty) if node['d']

  when 'rect'
    node['x']      = scale_coord(node['x'], scale, tx)      if node['x']
    node['y']      = scale_coord(node['y'], scale, ty)      if node['y']
    node['width']  = scale_coord(node['width'], scale)       if node['width']
    node['height'] = scale_coord(node['height'], scale)      if node['height']

  when 'circle'
    node['cx'] = scale_coord(node['cx'], scale, tx) if node['cx']
    node['cy'] = scale_coord(node['cy'], scale, ty) if node['cy']
    node['r']  = scale_coord(node['r'],  scale)     if node['r']

  when 'line'
    node['x1'] = scale_coord(node['x1'], scale, tx) if node['x1']
    node['y1'] = scale_coord(node['y1'], scale, ty) if node['y1']
    node['x2'] = scale_coord(node['x2'], scale, tx) if node['x2']
    node['y2'] = scale_coord(node['y2'], scale, ty) if node['y2']

  when 'text', 'tspan'
    node['x']         = scale_coord(node['x'], scale, tx)        if node['x']
    node['y']         = scale_coord(node['y'], scale, ty)        if node['y']
    node['font-size'] = scale_coord(node['font-size'], scale)     if node['font-size']

  when 'linearGradient'
    node['x1'] = scale_coord(node['x1'], scale, tx) if node['x1']
    node['y1'] = scale_coord(node['y1'], scale, ty) if node['y1']
    node['x2'] = scale_coord(node['x2'], scale, tx) if node['x2']
    node['y2'] = scale_coord(node['y2'], scale, ty) if node['y2']

  when 'g'
    next if node == wrapper  # ラッパー自身はスキップ
    next unless node['transform']
    inner = parse_transform(node['transform'])
    new_tx = r(inner[:tx] * scale + tx)
    new_ty = r(inner[:ty] * scale + ty)
    parts = ["translate(#{new_tx}, #{new_ty})"]
    parts << "scale(#{inner[:scale]})" if inner[:scale]
    node['transform'] = parts.join(' ')
  end
end

# ラッパーを除去して子を昇格
wrapper.children.each { |c| wrapper.before(c) }
wrapper.remove

output = doc.to_xml(indent: 2)

if DRY
  puts output
else
  File.write("#{input_path}.bak", File.read(input_path))
  File.write(input_path, output)
  puts "完了: #{input_path}  (バックアップ: #{input_path}.bak)"
end
