## chapter.css

book.yml の theme.style == image なら
chapter.css + image_header.css で、各章を装飾
book.yml の theme.style == simple なら
chapter.css + simple_header.css で、各章を装飾する仕様です。

pre_process.rbを改良し、chapter.cssに image_header.css / simple_header.css が適宜挿入されるようにせよ。