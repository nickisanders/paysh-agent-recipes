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
Set Height 290
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# Watch any web page. Get a plain-English summary of what changed:"
Enter
Sleep 1000ms
Type "DRY_RUN=1 SUMMARIZE=1 ./page-watch.sh 2>/dev/null | sed -n 's/^ALERT: //p'"
Enter
Sleep 3500ms

Type "# Only alert on changes you care about. Nothing about layoffs? Silence:"
Enter
Sleep 1000ms
Type "DRY_RUN=1 ALERT_IF=layoffs ./page-watch.sh 2>&1 | grep quiet"
Enter
Sleep 2500ms

Type "# But a price change pings you:"
Enter
Sleep 1000ms
Type "DRY_RUN=1 ALERT_IF='[$]' ./page-watch.sh 2>/dev/null | sed -n 's/^ALERT: //p'"
Enter
Sleep 3500ms
Sleep 1s
