#!/usr/bin/env bash
# ProsperoEden - Regenerate the launcher's baked assets (font atlas and art).
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The results are committed under headless/prosperoeden/ui; run this only after changing the
# font, the glyph set or the source images. Needs a host C++ compiler and Python with Pillow.

set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
build=${PROSPEROEDEN_LAUNCHER_BUILD:-"$HOME/.cache/prosperoeden-launcher"}
mkdir -p "$build" "$root/headless/prosperoeden/ui/fonts"

"${HOST_CXX:-c++}" -std=c++20 -O2 -w -I"$root/tools/launcher" -I"$root/headless/prosperoeden" \
    "$root/tools/launcher/bake_font.cpp" -o "$build/bake_font"
"$build/bake_font" "$root/third_party/fonts/Montserrat-Medium.ttf" \
    "$root/headless/prosperoeden/ui/fonts/montserrat-medium.pefont"
# The CJK subset shipped with the app, cut from Noto Sans CJK SC Regular (OFL,
# third_party/fonts/NotoSansCJKsc-Regular.otf, from https://github.com/notofonts/noto-cjk):
# rebuilt here whenever the source or a CJK catalog changes (needs fonttools).
# Without the source the committed subset stays as it is.
if [[ -f "$root/third_party/fonts/NotoSansCJKsc-Regular.otf" ]]; then
    python3 "$root/tools/launcher/strings.py" subset
elif [[ ! -f "$root/headless/prosperoeden/ui/fonts/noto-sans-cjk-subset.ttf" ]]; then
    echo "missing Noto Sans CJK source and no committed subset" >&2
    exit 1
fi
python3 "$root/tools/launcher/render-art.py"
