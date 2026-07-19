# demo.tape — reproducible terminal GIF for Lead Enricher.
#
# Render it:  brew install vhs && cd lead-enricher && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay balance, no network, no secrets.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 14
Set Width 1360
Set Height 300
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# A CSV of emails goes in:"
Enter
Sleep 900ms
Type "column -t -s, example-leads.csv"
Enter
Sleep 2400ms

Type "# ...a full lead list comes out:"
Enter
Sleep 900ms
Type "DRY_RUN=1 ./lead-enricher.sh 2>/dev/null | column -t -s,"
Enter
Sleep 3200ms
Sleep 1s
