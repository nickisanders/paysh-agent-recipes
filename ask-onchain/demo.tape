# demo.tape — reproducible terminal GIF for Ask Onchain.
#
# Render it:  brew install vhs && cd ask-onchain && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay balance, no network, no secrets.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 16
Set Width 1240
Set Height 322
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# Ask anything. It picks the tool, pays for it, answers:"
Enter
Sleep 1000ms
Type "DRY_RUN=1 ./ask-onchain.sh 'is 0x1111 a safe token?' 2>/dev/null"
Enter
Sleep 3200ms

Type "DRY_RUN=1 ./ask-onchain.sh 'what is the price of SOL?' 2>/dev/null"
Enter
Sleep 3200ms
Sleep 1s
