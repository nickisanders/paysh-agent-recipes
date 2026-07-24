# demo.tape — reproducible terminal GIF for Rate Limiter.
#
# Render it:  brew install vhs && cd rate-limiter && vhs demo.tape
# Produces:   demo.gif + demo.mp4  (embedded at the top of this recipe's README)
#
# Runs in DRY_RUN — no pay, nothing spent.

Output demo.gif
Output demo.mp4

Require bash

Set Shell bash
Set FontSize 16
Set Width 1160
Set Height 372
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "clear"
Enter
Show

Sleep 700ms
Type "# 3 calls per minute, then the breaker trips:"
Enter
Sleep 900ms
Type "./example.sh"
Enter
Sleep 5s
Sleep 1s
