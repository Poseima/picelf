# README visuals / 首页视觉素材

| Asset | Source / 来源 |
| :--- | :--- |
| `renshen-tidewater.gif` | User-supplied animated banner from `output/renshen-water-tidewater/renshen-tidewater.gif`, copied unchanged / 用户提供的水面光影动图，原样复制 |
| `scrolling.png` | `Picelf vibe marketing/appstore/滚动截图介绍图.png` |
| `editor.png` | `Picelf vibe marketing/appstore/编辑介绍图.png` |
| `desktop-pins.png` | `Picelf vibe marketing/appstore/贴图介绍图.png` |
| `hero-art.png` | Built-in ImageGen artwork with the existing Picelf app icon as a brand reference; shared by both languages / 使用内置 ImageGen、以现有 Picelf 图标为品牌参考生成，中英文共用 |
| `ocr.zh-CN.svg`, `ocr.en.svg` | Original workflow illustrations using generic sample text, not app screenshots / 使用通用示例文字的原创功能示意，非应用截图 |

The three PNG showcase images are unchanged copies of the supplied marketing assets and show the Chinese interface. README text, alternative text and OCR illustrations are localized in Simplified Chinese and English. The shared hero contains only the Picelf brand name.

三张 PNG 展示图直接复制自提供的营销素材，展示中文界面。README 正文、替代文本与 OCR 示意均提供简体中文和英文版本。共用主视觉仅包含 Picelf 品牌名。

The local marketing source folder is ignored. Pricing comparisons, old paid-edition claims, campaign notes and business-document OCR examples are not used by either README. Keep replacements free of account information and private documents.

本地营销源目录已忽略。两个 README 均不使用价格对比、旧付费版宣传、营销策略文档或业务文档 OCR 示例。替换展示图时，请避免账号信息和私人文档。

Keep the two README files structurally aligned. To add a language, create a localized README and OCR SVG variant, then add its language link to every README. The SVGs use system fonts, self-contained shapes and text; no scripts or external resources are required.

保持两个 README 结构一致。新增语言时，添加对应 README 与 OCR SVG，并在每个 README 的语言导航中加入链接。SVG 使用系统字体与自包含图形、文字，无需脚本或外部资源。

## Hero generation / 主视觉生成

Tool: built-in `image_gen.imagegen`. Brand reference: `Sources/Picelf/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`. The hero is conceptual artwork, not a screenshot of the application. The original app icon is unchanged.

工具：内置 `image_gen.imagegen`。品牌参考来自现有应用图标；主视觉为概念艺术画面，非应用截图，原应用图标未改动。

<details>
<summary>Generation prompt / 生成提示词</summary>

```text
Use case: ads-marketing. Asset: wide editorial hero banner for the GitHub README of Picelf, an open-source screenshot, long-image stitching and image annotation app. Generate a refined artistic banner, landscape about 2400 x 1000 (2.4:1). Reference image 1 is the EXISTING Picelf app logo, a green elf face surrounded by green-to-blue capture corners on a white rounded square. This is a supporting brand insert, not a style reference: reproduce this real logo faithfully, preserving its shape, smiling face, green-to-blue colors and white squircle. Place it unobtrusively but clearly in the left third, about 80px wide in a 2400px canvas, above the name. Do not invent a replacement logo. Background: warm ivory matte fine art paper, nearly white (#F8F7F3), very subtle natural texture. Composition: at least 60 percent empty breathing room, generous outer margins. Left third: logo and exquisite restrained dark graphite serif typography, exact text 'Picelf' ONLY. No other text. Right third: a delicate asymmetric paper art assemblage conveying collecting moments: two or three overlapping floating ivory photographic paper cards, a soft abstract sage-green landscape with a muted apricot sun, a narrow paper strip peeking out suggesting a long capture; one very fine loose pencil curve connecting them. This is conceptual art, not an app screenshot. Sophisticated art-book cover and Japanese stationery editorial sensibility, understated, airy, tactile, quiet. Palette: ivory dominates; soft sage, faint apricot and a tiny pale lavender accent; preserve the original logo's colors only in the logo. Soft daylight and barely perceptible realistic paper shadows. Small details, lots of negative space. Avoid dark backgrounds, teal tech grids, glowing gradients, fake app windows, dashboards, UI buttons, crowded objects, extra icons, ornate swirls, large saturated blobs, dense copy, slogans, badges, watermarks. No rounded background panel enclosing the whole banner; seamless warm-white canvas.
```

</details>

### Final palette correction / 最终配色修订

The final edit matches the app theme: emerald `#008C66`, deep emerald `#006B4C`, fresh emerald `#50C878`, with cyan-blue accents from the logo and a clean white paper base. Both OCR illustrations follow the same palette.

最终版本使用应用主题的翡翠绿、深翡翠绿与明亮绿色，辅以 logo 中的青蓝色及明亮纸白。两个 OCR 示意图采用相同配色。

<details>
<summary>Final edit prompt / 最终编辑提示词</summary>

```text
Use case: precise-object-edit. Edit target image 1 is the Picelf README hero. Supporting brand reference image 2 is the actual Picelf logo. Correct ONLY the palette to match the application. Preserve the wide landscape composition, generous empty space, typography 'Picelf', logo position, paper collage geometry, fine connecting line, delicate watercolor textures and soft natural shadows. The app's actual primary colors are emerald #008C66, deep emerald #006B4C and fresh emerald #50C878; its logo also has cyan and azure blue. Apply those EXACT hue families throughout the artwork: emerald and fresh mint green should dominate the landscape and foliage, with restrained clear cyan/azure watercolor washes on the long photographic strip. Neutral clean white cotton-paper background (#FBFDFC) with a very faint mint tint, not yellowed ivory. Use soft diluted versions of the saturated brand colors to retain a quiet airy aesthetic, but hues must remain emerald and cyan-blue; eliminate all olive, khaki, dusty sage, apricot, beige and lavender accents. Recolor the apricot sun to a pale mint circular watercolor accent and purple flowers/petal to soft cyan. Recolor the fine pencil curve to faint emerald. Keep the word Picelf elegant dark charcoal with a very slight green tint. Keep the actual logo from image 2 faithful and unchanged in identity, green-to-blue capture corners and smiling green elf face on the white rounded square. No added text, objects, UI, decoration or dark backgrounds. The goal is the SAME beautiful minimal editorial cover in Picelf's actual emerald, mint, cyan and blue brand palette.
```

</details>
