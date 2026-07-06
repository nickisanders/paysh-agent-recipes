# demo.tape — reproducible terminal GIF for Morning Brief.
#
# Render it:  brew install vhs && cd morning-brief && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay balance, no network, no secrets.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 16
Set Width 1120
Set Height 470
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# One paid web search per topic, assembled into a cited brief, emailed daily:"
Enter
Sleep 1000ms
Type "DRY_RUN=1 ./morning-brief.sh 2>/dev/null"
Enter
Sleep 4500ms
Sleep 1s
