#!/usr/bin/env bash
set -euo pipefail

# Build 11-install.md directly with Vivliostyle CLI
npx vivliostyle build -c scripts/direct_vivliostyle_11.config.js
# Build 81-install.md directly
npx vivliostyle build -c scripts/direct_vivliostyle_81.config.js

# Check outlines using HexaPDF
ruby scripts/check_pdf_outlines.rb 11-direct.pdf 81-direct.pdf
