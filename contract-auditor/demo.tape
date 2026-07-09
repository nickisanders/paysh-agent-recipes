# demo.tape — reproducible terminal GIF for Contract Auditor.
#
# Render it:  brew install vhs && cd contract-auditor && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay balance, no network, no secrets.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 16
Set Width 1400
Set Height 340
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# The raw findings are flag soup:"
Enter
Sleep 900ms
Type "DRY_RUN=1 SUMMARIZE=0 ./contract-auditor.sh 2>/dev/null"
Enter
Sleep 2800ms

Type "# Same audit, in plain English (pay claude):"
Enter
Sleep 900ms
Type "DRY_RUN=1 ./contract-auditor.sh 2>/dev/null"
Enter
Sleep 4200ms
Sleep 1s
