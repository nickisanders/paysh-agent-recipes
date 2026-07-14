# demo.tape — reproducible terminal GIF for Web Extractor.
#
# Render it:  brew install vhs && cd web-extractor && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay balance, no network, no secrets.

Output demo.gif
Output demo.mp4

Require bash
Require jq

Set Shell bash
Set FontSize 18
Set Width 1200
Set Height 340
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# Name the fields you want from any page. Get typed JSON back:"
Enter
Sleep 1000ms
Type "DRY_RUN=1 FIELDS=name,price,in_stock,rating ./web-extractor.sh 2>/dev/null"
Enter
Sleep 3200ms

Type "# It's real JSON, so in_stock is a boolean, not a string:"
Enter
Sleep 1000ms
Type "DRY_RUN=1 ./web-extractor.sh 2>/dev/null | jq '.in_stock'"
Enter
Sleep 3000ms
Sleep 1s
