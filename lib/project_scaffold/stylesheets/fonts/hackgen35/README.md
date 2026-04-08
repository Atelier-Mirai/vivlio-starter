# HackGen / HackGen35 for vivlio-starter

This directory is prepared for bundling the HackGen/HackGen35 fonts with the project.

- Project: https://github.com/yuru7/HackGen
- License: SIL Open Font License 1.1 (OFL-1.1)
- Copyright: (c) 2019, Yuko OTAWARA.
- License file: see `./LICENSE` (included verbatim from the upstream repository)

## How to place font files
- Put the required TTF/OTF files (e.g. `HackGen35-Regular.ttf`, `HackGen35-Bold.ttf`, etc.) in this directory.
- Keep the original file names. Do not modify or subset the fonts if you intend to keep the Reserved Font Name (RFN) "白源/HackGen".
- If you modify the fonts (subset, rename, merge, etc.), you must NOT use the RFN per OFL-1.1. Use a different font name.

## Suggested @font-face (example)
Place the files and then define the font-faces in your CSS, for example:

```css
@font-face {
  font-family: "hackgen35";
  src: url("./hackgen35/HackGen35-Regular.ttf") format("truetype");
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}
@font-face {
  font-family: "hackgen35";
  src: url("./hackgen35/HackGen35-Bold.ttf") format("truetype");
  font-weight: 700;
  font-style: normal;
  font-display: swap;
}
```

Then set in `config/book.yml`:

```yaml
page:
  code_font: hackgen35
```

## Notes
- OFL-1.1 allows bundling and embedding the unmodified fonts with software. Include the license text when distributing.
- Nerd Fonts or other merged variants are considered modified; ensure license and naming compliance if you use such variants.
