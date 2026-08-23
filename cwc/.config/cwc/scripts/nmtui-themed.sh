#!/usr/bin/env bash
# nmtui wrapper: pick a newt color palette that matches the desktop theme.
#
# nmtui (newt/slang) ignores the terminal palette for its widget colors and
# reads $NEWT_COLORS ONCE at startup — it cannot be retheme'd live. So the
# palette is chosen here, at launch, from the high-contrast state file (same
# contract as high-contrast.sh). An nmtui that is already open keeps its old
# colors; close and reopen it after a toggle.
#
# Color names resolve through the terminal's ANSI palette (kitty dark.conf /
# highcontrast.conf); "default" is the terminal's default fg/bg, which the
# kitty half of the toggle already controls.
#
# Entry points: the MOD+C command menu (rofi/commands.sh) and the
# ~/.local/bin/nmtui symlink that shadows /usr/bin/nmtui for shell use.

if [ -f "$HOME/.cache/high-contrast-mode" ]; then
    # sunlight: black on paper-white. lightgray (#888888 in highcontrast.conf)
    # marks inputs and the selected row — black-on-gray stays readable outdoors.
    NEWT_COLORS='
        root=black,default
        roottext=black,default
        window=default,default
        border=black,default
        shadow=,lightgray
        title=black,default
        label=default,default
        checkbox=default,default
        actcheckbox=black,lightgray
        entry=black,lightgray
        disentry=gray,default
        button=default,default
        actbutton=black,lightgray
        compactbutton=default,default
        listbox=default,default
        actlistbox=black,lightgray
        sellistbox=black,lightgray
        actsellistbox=black,lightgray
        textbox=default,default
        acttextbox=black,lightgray
        helpline=black,default
        emptyscale=,lightgray
        fullscale=,black
    '
else
    # glitchcore: teal-on-void base, cyan marks the active element,
    # classification red marks the focused button.
    NEWT_COLORS='
        root=green,default
        roottext=green,default
        window=green,default
        border=green,default
        shadow=,black
        title=cyan,default
        label=green,default
        checkbox=green,default
        actcheckbox=black,cyan
        entry=white,gray
        disentry=gray,default
        button=black,green
        actbutton=black,red
        compactbutton=green,default
        listbox=green,default
        actlistbox=black,cyan
        sellistbox=black,green
        actsellistbox=black,cyan
        textbox=green,default
        acttextbox=black,cyan
        helpline=cyan,default
        emptyscale=,gray
        fullscale=,cyan
    '
fi

export NEWT_COLORS
# absolute path: ~/.local/bin/nmtui links here, so a plain `exec nmtui` would recurse
exec /usr/bin/nmtui "$@"
