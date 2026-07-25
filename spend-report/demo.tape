# demo.tape — reproducible terminal GIF for Spend Report.
#
# Render it:  brew install vhs && cd spend-report && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay, nothing spent.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 16
Set Width 1320
Set Height 448
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# What did my agents actually spend?"
Enter
Sleep 900ms
Type "DRY_RUN=1 ./spend-report.sh"
Enter
Sleep 4s
Sleep 1s