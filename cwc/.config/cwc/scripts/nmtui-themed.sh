#!/usr/bin/env bash

if [ -f "$HOME/.cache/high-contrast-mode" ]; then
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
exec /usr/bin/nmtui "$@"
