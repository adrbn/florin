# Desktop Assets

## Tray Icon

Place the following files in this directory for the macOS menu bar icon:

- `tray-iconTemplate.png` — 16×16 px template icon
- `tray-iconTemplate@2x.png` — 32×32 px template icon (Retina)

### Template Icon Convention

The `Template` suffix in the filename tells macOS to treat the image as a
**template image**: it will be automatically inverted (black ↔ white) to
match the menu bar appearance in both Light and Dark mode.

### Design Guidelines

- Use a **black** monochrome icon on a transparent background.
- Keep it simple — fine detail is lost at 16×16 px.
- The macOS menu bar height is 24 px; icons are typically 16–18 px tall.
- Export at 1× (16×16) and 2× (32×32) for Retina displays.

### Generating a Placeholder

If you need a quick placeholder while iterating on the design, you can
generate one with ImageMagick:

```bash
# 16x16
convert -size 16x16 xc:none -fill black \
  -draw "roundrectangle 3,3 13,13 2,2" \
  apps/desktop/assets/tray-iconTemplate.png

# 32x32 (Retina @2x)
convert -size 32x32 xc:none -fill black \
  -draw "roundrectangle 6,6 26,26 4,4" \
  apps/desktop/assets/tray-iconTemplate@2x.png
```
