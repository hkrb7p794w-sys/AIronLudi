#!/bin/bash
# Erzeugt docs/roast/screenshots.md aus den Bildern.
cd docs/roast
{
echo "# Screenshots aus dem Prüfstand"
echo
echo "Erzeugt mit \`flutter test --tags screenshots --dart-define=SCREENSHOTS=true --update-goldens test/screenshots\`"
echo "(Demo-Daten: \`test/screenshots/demo_data.dart\`, Schrift Inter). Layoutfehler: [screenshots/layoutfehler.md](screenshots/layoutfehler.md)."
echo
echo "Geräte: **iPhone 15** (393 × 852 pt, Faktor 3) und **Android klein** (360 × 640 dp, Faktor 2); je *hell*, *dunkel*, *große Schrift* (1,3)."
echo "Langbilder (\`-lang\`) zeigen die ganze Seite (iPhone, hell)."
echo
for name in $(ls screenshots/iphone15/hell/*.png | xargs -n1 basename | sed 's/-lang\.png$/.png/' | sort -u | sed 's/\.png$//'); do
  echo "## $name"
  echo
  echo "| iPhone hell | iPhone dunkel | iPhone große Schrift | Android hell | Android dunkel | Android große Schrift |"
  echo "|---|---|---|---|---|---|"
  row="|"
  for d in iphone15 android-klein; do for l in hell dunkel grossschrift; do
    f="screenshots/$d/$l/$name.png"
    if [ -f "$f" ]; then row="$row <img src=\"$f\" width=\"140\"> |"; else row="$row – |"; fi
  done; done
  echo "$row"
  if [ -f "screenshots/iphone15/hell/$name-lang.png" ]; then echo; echo "Ganze Seite: <img src=\"screenshots/iphone15/hell/$name-lang.png\" width=\"220\">"; fi
  echo
done
} > screenshots.md
