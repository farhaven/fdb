#!/bin/bash

# dmenu defaults
if [ -f ~/.dmenurc ]; then
    source ~/.dmenurc
else
    DMENU="dmenu"
fi

# settings and cache files {{{
xdg_dir(){ # {{{
    local store=$1
    local name=$2
    local path=

    case "$store" in
        cache)
            if [ -z $XDG_CACHE_HOME ]; then
                path="$HOME/.cache/$name"
            else
                path="$XDG_CACHE_HOME/$name"
            fi
        ;;
        config)
            if [ -z $XDG_CONFIG_HOME ]; then
                path="$HOME/.config/$name"
            else
                path="$XDG_CONFIG_HOME/$name"
            fi
        ;;
    esac

    mkdir -p `dirname "$path"`
    touch "$path"
    echo "$path"
    return 0
} # }}}

cache_file=`xdg_dir cache fdb/files`
cache_cmds=`xdg_dir cache fdb/commands`

blacklist=`xdg_dir config fdb/blacklist`
directories=`xdg_dir config fdb/directories`

db_rebuild_lock=`xdg_dir cache fdb/db_rebuild`
rm "$db_rebuild_lock"
# }}}

verb_sleep() { # {{{
    local t=$1
    while [ $t -gt 0 ]; do
        sleep 1
        echo -n "."
        t=`expr $t - 1`
    done
    echo
} # }}}

db_waitlock(){ # {{{
    if [ -e "$db_rebuild_lock" ]; then
        echo "database rebuild is in progress... waiting "
        while [ -e "$db_rebuild_lock" ]; do
            echo -n "."
            sleep 1
        done
        echo
    fi
} # }}}

rebuilddb() { # {{{
    echo -n "rebuilding database... "
    db_waitlock
    touch "$db_rebuild_lock"
    local t=`mktemp`
    while read d; do
        nice -n 20 ionice -c 3 find "$d" 2>/dev/null | grep -vf "$blacklist" >> "$t"
    done < "$directories"
    mv "$t" "$cache_file"
    rm "$db_rebuild_lock"
    echo "done"
} # }}}

verbose="false"
if [ "$1" == "-v" ]; then
    verbose="true"
elif [ "$1" == "rebuild" ]; then
    rebuilddb
    exit 0
elif [ "$1" == "update" ]; then # {{{
    # recreate db (in case something changed while we were not watching)
    rebuilddb &

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
                echo "$path" | grep -qf "$blacklist" -e "$cache_file" -e "$db_rebuild_lock" 2> /dev/null && continue

                deleted=0

                echo "adding $path to file cache"
                db_waitlock
                # if a new directory appeared, list all of its contents (this mostly applies to moved directories)
                if [ -d "$path" ]; then
                    sleep 2 # maybe something got mounted there by pmount or some other kind of mount script
                    find "$path" >> "$cache_file" 2> /dev/null
                else
                    echo "$path" >> "$cache_file"
                fi
                ;;
            *DELETE*|*MOVED_FROM*)
                echo "$path" | grep -qf "$blacklist" -e "$cache_file" -e "$db_rebuild_lock" 2>/dev/null && continue

                db_waitlock
                deleted=`expr $deleted + 1`
                if [ $deleted -gt 10 ]; then
                    echo "mass delete detected. sleeping for at least 10 seconds and rebuilding the database"
                    verb_sleep 10
                    db_waitlock
                    break
                fi

                echo "deleting $path from file cache"
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

obj=`(sed -e 's/^/run /' < "$cache_cmds"; sed -e 's/^/open /' < "$cache_file") | $DMENU -l 7`
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
