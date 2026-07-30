# demo.tape — reproducible terminal GIF for NFT Floor Watcher.
#
# Render it:  brew install vhs && cd nft-floor-watcher && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay, nothing spent.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 16
Set Width 1200
Set Height 360
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# Ping me when the floor dips below my buy line:"
Enter
Sleep 900ms
Type "./example.sh"
Enter
Sleep 4s
Sleep 1s