# demo.tape — reproducible terminal GIF for Gas Ticker.
#
# Render it:  brew install vhs && cd gas-ticker && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay balance, no network, no secrets.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 18
Set Width 1240
Set Height 230
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# Ping me when gas drops below 20 gwei:"
Enter
Sleep 900ms
Type "DRY_RUN=1 GWEI_THRESHOLD=20 ./gas-ticker.sh 2>/dev/null | sed -n 's/^ALERT: //p'"
Enter
Sleep 2800ms

Type "# Want it cheaper? Set a tighter target and it just waits:"
Enter
Sleep 900ms
Type "DRY_RUN=1 GWEI_THRESHOLD=10 ./gas-ticker.sh 2>&1 | grep -i quiet | sed 's/^.gas-ticker. //'"
Enter
Sleep 2800ms
Sleep 1s
