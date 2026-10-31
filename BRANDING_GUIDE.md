# AZKAR brand guide

## Identity

AZKAR pairs a clean mihrab silhouette with a crescent and guiding star. The
arched frame represents a dedicated memorial space; the gold details signify
remembrance, light, and ongoing charity. The mark is original AZKAR artwork
created for this project and contains no third-party branding.

| Color | Hex | Use |
|---|---|---|
| Emerald | `#064E3B` | Primary mark, light-theme wordmark, app icon background |
| Gold | `#D4AF37` | Crescent, star, and restrained accents |
| Warm off-white | `#F8F5EC` | Light canvas and opaque launcher backgrounds |
| White | `#FFFFFF` | Existing theme surfaces |

Use the SVG wordmark for static design work. In Flutter, use
`AzkarBrandMark` for the symbol or `AzkarBrandLockup` for the symbol and
English/Arabic name. The widget selects an off-white mark on dark themes and
emerald on light themes while preserving the gold detail. Keep the mark
undistorted, use the app-icon PNG only as a square launcher asset, and do not
add text to launcher icons.

## Asset locations

- `assets/branding/azkar_logo.svg`: full-color horizontal vector lockup; primary
  editable master.
- `assets/branding/azkar_logo_light.svg`: transparent-background lockup for
  light surfaces.
- `assets/branding/azkar_logo_dark.svg`: lockup on an emerald field for dark
  surfaces.
- `assets/branding/azkar_logo_monochrome.svg`: single-color lockup.
- `assets/branding/azkar_logo_*.png`: 1024px square symbol variants
  (transparent, light background, dark background, full color, monochrome).
- `assets/branding/azkar_icon.png`: opaque square application icon.
- `assets/branding/azkar_icon_foreground.png` and
  `azkar_icon_monochrome.png`: transparent adaptive-icon layers.
- `android/app/src/main/res`: legacy density-specific launcher icons, adaptive
  icon resources, and branded native launch background.
- `ios/Runner/Assets.xcassets/AppIcon.appiconset`: opaque iOS AppIcon sizes.
- `ios/Runner/Assets.xcassets/LaunchImage.imageset`: branded launch artwork.
- `web/favicon.png` and `web/icons/`: favicon and installable PWA icons,
  including maskable variants.

## Platform integration

Flutter uses `lib/core/design/azkar_brand.dart` for in-app branding. Native
display names and launch assets are configured in the Android manifest and
resources, iOS `Info.plist`/asset catalog/launch storyboard, and the web
manifest/HTML metadata. The PWA theme and launch colors use the existing AZKAR
emerald and warm off-white palette.

## Regenerating raster assets

The SVG files are the vector wordmark masters. The geometric symbol is also
defined in `tools/generate_brand_assets.py`, which regenerates launcher, splash,
and logo-variant PNGs without adding a Flutter runtime dependency. From the
project root, run:

```powershell
python tools\generate_brand_assets.py
```

The script requires Python 3 and Pillow. If the symbol geometry changes, update
the SVG symbol paths and the matching `draw_mark` geometry in the generator,
then rerun the script. Keep the iOS icon backgrounds opaque and preserve the
safe margin in Android adaptive foreground and web maskable artwork.
