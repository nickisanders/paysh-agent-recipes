# demo.tape — reproducible terminal GIF for Page Watch.
#
# Render it:  brew install vhs && cd page-watch && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay balance, no network, no secrets.

Output demo.gif
Output demo.mp4

Require bash
Require jq

Set Shell bash
Set FontSize 18
Set Width 1400
Set Height 250
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 50ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# Watch any web page. Know the moment it changes."
Enter
Sleep 1200ms

Type "DRY_RUN=1 ./page-watch.sh 2>/dev/null | sed -n 's/^ALERT: //p'"
Enter
Sleep 3s

Type "# Add SUMMARIZE=1 and pay claude explains the change in plain English:"
Enter
Sleep 1200ms
Type "DRY_RUN=1 SUMMARIZE=1 ./page-watch.sh 2>/dev/null | sed -n 's/^ALERT: //p'"
Enter
Sleep 4s
Sleep 1s
