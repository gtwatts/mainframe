# Extension Icon

The MAINFRAME Bash Language Support extension icon should be placed here.

## Requirements

- **Filename**: `icon.png`
- **Size**: 128x128 pixels (minimum), 256x256 or 512x512 recommended
- **Format**: PNG with transparency
- **Design**: Should represent MAINFRAME and/or bash scripting

## Icon Design Guidelines

### Recommended Elements

- **Terminal/Shell** imagery (command prompt, terminal window)
- **Bash logo** elements (if license permits)
- **Function/Code** symbols (`f()`, `{}`, `</>`)
- **MAINFRAME** branding (subtle)

### Color Palette

- **Primary**: Blue/teal (tech/code)
- **Accent**: Green (bash/terminal traditional)
- **Background**: Transparent or dark

### Design Tools

- **Figma** (free, online)
- **Inkscape** (free, vector)
- **GIMP** (free, raster)
- **Canva** (free templates)

## Quick Icon Generation

If you don't have an icon yet, create a simple text-based icon:

### Using ImageMagick

```bash
# Simple text icon
convert -size 512x512 xc:transparent \
  -font DejaVu-Sans-Bold -pointsize 200 \
  -fill '#4EC9B0' -gravity center \
  -annotate +0+0 'M' \
  icon.png
```

### Using Python + PIL

```python
from PIL import Image, ImageDraw, ImageFont

# Create 512x512 transparent image
img = Image.new('RGBA', (512, 512), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Draw background circle
draw.ellipse([56, 56, 456, 456], fill='#2D2D30', outline='#4EC9B0', width=8)

# Draw 'M' for MAINFRAME
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 300)
draw.text((256, 256), 'M', fill='#4EC9B0', font=font, anchor='mm')

# Save
img.save('icon.png')
```

## Temporary Placeholder

Until a proper icon is created, the extension will use VS Code's default extension icon.

To use a temporary icon, create any 512x512 PNG and place it here as `icon.png`.

## Icon Checklist

Before finalizing:

- [ ] 512x512 pixels (or larger, square)
- [ ] PNG format with transparency
- [ ] Looks good at small sizes (32x32, 16x16)
- [ ] Professional appearance
- [ ] Matches MAINFRAME branding
- [ ] No copyright violations

## References

- [VS Code Icon Guidelines](https://code.visualstudio.com/api/references/extension-manifest#extension-icon)
- [Extension Publishing](https://code.visualstudio.com/api/working-with-extensions/publishing-extension)
