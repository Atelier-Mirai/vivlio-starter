# frozen_string_literal: true

require 'fileutils'

module Vivlio
  module Starter
    module Pdf
      # JPEG データを DCTDecode ストリームとして直接 PDF に埋め込む。
      # HexaPDF / img2pdf などの外部 gem・外部コマンドに依存しない。
      module JpegToPdf
        class Error < StandardError
        end

        module_function

        def convert(images, output_pdf)
          raise Error, '結合対象の画像がありません' if images.empty?

          PdfBuilder.new(images).write(output_pdf)
        end

        # JPEG 群から最小構成の PDF 1 ファイルを生成する内部ビルダー。
        class PdfBuilder
          def initialize(image_paths)
            @image_paths = image_paths
            @objects = {}
            @next_id = 0
          end

          def write(output_pdf)
            catalog_id = next_id
            pages_id = next_id
            page_ids = build_page_objects(pages_id)

            add_object(pages_id, "<< /Type /Pages /Kids [#{page_ids.map { "#{it} 0 R" }.join(' ')}] /Count #{page_ids.size} >>\n")
            add_object(catalog_id, "<< /Type /Catalog /Pages #{pages_id} 0 R >>\n")

            dir = File.dirname(output_pdf)
            FileUtils.mkdir_p(dir) unless dir == '.'
            File.binwrite(output_pdf, build_pdf(catalog_id))
          end

          private

          attr_reader :image_paths, :objects

          def build_page_objects(pages_id)
            image_paths.each_with_index.map do |path, index|
              jpeg_data = File.binread(path)
              jpeg_info = JpegInfo.read(jpeg_data, path:)
              emit_page_with_image(pages_id, jpeg_info, jpeg_data, image_name: "Im#{index + 1}")
            end
          end

          def emit_page_with_image(pages_id, jpeg_info, jpeg_data, image_name:)
            image_id = next_id
            content_id = next_id
            page_id = next_id

            add_object(image_id, image_object(jpeg_info, jpeg_data))
            add_object(content_id, stream_object("q #{jpeg_info.width} 0 0 #{jpeg_info.height} 0 0 cm /#{image_name} Do Q\n"))
            add_object(page_id, page_object(pages_id, content_id, image_id, jpeg_info, image_name:))

            page_id
          end

          def image_object(jpeg_info, jpeg_data)
            dictionary = "<< /Type /XObject /Subtype /Image\n" \
                         "   /Width #{jpeg_info.width} /Height #{jpeg_info.height}\n" \
                         "   /ColorSpace #{jpeg_info.color_space} /BitsPerComponent #{jpeg_info.bits_per_component}\n" \
                         "   /Filter /DCTDecode /Length #{jpeg_data.bytesize} >>\n"
            stream_object_with_dictionary(dictionary, jpeg_data)
          end

          def page_object(pages_id, content_id, image_id, jpeg_info, image_name:)
            "<< /Type /Page /Parent #{pages_id} 0 R\n" \
              "   /MediaBox [0 0 #{jpeg_info.width} #{jpeg_info.height}]\n" \
              "   /Resources << /XObject << /#{image_name} #{image_id} 0 R >> >>\n" \
              "   /Contents #{content_id} 0 R >>\n"
          end

          def stream_object(content)
            stream_object_with_dictionary("<< /Length #{content.b.bytesize} >>\n", content)
          end

          def stream_object_with_dictionary(dictionary, content)
            dictionary.b + "stream\n".b + content.b + "\nendstream\n".b
          end

          def next_id
            @next_id += 1
          end

          def add_object(id, content)
            objects[id] = content.b
          end

          def build_pdf(catalog_id)
            pdf = +'%PDF-1.4\n'.b
            offsets = {}

            objects.sort.each do |id, content|
              offsets[id] = pdf.bytesize
              pdf << "#{id} 0 obj\n".b << content << "endobj\n".b
            end

            xref_offset = pdf.bytesize
            pdf << build_xref(offsets)
            pdf << "trailer\n<< /Size #{@next_id + 1} /Root #{catalog_id} 0 R >>\n".b
            pdf << "startxref\n#{xref_offset}\n%%EOF\n".b
            pdf
          end

          def build_xref(offsets)
            xref = +"xref\n0 #{@next_id + 1}\n0000000000 65535 f \n".b
            (1..@next_id).each do |id|
              offset = offsets.fetch(id)
              xref << format("%010d 00000 n \n", offset).b
            end
            xref
          end
        end

        JpegMetadata = Data.define(:width, :height, :bits_per_component, :color_space)

        # JPEG の SOF マーカーから PDF 埋め込みに必要な寸法・色空間を読む。
        module JpegInfo
          module_function

          SOF_MARKERS = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].freeze
          STANDALONE_MARKERS = [0x01, *(0xD0..0xD9)].freeze

          def read(data, path: nil)
            raise Error, "JPEG ではありません: #{path}" unless jpeg?(data)

            offset = 2
            while offset < data.bytesize
              marker_offset = next_marker_offset(data, offset)
              raise Error, "JPEG の寸法を取得できませんでした: #{path}" unless marker_offset

              marker = data.getbyte(marker_offset + 1)
              offset = marker_offset + 2
              next if STANDALONE_MARKERS.include?(marker)

              segment_length = read_segment_length(data, offset, path:)
              return metadata_from_sof(data, offset, path:) if SOF_MARKERS.include?(marker)

              offset += segment_length
            end

            raise Error, "JPEG の寸法を取得できませんでした: #{path}"
          end

          def jpeg?(data)
            data.bytesize >= 4 && data.getbyte(0) == 0xFF && data.getbyte(1) == 0xD8
          end

          def next_marker_offset(data, offset)
            index = offset
            index += 1 while index < data.bytesize && data.getbyte(index) != 0xFF
            index += 1 while index < data.bytesize && data.getbyte(index) == 0xFF
            return nil if index >= data.bytesize

            index - 1
          end

          def read_segment_length(data, offset, path:)
            raise Error, "JPEG セグメントが壊れています: #{path}" if offset + 1 >= data.bytesize

            data.byteslice(offset, 2).unpack1('n')
          end

          def metadata_from_sof(data, offset, path:)
            segment_length = read_segment_length(data, offset, path:)
            raise Error, "JPEG SOF セグメントが壊れています: #{path}" if segment_length < 8

            bits = data.getbyte(offset + 2)
            height = data.byteslice(offset + 3, 2).unpack1('n')
            width = data.byteslice(offset + 5, 2).unpack1('n')
            components = data.getbyte(offset + 7)

            JpegMetadata.new(width:, height:, bits_per_component: bits, color_space: color_space_for(components, path:))
          end

          def color_space_for(components, path:)
            case components
            when 1 then '/DeviceGray'
            when 3 then '/DeviceRGB'
            else
              raise Error, "対応していないJPEG色空間です: components=#{components} #{path}"
            end
          end
        end
      end
    end
  end
end
