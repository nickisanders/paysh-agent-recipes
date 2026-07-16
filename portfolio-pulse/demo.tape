# demo.tape — reproducible terminal GIF for Portfolio Pulse.
#
# Render it:  brew install vhs && cd portfolio-pulse && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay balance, no network, no secrets.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 18
Set Width 1080
Set Height 300
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# One snapshot a day of where your bags stand:"
Enter
Sleep 1000ms
Type "DRY_RUN=1 ./portfolio-pulse.sh 2>/dev/null"
Enter
Sleep 4000ms
Sleep 1s
