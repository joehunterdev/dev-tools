# bin/assets

Static assets for XAMPP Tools (icons, images).

## Icons

| File | Used by | Notes |
|------|---------|-------|
| `logo.png` | `Create-Shortcuts.ps1` | Source logo (DT brand, mint + purple) |
| `logo.ico` | `Create-Shortcuts.ps1` | Preferred — Windows shortcut icon |

### Converting PNG → ICO

Windows shortcuts work best with `.ico`. Convert `logo.png` using any of:

- **Online**: [convertio.co](https://convertio.co/png-ico/) or [icoconvert.com](https://icoconvert.com)
- **ImageMagick** (if installed): `magick logo.png -resize 256x256 logo.ico`
- **IrfanView**: File → Save As → ICO

Place the resulting `logo.ico` in this folder. The shortcut module will prefer it over the PNG automatically.
