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
cache_cmds=`xdg_dir config fdb/commands`

blacklist=`xdg_dir config fdb/blacklist`
directories=`xdg_dir config fdb/directories`
blacklist_md5=`md5sum "$blacklist" | cut -d' ' -f1`
directories_md5=`md5sum "$directories" | cut -d' ' -f1`

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

adddir() { # {{{
    local t1=$1
    local t2=$2
    shift 2
    local d="$@"

    find "$d" -maxdepth 1 -mindepth 1 -type f >> "$t"
    find "$d" -maxdepth 1 -mindepth 1 -type d | while read line; do
        echo "$line" | grep -qf "$t2" || echo "$line" | grep -qf "$blacklist"

        if [[ $? -ne 0 ]]; then
            echo "$d" >> "$t"
            adddir "$t1" "$t2" "$line"
        fi
    done
}
# }}}

rebuilddb() { # {{{
    echo -n "rebuilding database... "
    db_waitlock
    touch "$db_rebuild_lock"
    local t=`mktemp`
    local t2=`mktemp`
    sed -ne '/^@/s/@//p' < "$directories" > "$t2"

    grep -v "^@" "$directories" | while read d; do
        adddir "$t1" "$t2" "$d"
    done

    mv "$t" "$cache_file"
    rm "$db_rebuild_lock"
    rm "$t2"
    echo "done"
} # }}}

verbose="false"
if [ "$1" == "-v" ]; then
    verbose="true"
elif [ "$1" == "rebuild" ]; then
    rebuilddb
    exit 0
elif [ "$1" == "update" ]; then # {{{
    renice -n 20 $$
    # recreate db (in case something changed while we were not watching)
    rebuilddb &

    deleted=0

    (inotifywait -r -m -e move -e create -e delete --format "%w%f,%:e" --fromfile "$directories" &
     inotifywait -m -e attrib --format "%w%f,%:e" "$blacklist" "$directories" "`which $0`") | while read l; do
        path=`echo $l | cut -d',' -f1`
        event=`echo $l | cut -d',' -f2`
        
        case $event in
            *CREATE*|*MOVED_TO*)
                # no need adding to the cache if it's already in there
                grep -qF "$path" "$cache_file" 2> /dev/null && continue
                # and also no need if it's on the blacklist or if the cache file changed (that'd cause
                # an infinite loop of changing the cache file over and over)
                echo "$path" | grep -qf "$blacklist" -e "$cache_file" -e "$db_rebuild_lock" 2> /dev/null && continue

                deleted=`expr $deleted - 2`
                [ $deleted -lt 0 ] && deleted=0

                echo "adding \"$path\" to file cache"
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
                if [ $deleted -gt 1000 ]; then
                    echo "Mass delete detected. Sleeping for at least 10 seconds and rebuilding the database"
                    verb_sleep 10
                    db_waitlock
                    break
                fi

                echo "Deleting \"$path\" from file cache"
                tmp=`mktemp`
                grep -vF "$path" "$cache_file" > "$tmp"
                mv "$tmp" "$cache_file"
                ;;
            *ATTRIB*)
                if [ "$path" == "$blacklist" ]; then
                    md5=`md5sum "$blacklist" | cut -d' ' -f1`
                    if [ "$blacklist_md5" != "$md5" ]; then
                        echo "blacklist changed, rebuilding database"
                        blacklist_md5=`md5sum "$blacklist" | cut -d' ' -f1`
                        rebuilddb
                    fi
                elif [ "$path" == "$directories" ]; then
                    md5=`md5sum "$directories" | cut -d' ' -f1`
                    if [ "$directories_md5" != "$md5" ]; then
                        echo "watchlist changed, reloading"
                        break
                    fi
                elif [ "$path" == "`which $0`" ]; then
                    md5=`md5sum "$path" | cut -d' ' -f1`
                    if [ "$self_md5" != "$md5" ]; then
                        echo "$path changed... reloading"
                        break
                    fi
                fi
                ;;
        esac

        rm -rf "$t"
    done
    db_waitlock
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

        grep -Fvxe "$obj" "$cache_cmds" > "$cache_cmds.$$"
        (echo "$obj"; cat "$cache_cmds.$$") > "$cache_cmds"

        [ "$verbose" == "false" ] && exec sh -c "$obj"
        output=`$obj | sed -e 's|<|\&lt;|g' -e 's|>|\&gt;|g'`
        [ "$output" != "" ] && notify-send -- "$output"
        # }}}
        ;;
esac
