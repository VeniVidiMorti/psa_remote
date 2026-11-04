#!/bin/sh
# Renders sailfish/icons/stellamaris.svg to the PNG sizes of the Sailfish launcher.
# Uses cairosvg in a temporary uv environment; ImageMagick's own SVG renderer drops the gradient.
set -e
cd "$(dirname "$0")/../sailfish/icons"
for size in 86 108 128 172; do
  mkdir -p "${size}x${size}"
  uv run --quiet --no-project --with cairosvg python -I -c \
    "import cairosvg; cairosvg.svg2png(url='stellamaris.svg', write_to='${size}x${size}/stellamaris.png', output_width=$size, output_height=$size)"
done
