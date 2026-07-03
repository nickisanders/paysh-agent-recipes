# demo.tape — reproducible terminal GIF for the Realtime Whale Watcher.
#
# Render it:  brew install vhs && cd realtime-whale-watcher && vhs demo.tape
# Produces:   demo.gif  (embedded at the top of this recipe's README)
#
# VHS renders the exact same GIF every time, so re-run it whenever the recipe
# output changes. Runs in DRY_RUN — no pay balance, no Telegram, no secrets.

Output demo.gif

Require bash
Require jq

Set Shell bash
Set FontSize 18
Set Width 1200
Set Height 720
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 55ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# Realtime Whale Watcher: alert the instant a big wallet move lands"
Enter
Sleep 1200ms

Type "./example.sh 2>/dev/null"
Enter
Sleep 4s

Type "# Same events as machine-readable JSON your agent can consume:"
Enter
Sleep 1200ms

Type "DRY_RUN=1 ./realtime-whale.sh 2>/dev/null | sed -n 's/^PAYLOAD: //p' | jq -c '{dir:.direction,value,symbol}'"
Enter
Sleep 4s
Sleep 1s
