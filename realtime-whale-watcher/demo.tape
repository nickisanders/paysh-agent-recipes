# demo.tape — reproducible terminal GIF for the Realtime Whale Watcher.
#
# Render it:  brew install vhs && cd realtime-whale-watcher && vhs demo.tape
# Produces:   demo.gif  (embedded at the top of this recipe's README)
#
# VHS renders the exact same GIF every time, so re-run it whenever the recipe
# output changes. Runs in DRY_RUN — no pay balance, no Telegram, no secrets.

Output demo.gif
Output demo.mp4

Require bash
Require jq

Set Shell bash
Set FontSize 18
Set Width 1280
Set Height 400
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 50ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# One script, any chain. Watch a wallet for whale-sized moves."
Enter
Sleep 1200ms

Type "DRY_RUN=1 NETWORK=ethereum ./realtime-whale.sh 2>/dev/null | sed -n 's/^ALERT: //p'"
Enter
Sleep 3s

Type "DRY_RUN=1 NETWORK=solana ./realtime-whale.sh 2>/dev/null | sed -n 's/^ALERT: //p'"
Enter
Sleep 3s

Type "# Agents get the same events as JSON, tagged by network:"
Enter
Sleep 1200ms
Type "DRY_RUN=1 NETWORK=solana ./realtime-whale.sh 2>/dev/null | sed -n 's/^PAYLOAD: //p' | jq -c '{network,dir:.direction,value,symbol}'"
Enter
Sleep 4s
Sleep 1s
