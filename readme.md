Introduction
============

fdb is a file database / program launcher similar to Apple's spotlight. It 
features a live index of all files in a set of directories and allows searching 
those files in a fast and uncomplicated manner.
It uses the inotify feature of recent Linux kernels and is thus only available 
for operating systems implementing inotify (though it _could_ be adapted to, 
say, dnotify, with some shortcomings).
The menu is displayed using the `dmenu` utility from http://suckless.org and 
the notificitations (should a program not be found or the output captured) need 
notify-send (though adapting for `dzen` or
similar should be trivial).

Overview
========

fdb consists of two scripts which need `notify-send` (they can do without
but with it's nicer) and `inotifywait` (which on gentoo is in the ebuild
sys-fs/inotify-tools). Also they need `dmenu`.

The first, `mimehandler`, is a simple script which checks the mime-type of
a file and opens an appropriate application. It can also handle magnet
links and http URLs, but that is just a bonus for using it as a browser
for the `xdg-open` script.

The second script, `fdb.sh`, is where the magic happens. The script has
three modes of operation:

* rebuilddb: this one simply rebuilds the file database
* update   : this one runs as a daemon, watching the specified
    directories for new and removed files, updating the database as
    needed
* command  : this one launches `dmenu`, piping in the file database and
    the command cache. It then launches either the mimehandler with
    the specified file or the commandline entered.

Setup
=====

The `fdb.sh` script uses four files:

`~/.config/fdb/directories` contains a list of directories to watch. Mine
looks like this:

    /home/gregor
    /mnt
    /media

`~/.config/fdb/blacklist` contains a list of grep regular expressions for
pathes not to watch. Mine looks like this:

    \.adobe
    \..*swp
    \.cache/chromium
    \.cache/vlc
    \.ccache
    \.config/chromium/.*Cache.*
    \.dbus
    \.git/
    \.git$
    \.macromedia
    \.mc
    \.subversion
    \.svn

`~/.cache/fdb/files` contains a list of files in the watched directories
`~/.cache/fdb/commands` contains a list of commands entered.

fdb supports a `~/.dmenurc`, which is a short snipped of shellscript
that sets the DMENU variable. The variable contains the `dmenu` command
to run. Mine looks like this:

    DMENU='dmenu -b '                                      # bottom
    DMENU=$DMENU'-xs '                                     # xmms matching
    DMENU=$DMENU'-i '                                      # case insensitive
    DMENU=$DMENU'-o 0.9 '                                  # opacity
    DMENU=$DMENU'-nb #333333 -nf #999999 '                 # not selected colors
    DMENU=$DMENU'-sb #1279bf -sf #ffffff '                 # selected colors
    DMENU=$DMENU'-fn -*-terminus-*-*-*-*-12-*-*-*-*-*-*-*' # font

where `-xs`, `-i` and `-o` might need additional patching (`-xs` and `-i` are
available from the `dmenu` repo, `-o` is a patch i have in my local tree. If
anyone wants that, drop me a line (the patch is kind of a mess at the
moment so I'd rather not put it out there for any unsuspecting soul to
stumble upon)).

Usage
=====

Usually, the `fdb.sh` script is started like this to enter monitor mode:

    fdb.sh update &

I do that in my `~/.xinitrc`. Then one simply needs to run

    fdb.sh

to pop up the `dmenu` with files and commands. At first the command list
will be empty, but simply entering the commandline will lead to the
command being run and cached in the command cache. That allows creating
a cache of often used commands for convenience. I have that command
bound to Caps + Enter by the way.

The script also supports a verbose mode which uses `notify-send` to
capture the command output and display it in a notification. For example
one might run

    fdb.sh -v

to start the verbose mode and then enter

    cal -3

to have a notification show a three months calendar.
