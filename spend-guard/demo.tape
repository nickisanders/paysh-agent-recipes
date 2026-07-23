# demo.tape — reproducible terminal GIF for Spend Guard.
#
# Render it:  brew install vhs && cd spend-guard && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay, nothing spent.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 16
Set Width 1120
Set Height 424
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# Give your agent a spending limit. It stops at the cap:"
Enter
Sleep 900ms
Type "./example.sh"
Enter
Sleep 5s
Sleep 1s
