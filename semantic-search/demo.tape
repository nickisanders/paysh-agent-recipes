# demo.tape — reproducible terminal GIF for Semantic Search.
#
# Render it:  brew install vhs && cd semantic-search && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay, nothing spent.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 16
Set Width 1280
Set Height 236
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# find the answer by meaning, not keywords:"
Enter
Sleep 900ms
Type "DRY_RUN=1 ./semantic-search.sh"
Enter
Sleep 4s
Sleep 1s