#!/bin/bash

# dmenu defaults
if [ -f ~/.dmenurc ]; then
    source ~/.dmenurc
else
    DMENU="dmenu"
fi

# settings and cache files {{{
cache_file="$XDG_CACHE_HOME"
[ "x$XDG_CACHE_HOME" = "x" ] && cache_file="${HOME}/.cache"
cache_file="${cache_file}/fdb/files"
if [ ! -d $(dirname "$cache_file") ]; then
    mkdir -p $(dirname "$cache_file")
fi
touch "$cache_file"

cache_cmds="$XDG_CACHE_HOME"
[ "x$XDG_CACHE_HOME" = "x" ] && cache_cmds="${HOME}/.cache"
cache_cmds="${cache_cmds}/fdb/commands"
if [ ! -d $(dirname "$cache_cmds") ]; then
    mkdir -p $(dirname "$cache_cmds")
fi
touch "$cache_cmds"

blacklist="$XDG_CONFIG_HOME"
[ "x$XDG_CONFIG_HOME" = "x" ] && blacklist="${HOME}/.config"
blacklist="${blacklist}/fdb/blacklist"
if [ ! -d $(dirname $blacklist) ]; then
    mkdir -p $(dirname $blacklist)
fi
touch "$blacklist"

directories="$XDG_CONFIG_HOME"
[ "x$XDG_CONFIG_HOME" = "x" ] && directories="${HOME}/.config"
directories="${directories}/fdb/directories"
if [ ! -d $(dirname $directories) ]; then
    mkdir -p $(dirname $directories)
fi
touch "$directories"
# }}}

rebuilddb() {
    local t=`mktemp`
    while read d; do
        nice -n 20 ionice -c 3 find "$d" | grep -vf "$blacklist" >> "$t" 2> /dev/null
    done < "$directories"
    mv "$t" "$cache_file"
}

verbose="false"
if [ "$1" == "-v" ]; then
    verbose="true"
elif [ "$1" == "rebuild" ]; then
    rebuilddb
    exit 0
elif [ "$1" == "update" ]; then # {{{
    # recreate db (in case something changed while we were not watching)
    rebuilddb

    deleted=0

    inotifywait -r -m -e move -e create -e delete -e modify --format "%w%f,%:e" --fromfile "$directories" | while read l; do
        path=`echo $l | cut -d',' -f1`
        event=`echo $l | cut -d',' -f2`
        
        case $event in
            *CREATE*|*MOVED_TO*)
                # no need adding to the cache if it's already in there
                grep -qF "$path" "$cache_file" 2> /dev/null && continue
                # and also no need if it's on the blacklist or if the cache file changed (that'd cause
                # an infinite loop of changing the cache file over and over)
                echo "$path" | grep -qf "$blacklist" -e "$cache_file" 2> /dev/null && continue

                deleted=0

                # if a new directory appeared, list all of its contents (this mostly applies to moved directories)
                if [ -d "$path" ]; then
                    sleep 2 # maybe something got mounted there by pmount or some other kind of mount script
                    find "$path" >> "$cache_file" 2> /dev/null
                else
                    echo "$path" >> "$cache_file"
                fi
                ;;
            *DELETE*|*MOVED_FROM*)
                echo "$path" | grep -qf "$blacklist" -e "$cache_file" 2>/dev/null && continue

                deleted=`expr $deleted + 1`
                if [ $deleted -gt 10 ]; then
                    echo "mass delete detected. sleeping for 10 seconds and rebuilding the database"
                    sleep 10
                    break
                fi
                tmp=`mktemp`
                grep -vF "$path" "$cache_file" > "$tmp"
                mv "$tmp" "$cache_file"
                ;;
            *MODIFY*)
                if [ "$path" == "$blacklist" ]; then
                    echo "blacklist changed, rebuilding database"
                    rebuilddb
                elif [ "$path" == "$directories" ]; then
                    echo "watchlist changed, reloading"
                    break
                fi
                ;;
        esac

        rm -rf "$t"
    done
    exec $0 update
    # }}}
fi

obj=`(sed -e 's/^/run /' < "$cache_cmds"; sed -e 's/^/open /' < "$cache_file") | $DMENU -l 7 -p '?'`
[[ "" == "$obj" ]] && exit 0
action=`echo "$obj" | cut -d' ' -f1`
case "$action" in
    open)
        exec mimehandler "`echo $obj | cut -d' ' -f2-`"
        ;;
    *)
        # cache command and run it {{{
        if [ "$action" == "run" ]; then
            obj=`echo $obj | cut -d' ' -f2-`
        fi
        hash `echo $obj | cut -d' ' -f1` 2>/dev/null
        if [ $? == 1 ]; then
            notify-send "not found: \"$obj\""
            exit 0
        fi
        echo "$obj" >> "$cache_cmds"
        sort "$cache_cmds" | uniq > "$cache_cmds.$$"
        mv "$cache_cmds.$$" "$cache_cmds"
        [ "$verbose" == "false" ] && exec $obj
        output=`$obj | sed -e 's|<|\&lt;|g' -e 's|>|\&gt;|g'`
        [ "$output" != "" ] && notify-send -- "$output"
        # }}}
        ;;
esac
