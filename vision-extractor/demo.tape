# demo.tape — reproducible terminal GIF for Vision Extractor.
#
# Render it:  brew install vhs && cd vision-extractor && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay, nothing spent.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 16
Set Width 1120
Set Height 404
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# photo of a receipt in, structured JSON out:"
Enter
Sleep 900ms
Type "DRY_RUN=1 ./vision-extractor.sh"
Enter
Sleep 4s
Sleep 1s