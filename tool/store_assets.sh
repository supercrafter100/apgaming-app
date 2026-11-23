#!/usr/bin/env bash
# Builds the Google Play store assets in store/google-play/:
#   icon-512.png         app icon, 512 × 512
#   feature-graphic.png  1024 × 500
#   phone/*.png          phone screenshots, 1080 × 1920, rendered from the real screens with the demo data
#
# Needs flutter, rsvg-convert and ImageMagick 7 (magick). Run from the project root: tool/store_assets.sh
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=store/google-play
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Inter, the app's font, as the google_fonts package downloads it (content-addressed, so the hashes check the files)
FONTS=build/store-fonts
mkdir -p "$FONTS"
while read -r weight hash; do
  file="$FONTS/Inter-$weight.ttf"
  if ! echo "$hash  $file" | sha256sum -c --status 2>/dev/null; then
    curl -fsSL -o "$file" "https://fonts.gstatic.com/s/a/$hash.ttf"
    echo "$hash  $file" | sha256sum -c --status
  fi
done <<'EOF'
100 36201b34de0f9164edaadfa3854a84e0e4e6184588a03e775ef0ac0a24783139
200 4fbc12952c229be983a58502c92fc6bcde626d86d490cc71d980de52e5e975b1
300 8641cf8fd5e04d0f94062395a2d1ab1ba5467831af690069e8f3ea0efe640d70
400 15b294b67f2f8bbc04d990023ef4aec66502b87dc9040d84abe5f896ccb693de
500 36a36ff7ac46dc2aeceac3a80a87a67e7b844b8fc936699259aac8fba9bcf734
600 334bb2c51aeba5f566abac8d03a7e75ab3234d6926b52e92a85dc704129258b5
700 76121a34a606cc8a0e1ef5a47d2b9ba9678c41f5c852d63eb28f62069373bfad
800 6af943899936fd3fd15a5889db4a384cec311c9bfe33d74bcfd3e0ae56f1b1d1
900 d892b18d080d1200aa41ea8851da84dd8c24c33843d491fa034ac57b16f22973
EOF

echo "Rendering screenshots…"
flutter test tool/store_screenshots_test.dart --dart-define=FONT_DIR="$PWD/$FONTS" > "$WORK/flutter.log" 2>&1 ||
  { cat "$WORK/flutter.log"; exit 1; }

echo "Icon…"
rsvg-convert -w 512 -h 512 assets/icon/icon.svg | magick - -strip "PNG32:$OUT/icon-512.png"

echo "Feature graphic…"
cat > "$WORK/bg.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0d1430"/><stop offset="1" stop-color="#020618"/></linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#d42422"/><stop offset="1" stop-color="#d42422" stop-opacity="0"/></radialGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#bg)"/>
  <ellipse cx="150" cy="190" rx="330" ry="260" fill="url(#glow)" opacity="0.32"/>
  <ellipse cx="820" cy="330" rx="300" ry="260" fill="url(#glow)" opacity="0.22"/>
</svg>
EOF
rsvg-convert "$WORK/bg.svg" -o "$WORK/bg.png"
rsvg-convert -w 260 -h 260 assets/icon/android_foreground.svg | magick - -trim +repage -resize x96 "$WORK/mark.png"
magick -background none -fill white -font "$FONTS/Inter-800.ttf" -pointsize 70 label:"AP " "$WORK/title-1.png"
magick -background none -fill '#d42422' -font "$FONTS/Inter-800.ttf" -pointsize 70 label:"Gaming Hub" "$WORK/title-2.png"
magick -background none -fill '#cbd5e1' -font "$FONTS/Inter-500.ttf" -pointsize 28 -interline-spacing 6 \
  label:$'Reserveer een gaming-pc of console\nin de AP Gaming Hub.' "$WORK/tagline.png"
# A screenshot as a phone: rounded corners, a faint edge and a shadow
magick "$OUT/phone/3-choose-hardware.png" -resize 330x \
  \( +clone -alpha extract -fill black -colorize 100 -fill white -draw "roundrectangle 0,0 %[fx:w-1],%[fx:h-1] 34,34" \) \
  -alpha off -compose CopyOpacity -composite "$WORK/phone-round.png"
magick "$WORK/phone-round.png" \
  \( +clone -alpha extract -morphology EdgeIn Diamond:2 -background 'rgba(255,255,255,0.18)' -alpha shape \) \
  -compose over -composite \( +clone -background black -shadow 70x22+0+14 \) +swap -background none -layers merge +repage \
  "$WORK/phone.png"
TITLE_1_WIDTH=$(magick identify -format %w "$WORK/title-1.png")
magick "$WORK/bg.png" \
  "$WORK/mark.png" -geometry +72+92 -composite \
  "$WORK/title-1.png" -geometry +64+214 -composite \
  "$WORK/title-2.png" -geometry +$((64 + TITLE_1_WIDTH))+214 -composite \
  "$WORK/tagline.png" -geometry +68+318 -composite \
  "$WORK/phone.png" -geometry +625+48 -composite \
  -alpha off -strip "PNG24:$OUT/feature-graphic.png"

echo "Done:"
ls -1 "$OUT"/*.png "$OUT"/phone/*.png
