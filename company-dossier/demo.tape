# demo.tape — reproducible terminal GIF for Company Dossier.
#
# Render it:  brew install vhs && cd company-dossier && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay balance, no network, no secrets.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 16
Set Width 1400
Set Height 322
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# One domain in. A one-page company brief out:"
Enter
Sleep 1000ms
Type "DRY_RUN=1 ./company-dossier.sh 2>/dev/null"
Enter
Sleep 4200ms
Sleep 1s
