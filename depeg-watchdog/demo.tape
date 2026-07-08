# demo.tape — reproducible terminal GIF for Depeg Watchdog.
#
# Render it:  brew install vhs && cd depeg-watchdog && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay balance, no network, no secrets.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 18
Set Width 1440
Set Height 236
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# Watch stablecoins. Only hear about the ones that break peg:"
Enter
Sleep 1000ms
Type "DRY_RUN=1 ./depeg-watchdog.sh 2>&1 | grep -E 'within band|^ALERT: ' | sed 's/^\[depeg-watchdog\] //;s/^ALERT: //'"
Enter
Sleep 3800ms
Sleep 1s
