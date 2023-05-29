#!/usr/bin/env bash

##############################################################################
# Preferences
NSH_DEFAULT_CONFIG="# preferences
NSH_PROMPT_SEPARATOR='\xee\x82\xb0'
NSH_PROMPT_SHOW_TIME=1
NSH_PROMPT_PREFIX= # this could be a string, a variable, or even a function, e.g. date
NSH_BOTTOM_MARGIN=20%
NSH_DEFAULT_EDITOR=vim
NSH_ITEMS_TO_HIDE=.*,*.pyc
NSH_DO_NOT_SHOW_ELAPSED_TIME=vi,vim,htop,config,grep,git
NSH_TEXT_PREVIEW='bat --color=always --number'
NSH_IMAGE_PREVIEW=
NSH_REMEMBER_LOCATION=1
HISTSIZE=1000

# colors
NSH_COLOR_TOP=$'\e[30;48;5;248m'
NSH_COLOR_CUR=$'\e[7m'
NSH_COLOR_TXT=$'\e[37m'
NSH_COLOR_CMD=$'\e[32m'
NSH_COLOR_VAR=$'\e[36m'
NSH_COLOR_VAL=$'\e[33m'
NSH_COLOR_ERR=$'\e[31m'
NSH_COLOR_DIR=$'\e[94m'
NSH_COLOR_EXE=$'\e[32m'
NSH_COLOR_IMG=$'\e[95m'
NSH_COLOR_LNK=$'\e[96m'
NSH_COLOR_SC1=$'\e[37;47m'    # scrollbar foreground
NSH_COLOR_SC2=$'\e[48;5;240m' # scrollbar background
NSH_COLOR_SH1=$'\e[30;47m'    # shortcut color1
NSH_COLOR_SH2=$'\e[37;100m'   # shortcut color2
NSH_COLOR_DLG=$'\e[48;5;250;30m'
NSH_COLOR_BKG='48;5;239'

# menu
NSH_MENU_DEFAULT_CURSOR=$'\e[31;40m>'
NSH_MENU_DEFAULT_SEL_COLOR='32;40'

# aliases
alias ls='command ls --color=auto'
alias ll='ls -Al'
alias diff='command diff --color=always {} | less -RF'
"
eval "$NSH_DEFAULT_CONFIG"

# since alias doesn't work in the script, define a function with the same name
(return 0 2>/dev/null) || alias() {
    local l="$@"
    local n="${l%%=*}"
    local c="${l#*=}"
    [[ $c != *\{\}* ]] && c="$c {}"
    if [[ $c == \'* || $c == \" ]]; then
        [[ $c != *"${c:0:1}" ]] && echo "unmatched quote" >&2 && return 1
        c="${c:1:$((${#c}-2))}"
    fi
    #eval "$n() { $c \"\$@\"; }"
    eval "$n() { ${c/\{\}/\"\$@\"}; }"
}

GIT_COMMANDS=(clone init add mv restore rm checkout bisect diff grep log blame show status branch commit merge rebase reset switch tag fetch pull push)

# check compatibility
LS_COLOR_PARAM='--color'
ls $LS_COLOR_PARAM &>/dev/null || LS_COLOR_PARAM='-G'
LS_TIME_STYLE=
ls -l --time-style=long-iso &>/dev/null && LS_TIME_STYLE="--time-style=long-iso"
STAT_FSIZE_PARAM='--printf=%s'
stat "$STAT_FSIZE_PARAM" . &>/dev/null || STAT_FSIZE_PARAM='-f%z'
NSH_PROMPT=$'\e[31m>\e[33m>\e[32m>\e[0m'

##############################################################################
# utility functions
hide_cursor() {
    printf '\e[?25l'
}

show_cursor() {
    printf '\e[?25h'
}

get_terminal_size() {
    read -r LINES COLUMNS < <(stty size)
    max_lines=$((LINES-2))
}

# CAUTION: index starts at 1 not 0
move_cursor() {
    [[ $1 == -* ]] && printf '\e[%sH' "$(($(get_cursor_row)+$1))" || printf '\e[%sH' "$1"
}

save_cursor_pos() {
    printf '\e[7'
}

restore_cursor_pos() {
    printf '\e[8'
}

get_cursor_pos() {
    while true; do
        IFS=';' read -sdR -p $'\E[6n' ROW COL </dev/tty; ROW=${ROW#*[};
        [[ $ROW =~ ^[0-9]*$ ]] && return # sometimes ROW has weird values
    done
}

get_cursor_row() {
    IFS=';' read -sdR -p $'\E[6n' ROW COL </dev/tty; echo ${ROW#*[};
}

get_cursor_col() {
    IFS=';' read -sdR -p $'\E[6n' ROW COL </dev/tty; echo $COL;
}

get_timestamp() {
    if [[ "$OSTYPE" == darwin* ]]; then
        echo $(($(date -u +%s) * 1000))
    else
        echo $(($(date +%s%N) / 1000000))
    fi
}

enable_echo() {
    stty echo
}

disable_echo() {
    stty -echo
}

enable_line_wrapping() {
    printf '\e[?7h'
}

disable_line_wrapping() {
    printf '\e[?7l'
}

open_screen() {
    printf '\e[?1049h' # alternative screen buffer
    printf '\e[2J' # clear screen
    # set the scrolling area and move to (0, 0)
    printf '\e[%sr' "${1:-1;$LINES}"
}

close_screen() {
    printf '\e[2J' # clear the terminal
    printf '\e[;r' # reset the scroll region
    printf '\e[?1049l' # restore main screen buffer
}

strlen() {
    local nbyte nchar str oLang=$LANG oLcAll=$LC_ALL
    LANG=C LC_ALL=C
    nbyte=${#1}
    LANG=$oLang LC_ALL=$oLcAll
    nchar=${#1}
    echo $(((nbyte-nchar)/2+nchar))
}

strip_escape() {
    if [[ $# -eq 0 ]]; then
        while read line; do
            strip_escape "$line"
        done
    else
        sed 's/\x1b\[[0-9;]*[mK]//g' <<< "$@"
    fi
}

get_num_cpu() {
    (grep 'physical id' /proc/cpuinfo 2>/dev/null | wc -l 2>/dev/null) || echo 1
}

print_filename() {
    local n="$1"
    local d=
    if [[ $n == */* ]]; then
        d="${n%/*}/"
        d="${d/#$PWD\//}" && d="${d/#$HOME\//$tilde/}"
        d="$NSH_COLOR_DIR$d"
        n="${n##*/}"
    fi
    [[ -e "$1" ]] && d=$'\e[4m'"$d"
    echo -ne "$d$(put_file_color "$n")$n\e[0m"
}

nshcp() {
    local op='command cp' && [[ $1 == --mv ]] && shift && op='command mv'
    local dst= && for dst in "$@"; do :; done
    local overwrite_all=no
    local skip_all=no
    local cancel=no
    local idx=0
    local num_thread=$(($(get_num_cpu)*2))
    local pids=()
    set +m
    __worker() {
        local s="$1"
        local d="$2" && [[ -d "$d" ]] && d="$d/${s##*/}"
        if [[ -e "$d" ]]; then
            [[ -d "$d" ]] && return
            [[ $skip_all == yes ]] && return
            if [[ $overwrite_all == no ]]; then
                #$(command diff --brief "$s" "$d" &>/dev/null) && return
                local ssize=$(stat "$STAT_FSIZE_PARAM" "$s" 2>/dev/null)
                local dsize=$(stat "$STAT_FSIZE_PARAM" "$d" 2>/dev/null)
                local cmp= && $(command diff --brief "$s" "$d" &>/dev/null) && cmp=', same file'
                while true; do
                    dialog "$(print_filename "$d") already exists\n($(get_hsize $ssize) --> $(get_hsize $dsize)$cmp)" Overwrite Overwrite\ all Skip Skip\ all Rename Cancel
                    local ans=$?
                    case "$ans" in
                        0) ;;
                        1) overwrite_all=yes;;
                        #2) return;;
                        3) skip_all=yes && return;;
                        4)
                            dialog --input "New name: " "${d##*/}"
                            [[ -n $STRING ]] && d="${d%/*}/$STRING" || continue
                            ;;
                        5) cancel=yes; return;;
                        *)
                            dialog --notice "Skipped: $(print_filename "$d")"
                            [[ $opened == yes ]] && sleep 1
                            return
                            ;;
                    esac
                    [[ $ans != 4 || ! -e "$d" ]] && break
                    dialog "Sorry, $(print_filename "$d") also exists."
                done
            fi
        fi
        [[ -n "${pids[$idx]}" ]] && wait "${pids[$idx]}"
        $op "$s" "$d" &
        pids[$idx]="$!"
        ((idx++)) && [[ $idx -ge $num_thread ]] && idx=0
    }
    while [ $# -gt 1 ]; do
        [[ -z "$1" ]] && shift && continue
        [[ $opened == yes ]] && dialog --notice "${op#* }: $(print_filename "$1")" # --> $(print_filename "$dst")"
        if [[ -e "$1" ]]; then
            if [[ -d "$1" ]]; then
                local src="$(command cd "$1"; pwd -P)"
                local b="${src##*/}"
                local tmp="$dst/${1##*/}"
                if [[ -d "$tmp" && $op == *cp ]]; then
                    local i= && for i in {1..99999}; do
                        if [[ ! -d "${tmp}_($i)" ]]; then
                            tmp="$(strip_escape "$(print_filename "$tmp")")"
                            dialog "$tmp already exists.\nchanged name --> $tmp($i)"
                            [[ $opened == yes ]] && dialog --notice "${op#* }: $tmp"
                            eval "$op -r \"$1\" \"${tmp}($i)\""
                            break
                        fi
                    done
                elif [[ $op == *mv && ! -d "$dst/$b" ]]; then
                    eval "$op \"$1\" \"$dst\""
                else
                    if [[ -d "$dst" ]]; then
                        dst="$(command cd "$dst" &>/dev/null; pwd -P)"
                    else
                        mkdir -p "$dst"
                        b=
                    fi
                    mkdir -p "$dst/$b"
                    while read line; do
                        [[ $line == $src ]] && continue
                        local n="${line#$src/}"
                        if [[ -d "$line" ]]; then
                            mkdir -p "$dst/$b/$n"
                        else
                            __worker "$line" "$dst/$b/${n%/*}"
                            [[ $cancel == yes ]] && break
                        fi
                    done < <(find "$src" 2>/dev/null)
                    [[ $op == command\ mv && -e "$src" ]] && rm -rf "$src" &>/dev/null
                fi
            else
                __worker "$1" "$dst"
            fi
        else
            dialog "$1: No such file or directory"
        fi
        [[ $cancel == yes ]] && break
        shift
    done
    unset __worker
    wait "${pids[@]}"
    [[ $cancel == yes ]] && cancel=Cancelled. || cancel=Done.
    if [[ "$PWD" != "$(command cd "$dst"; echo "$PWD")" ]]; then
        dialog "$cancel\nJump to the destination ($(print_filename "$dst"))?" Yes No
        [[ $? == 0 ]] && command cd "$dst"
    else
        dialog "$cancel"
    fi
    set -m
}

nshmv() {
    nshcp --mv "$@"
}

get_key() {
    _key=
    local k
    local param=''
    while [ $# -gt 1 ]; do
        param="$param $1"
        shift
    done
    [[ "$get_key_eps" == 1 && "$param" == *-t\ 0\.* ]] && printf -v "${1:-_key}" "%s" "$_key" && return
    IFS= read -srn 1 $param _key 2>/dev/null
    __ret=$?
    if [[ $__ret -eq 0 && "$_key" == '' ]]; then
        _key=$'\n'
    elif [[ "$_key" == $'\e' ]]; then
        while IFS= read -sn 1 -t $get_key_eps k; do
            _key=$_key$k
            case $k in
                $'\e')
                    _key=$'\e'
                    break
                    ;;
                [a-zA-NP-Z~])
                    break
                    ;;
            esac
        done
    fi
    printf -v "${1:-_key}" "%s" "$_key"
    return $__ret
}

get_key_debug() {
    _key=
    local k
    local param=''
    while [ $# -gt 1 ]; do
        param="$param $1"
        shift
    done
    [[ "$get_key_eps" == 1 && "$param" == *-t\ 0\.* ]] && return
    IFS= read -srn 1 $param _key
    __ret=$?
    if [[ $__ret == 0 && "$_key" == '' ]]; then
        _key='\n'
    elif [[ "$_key" == $'\e' ]]; then
        _key='\e'
        while IFS= read -sn 1 -t $get_key_eps k; do
            _key="$_key$k"
            case $k in
                $'\e')
                    _key='\e'
                    break
                    ;;
                [a-zA-NP-Z~])
                    break
                    ;;
            esac
        done
    else
        echo -e $_key | hexdump | head -n 1 | awk '{print $2}' | sed 's/^0a/\\/'
        return
    fi
    echo "$_key"
    return $__ret
}

STRING=
read_string() {
    local highlight=0 && [[ $1 == --highlight ]] && highlight=1 && shift
    STRING="$1"
    local default="$STRING"
    local cursor=${#STRING}
    get_cursor_pos
    show_cursor
    while true; do
        local cx=$((cursor%COLUMNS))
        local cy=$((cursor/COLUMNS))
        hide_cursor
        move_cursor "$((ROW+cy));$COL"
        if [[ $cursor -lt ${#STRING} ]]; then
            echo "$STRING"
            move_cursor "$((ROW+cy));$COL"
        fi
        [[ $highlight -eq 0 ]] && echo -n "${STRING:0:$cursor}" || print_command "${STRING:0:$cursor}"
        show_cursor
        get_key KEY </dev/tty
        case $KEY in
        $'\e'|$'\04')
            STRING=
            break
            ;;
        $'\t')
            local pre="${STRING:0:$cursor}"
            local post="${STRING:$cursor}"
            STRING="$pre    $post"
            cursor=$((cursor+4))
            ;;
        $'\177'|$'\b') # backspace
            if [ $cursor -gt 0 ]; then
                local pre="${STRING:0:$cursor}"
                local post="${STRING:$cursor}"
                STRING="${pre%?}$post"
                move_cursor "$((ROW+cy));$COL"
                echo -n "$STRING "
                ((cursor--))
            fi
            ;;
        $'\e[3~') # del
            local pre="${STRING:0:$cursor}"
            local post="${STRING:$cursor}"
            STRING="$pre${post:1}"
            echo -n "$STRING "
            ;;
        $'\e[D')
            [[ $cursor -gt 0 ]] && ((cursor--))
            ;;
        $'\e[C')
            [[ $cursor -lt ${#STRING} ]] && ((cursor++))
            ;;
        $'\e[1~'|$'\e[H')
            cursor=0
            ;;
        $'\e[4~'|$'\e[F')
            cursor=${#STRING}
            ;;
        $'\n')
            cursor=-1
            [[ $highlight -ne 0 ]] && move_cursor "$((ROW+cy));$COL" && print_command "$STRING"
            break
            ;;
        [[:print:]])
            local pre="${STRING:0:$cursor}"
            local post="${STRING:$cursor}"
            STRING="$pre$KEY$post"
            ((cursor++))
            ;;
        esac
    done
}

get_common_string() {
    if [[ "$OSTYPE" == darwin* ]]; then
        local item0="$1"
        local len=${#item0}
        shift
        while [ $# -gt 0 ]; do
            local item1="$1"
            local n= && for ((n=0; n<$len; n++)); do
                if [[ ${item0:n:1} != ${item1:n:1} ]]; then
                    len=$n
                    break
                fi
            done
            shift
        done
        echo "${item0:0:$len}"
    else
        # this doesn't work on mac
        echo "$(printf "%s\n" "$@" | sed -e '$!{N;s/^\(.*\).*\n\1.*$/\1\n\1/;D;}')"
    fi
}

fuzzy_word() {
    local p= && [[ $1 == -n ]] && p='-n' && shift
    if [[ $1 == *\"* ]]; then
        local word="$1"
        local cur="${word%%\"*}"
        fuzzy_word -n "$cur"
        word="${word:$((${#cur}+1))}"
        cur="${word%%\"*}"
        echo -n "$cur"
        word="${word:$((${#cur}+1))}"
        fuzzy_word "$word"
    else
        if [[ $1 == *$ ]]; then
            echo $p "${1:-*}" | sed -e 's/[^.^~^/^*]/*&*/g' -e 's/\*\*/\*/g' -e 's/[\*]*\$[\*]*$//'
        else
            echo $p "${1:-*}" | sed -e 's/[^.^~^/^*]/*&*/g' -e 's/\*\*/\*/g'
        fi
    fi
}

put_file_color() {
    if [ -h "$1" ]; then
        printf "$NSH_COLOR_LNK"
    elif [ -d "$1" ]; then
        printf "$NSH_COLOR_DIR"
    elif [ -x "$1" ]; then
        printf "$NSH_COLOR_EXE"
    elif [[ $(is_image "$1") == YES ]]; then
        printf "$NSH_COLOR_IMG"
    else
        printf "$NSH_COLOR_TXT"
    fi
}

get_hsize() {
    if [ $1 -ge 1073741824 ]; then
        local t=$(($1*10/1073741824))
        echo "$((t/10)).$((t%10)) G"
    elif [ $1 -ge 1048576 ]; then
        local t=$(($1*10/1048576))
        echo "$((t/10)).$((t%10)) M"
    elif [ $1 -ge 1024 ]; then
        local t=$(($1*10/1024))
        echo "$((t/10)).$((t%10)) K"
    elif [ $1 -ge 0 ]; then
        echo "$1 b"
    fi
}

print_number() {
    local str="$(echo "${1%%\.*}" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta' 2>/dev/null)"
    [[ $1 == *\.* ]] && str+=".${1#*\.}"
    echo "$str"
}

is_image() {
    local n="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    [[ "${n%\"}" == *.jpg || "$n" == *.jpeg || "$n" == *.png || "$n" == *.gif || "$n" == *.bmp ]] && echo YES || echo NO
}

is_binary() {
    LC_MESSAGES=C grep -Hm1 '^' < "${1-$REPLY}" | grep -q '^Binary'
}

pipe_context() {
    local c='>>'
    [[ -t 0 ]] && c='->'
    [[ -t 1 ]] && c="${c%?}-"
    echo "$c"
}

menu() {
    disable_line_wrapping >&2
    hide_cursor >&2

    get_terminal_size </dev/tty
    local max_height=$((LINES-1))
    local min_height=${NSH_BOTTOM_MARGIN:-20%}
    local toprow=

    local cursor0="$NSH_MENU_DEFAULT_CURSOR"
    local items=()
    local cur=-1 cur_bak=0
    local popup=0
    local hscroll=-1
    local return_idx=0
    local sel_color="$NSH_MENU_DEFAULT_SEL_COLOR"
    local readparam=
    local header=
    local footer=
    local preview=
    local return_key=()
    local return_fn=()
    local search=off
    local items_bak=()
    local accent_header=
    local accent_color0=
    local accent_color1=
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--initial)
                shift
                cur=$1
                ;;
            -p|--popup)
                popup=1
                ;;
            --return-idx)
                return_idx=1
                ;;
            --sel-color)
                shift
                sel_color="$1"
                ;;
            --cursor)
                shift
                cursor0="$1"
                ;;
            --header)
                shift
                header="$1"
                ;;
            --footer)
                shift
                footer="$1"
                ;;
            -r)
                readparam='-r'
                ;;
            --preview)
                shift
                preview="$1"
                ;;
            -h|--height)
                shift
                max_height=$1 && [[ $max_height -gt $LINES ]] && max_height=$LINES
                ;;
            --hscroll)
                hscroll=0
                ;;
            --searchable)
                search=on
                ;;
            --key)
                shift && return_key+=("$1")
                shift && return_fn+=("$1")
                ;;
            --accent)
                shift; accent_header="$1"
                shift; accent_color0="$1"
                shift; accent_color1="$1"
                ;;
            *)
                items+=("$1")
                ;;
        esac
        shift
    done <&1
    [[ -z $footer && $search == on ]] && footer=+
    if [[ $(pipe_context) == \>* ]]; then
        local i=0
        local ahlen="${#accent_header}"
        local t=$(get_timestamp)
        while IFS= read $readparam line; do
            if [[ $ahlen -gt 0 ]]; then
                if [[ $line == "$accent_header"* ]]; then
                    line=$'\e'"[${accent_color0}m${line:$ahlen}"
                    [[ $cur -lt 0 ]] && cur=$i
                else
                    line=$'\e'"[${accent_color1}m$line"
                fi
            fi
            [[ -n "$line" ]] && items+=("$line")
            ((i++))
            [[ $i -eq 100 && $(($(get_timestamp)-t)) -gt 300 ]] && echo -en "\rLoading..." >&2
        done
    fi
    [[ $cur -lt 0 ]] && cur=0

    local cursor1="$(strip_escape "$cursor0" | sed 's/./ /g')"
    [[ $header == - ]] && header="$cursor1 ${items[0]}" && items=("${items[@]:1}")

    local ret=
    local beg=0
    local cnt=${#items[@]}
    local lines=0
    [[ $cnt == 0 ]] && return 0
    [[ $cur -ge $cnt ]] && cur=$((cnt-1))

    display_menu() {
        [[ -n $toprow ]] && move_cursor $toprow >&2
        lines=${#items[@]}
        [[ $search == /* ]] && lines=$max_height
        [[ $1 == clear ]] && cur=-1 && header="${header//?/ }" && items=()

        local height=$((LINES-$(get_cursor_row < /dev/tty)+1))
        [[ $min_height == *% ]] && min_height=$((LINES*${min_height%?}/100))
        [[ $height -le $min_height ]] && height=$((min_height))
        [[ $height -gt $max_height ]] && height=$((max_height))
        [[ $height -gt 1 ]] && ((height--))
        [[ -z $footer ]] && ((height++))

        [[ -n "$header" ]] && printf "\r\e[0m\e[K$header\n" >&2 && ((height--))
        [[ $lines -gt $height ]] && lines=$height
        [[ $cur -lt 0 && $1 != show ]] && cur=0
        [[ $cur -ge ${#items[@]} ]] && cur=$((${#items[@]}-1))
        [[ $cur -ge 0 && $cur -lt $beg ]] && beg=$cur
        [[ $cur -ge $((beg+lines)) ]] && beg=$((cur-lines+1))
        #[[ $1 == show ]] && beg=0 && lines=${#items[@]}
        local i= && for ((i=$beg; i<$((beg+lines)); i++)); do
            local m="$cursor1" && [[ $i == $cur ]] && m="$cursor0"
            local c=0
            local line="${items[$i]}" && [[ $hscroll -gt 0 ]] && line="${line:$hscroll}"
            if [[ $i == $cur ]]; then
                c="$sel_color"
                [[ -n $sel_color && $sel_color != 7 ]] && line="$(strip_escape "$line")"
            fi
            local cr=$'\n' && [[ -z $footer && $i == $((beg+lines-1)) ]] && cr=
            printf "\r%s %b%s\e[0m \e[K$cr" "$m" "\e[0;${c}m" "$line" >&2
        done
        [[ $1 == show && -z $footer ]] && echo >&2
        [[ $1 == show ]] && return
        if [[ -n $footer ]]; then
            [[ -z $footer || $footer == +* ]] && printf '\r\e[0;7m(%*s/%s)\e[0m\e[K' ${#cnt} $((cur+1)) $cnt >&2
            [[ -n $footer && $search != /* ]] && printf "\e[0m\e[K${footer/#+/}\e[0m" >&2
        fi
        [[ $search == /* ]] && printf "\e[37;41m\e[K$search\e[0m" >&2
        [[ $1 == clear ]] && printf '\r\e[K' >&2 && toprow=
        if [[ -z $toprow ]]; then
            get_cursor_pos < /dev/tty
            [[ -n $header ]] && ((lines++))
            toprow=$((ROW-lines))
            [[ -z $footer ]] && ((toprow++))
            move_cursor $toprow >&2
        fi
    }

    local keys="${return_key[@]}"
    while true; do
        display_menu

        get_key KEY < /dev/tty
        if [[ $KEY != $'\e' && "$keys" == *$KEY* ]]; then # cannot override ESC
            ret="$cur" && [[ $return_idx -eq 0 ]] && ret="$(strip_escape "${items[$ret]}")"
            local i= && for ((i=0; i<${#return_key[@]}; i++)); do
                if [[ "${return_key[$i]}" == *"$KEY"* ]]; then
                    if [[ $(type -t "${return_fn[$i]}") == function ]]; then
                        "${return_fn[$i]}" "$ret"
                    else
                        eval "TEMPFUNC() { ${return_fn[$i]}; }"
                        TEMPFUNC "$ret" "$cur"
                    fi
                    break
                fi
            done
            ret=
            break
        fi
        case $KEY in
            $'\e'|q)
                if [[ ${#items_bak[@]} -gt 0 ]]; then
                    items=("${items_bak[@]}")
                    items_bak=()
                    [[ $cur -lt 0 ]] && cur=0
                    cnt=${#items[@]}
                    cur=$cur_bak
                    search=on
                else
                    break
                fi
                ;;
            j|$'\e[B')
                [[ $cur -lt $((cnt-1)) ]] && cur=$((cur+1))
                ;;
            k|$'\e[A')
                [[ $cur -gt 0 ]] && cur=$((cur-1))
                ;;
            h)
                if [[ $hscroll -ge 0 ]]; then ((hscroll--)); [[ $hscroll -lt 0 ]] && hscroll=0; fi
                ;;
            0)
                [[ $hscroll -ge 0 ]] && hscroll=0
                ;;
            g)
                cur=0
                ;;
            G)
                cur=$((${#items[@]}-1))
                ;;
            $'\04')
                cur=$((cur+(lines-1)/2))
                ;;
            $'\25')
                cur=$((cur-(lines-1)/2))
                ;;
            $'\t')
                if [ -n "$preview" ]; then
                    "$preview" "$(strip_escape "${items[$cur]}")" >&2 < /dev/tty
                    hide_cursor >&2
                fi
                ;;
            $'\n'|' '|l|$'\e[C')
                if [[ $KEY == l && $hscroll -ge 0 ]]; then
                    ((hscroll++))
                else
                    ret=$cur
                    [[ $return_idx -eq 0 ]] && ret="${items[$ret]}"
                    break
                fi
                ;;
            '/')
                if [[ $search == on || $search == /* ]]; then
                    cur_bak=$cur
                    [[ $search != /* ]] && search=/
                    [[ $hscroll -ge 0 ]] && hscroll=0
                    items_bak=("${items[@]}")
                    show_cursor >&2
                    display_menu
                    NEXT_KEY=
                    while true; do
                        KEY="$NEXT_KEY" && NEXT_KEY=
                        [[ -z "$KEY" ]] && get_key KEY </dev/tty
                        case $KEY in
                            $'\e'|$'\t'|$'\n')
                                [[ ${#items[@]} -gt 0 ]] && cur=0
                                break
                                ;;
                            $'\177'|$'\b')
                                search="${search%?}"
                                ;;
                            $'\e'*)
                                ;;
                            *)
                                search="$search$KEY"
                                ;;
                        esac
                        [[ $search == /?* ]] && IFS=$'\n' read -d "" -ra items < <(printf '%s\n' "${items_bak[@]}" | grep -i "${search#/}")
                        beg=0 && cur=-1 && cnt=${#items[@]}
                        get_key -t $get_key_eps NEXT_KEY </dev/tty
                        [[ -z $NEXT_KEY ]] && display_menu
                    done
                    hide_cursor >&2
                fi
                ;;
            z)
                local newrow=$((toprow*80/100))
                [[ $newrow -le 2 ]] && newrow=2
                local i= && for ((i=0; i<$((toprow-newrow)); i++)); do
                    move_cursor "$LINES;9999" >&2
                    echo >&2
                done
                toprow=$newrow
                ;;
        esac
    done
    [[ -z $ret ]] && cur=-1
    [[ $popup -eq 0 ]] && display_menu show || display_menu clear

    unset -f display_menu

    if [[ $opened != yes ]]; then
        enable_line_wrapping >&2
        show_cursor >&2
    fi

    [[ -n "$ret" ]] && strip_escape "$ret"
}

nshls() {
    __d=() && __f=()
    local l="${1:-.}"
    if [[ -z $lssort ]]; then
        while read ff; do
            f="$l/$ff"
            if [ -d "$f" ]; then
                __d+=("${f##*/}/")
            elif [ -e "$f" ]; then
                __f+=("${f##*/}")
            fi
        done < <(echo "$lsparam \"$l\"" | xargs ls 2>/dev/null | sort --ignore-case)
        [[ ${#__d[@]} -gt 0 ]] && printf '%s\n' "${__d[@]}"
        [[ ${#__f[@]} -gt 0 ]] && printf '%s\n' "${__f[@]}"
    else
        while read ff; do
            f="$l/$ff"
            if [ -d "$f" ]; then
                echo "${f##*/}/"
            elif [ -e "$f" ]; then
                echo "${f##*/}"
            fi
        done < <(echo "$lsparam $lssort \"$l\"" | xargs ls 2>/dev/null)
    fi
    return 0
}

cpu() {
    disable_line_wrapping
    (ps -ax -o %cpu,user,pid,cmd --sort=-%cpu 2>/dev/null || ps -ax -r) | head
    enable_line_wrapping
}

mem() {
    disable_line_wrapping
    (ps -ax -o %mem,user,pid,cmd --sort=-%mem 2>/dev/null || ps -ax -m) | head
    enable_line_wrapping
}

gpu() {
    disable_line_wrapping
    __skip_header() {
        while IFS= read line; do
            [[ "$line" == '|===='* ]] && break
        done
    }
    local res=()
    while true; do
        __skip_header
        local ll=
        while IFS= read line; do
            ll="$ll$line "
            if [[ $line == +----* ]]; then
                ll=($ll)
                local w= && for w in "${ll[@]}"; do
                    [[ $w == *% ]] && res[${ll[1]}]="$(printf '%2d %4s' "${ll[1]}" "$w")" && break
                done
                ll=
            elif [[ $line != \|* ]]; then
                break
            fi
        done
        while IFS= read line; do
            if [[ $line == *\ PID\ * ]]; then
                ll="${line%% PID *} PID" && ll=${#ll}
                __skip_header
                while IFS= read line; do
                    [[ $line != \|* ]] && break
                    line="${line:0:$ll}"
                    local pid="${line##* }"
                    line=($line)
                    res[${line[1]}]+=" $(ps -p $pid -o user= -o pid= -o command= 2>/dev/null)"
                done
            fi
        done
        break
    done < <(nvidia-smi 2>/dev/null)
    [[ ${#res[@]} -gt 0 ]] && echo ' # UTIL USER     PID' && printf '%s\n' "${res[@]}"
    enable_line_wrapping
}

disk() {
    disable_line_wrapping
    local cur="$PWD"
    get_terminal_size
    local max_h=$((LINES-3))
    while IFS= read line; do
        echo "$line" && ((max_h--))
    done < <(df -h .)
    local bars=("          " "|         " "||        " "|||       " "||||      " "|||||     " "||||||    " "|||||||   " "||||||||  " "||||||||| " "||||||||||")
    while true; do
        local l0=() && local l1=()
        local s0=() && local s1=()
        local total=0
        while read f; do
            if [[ -d "$f" ]]; then
                if [[ "$f" == \.\. ]]; then
                    l0=("../" "${l0[@]}")
                    s0=("-1" "${s0[@]}")
                elif [[ "$f" != \. && "$f" != \.\. ]]; then
                    l0+=("$f/")
                    size=$(du -sk "$f" 2>/dev/null | cut -f 1)
                    size=$((size*1024))
                    total=$((total+size))
                    s0+=("$size")
                fi
            elif [[ -e "$f" ]]; then
                l1+=("$f")
                size=$(stat "$STAT_FSIZE_PARAM" "$f" 2>/dev/null)
                [ -z $size ] && size=0
                total=$((total+size))
                s1+=("$(stat "$STAT_FSIZE_PARAM" "$f" 2>/dev/null)")
            fi
        done < <(ls -a | sort --ignore-case)
        local files=("${l0[@]}" "${l1[@]}")
        local sideinfo=("${s0[@]}" "${s1[@]}")

        # sort by size
        local i= && for ((i=0; i<$((${#files[@]}-1)); i++)); do
            [[ ${files[$i]} == ../ ]] && continue
            local idx=$i
            local j= && for ((j=$((i+1)); j<${#files[@]}; j++)); do
                [[ ${sideinfo[$j]} -gt ${sideinfo[$idx]} ]] && idx=$j
            done
            local t=${sideinfo[$i]}
            sideinfo[$i]=${sideinfo[$idx]}
            sideinfo[$idx]=$t
            t="${files[$i]}"
            files[$i]="${files[$idx]}"
            files[$idx]="$t"
        done

        echo -e "\r\033[4m$NSH_COLOR_DIR$PWD\033[0m ($(get_hsize $total))"
        local ret="$(for ((i=0; i<${#files[@]}; i++)); do
            local p='            ' && [[ ${sideinfo[$i]} -ge 0 ]] && p="[${bars[$(((${sideinfo[$i]}*100/$total+5)/10))]}]"
            printf "%8s %s\n" "$(get_hsize ${sideinfo[$i]})" "$p $(put_file_color "${files[$i]}")${files[$i]}"
        done | menu --popup --return-idx --cursor '' --sel-color 7 --key 'h' '[[ $(pwd) != / ]] && echo 0' --key 'o' 'echo cd \"${files[$1]}\"' --key 'x' 'echo quit here' --footer "+ $(draw_shortcut o Open z Zoom x QuitHere q Quit)")"
        move_cursor $(($(get_cursor_row)-1)) && printf '\e[K'
        [[ -z "$ret" ]] && break
        [[ $ret == cd\ * ]] && eval "$ret" && cur="$(pwd)" && break
        [[ $ret == quit\ here ]] && cur="$(pwd)" && break
        cd "${files[$ret]}" &>/dev/null
    done
    cd "$cur"
    enable_line_wrapping
}

__grep_match_case=OFF
__grep_whole_word=OFF
__grep_results=ALL
__grep_prev=
nshgrep() {
    if [[ $# -eq 0 ]]; then
        echo -en "$NSH_PROMPT search: "
        read_string "$__grep_prev"
        echo
        [[ -z "$STRING" ]] && return
    elif [[ $# -eq 1 ]]; then
        STRING="$1"
    else
        echo 'Too many arguments' >&2
        return 1
    fi
    __grep_prev="$STRING"

    local opt
    local opt_idx=0
    while true; do
        str=("match case: $__grep_match_case" "match whole word: $__grep_whole_word" "show results: $__grep_results")
        opt="$(menu --popup -i $opt_idx --return-idx --key ' l' 'echo "$1 "' --footer "\e[7mSPACE\e[0m Change options \e[7mENTER\e[0m Start searching" "${str[@]}")"
        [[ -z "$opt" || "$opt" != *\  ]] && break
        if [[ $opt -eq 0 ]]; then
            [[ $__grep_match_case == OFF ]] && __grep_match_case=ON || __grep_match_case=OFF
        elif [[ $opt -eq 1 ]]; then
            [[ $__grep_whole_word == OFF ]] && __grep_whole_word=ON || __grep_whole_word=OFF
        elif [[ $opt -eq 2 ]]; then
            [[ $__grep_results == ALL ]] && __grep_results='FIRST MATCH' || __grep_results=ALL
        fi
        opt_idx=$opt
    done
    local s= && for s in "${str[@]}"; do echo -e "$s\033[K"; done
    echo -ne '\033[4msearching...\033[0m'
    __param=
    [[ $__grep_match_case == OFF ]] && __param+=' -i '
    [[ $__grep_whole_word == ON ]] && __param+=' -w '
    [[ $__grep_results == 'FIRST MATCH' ]] && __param+=' -m 1 '
    grep_preview() {
        local f="$(strip_escape "$1")"
        local opt="${f#*:}"
        vi -s <(echo ":${opt%%:*}"; echo -n "V") "${f%%:*}"
    }
    f="$(grep -IHrn --color=always $__param "$__grep_prev" . 2>/dev/null | sed -e 's/\x1b\[[0]*m/\x1b\[37m/g' -e 's/\r//g' | menu --searchable --cursor '' --sel-color 7 --preview grep_preview --footer '+ \e[7m / \e[0m Search \e[7mTAB\e[0m Preview \e[7m z \e[0m Zoom' | strip_escape)"
    if [[ -n "$f" ]]; then
        if [[ "$NSH_DEFAULT_EDITOR" == vi || "$NSH_DEFAULT_EDITOR" == vim ]]; then
            opt="${f#*:}"
            "$NSH_DEFAULT_EDITOR" -s <(echo ":${opt%%:*}") "${f%%:*}"
        else
            "$NSH_DEFAULT_EDITOR" "${f%%:*}"
        fi
    else
        printf '\r\e[K'
    fi
}

git_root() {
    command git rev-parse --show-toplevel 2>/dev/null
}

git_branch_name() {
    command git rev-parse --abbrev-ref HEAD 2>/dev/null
}

git_branch() {
    while IFS=$'\n' read line; do
        [[ "$line" != \(HEAD\ *detached\ * ]] && echo "$line"
    done < <(LANGUAGE=en_US.UTF-8 command git branch 2>/dev/null | sed 's/[ *]*//')
    #git branch -r 2>/dev/null | sed -n '/[ ]*origin\//p' | sed -n '/ -> /!p' | sed 's/^[ *]*//'
    #git branch -r 2>/dev/null | sed -n '/[ ]*origin\//!p' | sed -n '/ -> /!p' | sed 's/^[ *]*//'
    local remote= && for remote in $(command git remote 2>/dev/null); do
        echo "$remote"
        command git branch -r 2>/dev/null | sed 's/^[ *]*//' | grep "^$remote/" | sed -n '/ -> /!p'
    done
}

git_parent() {
    local n="$(git_branch_name)"
    [[ -n "$n" ]] && command git show-branch | sed 's/\].*//' | grep '\*' | grep -v "$n" -m 1 | sed -e 's/^[^[]*\[//' -e 's/[\^~].*$//'
}

git_commit_preview() {
    local c="$(sed 's/^[^0-9^a-z^A-Z]*//' <<< "$1")" && c="${c%% *}" && c="${c/#^/}"
    local s=$(printf '%*s' $COLUMNS ' ') && s="${s//\ /-}"
    (command git log --color=always -n 1 $c; echo $s; command git diff --color=always --stat $c~ $c 2>/dev/null || command git diff --color=always --stat $c; echo $s; (command git diff $c~ $c 2>/dev/null || command git diff $c) | git_diff_formatter) | less -r
}

git_fix_conflicts() {
    local files=()
    while read line; do
        files+=("$line")
    done < <(LANGUAGE=en_US.UTF-8 command git status 2>/dev/null | grep 'both modified:' | sed 's/.*modified:[ ]*//')
    [[ ${#files[@]} -eq 0 ]] && return

    [[ $# -gt 0 ]] && echo "$@"
    while true; do
        idx="$(for f in "${files[@]}"; do
            [[ $(grep -c '^<\+ HEAD' "$f" 2>/dev/null) -gt 0 ]] && echo "@@$f" || echo "$f"
        done | menu --popup --return-idx --accent "@@" 31 32)"
        [[ -z "$idx" ]] && break
        $NSH_DEFAULT_EDITOR "${files[$idx]}"
        local cont=false
        local f= && for f in "${files[@]}"; do
            [[ $(grep -c '^<\+ HEAD' "$f" 2>/dev/null) -gt 0 ]] && cont=true && break
        done
        if [[ $cont == false ]]; then
            echo -n 'All conflicts were fixed. Apply the changes to continue? (Y/n) ' && get_key KEY
            echo
            if [[ $KEY == Y || $KEY == y ]]; then
                for f in "${files[@]}"; do
                    command git add "$f"
                done
                if [[ $(LANGUAGE=en_US.UTF-8 command git status 2>/dev/null | grep -q 'rebase in progress') -eq 0 ]]; then
                    command git rebase --continue && break
                else
                    command git commit
                    break
                fi
            fi
        fi
    done
}

git_log() {
    local header=
    local mopt=
    if [[ $1 == --header ]]; then
        header="$2"
        shift; shift
    elif [[ $1 == --return-idx ]]; then
        mopt="$1"
        shift
    fi
    if [[ " $@" == *\ -* ]]; then
        command git log $@
    else
        local gopt=
        local commit="$(command git status | grep 'HEAD detached' | sed 's/.*\ //')"
        if [[ -n $commit ]]; then
            extra="$(command git branch --remote --contains | head -n 1 | sed -e 's/.*->\ //' -e 's/^[ ]*origin\///')"
            extra="command git log "$extra" --decorate --oneline "$@" | sed '/^'$commit' /q' | (head -n -1 2>/dev/null || sed -e '$ d') | sed 's/^/\ /';"
        fi
        while true; do
            commit="$(eval "$extra command git log --decorate --color=always --oneline $gopt "$@" 2>/dev/null" | menu -r --footer "+ $(draw_shortcut TAB Preview ENTER Checkout \/ Search . Detail e Edit z Zoom)" --popup --preview git_commit_preview --searchable $mopt --key h 'echo' --key . 'echo !Detail' --key ev 'echo !edit $2' --header "$header")"
            [[ -z $commit ]] && return 0
            if [[ $commit == \!Detail ]]; then
                [[ $gopt == *--graph* ]] && gopt= || gopt="$gopt --graph --pretty='format:%C(yellow)%h%Creset %C(blue)(%cr|%an)%Creset%C(auto)%d %s'"
            elif [[ $commit == \!edit* ]]; then
                nshgit_prompt --force 'edit commits'
                commit="${commit#\!edit }"
                nshgit_run rebase -i "@~$(($commit+1))"
                return $?
            else
                commit="$(sed 's/^[^0-9^a-z^A-Z]*//' <<< "$commit")" && commit="${commit%% *}"
                echo -ne "$postfix\r$git_stat "; command git log --color=always -n 1 $commit | sed 's/^/|\ /' | sed '1 s/^| //'
                str="$(menu --popup 'Checkout this commit' 'Roll back to this commit' 'Roll back but keep the changes' 'Edit commits')"
                case $str in
                Checkout*)
                    nshgit_prompt --force "checkout $commit"
                    nshgit_run checkout $commit
                    return;;
                Roll\ back\ to*)
                    if dialog 'You will lose the commits. Continue?' OK Cancel; then
                        nshgit_prompt --force "reset --hard $commit"
                        nshgit_run reset --hard $commit
                        return
                    fi
                    ;;
                Roll*keep*)
                    if dialog 'Roll back to this commit?\nYou can cancel rollback by run "git restore FILE" and git pull' OK Cancel; then
                        nshgit_prompt --force "reset --soft $commit"
                        nshgit_run reset --soft $commit && nshgit_run restore --staged .
                        return
                    fi
                    ;;
                Edit\ *)
                    commit="$(command git log --oneline | grep -n "$commit ")" && commit="${commit%%:*}"
                    nshgit_prompt --force edit last "$commit" commits
                    nshgit_run rebase -i "@~$commit"
                    ;;
                esac
            fi
        done
    fi
}

nshgit() {
    local param="$1"
    local op=("$@") && shift
    local remote=()
    local stat
    if [[ -z $op ]]; then
        IFS=$'\n' read -d "" -ra remote < <(command git remote -v | sed -e 's/\t/ (/g' -e 's/\(.*\)\ (\([^(]*\))/\2 \1)/' -e 's/^fetch/& from/' -e 's/^push/& to/')
        [[ ${#remote[@]} -eq 0 ]] && return 1
    fi
    nshgit_prompt() {
        [[ -n $param && $1 != --force ]] && return
        [[ $1 == --force ]] && shift
        [[ -n "$@" ]] && echo -e "$postfix\r$git_stat $@" || echo -e "$postfix\r$git_stat"
    }
    nshgit_run() {
        command git "$@"
        local ret=$? && [[ $ret -ne 0 ]] && echo -e "\e[31m[$ret returned]\e[0m"
        return $ret
    }
    nshgit_strip_filename() {
        sed -e 's/^[A-Z] //' -e 's/^[??] //' -e 's/^[ ]*//' -e 's/^"//' -e 's/"$//' <<< "$1"
    }
    nshgit_get_selected() {
        op=() && local s= && for s in "${stat[@]}"; do
            if [[ $s == \** ]]; then
                s="$(strip_escape "${s#\* }")"
                op+=("$(nshgit_strip_filename "$s")")
            fi
        done
    }
    while true; do
        local postfix="$(printf '%*s' $COLUMNS a | sed 's/./-/g')"
        update_git_stat
        if [[ -z $op || $op == \!select* ]]; then
            [[ $op != \!select* ]] && IFS=$'\n' read -d "" -ra stat < <(command git -c color.status=always status --short | sed -e 's/^[ ]*//')
            local initial="${#stat[@]}" && [[ $op == \!select* ]] && initial="$((${op#*select }+1))"
            local title=
            [[ ${#stat[@]} -gt 0 ]] && title="${#stat[@]} file(s) to commit" && [[ "$(strip_escape ${stat[0]})" == \?\?* ]] && title="${#stat[@]} untracked files"
            op="$(menu --popup "${stat[@]}" pull commit "${remote[@]}" log branch --initial $initial --key p 'echo pull' --key h 'echo push' --key c 'echo \!commit' --key b 'echo branch' --key u 'echo !revert' --key r 'echo !refresh' --key ' ' 'echo !select $2' --header "$(nshgit_prompt "$title")")"
            [[ -z $op ]] && return
            if [[ $op == \!select* ]]; then
                op="${op#*select }"
                if [[ $op -lt ${#stat[@]} ]]; then
                    [[ ${stat[$op]} != \** ]] && stat[$op]="* ${stat[$op]}" || stat[$op]="${stat[$op]#\* }"
                fi
                op="!select $op" && continue
            fi
            [[ $op == \!refresh ]] && op= && continue
            [[ $op == D\ * ]] && op="${op#D }" && nshgit_prompt --force "diff $op" && echo "$op was deleted" && op= && continue
            [[ $op == \?\?\ * ]] && op=(add "$(nshgit_strip_filename "${op#\?\? }")")
        fi
        case "$op" in
            add*)
                op=("${op[@]:1}")
                if [[ -n $param || $(menu --popup --header "$(nshgit_prompt --force "add $(print_filename "$op")")" OK Cancel) == OK ]]; then
                    nshgit_run add "${op[@]}" && [[ $(menu --popup --header "$(nshgit_prompt --force Commit?)" OK Not\ now) == OK ]] && op=commit && continue
                fi
                ;;
            pull)
                nshgit_prompt pull from $(git_branch_name)
                nshgit_run pull origin "$(git_branch_name)"
                ;;
            push|push\ to\ *)
                local r=origin && [[ $op == push\ to\ * ]] && r="${op#push to }" && r="${r%% *}"
                nshgit_prompt --force "push to $r/$(git_branch_name)"
                if [[ $(LANGUAGE=en_US.UTF-8 command git status 2>/dev/null) == *modified* ]]; then
                    op=
                    dialog "You need to commit first." OK Cancel || continue
                    nshgit_run commit "$(git_root)" || continue
                fi
                nshgit_run push "$r" "$(git_branch_name)" -f
                ;;
            fetch*)
                local r=origin && [[ $op == fetch\ from\ * ]] && r="${op#fetch from }" && r="${r%% *}"
                nshgit_prompt --force "fetch from $r"
                nshgit_run fetch "$r"
                ;;
            \!commit)
                nshgit_get_selected
                op=(commit "${op[@]}")
                continue
                ;;
            commit)
                op=("${op[@]:1}")
                nshgit_prompt commit "${op[@]}"
                nshgit_run commit "${op:-.}"
                ;;
            log|log\ *)
                op=("${op[@]:1}")
                git_log --header "$(nshgit_prompt log ${op[@]})" "${op[@]}"
                ;;
            branch)
                local branch="$((echo '+ Create a new branch'; git_branch) | menu --popup --searchable --key h 'echo' --key $'\t' 'echo !view $1' --key d 'echo !delete $1' --key + 'echo +' --key m 'echo !merge $1' --key r 'echo !rebase $1' --footer "$(draw_shortcut ENTER Checkout TAB View + Create d Delete m Merge r MoveTo)" --header "$(nshgit_prompt branch)")"
                if [[ $branch == \+\ * ]]; then
                    nshgit_prompt --force New branch
                    dialog --input "Branch name: "
                    [[ -z $STRING ]] && op=branch && continue
                    nshgit_run checkout -b "$STRING"
                elif [[ -n $branch && $branch != \!* ]]; then
                    op="$(menu --popup --header "$(nshgit_prompt --force branch \'$branch\')" 'Checkout this branch' 'Merge this branch' 'Move the current branch on to this' 'Explore this branch' 'Compare this branch and the current branch' 'Delete this branch')"
                    if [[ $op == Checkout* ]]; then
                        nshgit_prompt --force "checkout $branch"
                        nshgit_run checkout "${branch#origin\/}"
                    elif [[ $op == Merge* ]]; then
                        branch="!merge $branch"
                    elif [[ $op == Move* ]]; then
                        branch="!rebase $branch"
                    elif [[ $op == Explore* ]]; then
                        branch="!view $branch"
                    elif [[ $op == Compare* ]]; then
                        nshgit_prompt "diff $(git_branch_name) - $branch"
                        nshgit_run diff "$(git_branch_name)..$branch" | git_diff_formatter
                    elif [[ $op == Delete* ]]; then
                        branch="!delete $branch"
                    else
                        op=branch; continue
                    fi
                fi
                if [[ $branch == \!view* ]]; then
                    branch="${branch#* }"
                    [[ $branch == +\ * ]] && continue
                    local path=
                    while true; do
                        local p="$((echo -ne "\r$postfix\r$git_stat "; comand git show --color=always "$branch:$path") | sed "s/.*\/$/$NSH_COLOR_DIR&\x1b\[0m/" | menu -r --popup --header - --key h 'echo ..' --footer "$(draw_shortcut c Checkout y Copy)" --key c 'echo !checkout $1' --key y 'echo !copy $1')"
                        [[ -z $p ]] && break
                        p="$(strip_escape "$p")"
                        if [[ $p == \!* ]]; then
                            if [[ $p == \!checkout\ * ]]; then
                                nshgit_run checkout "$branch" -- "${p#*checkout }"
                            else
                                p="${p#*copy }" && [[ "$p" == */ ]] && dialog "Cannot copy a directory! Use Checkout instead" && continue
                                local new_name="${p%/}"
                                read_string "$new_name"
                                [[ -z $STRING ]] && continue
                                nshgit_run show "$branch:$path$p" >> "$STRING" && dialog "copied $p from $branch --> $STRING"
                            fi
                        elif [[ $p == .. ]]; then
                            path="$(sed 's/[^/]*\/$//' <<< "$path")"
                        elif [[ "$p" == */ ]]; then
                            [[ -z $path ]] && path="$p" || path="$path$p"
                        fi
                    done
                    op=branch && continue
                elif [[ $branch == \!delete* ]]; then
                    branch="${branch#* }"
                    [[ $branch == +\ * ]] && continue
                    if [[ $branch == origin/* ]]; then
                        if [[ $(menu --popup --header "$(nshgit_prompt --force "This will completely delete $branch branch from the repository.")" OK Cancel) == OK ]]; then
                            nshgit_run push origin --delete "${branch#*/}"
                        fi
                    else
                        if [[ $(menu --popup --header "$(nshgit_prompt --force "This will delete $branch branch locally")" OK Cancel) == OK ]]; then
                            nshgit_run branch -D "$branch"
                        fi
                    fi
                    op=branch && continue
                elif [[ $branch == \!merge* ]]; then
                    branch="${branch#* }"
                    [[ $branch == +\ * ]] && continue
                    if [[ $(menu --popup --header "$(nshgit_prompt --force "Merge $branch?")" OK Cancel) == OK ]]; then
                        nshgit_prompt "Merge $branch"
                        nshgit_run merge $branch
                    fi
                elif [[ $branch == \!rebase* ]]; then
                    branch="${branch#* }"
                    if [[ -n "$(command git branch --list "$branch")" || -n "$(command git branch -r | sed 's/$/ /' | grep " $branch ")" ]]; then
                        local p="$(git_parent)"
                        local c="$(git_branch_name)"
                        if [[ -n "$p" && "$p" != "$ranch" ]]; then
                            dialog "It is recommended to use --onto option since this branch seems to be based on $p:\n  git rebase --onto $branch $p $c"
                            nshgit_run rebase --onto "$branch" "$p" "$c"
                        else
                            nshgit_run rebase -i "$branch"
                        fi
                        [[ $? -ne 0 ]] && git_fix_conflicts "Conflicts were found. Fix them and commit the changes."
                    fi
                fi
                ;;
            \!revert)
                op=("${op[@]:1}")
                [[ -z $op ]] && nshgit_get_selected; [[ -z $op ]] && op=(all)
                op="$(printf '%s, ' "${op[@]}")" && op="${op%, }"
                if [[ $(menu --popup --header "$(nshgit_prompt --force revert $op?)" OK Cancel) == OK ]]; then
                    nshgit_prompt revert $op
                    local f= && for f in "${stat[@]}"; do
                        f="$(strip_escape "$f")"
                        if [[ $f == \*\ * ]]; then
                            f="${f#\* }"
                            if [[ $f == A\ * ]]; then
                                nshgit reset "$(nshgit_strip_filename "$f")"
                            elif [[ $f =~ ^[A-Z]\  ]]; then
                                nshgit checkout -- "$(nshgit_strip_filename "$f")"
                            else
                                nshgit checkout -- .
                                break
                            fi
                        fi
                    done
                fi
                ;;
            revert)
                op=("${op[@]:1}")
                local f && for f in "${op[@]}"; do
                    nshgit checkout -- "$f"
                done
                ;;
            blame)
                op=("${op[@]:1}")
                command git blame "${op[@]}" | sed -e 's/\([^ ]\+ \)[^(]*/\1/' -e 's/\t/    /g' | sed -e 's/\r//g' | menu --header "$(nshgit_prompt "blame $(print_filename ${op[@]})")" -h $((LINES-1)) --popup --preview git_commit_preview --searchable --hscroll --footer "+ $(draw_shortcut l ScrollRight h ScrollLeft \/ Search Tab ViewCommit)"
                op= # to return 0
                ;;
            *)
                f="$(sed 's/^[ ]*[A-Z][ ]*//' <<< "$op")" && f="${f#\"}" && f="${f%\"}"
                if [[ $op == A\ * ]]; then
                    op="$(menu --popup --header "$NSH_PROMPT $(print_filename "$f")" Commit Undo\ add View)"
                    if [[ $op == Commit ]]; then
                        op="commit $f"
                    elif [[ $op == Undo* ]]; then
                        nshgit_prompt "Unstage $(print_filename "$f")"
                        nshgit_run reset "$f"
                    elif [[ $op == View ]]; then
                        "$NSH_DEFAULT_EDITOR" "$f"
                    fi
                    [[ $op == Commit ]] && continue
                elif [[ $op =~ ^[A-Z]\  && -e "$f" ]]; then
                    nshgit_prompt "diff $(print_filename "$f")"
                    command git diff "$f" | git_diff_formatter
                    op="$(menu --popup "commit $f" "revert $f" "blame $f" open)"
                    if [[ $op == open ]]; then
                        "$NSH_DEFAULT_EDITOR" "$f"
                    else
                        op=("${op%% *}" "${op#* }")
                        continue
                    fi
                else
                    nshgit_run "${op[@]}"
                fi
                ;;
        esac
        [[ $(get_cursor_col) -gt 1 ]] && echo
        [[ -n $param ]] && break
        op=
    done
}

get_num_words() {
    echo $#
}

find_duplicated() {
    find -not -empty -type f -printf "%s\n" | sort -rn | uniq -d | xargs -I{} -n1 find -type f -size {}c -print0 | xargs -0 md5sum | sort | uniq -w32 --all-repeated=separate
}

__unroll_string() {
    local params=("")
    local varpos=""
    local varcnt=0
    local pos=1
    while [ $# -gt 0 ]; do
        param=$1
        if [[ $param == *=* ]]; then
            p=${param%=*}
            param=${param#*=}
            local i= && for ((i=0; i<${#params[@]}; i++)); do
                params[$i]="${params[$i]} $p"
            done
        fi
        if [[ "$param" == *, ]]; then
            param="${param%?}"
            varpos="$varpos $pos"
            varcnt=$((varcnt+1))
            clone=("${params[@]}")
            local i= && for ((i=0; i<${#params[@]}; i++)); do
                params[$i]="${params[$i]} $param"
            done
            shift
            while [ $# -gt 0 ]; do
                if [[ "$1" == *, ]]; then
                    param="${1%?}"
                else
                    param="$1"
                    [[ "$1" == - ]] && param=''
                fi
                local c= && for c in "${clone[@]}"; do
                    params+=("$c $param")
                done
                [[ "$1" != *, ]] && break
                shift
            done
        else
            local i= && for ((i=0; i<${#params[@]}; i++)); do
                params[$i]="${params[$i]} $param"
            done
        fi
        pos=$((pos+1))
        shift
    done
    local i= && for ((i=0; i<${#params[@]}; i++)); do
        local v= && for ((v=1; v<=$varcnt; v++)); do
            var="$(echo $varpos | awk "{ printf \$$v; }")"
            var="$(echo ${params[$i]} | awk "{ printf \$$var; }")"
            params[$i]="$(echo ${params[$i]} | sed "s@{$v}@$var@g")"
        done
        echo "${params[$i]}"
    done
}

play2048() {
    local board=()
    local board_prev=()
    local board_hist=()
    local hlpos=()
    local buf=()
    local col=$(get_cursor_col)
    init_board() {
        board=()
        if [[ $1 != force && -e ~/.cache/nsh/2048 ]]; then
            IFS=$'\n' read -d "" -ra board < ~/.cache/nsh/2048
        fi
        if [ ${#board[@]} -ne 16 ]; then
            board=()
            local i= && for i in {1..16}; do
                board+=("0")
            done
            add 2
            add 2
        fi
        board_prev=("${board[@]}")
        board_hist=()
        hlpos=()
    }
    display() {
        local r0=$(($(get_cursor_row)-4))
        local j= && for j in {0..3}; do
            move_cursor "$((r0+j));$col"
            local i= && for i in {0..3}; do
                local n=${board[$((i+j*4))]}
                local c='36'
                case $n in
                    0) c='90';;
                    2) c='37';;
                    4) c='35';;
                    8) c='95';;
                    16) c='31';;
                    32) c='91';;
                    64) c='33';;
                    128) c='93';;
                    256) c='34';;
                    512) c='94';;
                    1024) c='32';;
                    2048) c='92';;
                esac
                [[ $n -eq 0 ]] && n=''
                [[ " ${hlpos[@]} " =~ " $((i+j*4)) " ]] && c="$c;7"
                printf '\e[0m %b%b%5s\e[0m' "\e[${c}m" $'\e[48;5;236m' "$n"
            done
            echo ' '
        done
        if [ ${#hlpos[@]} -gt 0 ]; then
            hlpos=()
            sleep 0.1
            display
        fi
    }
    add() {
        while true; do
            i=$(((RANDOM%4)+(RANDOM%4)*4))
            [[ ${board[$i]} -eq 0 ]] && board[$i]=${1:-2} && display && sleep 0.1 && break
        done
    }
    merge() {
        local i=$1
        local inc=$2
        buf=()
        local n= && for n in {1..4}; do
            [[ ${board[$i]} -ne 0 ]] && buf+=("${board[$i]}") && board[$i]=0
            i=$((i+inc))
        done
        buf+=(0 0 0 0)
        local prev=${buf[0]} && buf=("${buf[@]:1}")
        local dst=$1
        for n in {1..3}; do
            local cur=${buf[0]} && buf=("${buf[@]:1}")
            if [[ $cur -eq $prev ]]; then
                board[$dst]=$((prev+cur))
                prev=${buf[0]} && buf=("${buf[@]:1}")
                [[ $cur -ne 0 ]] && hlpos+=("$dst")
            else
                board[$dst]=$prev
                prev=$cur
            fi
            dst=$((dst+inc))
        done
        [[ $prev -ne 0 ]] && board[$dst]=$prev
    }

    hide_cursor
    echo; echo; echo; echo
    init_board
    while true; do
        display
        get_key KEY
        local new=2 && [[ $((RANDOM%10)) -eq 0 ]] && new=4
        board_prev=("${board[@]}")
        [[ ${#board_hist[@]} -gt 160 ]] && board_hist=("${board_hist[@]:${#board_hist[@]}-160}")
        hlpos=()
        case $KEY in
            $'\e'|'q')
                break
                ;;
            'r')
                init_board force
                ;;
            'u')
                i=$((${#board_hist[@]}-16))
                if [ $i -ge 0 ]; then
                    local n= && for ((n=0; n<16; n++)); do
                        board[$n]="${board_hist[$((i+n))]}"
                    done
                    board_prev=("${board[@]}")
                    board_hist=("${board_hist[@]:0:$i}")
                fi
                ;;
            'h'|$'\e[D')
                merge 0 1
                merge 4 1
                merge 8 1
                merge 12 1
                ;;
            'l'|$'\e[C')
                merge 3 -1
                merge 7 -1
                merge 11 -1
                merge 15 -1
                ;;
            'k'|$'\e[A')
                merge 0 4
                merge 1 4
                merge 2 4
                merge 3 4
                ;;
            'j'|$'\e[B')
                merge 12 -4
                merge 13 -4
                merge 14 -4
                merge 15 -4
                ;;
        esac
        [[ "${board[@]}" != "${board_prev[@]}" ]] && display && board_hist+=("${board_prev[@]}") && sleep 0.1 && add $new
    done
    printf '%s\n' "${board[@]}" > ~/.cache/nsh/2048
    show_cursor
}

############################################################################
# main function
############################################################################
nsh() {
    local version='0.1.2'
    local nsh_mode=
    local subprompt=
    local INDENT=
    local STRING=
    local STRING_SUGGEST=
    local PRESTRING=
    local STRINGBUF=
    local selected=()
    local tilde='~'
    local dirs
    local files
    local list
    local list_width
    local list2=()
    local update_list2
    local sideinfo bytesizes
    local mime
    local max_lines
    local focus # index of the item that has focus
    local y # index of the item that is on the top of the screen
    local cursor
    local filter
    local last_item
    local history=()
    local history_idx=0
    local side_info_idx
    local git_stat=
    local git_stat_c=
    local git_mark=()
    local NEXT_KEY=
    local show_all=0
    local lsparam=
    local lssort=
    local opened=no
    local git_mode=0
    local bookmarks=()
    local visited=()

    # load config
    config() {
        local config_file=~/.config/nsh/nshrc
        if [[ $1 == load ]]; then
            mkdir -p ~/.config/nsh
            [[ ! -e $config_file ]] && echo "$NSH_DEFAULT_CONFIG" > $config_file
        elif [[ $1 == default ]]; then
            echo "$NSH_DEFAULT_CONFIG" > $config_file
        else
            "$NSH_DEFAULT_EDITOR" "$config_file"
        fi
        source "$config_file"
        #[[ -e ~/.bashrc ]] && source ~/.bashrc
    }
    config load

    # bash version check
    (man ls 2>/dev/null | grep -- '-I.*--ignore' &>/dev/null) || NSH_ITEMS_TO_HIDE=
    get_key_eps=0.1
    read -sn 1 -t $get_key_eps _key &>/dev/null
    [[ $? -ne 142 ]] && get_key_eps=1

    # detect terminal size change
    local resized=0
    trap "resized=1" WINCH SIGWINCH

    # load bookmarks
    load_bookmarks() {
        touch ~/.config/nsh/bookmarks
        IFS=$'\n' read -d "" -ra bookmarks < <(cat ~/.config/nsh/bookmarks | sort)
    }
    load_bookmarks

    # last directory
    mkdir -p ~/.cache/nsh
    touch ~/.cache/nsh/lastdir
    if [[ "$PWD" == "$HOME" && $NSH_REMEMBER_LOCATION -ne 0 ]]; then
        read PWD < ~/.cache/nsh/lastdir
        command cd "$PWD"
    fi
    OLDPWD="$PWD"

    # read history
    touch ~/.cache/nsh/history
    STRING=
    while read -r line; do
        [[ -n "$line" && "$line" != "$STRING" ]] && history+=("$line")
        STRING="$line"
    done <~/.cache/nsh/history
    [[ ${#history[@]} -gt $HISTSIZE ]] && history=("${history[@]:$((${#history[@]}-HISTSIZE))}")
    history_idx=${#history[@]}

    show_logo() {
        disable_line_wrapping
        echo -e '                   _
 __               | |
 \ \     ____  ___| |__
  \ \   |  _ \/ __|  _ \
  / /   | | | \__ \ | | |
 /_/    |_| |_|___/_| |_| ' $version
        echo "        nsh is Not a SHell"
        enable_line_wrapping
    }

    open_pane() {
        save_cursor_pos
        get_terminal_size
        open_screen "2;$((LINES-1))"
        disable_line_wrapping
        hide_cursor
        disable_echo
        opened=yes

        # job control
        set -m
        # show hidden files
        shopt -s dotglob
    }
    close_pane() {
        show_cursor
        enable_echo
        enable_line_wrapping
        if [[ $opened == yes ]]; then
            close_screen
            restore_cursor_pos
        fi
        printf '\e[0m\e[K'
        opened=no
    }
    quit() {
        close_pane
        # store history
        if [ $history_idx -eq 0 ]; then
            printf '%s\n' "${history[@]}" > ~/.cache/nsh/history
        else
            printf '%s\n' "${history[@]:$((history_idx-1))}" >> ~/.cache/nsh/history
        fi
        exit "$@"
    }
    clear_screen() {
        get_terminal_size
        move_cursor "$((LINES-1));9999"
        local i= && for ((i=0; i<$max_lines; i++)); do echo; done
        list2=()
    }
    print_prompt() {
        if [ $resized -ne 0 ]; then
            resized=0
            local offset=$((LINES-row0))
            get_terminal_size
            row0=$((LINES-offset))
        fi
        hide_cursor

        # ps
        if [[ -n $STRINGBUF ]]; then
            subprompt="$NSH_PROMPT "
        elif [[ -z $subprompt ]]; then
            local prefix=
            [[ -n $nsh_mode ]] && prefix=$'\e[37;45m'"[$nsh_mode]"
            if [[ -n "$NSH_PROMPT_PREFIX" ]]; then
                prefix="\e[32;40m$(eval "$NSH_PROMPT_PREFIX" 2>/dev/null || echo "$NSH_PROMPT_PREFIX")"
                if [[ -n "$1" ]]; then
                    prefix="$prefix\e[30;47m$NSH_PROMPT_SEPARATOR\e[34;47m$1\e[47;7m$NSH_COLOR_DIR$NSH_PROMPT_SEPARATOR"
                else
                    prefix="$prefix\e[40;7m$NSH_COLOR_DIR$NSH_PROMPT_SEPARATOR"
                fi
            elif [[ -n "$1" ]]; then
                prefix="\e[34;47m$1\e[47;7m$NSH_COLOR_DIR$NSH_PROMPT_SEPARATOR"
            fi
            subprompt="$prefix\e[0;7m$NSH_COLOR_DIR $(dirs) \e[0;${git_stat_c}m$NSH_COLOR_DIR$NSH_PROMPT_SEPARATOR$git_stat\e[0m "
        fi
        if [[ $opened == yes ]]; then
            move_cursor 1
        else
            local plain_ps="$(strip_escape "$subprompt $INDENT$STRING")"
            local h_plain_ps=$(($(strlen "$plain_ps")/COLUMNS))
            if [[ $((row0+h_plain_ps)) -gt $LINES ]]; then
                local i= && for ((i=0; i<$((LINES-row0-h_plain_ps)); i++)); do
                    echo
                done
                echo -e '\r\e[K'
                row0=$((LINES-h_plain_ps))
            fi
            move_cursor "$row0"
        fi
        printf "$subprompt$INDENT"
        # command line
        if [[ $cursor -lt 0 || $opened == yes ]]; then
            local p= && [[ $opened == yes ]] && p="$PRESTRING"
            if [[ $nsh_mode == search && $focus -ge 0 ]]; then
                if [[ ${#selected[@]} -eq 0 ]]; then
                    syntax_highlight "$p\"${list[$focus]}\""
                else
                    STRING="$p"
                    local i= && for ((i=0; i<${#list[@]}; i++)); do
                        [[ -n ${selected[$i]} ]] && STRING="$STRING\"${list[$i]}\" "
                    done
                    syntax_highlight "$STRING"
                fi
            else
                syntax_highlight "$p$STRING"
            fi
            printf '\e[K'
        else
            if [[ -z $NEXT_KEY && -n $STRING && $cursor -eq ${#STRING} ]] && [[ -z $STRING_SUGGEST || $STRING_SUGGEST != $STRING* ]]; then
                STRING_SUGGEST="$(printf "%s\n" "${history[@]}" | grep "^${STRING//./\\.}" | tail -n 1)"
            fi
            print_command "${STRING:0:$cursor}"
            if [ $cursor -lt ${#STRING} ]; then
                get_cursor_pos
                printf '\e[0m%s\e[0m \b\e[K' "${STRING:$cursor}"
                move_cursor "$ROW;$COL"
            elif [[ -n $STRING && -n $STRING_SUGGEST ]]; then
                get_cursor_pos
                [[ $ROW -eq $LINES ]] && disable_line_wrapping
                printf '\e[38;5;240m%s\e[0m \b\e[K' "${STRING_SUGGEST:$cursor}"
                [[ $ROW -eq $LINES ]] && enable_line_wrapping
                move_cursor "$ROW;$COL"
            else
                printf ' \b\e[K'
            fi
        fi

        [[ $opened != yes ]] && show_cursor
    }
    NSH_CURSORCH=$'\007'
    syntax_highlight() {
        if [[ $# -eq 0 ]]; then
            while IFS= read -r line; do
                syntax_highlight "$line"; echo
            done
            return
        fi
        local str="$@"
        local out=
        local prefix postfix
        local highlight_word=0 && [[ $str == *$NSH_CURSORCH ]] && highlight_word=1 && str="${str/$NSH_CURSORCH/}"
        if [[ $str == sudo\ * || $str == command\ * || $str == exec\ * ]]; then
            word="${str%% *}"
            out+="$NSH_COLOR_CMD"$'\e[4m'"$word"$'\e[0m '
            str="${str:$((${#word}+1))}"
        fi
        word=
        word_idx=0
        while [[ -n "$str" ]]; do
            prefix=
            postfix=
            if [[ $str == \ * ]]; then
                prefix="${str%% *} "
                word=
                ((word_idx--))
            elif [[ $str == [\'\"]* ]]; then
                prefix="${str:0:1}"
                word="$(sed "s/\([^\\]\)$prefix.*$/\1/" <<<"$str")"
                [[ "$word" != "$str" ]] && postfix=$prefix
                word="${word#?}"
            else
                word="$(sed 's/\([^\\]\)[ =;].*$/\1/' <<<"$str")"
                postfix="${str:${#word}:1}"
            fi

            str="${str:$((${#word}+${#prefix}+${#postfix}))}"

            local c=$'\e[0m'
            local wordbak=
            local lword="${word/#$tilde/$HOME}"
            if [[ -e "$lword" ]]; then
                c="$(put_file_color "$lword")"$'\e[4m'
                if [[ $word == */* ]]; then
                    wordbak="$word"
                    local d="${word%/*}/"
                    word="${word:${#d}}"
                    prefix="$prefix"$'\e[4m'"$NSH_COLOR_DIR${d/$HOME/$tilde}"
                fi
            elif [[ $prefix == [\'\"] && -n $postfix ]]; then
                c="$NSH_COLOR_VAL"
            elif [[ $word == -* ]]; then
                c="$NSH_COLOR_VAR"
            elif [[ $word == \$* || $word == \"\$* ]]; then
                c="$NSH_COLOR_ERR"
                #[[ -v "${word#?}" ]] && c="$NSH_COLOR_VAR"
                [[ -n "$(eval echo \"$word\" 2>/dev/null)" ]] && c="$NSH_COLOR_VAR"
            elif [[ $postfix == \= ]]; then
                c="$NSH_COLOR_VAL"
            elif [[ $word_idx -eq 0 ]]; then
                c="$NSH_COLOR_ERR"
                type "$word" &>/dev/null && c="$NSH_COLOR_CMD"
            elif [[ $word == */* || $word =~ \.[A-Za-z]+$ ]] && [[ $word != http:* && $word != https:* ]]; then
                wordbak="$word"
                local d="${word%/*}" && [[ -n $d ]] && d+=/
                local f="$NSH_COLOR_ERR${word##*/}"
                if [[ -e $d ]]; then
                    word="$NSH_COLOR_DIR$d$NSH_COLOR_ERR$f"
                else
                    word="$NSH_COLOR_ERR$word"
                fi
            fi
            [[ $highlight_word -ne 0 && -z "$str$postfix" ]] && c+=$'\e'"[${NSH_COLOR_BKG}m"
            out+="$prefix$c$word"$'\e[0m'"$postfix"
            [[ -n $wordbak ]] && word="$wordbak"
            ((word_idx++))
            [[ $postfix == [\;\|] || $word =~ [\;\|\&]+ ]] && word_idx=0
        done
        printf '\e[0m%s\e[0m\e[K' "$out"
        [[ $postfix == *\  ]] && word= || ((word_idx--))
    }
    print_command() {
        local cur="$@"
        if [ $# -eq 0 ]; then
            while IFS= read line; do
                print_command "$line"
                echo
            done
            return
        fi
        if [[ $cursor -lt 0 ]]; then
            syntax_highlight "$cur"
        else
            syntax_highlight "${cur:0:$cursor}$NSH_CURSORCH${cur:$cursor}"
        fi
        [[ $word == \  ]] && word=
    }
    draw_title() {
        if [ $resized -ne 0 ]; then
            resized=0
            close_pane
            open_pane
            if [[ -z $filter ]]; then
                update
            else
                list_width=$((COLUMNS*3/10))
                side_info_idx=0
                redraw
                update_side_info
            fi
            return
        fi
        move_cursor 1
        if [[ -n $filter || -n "$nsh_mode$PRESTRING" ]]; then
            cursor=${#STRING}
            print_prompt
        else
            local path="$(dirs)$git_stat$NSH_COLOR_TOP/*"
            [[ $(dirs) == / ]] && path='/*'
            [[ $1 == show_filename ]] && path="${path%?}${list[$focus]}" && [[ ${list[$focus]} == /* ]] && path="${list[$focus]}"
            local tstr=$(date +%H:%M:%S)
            local pstr="$(eval "$NSH_PROMPT_PREFIX" 2>/dev/null || echo "$NSH_PROMPT_PREFIX")"
            [[ -n "$pstr" ]] && pstr=$'\e[32;40m'" $pstr $NSH_COLOR_TOP"
            [[ -n $nsh_mode ]] && pstr=$'\e[37;45m'"[$nsh_mode]$NSH_COLOR_TOP$pstr"
            printf "%b%*s\r%b\e[0m" "$NSH_COLOR_TOP" "$COLUMNS" "|$diskusage$cpustr$memstr|$tstr" "$pstr $path"
            if [[ $tstr == *0 || $tstr == *5 ]]; then
                [[ $tstr == *0 ]] && update_git_stat
                diskusage=
                __cpu=
                __mem=
            fi
            if [ -z "$diskusage" ]; then
                diskusage="$(df -kh . | tail -n 1 | awk '{ print $3 "/" $2; }')"
            fi
            if [ -z "$__cpu" ]; then
                if read __cpu user nice system idle iowait irq softirq steal guest 2>/dev/null < /proc/stat; then
                    if [[ -z $cpu_activ_prev ]]; then
                        cpu_activ_prev=$((user+system+nice+softirq+steal))
                        cpu_total_prev=$((user+system+nice+softirq+steal+idle+iowait))
                        __cpu=0
                    else
                        cpu_activ_cur=$((user+system+nice+softirq+steal))
                        cpu_total_cur=$((user+system+nice+softirq+steal+idle+iowait))
                        __cpu=$((((cpu_activ_cur-cpu_activ_prev)*1000/(cpu_total_cur-cpu_total_prev)+5)/10))
                        cpustr="|$(printf "CPU%3d%%" $__cpu)"
                        cpu_activ_prev=$cpu_activ_cur
                        cpu_total_prev=$cpu_total_cur
                    fi
                else
                    __cpu=0
                fi
            fi
            if [ -z "$__mem" ]; then
                __mem=(`free -m 2>/dev/null | grep '^Mem:'`)
                if [ -z "$__mem" ]; then
                    __mem=0
                else
                    __mem=$(((${__mem[2]}*1000/${__mem[1]}+5)/10))
                    memstr="|$(printf "Mem%3d%%" $__mem)"
                fi
            fi
            if [ -z $blink ]; then
                if [ $__cpu -ge 50 ]; then
                    move_cursor "1;$((COLUMNS-23))"
                    echo -e "\033[37;41m${cpustr#?}\033[0m"
                fi
                if [ $__mem -ge 50 ]; then
                    move_cursor "1;$((COLUMNS-15))"
                    echo -e "\033[37;41m${memstr#?}\033[0m"
                fi
                blink=1
            else
                blink=
            fi
        fi
    }
    draw_line() {
        local item="${list[$1]}"
        local mark=' '
        local additional_mark=
        local o=0
        if [ ! -z "$item" ]; then
            local fmt="$(put_file_color "$item")"
            [[ $1 == $focus ]] && fmt+="$NSH_COLOR_CUR"
            if [[ ${selected[$1]} == "$PWD/$item" ]]; then
                fmt+=$'\e'"[33;${NSH_COLOR_BKG}m"
                mark=$'\e[0m*'
            fi
            [[ -d "$item" && $item != */ ]] && item+='/'

            if [[ ${#git_mark[@]} -gt 0 ]]; then
                additional_mark="${git_mark[$1]}"
                o=1
            fi
            item="${item/#$HOME\//$tilde/}"

            #printf '\r%s%b%-*s\e[0m\r' "$mark" "$fmt" "$((list_width-1))" "$item"
            local il=$((${#item}+o))
            local sl=${#sideinfo[$1]}
            local ll=$((list_width-1-o-sl)) && [[ $focus -lt 0 ]] && ll=$((COLUMNS-1-o-sl))
            if [[ $il -gt $ll && $item == */* ]]; then
                local prefix= && [[ $item == ../* ]] && prefix="${item%../*}../" && item="${item:${#prefix}}"
                local postfix="${item: -1}"
                item="$prefix$(echo "${item%?}" | sed 's#\(\.\?[^/]\)[^/]\+/#\1/#g')$postfix"
                il=$((${#item}+o))
            fi
            if [ $il -gt $ll ]; then
                if [ $ll -gt 2 ]; then
                    item="${item:0:$((ll-2))}~"
                else
                    item="$item "
                fi
            fi
            if [[ -h "${list[$1]}" ]]; then
                local t="$NSH_COLOR_LNK"
                [[ $focus != $1 ]] && t="$(eval "put_file_color \"${sideinfo[$1]}\"")"
                printf '\e[0m%s%b%-*s%b%*s\e[0m' "$additional_mark$mark" "$fmt" "$ll" "$gm$item" "$t" "$sl" "${sideinfo[$1]/#$HOME\//$tilde/}"
            elif [[ $item == */?* ]]; then
                local d="${item%/*}/"
                local dl=${#d}
                printf '\e[0m%s%b%-*s' "$additional_mark$mark" "$fmt$NSH_COLOR_DIR" "$dl" "$gm$d"
                printf '%b%-*s%*s\e[0m' "$fmt" "$((ll-dl))" "${item:$dl}" "$sl" "${sideinfo[$1]}"
            else
                printf '\e[0m%s%b%-*s%*s\e[0m' "$additional_mark$mark" "$fmt" "$ll" "$gm$item" "$sl" "${sideinfo[$1]}"
            fi
        fi
    }
    draw_list() {
        move_cursor 2
        local i= && for ((i=0; i<$max_lines; i++)); do
            draw_line $((y+i))
            [[ $i -lt $((max_lines-1)) ]] && echo
        done
    }
    draw_list2() {
        [[ $focus -lt 0 ]] && return
        [[ $1 != full && "$update_list2" == "${list[$focus]}" && ${#list2[@]} -gt 0 ]] && return
        update_list2=
        [[ ! -n "$NEXT_KEY" ]] && get_key -t $get_key_eps NEXT_KEY
        if [[ -n "$NEXT_KEY" && ! -d "${list[$focus]}" ]]; then
            local i= && for ((i=0; i<$max_lines; i++)); do
                move_cursor "$((i+2));$((list_width+2))"
                printf '\e[0m\e[K'
            done
            update_list2="${list[$focus]}"
            return
        fi

        local list_size=${#list[@]}
        [ $list_size -eq 0 ] && return
        local lines=$max_lines
        local pb=-1
        local pe=-1
        if [ $list_size -gt $max_lines ]; then
            pb=$((y*max_lines/list_size))
            pe=$(((y+max_lines)*max_lines/list_size))
        fi

        list2=()
        local is_dir=0
        if [ -n "${git_mark[$focus]}" ]; then
            git_diff_list2 brief
        fi
        if [ ${#list2[@]} -eq 0 ]; then
            if [ -d "${list[$focus]}" ]; then
                IFS=$'\n' read -d "" -ra list2 < <(nshls "${list[$focus]}")
                is_dir=1
            elif [[ -n "$NSH_IMAGE_PREVIEW" && $(is_image "${list[$focus]}") == YES ]]; then
                IFS=$'\n' read -d "" -ra list2 < <($NSH_IMAGE_PREVIEW "${list[$focus]}" 2>&1)
            else
                local type="${mime[$focus]}"
                if [ -z "$type" ]; then
                    local fname="${list[$focus]}"
                    [[ -h "$fname" ]] && fname="$(readlink -f "$fname" 2>/dev/null || readlink "$fname" 2>/dev/null)"
                    type="$(file "$fname" 2>/dev/null)"
                    type="${type/#$fname:/}"
                    [[ -z "$type" && ! $(is_binary "$fname") ]] && type="text"
                    mime[$idx]="$type"
                fi
                if [[ $type == *ASCII* || $type == *UTF* || $type == *text* ]]; then
                    if [[ $1 == full ]]; then
                        while IFS=$'\n' read -r line; do
                            list2+=("$line")
                        done < <(($NSH_TEXT_PREVIEW "${list[$focus]}" 2>/dev/null || cat "${list[$focus]}") | tr -d '\r' 2>/dev/null | sed 's/\x1b\[[0-9;=?]\+[JKh]//g')
                    else
                        while IFS=$'\n' read -r line; do
                            list2+=("$line")
                        done < <(($NSH_TEXT_PREVIEW "${list[$focus]}" 2>/dev/null || cat "${list[$focus]}") | head -n "$max_lines" | tr -d '\r' 2>/dev/null | sed 's/\x1b\[[0-9;=?]\+[JKh]//g')
                    fi
                else
                    list2+=("$type")
                fi
            fi
        fi
        local list2_size=${#list2[@]}
        [[ $list2_size -gt $lines ]] && lines=$list2_size
        [[ $lines -gt $max_lines ]] && lines=$max_lines

        local w=$((COLUMNS-list_width))
        if [ $is_dir -eq 0 ]; then
            local i= && for ((i=0; i<$lines; i++)); do
                move_cursor "$(($i+2));$((list_width+1))"
                local sc="$NSH_COLOR_SC2" && [[ $i -ge $pb && $i -le $pe ]] && sc="$NSH_COLOR_SC1"
                printf '\e[0m %s \e[0m %s\e[K' "$sc" "${list2[$i]//$'\t'/    }"
            done
        else
            local i= && for ((i=0; i<$lines; i++)); do
                move_cursor "$(($i+2));$((list_width+1))"
                local f="${list[$focus]}/${list2[$i]}"
                local sc="$NSH_COLOR_SC2" && [[ $i -ge $pb && $i -le $pe ]] && sc="$NSH_COLOR_SC1"
                printf '\e[0m %s \e[0m ' "$sc"
                put_file_color "$f"
                printf '%s\e[0m\e[K' "${list2[$i]}"
            done
        fi
        move_cursor "$max_lines;9999"
    }
    git_diff_formatter() {
        local fn=
        local prev=
        local ln=0
        local started=
        while IFS=$'\n' read -r line; do
            if [[ $line == diff\ * || $line == index* ]]; then
                continue
            elif [[ $line == +++* || $line == ---* ]]; then
                [[ -n "$fn" || $line == */dev/null* ]] && continue
                [[ -n $started ]] && echo
                fn="$(echo ${line:6})" # to handle non-printable characters
                line=$'\e[36m'"$fn"$'\e[0m'
                [[ $1 == brief ]] && line=$'\e[1;4m'"$line"$'\e[0m'
            elif [[ $line == @@* ]]; then
                fn=
                ln="${line#* +}"
                ln="${ln%%,*}"
                ln="${ln%% *}"
                [[ $ln == 1 ]] && continue
                line="${line:3}"
                line="${line#* @@}"
                if [[ "$prev" == "$line" ]]; then
                    line='      ...'
                else
                    prev="$line"
                    line=$'\e[4m'"      $line"$'\e[0m'
                fi
            elif [[ $line == -* || $line == \ -* ]]; then
                line=$'\e[31m'"      $line"
            else
                [[ $line == +* || $line == \ +* ]] && line=$'\e[32m'"$line"
                [[ $ln -gt 0 ]] && line=$'\e[33m'$(printf "%5d%b %s" $ln $'\e[37m' "$line") && ((ln++)) 2>/dev/null
            fi
            echo "$line"
            started=yes
        done
    }
    git_diff_list2() {
        fn() {
            local w=$((COLUMNS-list_width-3))
            if [[ $1 != brief && -d "${list[$focus]}" ]]; then
                cd "${list[$focus]}"; command git diff --stat --stat-width=$w --color=always . 2>/dev/null; git diff . 2>/dev/null
            else
                command git diff --stat --stat-width=$w --color=always -- "${list[$focus]}" 2>/dev/null
                command git diff -- "${list[$focus]}" 2>/dev/null | tr -d '\r' 2>/dev/null
            fi
        }
        IFS=$'\n' read -d "" -ra list2 < <(fn $@ | git_diff_formatter)
    }
    redraw() {
        hide_cursor
        get_terminal_size
        draw_title
        hide_cursor
        draw_list
        local w=$list_width && [[ $focus -lt 0 ]] && w=$COLUMNS
        local i= && for ((i=${#list[@]}; i<$max_lines; i++)); do
            move_cursor $((i+2))
            printf '%*s' "$w" ' '
        done
        list2=()
        draw_list2
        [[ -z "$filter" ]] && draw_filestat
    }
    draw_shortcut() {
        printf "$NSH_COLOR_SH2\e[K"
        while [ $# -gt 1 ]; do
            printf "$NSH_COLOR_SH1 $1 $NSH_COLOR_SH2 $2 "
            shift
            shift
        done
        printf '\e[0m'
    }
    draw_filestat() {
        move_cursor $LINES
        if [[ ${#selected[@]} -gt 0 ]]; then
            local size=0
            local i= && for ((i=0; i<${#list[@]}; i++)); do
                [[ -n ${selected[$i]} && -n ${bytesizes[$i]} ]] && size=$((size+${bytesizes[$i]}))
            done
            size="$(get_hsize $size)"
            echo -e "$NSH_COLOR_TOP${#selected[@]} selected | $size | \033[K\033[0m"
            return
        fi
        [[ ${#list[@]} -eq 0 ]] && echo -e '\033[37;41mNo files\e[K\033[0m' && return
        [[ $focus -lt 0 ]] && echo -e "\033[30;47m${#list[@]}\033[K\033[0m" && return
        format_filestat() {
            local ftype=${1:0:1}
            case $ftype in
                '-') ftype='File';;
                'b') ftype='Block special file';;
                'c') ftype='Character special file';;
                'd') ftype='Directory';;
                'l') ftype='Symbolic link';;
                'n') ftype='Network file';;
                'p') ftype='FIFO';;
                's') ftype='Socket';;
            esac
            local permission=${1#?}
            local num_hard_links=$2
            local owner=$3
            local group=$4
            local size="$(print_number $5) bytes"
            #local mod_time="$6 $7"
            local mod_time="$(date -r "${list[$focus]}")"
            if [[ "${list[0]}" != .. ]]; then
                ftype="$((focus+1))/${#list[@]} | $ftype"
            else
                [[ $focus -gt 0 ]] && ftype="$focus/$((${#list[@]}-1)) | $ftype"
            fi
            [[ ${#selected[@]} -gt 0 ]] && ftype="${#selected[@]} selected | $ftype"
            if [ $# -gt 0 ]; then
                echo -e "$NSH_COLOR_TOP$ftype | $size | $permission | $num_hard_links | $owner | $group | $mod_time |\033[K\033[0m"
            else
                echo -e "$NSH_COLOR_TOP$ftype\033[K\033[0m"
            fi
        }
        format_filestat $(ls -dl "$LS_TIME_STYLE" "${list[$focus]}" 2>/dev/null)
        unset format_filestat
    }
    show_help() {
        if [[ $opened == yes ]]; then
            move_cursor $LINES; printf "$NSH_COLOR_SH1 Press any key...\e[K\e[0m"
            move_cursor 2
            enable_line_wrapping
        fi
        draw_help_line() {
            echo -e "$NSH_PROMPT $@\e[K"
        }
        draw_shortcut_ml() {
            local l0=0 l1=0
            local p=("$@")
            while [ $# -gt 0 ]; do
                [[ ${#1} -gt $l0 ]] && l0=${#1}
                [[ ${#2} -gt $l1 ]] && l1=${#2}
                shift; shift
            done
            local w=0 wl=$((l0+l1+4))
            local i= && for ((i=0; i<${#p[@]}; i+=2)); do
                [[ $((w+wl)) -ge $COLUMNS ]] && echo -e '\e[K' && w=0
                printf "$NSH_COLOR_SH1 %-*s " $l0 "${p[$i]}"
                printf "$NSH_COLOR_SH2 %-*s " $l1 "${p[$((i+1))]}"
                w=$((w+wl))
            done
            #echo -ne "\e[0m\e[K\n$NSH_PROMPT Press any key...\e[K"
            printf "\e[0m\e[K\n%*s\e[K" $COLUMNS ' ' | sed 's/ /-/g'
        }
        draw_help_line "nsh $version. designed by naranicca (naranicca@gmail.com)"
        echo -e "\e[K"
        if [[ $opened == yes ]]; then
            draw_help_line "nsh supports vim keybindings. Use $NSH_COLOR_SH1 j \e[0m and $NSH_COLOR_SH1 k \e[0m to move a cursor, and use $NSH_COLOR_SH1 h \e[0m and $NSH_COLOR_SH1 l \e[0m to jump between directories."
            draw_help_line "Press $NSH_COLOR_SH1 l \e[0m or $NSH_COLOR_SH1 TAB \e[0m on the file to see the preview.\e[K"
            draw_help_line "Press $NSH_COLOR_SH1 ENTER \e[0m to run the file, and $NSH_COLOR_SH1 SPACE \e[0m to select files.\e[K"
            draw_help_line "Press $NSH_COLOR_SH1 v \e[0m to edit the file using the default editor. To check the default editor, see NSH_DEFAULT_EDITOR in config.\e[K"
            draw_help_line "See the table of important keyboard shortcuts below:\e[K"
            local c='Less' && [[ $show_all -eq 0 ]] && c='All'
            draw_shortcut_ml F2 Rename F5 Copy F6 Move F7 Mkdir F10 Config g Git y Yank P Paste r Refresh i Rename I Touch dd Delete m Mark \' Bookmarks \; Commands Tab View \: Shell \/ Search \^G Git \. "Show$c" s Sort \~ Home 2 2048
            show_cursor
            get_key
            disable_line_wrapping
            update
        else
            draw_help_line "nsh's shell mode basically works just like BASH, but nsh provide more functionalities:"
            echo -e "    - Syntax highlight"
            echo -e "    - Auto-complete with $NSH_COLOR_SH1 TAB \e[0m key"
            echo -e "    - Automaticcaly help page of your command pops up under the cursor"
            echo -e "    - Show you the elapsed time and return value of your command"
            echo -e "    - Show system stat with very simple commands such as $NSH_COLOR_SH1 cpu \e[0m, $NSH_COLOR_SH1 mem \e[0m, $NSH_COLOR_SH1 gpu \e[0m, and $NSH_COLOR_SH1 disk \e[0m"
            echo -e "    - Advanced Search with $NSH_COLOR_SH1 ^F \e[0m"
            echo -e "    - Easy version of grep with $NSH_COLOR_SH1 ^G \e[0m"
            draw_help_line "To change preferences, type $NSH_COLOR_SH1 config \e[0m."
            draw_help_line "To go back to the pane mode, press $NSH_COLOR_SH1 ESC \e[0m."
            draw_help_line "To quit, press $NSH_COLOR_SH1 ^D \e[0m or type $NSH_COLOR_SH1 exit \e[0m."
        fi
    }
    dialog() {
        local mode=
        local redraw_on_exit=$opened
        if [[ $1 == --input ]]; then
            mode=$1
            shift
        elif [[ $1 == --notice ]]; then
            mode=$1
            shift
        elif [[ $1 == --no-redraw-on-exit ]]; then
            redraw_on_exit=no
            shift
        fi
        if [[ $# -eq 1 && $mode != --input ]]; then
            dialog $mode "$@" " OK "
            return $?
        fi
        get_terminal_size

        local w=$((COLUMNS*3/10))
        local h=4
        local str=()
        local btn=()
        local btnw=()
        local bidx=0
        local color="$NSH_COLOR_DLG"
        while IFS='\n' read line; do
            [[ $opened == yes ]] && line="$(strip_escape "$line")"
            local len=${#line}
            if [ $len -gt $((COLUMNS-4)) ]; then
                line="${line:0:$((COLUMNS-7))}..."
                len=$((COLUMNS-4))
            fi
            str+=("$line")
            if [ $((len+4)) -gt $w ]; then
                w=$((len+4))
            fi
            ((h++))
        done < <(echo -e "$1")
        shift
        local bw=0 && local bh=0
        while [ $# -gt 0 ]; do
            btn+=("$1")
            btnw+=(${#1}+2)
            bw=$((bw+${#1}+2))
            [[ $bw -gt $((COLUMNS-4)) ]] && bw=$((${#l}+2)) && ((bh++))
            shift
        done
        if [[ $opened == yes ]]; then
            h=$((h+bh))
            [[ $bh -gt 0 ]] && bw=$((COLUMNS-4))
            [[ $((bw+2)) -gt $w ]] && w=$((bw+2))
            local x=$(((COLUMNS-w)/2))
            local y=$(((LINES-h)/2+1))
            move_cursor "$y;$x"
            printf "$color  %-*s\e[0m" "$w" ' '
            ((y++))
            local line= && for line in "${str[@]}"; do
                move_cursor "$y;$x"
                printf "$color  %-*s\e[0m" "$w" "$line"
                ((y++))
            done
            local i= && for ((i=0; i<$((3+bh)); i++)); do
                move_cursor "$((y+i));$x"
                printf "$color  %-*s\e[0m" "$w" ' '
            done
            ((y++))
        else
            echo -ne "\r$NSH_PROMPT ${str[0]}\e[K"
            local i= && for ((i=1; i<${#str[@]}; i++)); do
                echo -ne "\n    ${str[$i]}\e[K"
            done
            [[ $mode != --input ]] && echo
            if [[ -z $mode ]]; then
                [[ ${#btn[@]} -eq 1 ]] && return 0
                i="$(menu "${btn[@]}" --return-idx)"
                return ${i:-255}
            fi
        fi
        if [[ $mode == --input ]]; then
            if [[ $opened == yes ]]; then
                move_cursor "$y;$((x+2))"
                printf "\e[0m%*s\e[0m" $((w-2)) ' '
                move_cursor "$y;$((x+2))"
                read_string "${btn[0]}"
                hide_cursor
                [[ $redraw_on_exit == yes ]] && redraw
            else
                read_string "${btn[0]}"
                echo
            fi
        elif [[ $mode == --notice ]]; then
            :
        else
            draw_buttons() {
                local j=$y && local r=0
                move_cursor "$j;$((x+w-bw))"
                local i= && for ((i=0; i<${#btn[@]}; i++)); do
                    r=$((r+${btnw[$i]}))
                    if [[ $r -gt $((COLUMNS-2)) ]]; then
                        ((j++)) && move_cursor "$j;$((x+w-bw))" && r=0
                    fi
                    if [ $i -eq $bidx ]; then
                        if [[ $1 == bold ]]; then
                            printf "\e[30;44m%s\e[0m" "[${btn[$i]}]"
                        else
                            printf "\e[37;44m%s\e[0m" "[${btn[$i]}]"
                        fi
                    else
                        printf "$color%s\e[0m" " ${btn[$i]} "
                    fi
                done
                move_cursor "1;1"
            }
            draw_buttons
            echo -ne '\007'

            while true; do
                get_key KEY
                case $KEY in
                    $'\e')
                        [[ $redraw_on_exit == yes ]] && redraw
                        return 255
                        ;;
                    $'\t'|'j'|'l')
                        ((bidx++))
                        [[ $bidx -ge ${#btn[@]} ]] && bidx=0
                        draw_buttons
                        ;;
                    'h'|'k')
                        ((bidx--))
                        if [ $bidx -lt 0 ]; then
                            bidx=$((${#btn[@]}-1))
                        fi
                        draw_buttons
                        ;;
                    $'\n'|' ')
                        draw_buttons bold
                        [[ $redraw_on_exit == yes ]] && redraw
                        return $bidx
                        ;;
                esac
            done
        fi
    }
    open_file() {
        local fname="${1/#$tilde\//$HOME/}"
        if [ -d "$fname" ]; then
            command cd "$fname"
            update
        else
            eval "[[ -e $fname ]] && echo" &>/dev/null || fname="\"$fname\""
            if [[ "$fname" == *.py ]]; then
                subshell "python $fname "
            elif [ -x "$1" ]; then
                subshell "./$fname "
            else
                subshell " $fname "
            fi
        fi
    }
    add_visited() {
        pwd >~/.cache/nsh/lastdir
        local n=${#visited[@]}
        local d="${1:-$PWD}" && [[ "$d" != */ ]] && d="$d/"
        if [[ $n -eq 0 || "${visited[$((n-1))]}" != "${d/#$HOME\//$tilde/}" ]]; then
            [[ $n -ge 100 ]] && visited=("${visited[@]:1:99}")
            visited+=("${d/#$HOME\//$tilde/}")
        fi
    }
    update_lsparam() {
        lsparam='-A'
        [[ $show_all -eq 0 && -n "$NSH_ITEMS_TO_HIDE"  ]] && lsparam="-I ${NSH_ITEMS_TO_HIDE//,/ -I }"
    }
    update_lsparam
    update() {
        add_visited
        dirs=()
        files=()
        list=()
        sideinfo=()
        bytesizes=()
        mime=()
        selected=()
        update_list2=
        filter=
        focus=0
        y=0
        side_info_idx=0
        if [ $git_mode -ne 0 ]; then
            #command cd "$(git_root)"
            :
        elif [[ $PWD && $PWD != / ]]; then
            list+=("..")
            focus=1
        else
            PWD=
        fi
        list_width=$((COLUMNS*3/10))
        list_files() {
            if [ $git_mode -eq 0 ]; then
                echo "$lsparam" $lssort | xargs ls
            else
                command git status --short 2>/dev/null | sed -e 's/^[ ]*[^ ]*\ //' -e 's/\/$//' | sed -e 's/^\"\(.*\)\"$/\1/'
            fi
        }
        if [[ -z $lssort ]]; then
            while read f; do
                local l=${#f}
                if [ -d "$f" ]; then
                    dirs+=("$f")
                else
                    files+=("$f")
                    l=$((l+6))
                fi
                [[ $((l+4)) -gt $list_width ]] && list_width=$((l+4))
            done < <(list_files | sort --ignore-case)
        else
            while read f; do
                local l=${#f}
                files+=("$f")
                [[ ! -d "$f" && $((l+10)) -gt $list_width ]] && list_width=$((l+10))
            done < <(list_files)
        fi
        list+=("${dirs[@]}" "${files[@]}")
        #[[ $git_mode -ne 0 && ${#list[@]} -eq 0 ]] && git_mode=0 && update
        [[ $focus -ge ${#list[@]} ]] && focus=0

        local i= && for ((i=0; i<${#list[@]}; i++)); do
            if [[ "$PWD/${list[$i]}" == $last_item ]]; then
                focus=$i
                [[ $focus -ge $max_lines ]] && y=$((focus-max_lines+1))
                break
            fi
        done

        update_git_stat
        redraw
        update_side_info
        last_item="$PWD"
    }
    update_side_info() {
        local tbeg=$(get_timestamp)
        local redraw=0
        local sort_by_size=0 && [[ $lssort == -S ]] && sort_by_size=1
        print_permission() {
            local p="$(ls -ld "$1")" && p="${p%% *}"
            printf "%s" "${p:1:10}"
        }
        [[ -z $NEXT_KEY ]] && get_key -t $get_key_eps NEXT_KEY
        [[ -n $NEXT_KEY ]] && return
        while true; do
            [[ $side_info_idx -ge ${#list[@]} ]] && break
            [[ $((side_info_idx%10)) -eq 9 && $(($(get_timestamp)-tbeg)) -ge 1000 ]] && break

            local f="${list[$side_info_idx]}"
            local size=
            bytesizes[$side_info_idx]=0
            if [ -h "$f" ]; then
                size="$(readlink -f "$f" 2>/dev/null || readlink "$f" 2>/dev/null)"
                eval "[[ -d \"$size\" ]] && size+=/"
                size="${size/#$HOME\//$tilde\/}"
            elif [ -d "$f" ]; then
                size=
                if [[ $sort_by_size -ne 0 && $f != .. ]]; then
                    size=$(du -sk "$f" 2>/dev/null | cut -f 1)
                    size=$((size*1024))
                    size=$((size+$(stat "$STAT_FSIZE_PARAM" "$f" 2>/dev/null)))
                    bytesizes[$side_info_idx]=$size
                    sideinfo[$side_info_idx]="$(get_hsize $size)"
                    local i=0 && [[ ${list[0]} == .. || ${list[0]} == ../ ]] && i=1
                    local i= && for (( ; i<$side_info_idx; i++)); do
                        if [[ $size -gt ${bytesizes[$i]} ]]; then
                            local t=("${git_mark[$side_info_idx]}" "${list[$side_info_idx]}" "${sideinfo[$side_info_idx]}" "${bytesizes[$side_info_idx]}")
                            local j= && for ((j=$side_info_idx; j>$i; j--)); do
                                git_mark[$j]="${git_mark[$((j-1))]}"
                                list[$j]="${list[$((j-1))]}"
                                sideinfo[$j]="${sideinfo[$((j-1))]}"
                                bytesizes[$j]="${bytesizes[$((j-1))]}"
                            done
                            git_mark[$i]="${t[0]}"
                            list[$i]="${t[1]}"
                            sideinfo[$i]="${t[2]}"
                            bytesizes[$i]="${t[3]}"
                            if [[ $focus == $side_info_idx ]]; then
                                focus=$i
                            elif [[ $focus -ge $i && $focus -lt $side_info_idx ]]; then
                                ((focus++))
                            fi
                            break
                        fi
                    done
                    size=${sideinfo[$side_info_idx]}
                fi
            elif [ -e "$f" ]; then
                size=$(stat "$STAT_FSIZE_PARAM" "$f" 2>/dev/null)
                bytesizes[$side_info_idx]=$size
                size="$(get_hsize $size)"
            fi
            #[[ ! -h "$f" ]] && size="$size $(print_permission "$f")"
            sideinfo[$side_info_idx]="$size"

            local l=$((${#f}+4+${#size}))
            [[ $l -gt $list_width ]] && list_width=$l
            [[ $list_width -gt $((COLUMNS*7/10)) ]] && list_width=$((COLUMNS*7/10))

            ((side_info_idx++))
            redraw=1
        done
        if [ $redraw -ne 0 ]; then
            redraw
            local i= && for ((i=${#list[@]}; i<$max_lines; i++)); do
                move_cursor $((i+2))
                printf '%*s' "$list_width" ' '
            done
        fi
    }
    update_git_stat() {
        subprompt=
        local old_git_stat="$git_stat"
        local old_git_mark="${git_mark[@]}"
        git_stat=
        git_stat_c=0
        git_mark=()
        local tmp=
        while read line; do
            case "$line" in
                *not\ a\ git*|*Not\ a\ git*|*Untracked*)
                    break
                    ;;
                *On\ branch*|*HEAD\ detached\ at*)
                    git_stat="${line##* }"
                    git_stat_c=42
                    ;;
                *rebase\ in\ progress*)
                    git_stat="rebase-->${line##* }"
                    git_stat_c=41
                    ;;
                *modified:*|*deleted:*|*new\ file:*|*renamed:*)
                    git_stat_c=101
                    if [[ "$line" == *modified:* ]]; then
                        fname="$(echo $line | sed 's/.*modified:[ ]*//')"
                        [[ $git_mode -eq 0 && -z "$filter" ]] && fname="${fname%%/*}"
                        tmp="$tmp;$fname"
                        [[ "$line" == *both\ modified:* ]] && tmp="$tmp*"
                    fi
                    #break
                    ;;
                *Your\ branch*ahead*)
                    line="${line% *}"
                    line="${line##* }"
                    git_stat="$git_stat +$line"
                    git_stat_c=43
                    ;;
                *Your\ branch\ is\ behind*)
                    line="${line#*by }"
                    line="${line%% *}"
                    git_stat="$git_stat -$line"
                    git_stat_c=43
                    ;;
                *all\ conflicts*fixed*git\ rebase\ --continue*)
                    git_stat="run 'git rebase --continue'"
                    ;;
                @@@ERROR@@@)
                    return
                    ;;
            esac
        done < <(LANGUAGE=en_US.UTF-8 command git status 2>&1 || echo @@@ERROR@@@)
        if [ -z "$git_stat" ]; then
            [[ $opened == yes ]] && local i= && for ((i=0; i<${#list[@]}; i++)); do
                git_mark[$i]=' '
                if [ -d "${list[$i]}" -a -d "${list[$i]}/.git/" ]; then
                    git_mark[$i]=$'\e[42m \e[0m'
                    (command cd "${list[$i]}"; command git diff --quiet 2>/dev/null)
                    if ! (command cd "${list[$i]}"; command git diff --quiet 2>/dev/null); then
                        git_mark[$i]=$'\e[41m \e[0m'
                    else
                        tmp="$(command cd "${list[$i]}"; LANGUAGE=en_US.UTF-8 command git status -sb | head -n 1)"
                        m='\[(ahead|behind) [0-9]+\]$'
                        [[ "$tmp" =~ $m ]] && git_mark[$i]=$'\e[43m \e[0m'
                    fi
                    tmp='found'
                fi
            done
            [[ -z $tmp ]] && git_mark=()
        else
            local s="$NSH_PROMPT_SEPARATOR" && [[ $opened == yes && -z "$nsh_mode$PRESTRING" ]] && s=
            git_stat="\e[30;${git_stat_c}m($git_stat)\e[0;$((git_stat_c-10))m$s\e[0m"
            if [[ $opened == yes ]]; then
                if [ -n "$tmp" -o $git_mode -ne 0 ]; then
                    local i= && for ((i=0; i<${#list[@]}; i++)); do
                        [[ "${list[$i]}" == .. ]] && continue
                        if [[ "$tmp;" == *";${list[$i]};"* ]]; then
                            git_mark[$i]=$'\e[41m \e[0m'
                        elif [[ "$tmp;" == *";${list[$i]}*;"* ]]; then
                            git_mark[$i]=$'\e[37;101m!\e[0m'
                        else
                            if [ $git_mode -ne 0 ]; then
                                [[ -e "${list[$i]}" ]] && git_mark[$i]='?' || git_mark[$i]=$'\e[31mD\e[0m'
                            else
                                git_mark[$i]=' '
                            fi
                        fi
                    done
                fi
                tmp= && while read line; do
                    tmp="$tmp;$line"
                done < <(command git ls-files --others --exclude-standard 2>/dev/null | awk -F / '{print $1}' | uniq)
                local i= && for ((i=0; i<${#list[@]}; i++)); do
                    if [[ "$tmp;" == *"${list[$i]};"* ]]; then
                        [[ ${#git_mark[@]} -eq 0 ]] && local n= && for ((n=0; n<${#list[@]}; n++)); do
                            [[ -z "${git_mark[$n]}" ]] && git_mark[$n]=' '
                        done
                        [[ "${git_mark[$i]}" == \  ]] && git_mark[$i]='?'
                    fi
                done
                [[ "${git_mark[@]}" != "$old_git_mark" ]] && redraw
            fi
        fi
        if [[ "$git_stat" == "$old_git_stat" ]]; then
            return 0
        else
            return 1
        fi
    }
    yank() {
        local path="$PWD"
        local ylist
        local listy_size
        local dirs
        local files
        local filter
        local yfocus
        local yy
        local ylast_item
        local op="$1"
        yopen() {
            path="$(command cd "$1/"; pwd)"
            move_cursor "1;$((list_width+1))"
            if [[ $op == cp ]]; then
                printf '\e[30;42m\e[K| Copy to: %s\e[0m' "$(print_filename "$path")"
            elif [[ $op == mv ]]; then
                printf '\e[30;42m\e[K| Move to: %s\e[0m' "$(print_filename "$path")"
            else
                printf '\e[30;42m\e[K| Bring to the left pane\e[0m'
            fi
            [[ $path == / ]] && path=
            dirs=()
            files=()
            yfocus=0
            yy=0
            ylist=() && [[ -n "$path" ]] && ylist=('../')
            if [[ -z "$filter" ]]; then
                while read line; do
                    ylist+=("$line")
                done < <(nshls "${path:-/}")
            else
                shopt -s nocaseglob
                while read line; do
                    if [[ -d "$path/$line" ]]; then
                        dirs+=("$line/")
                    else
                        files+=("$line")
                    fi
                done < <(cd "${path:-/}"; eval ls -Ad "$(fuzzy_word "$filter")" | sort --ignore-case)
                ylist=("${dirs[@]}" "${files[@]}")
            fi
            listy_size=${#ylist[@]}
            local idx=0
            local f= && for f in "${ylist[@]}"; do
                if [[ "$path/$f" == "$ylast_item" ]]; then
                    yfocus=$idx
                    break
                fi
                ((idx++))
            done
            ydraw
            ylast_item="$path/"
            add_visited "$path/"
        }
        ydraw() {
            local d=${#dirs[@]}
            local w=$((COLUMNS-list_width))
            [[ $((yy+max_lines)) -lt $yfocus ]] && yy=$((yfocus-max_lines+1))
            local i= && for ((i=0; i<$max_lines; i++)); do
                move_cursor "$((i+2));$((list_width+3))"
                if [ $((yy+i)) -lt $listy_size ]; then
                    local fmt="$(put_file_color "$path/${ylist[$((yy+i))]}")"
                    [[ $((yy+i)) -eq $yfocus ]] && fmt='\e[37;44m'
                    printf '%b%-*s\e[0m' "$fmt" "$w" " ${ylist[$((yy+i))]}"
                else
                    printf '%*s' "$w" ''
                fi
            done
        }
        draw_shortcut_yank() {
            move_cursor $LINES
            if [[ $op == cp ]]; then
                draw_shortcut "p" "Paste " "/" "Search" "I" "Mkdir " "L" "SymbolicLink" "~" "Home  " "//" "Root  " "'" "Jump  "
            elif [[ $op == mv ]]; then
                draw_shortcut "p" "Paste " "D" "Delete" "/" "Search" "I" "Mkdir " "~" "Home  " "//" "Root  " "'" "Jump  "
            else
                draw_shortcut SPACE Select "/" "Search" "I" "Mkdir " "~" "Home  " "//" "Root  " "'" "Jump  "
            fi
        }

        if [[ ${#selected[@]} -eq 0 && $op != bring ]]; then
            if [[ ${list[$focus]} != ".." ]]; then
                selected[$focus]="$PWD/${list[$focus]}"
            else
                dialog "No files or directories are selected."
                return
            fi
        fi
        last_item="$PWD/${list[$focus]}"
        local focus_bak=$focus
        focus=-1
        draw_list

        yopen "$PWD"
        draw_shortcut_yank
        while true; do
            get_key KEY
            case $KEY in
                $'\e')
                    if [ -z "$filter" ]; then
                        focus=$focus_bak
                        redraw
                        return
                    else
                        filter=
                        yopen "$path"
                    fi
                    ;;
                'j'|$'\e[B')
                    if [ $yfocus -lt $((listy_size-1)) ]; then
                        if [ $yfocus -eq $((yy+max_lines-1)) ]; then
                            ((yy++))
                        fi
                        ((yfocus++))
                        ydraw
                    fi
                    ;;
                'k'|$'\e[A')
                    if [ $yfocus -gt 0 ]; then
                        if [ $yfocus -eq $yy ]; then
                            ((yy--))
                        fi
                        ((yfocus--))
                        ydraw
                    fi
                    ;;
                'g')
                    yfocus=0
                    yy=0
                    ydraw
                    ;;
                'G')
                    yfocus=$((${#ylist[@]}-1))
                    yy=$((yfocus-max_lines+2))
                    if [ $yy -lt 0 ]; then yy=0; fi
                    ydraw
                    ;;
                'h'|$'\177'|$'\b')
                    if [[ $path != / ]]; then
                        filter=
                        yopen "$path/.."
                    fi
                    ;;
                $'\n'|'l'|' ')
                    if [[ $KEY != l && $op == bring ]]; then
                        dialog "$path/${ylist[$yfocus]}" Copy Move Symbolic\ Link
                        case $? in
                        0)
                            cp -r "$path/${ylist[$yfocus]}" "$PWD"
                            ;;
                        1)
                            mv "$path/${ylist[$yfocus]}" "$PWD"
                            ;;
                        2)
                            ln -s "$path/${ylist[$yfocus]}" "${ylist[yfocus]}"
                            ;;
                        esac
                        break
                    else
                        filter=
                        yopen "$path/${ylist[$yfocus]}"
                    fi
                    ;;
                '.')
                    [[ $show_all -eq 0 ]] && show_all=1 || show_all=0
                    update_lsparam
                    yopen "$path"
                    ;;
                '/')
                    while true; do
                        move_cursor $LINES
                        show_cursor
                        printf '\e[37;41m\e[K%s\e[0m' "/$filter"
                        get_key KEY
                        case $KEY in
                            $'\e')
                                break
                                ;;
                            $'\177'|$'\b')
                                filter=${filter%?}
                                yopen "$path"
                                ;;
                            '/')
                                if [ -z "$filter" ]; then
                                    yopen ''
                                    filter=
                                elif [ $listy_size -gt 0 -a -d "$path/${ylist[0]}" ]; then
                                    filter="${ylist[0]}/"
                                fi
                                ;;
                            $'\t')
                                local c="$(get_common_string "${ylist[@]}")"
                                filter="${c:-$filter}"
                                ;;
                            $'\n')
                                filter=
                                yopen "$path/${ylist[$yfocus]}"
                                break
                                ;;
                            [[:print:]])
                                local f= && for f in "$path"/*"$filter$KEY"*; do
                                    if [ -e "$f" ]; then
                                        filter="$filter$KEY"
                                        yopen "$path"
                                        break
                                    fi
                                done
                                ;;
                        esac
                        if [[ "$filter" == */ ]]; then
                            local p="$filter"
                            filter=
                            yopen "$path/$p"
                        fi
                    done
                    draw_shortcut_yank
                    hide_cursor
                    ;;
                '~')
                    filter=
                    yopen "$HOME"
                    ;;
                "'")
                    local addr="$(select_bookmark "$KEY")"
                    draw_list
                    yopen "${addr:-$path}"
                    ;;
                $'\e[18~'|I) # F7
                    dialog --input "Make a directory"
                    if [ -n $STRING ]; then
                        local err="$(mkdir -p "$path/$STRING" 2>&1)"
                        if [ -z "$err" ]; then
                            ylast_item="$path/$STRING/"
                            yopen "$path"
                        else
                            dialog "$err"
                        fi
                    fi
                    draw_shortcut_yank
                    ;;
                p)
                    if [[ $op == cp || $op == mv ]]; then
                        if [[ $op == 'mv' ]]; then
                            nshmv "${selected[@]/#$PWD\//}" "$path"
                        else
                            nshcp "${selected[@]/#$PWD\//}" "$path"
                        fi
                        #command cd "$path"
                        focus=$focus_bak
                        last_item="$path/${list[$focus]}"
                        update
                        return
                    fi
                    ;;
                d)
                    if [[ $op == cp || $op == mv ]]; then
                        if [[ $op == 'mv' ]]; then
                            if [[ ${#selected[@]} -eq 1 ]]; then
                                dialog --no-redraw-on-exit "Delete ${selected[@]/#$HOME/$tilde}?" " Yes " " No "
                            else
                                dialog --no-redraw-on-exit "Delete ${#selected[@]} files?" " Yes " " No "
                            fi
                            [[ $? -eq 0 ]] && local f= && for f in "${selected[@]}"; do
                                rm -rf "$f"
                            done
                        fi
                        update
                        return
                    fi
                    ;;
                L)
                    if [[ $op == ln ]]; then
                        last_item="$PWD/${ylist[$yfocus]%/}"
                        ln -s "$path/${ylist[$yfocus]}" "${last_item##*/}"
                        update
                        return
                    elif [[ $op == cp ]]; then
                        local f= && for f in "${selected[@]}"; do
                            f="${f%/}" && f="${f/$PWD\//}"
                            ln -s "$PWD/$f" "$path/$f"
                        done
                        update
                        return
                    fi
            esac
        done
        update
    }
    search_simple() {
        show_cursor
        local cmd="$filter"
        local cmd_prev=

        shopt -s nocaseglob

        while true; do
            while true; do
                move_cursor $LINES
                printf '\r\e[37;41m\e[K\r%s\e[0m' "/$cmd"
                if [[ -n "$NEXT_KEY" ]]; then
                    KEY="$NEXT_KEY"
                    NEXT_KEY=
                else
                    get_key -t 1 KEY
                fi
                [[ ! -z "$KEY" ]] && break
                draw_title
            done
            case $KEY in
                $'\177'|$'\b') # backspace
                    cmd=${cmd%?}
                    ;;
                $'\e') # ESC
                    hide_cursor
                    last_item="$PWD/${list[$focus]}"
                    if [ -n "$filter" ]; then
                        filter="$cmd"
                        cmd=""
                        break
                    else
                        update
                        return
                    fi
                    ;;
                $'\n') # enter
                    if [ ${#list[@]} -gt 0 ]; then
                        open_file "${list[$focus]}"
                    fi
                    break
                    ;;
                '/')
                    cmd="$cmd/"
                    if [[ "$cmd" == "/" ]]; then
                        command cd /
                    elif [ ${#list[@]} -gt 0 ]; then
                        command cd "${list[0]}"
                    fi
                    cmd=
                    cmd_prev=
                    ;;
                $'\t')
                    local c="$(get_common_string "${list[@]}")"
                    cmd="${c:-$cmd}"
                    if [ ${list[@]} -eq 1 -a -d "${list[0]}" ]; then
                        command cd "${list[0]}"
                        cmd=
                        cmd_prev=
                    fi
                    ;;
                *)
                    case $KEY in
                        [A-Z])
                            shopt -u nocaseglob
                            ;;
                    esac
                    cmd+="$KEY"
                    comp=()
                    move_cursor $LINES
                    printf '\r\e[37;41m\e[K\r%s\e[0m' "/$cmd"
                    ;;
            esac

            fill_dirs_files() {
                dirs=()
                files=()
                sideinfo=()
                while read f; do
                    if [ -d "$f" ]; then
                        dirs+=("$f")
                    elif [ -e "$f" ]; then
                        files+=("$f")
                    fi
                done < <(eval ls -Ad "$(fuzzy_word "$1")" | sort --ignore-case)
            }
            filter="$cmd"
            fill_dirs_files "$filter"
            list=("${dirs[@]}" "${files[@]}")

            if [ ${#list[@]} -eq 0 ]; then
                # revert
                fill_dirs_files "$cmd_prev"
                filter="$cmd_prev"
                list=("${dirs[@]}" "${files[@]}")
                cmd="$cmd_prev"
            else
                hide_cursor
                clear_screen
                draw_title
                focus=0
                y=0
                draw_list
                [[ ${#list[@]} -gt 0 ]] && draw_list2
                show_cursor
            fi
            cmd_prev="$cmd"
        done
        hide_cursor
        draw_title
        draw_filestat
    }
    search() {
        selected=()
        if [[ $opened != yes ]]; then
            nsh_main_loop search "$@" 1>&2
            local s= && for s in "${selected[@]}"; do
                [[ -n $s ]] && echo "$s"
            done
            nsh_mode=
            PRESTRING=
            STRING=
            return
        fi
        build_file_list() {
            fuzzy_out="$HOME/.cache/nsh/deep_search_result.$RANDOM"
            #find "${1:-.}" 2>/dev/null > "$fuzzy_out" &
            local l="${1:-.}"
            __build() {
                __find_posix() {
                    #find "$@" \( -type d -printf "%p\n" , ! -type d -print \) ||
                    while IFS=$'\n' read line; do
                        [[ -d "$line" ]] && line+=/
                        echo "${line/.\//}"
                    done < <(find "$@" 2>/dev/null | sed -e 's/\/\//\//g')
                }
                __find_posix "$l" > "$fuzzy_out"
            }
            read < <(__build & echo $!)
            fuzzy_idx=$REPLY
        }
        update_search_result() {
            sideinfo=()
            bytesizes=()
            git_mark=()

            local p="$(fuzzy_word "${1/#$tilde/$HOME/}")"
            p="${p//./\\.}"; p="${p//\*/.*}"
            local opt=-iE && LC_ALL=C bash -c "[[ $1 =~ [A-Z] ]] && echo" &>/dev/null && opt=-E
            local w="$1"
            __sort_results() {
                local cnt=0
                while read line; do
                    local dist=0
                    local cur="${w:0:1}"
                    local l="$line"
                    local i= && for ((i=1; i<${#w}; i++)); do
                        cur+="${w:$i:1}"
                        if ! grep $opt "$cur" <<< "$l" &>/dev/null; then
                            ((dist++))
                            l="${l#*$cur}"
                            cur="${cur:$((${#cur}-1))}"
                        fi
                    done
                    #local depth=0 && [[ $line == */* ]] && depth="${line//[^\/]/}" && depth=${#depth}
                    local depth="${#line}"
                    printf '%04d\t%04d\t%s\n' "$dist" "$depth" "$line"
                    ((cnt++))
                    if [[ $cnt -eq 30 ]]; then
                        get_key -t $get_key_eps cnt </dev/tty
                        if [[ -n $cnt ]]; then
                            [[ $cnt != $'\e' ]] && printf '!!!!\t!!!!\t!%b\n' "$cnt"
                            break
                        fi
                        cnt=0
                    fi
                done | sort -t $'\t' --ignore-case | awk -F$'\t' '{print $3}'
            }
            IFS=$'\n' read -d "" -ra list < <(grep $opt "$p\$" "$fuzzy_out" | __sort_results)
            [[ ! -e "${list[0]}" ]] && return

            draw_title
            focus=-1
            y=0
            side_info_idx=0
            redraw
        }

        PRESTRING='search '
        [[ $2 == --prestring ]] && PRESTRING="$3"
        cmd= && [[ -n $1 ]] && filter="$1"
        if [[ -n $filter ]]; then
            cmd="${filter%?}"
            NEXT_KEY="${filter:$((${#filter}-1))}"
            filter=
        fi
        focus=-1; update_git_stat; redraw
        local searchword=
        local location='!@#$%^&*()'
        local location_prev=
        local need_update=0
        local mtime=0

        shopt -s nocaseglob
        while true; do
            searchword="$cmd"
            location='./'
            if [[ $searchword == /* ]]; then
                location='/'
            elif [[ $searchword == \~/* ]]; then
                location="$HOME/"
                searchword="${searchword#*/}"
            elif [[ $searchword == ../* ]]; then
                location=
                while [[ $searchword == ../* ]]; do
                    location="$location../"
                    searchword="${searchword#*/}"
                done
            fi
            if [[ $location != $location_prev ]]; then
                location_prev="$location"
                if [[ $fuzzy_idx -ge 0 ]]; then
                    kill -9 $fuzzy_idx &>/dev/null
                    rm "$fuzzy_out" &>/dev/null
                    fuzzy_idx=0
                fi
                build_file_list "$location"
            fi
            while true; do
                move_cursor $LINES
                if [[ -z $filter ]]; then
                    printf '\r%b\e[K\r%s\e[0m' "$NSH_COLOR_TOP" ""
                else
                    if kill -0 $fuzzy_idx &>/dev/null || [[ $need_update -ne 0 ]]; then
                        printf '\r%b\e[K\r%s\e[0m' $'\e[37;41m' "Searching... ${#list[@]} results"
                    else
                        printf '\r%b\e[K\r%s\e[0m' "$NSH_COLOR_TOP" "Found ${#list[@]} results"
                    fi
                fi
                draw_title ; show_cursor
                [[ -z "$NEXT_KEY" ]] && get_key -t $get_key_eps NEXT_KEY
                if [[ -n "$NEXT_KEY" ]]; then
                    KEY="$NEXT_KEY"
                    NEXT_KEY=
                else
                    get_key -t 1 KEY
                fi
                [[ -n "$KEY" ]] && break

                if kill -0 $fuzzy_idx &>/dev/null; then need_update=1; fi
                if [[ $need_update -ne 0 && -n $filter ]]; then
                    update_search_result "$searchword"
                    need_update=0
                    [[ ! -e "${list[0]}" ]] && KEY="${list[0]#?}" && break
                    mtime="$t"
                else
                    update_side_info
                fi
            done
            case $KEY in
                $'\177'|$'\b') # backspace
                    cmd=${cmd%?}
                    searchword=${searchword%?}
                    ;;
                $'\e'|$'\t'|$'\n')
                    if [[ $KEY == $'\e' || ${#list[@]} -gt 0 ]]; then
                        [[ -z "$cmd" ]] && NEXT_KEY=$'\e' && break
                        list_width=$((COLUMNS/2))
                        side_info_idx=0
                        update_side_info
                        break
                    fi
                    ;;
                $'\e'*)
                    ;;
                '*')
                    [[ $cmd != \"* ]] && cmd="\"$cmd\""
                    ;;
                *)
                    cmd+="$KEY"
                    searchword+="$KEY"
                    ;;
            esac
            if [[ $cmd != $filter ]]; then
                filter="$cmd"
                STRING="$filter"
                if [[ -z $filter ]]; then
                    IFS=$'\n' read -d "" -ra list < <(nshls 2>/dev/null | sed -e 's/\/\//\//g' -e 's/^\.\///')
                else
                    # quick results
                    [[ -z $NEXT_KEY ]] && get_key -t $get_key_eps NEXT_KEY
                    [[ -z $NEXT_KEY ]] && IFS=$'\n' read -d "" -ra list < <(eval ls -d "$location$(fuzzy_word "$searchword")" 2>/dev/null | sed -e 's/\/\//\//g' -e 's/^\.\///')
                fi
                [[ -z $NEXT_KEY ]] && redraw
                need_update=1
            fi
        done
        hide_cursor
        focus=0 && redraw
        unset build_file_list
        unset update_search_result
        rm "$fuzzy_out"
    }
    subshell() {
        close_pane
        show_cursor
        disable_echo
        shopt -s nocaseglob

        local oneshot=0 && [[ $1 == --oneshot ]] && oneshot=1 && shift
        local running=1
        local first=1
        local margin
        local row0 col0
        local word last_word word_idx
        STRING="$@"
        if [[ -n "$STRING" ]]; then
            word="${STRING% *}" && word="${word##* }" && last_word="${word%?}"
            if [[ $STRING != *\  ]]; then
                NEXT_KEY=$'\n'
            else
                STRING="${STRING% }"
            fi
        fi
        local cand cand_color
        local fuzzy
        local fuzzy_idx=-1
        local fuzzy_out=
        local w_cand
        local x_cand
        local y_cand=0
        local c_cand=-1
        local t_cand=0
        local show_cand_delayed=
        local num_cand=0
        local usage
        local fname fname_old
        local cand_scroll=0

        reserve_margin() {
            local __m=$1 && [[ $# -eq 0 ]] && __m=${NSH_BOTTOM_MARGIN:-20%}
            [[ $__m == *% ]] && __m=$((LINES*${__m%?}/100))
            [[ $__m -ge $LINES ]] && __m=$((LINES-1))
            get_cursor_pos
            [[ $((ROW+__m)) -lt $LINES ]] && return
            local i= && for ((i=0; i<$__m; i++)); do echo; done
            row0=$((LINES-__m))
            move_cursor "$row0;$COL"
        }
        [[ -n $STRING ]] && reserve_margin "$(($(strlen "$INDENT$STRING")/COLUMNS+1))"
        fill_cand() {
            if [[ $1 != force ]]; then
                [[ -z "$NEXT_KEY" ]] && get_key -t $get_key_eps NEXT_KEY
                [[ -n "$NEXT_KEY" ]] && show_cand_delayed=FILL && return
            fi

            if [[ $word == $last_word && $1 != force ]]; then
                show_cand
                return
            fi

            local abword="${word/#$tilde\//$HOME/}"
            cand=() && cand_color=() && num_cand=0 && c_cand=-1
            if [[ $cursor -eq 0 ]]; then
                :
            elif [[ -z $word && ${STRING:0:$cursor} == *\' ]]; then
                cand=() && cand_color=() && local i= && for ((i=0; i<${#bookmarks[@]}; i++)); do
                    cand+=("${bookmarks[$i]#* }")
                    cand_color+=("$NSH_COLOR_DIR")
                done
                local i= && for ((i=$((${#visited[@]}-1)); i>=0; i--)); do
                    cand+=("${visited[$i]}")
                    cand_color+=("$NSH_COLOR_DIR")
                done
            elif [[ "$word" == \; ]]; then
                cand=() && cand_color=() && local i= && for ((i=$((${#history[@]}-1)); i>=0; i--)); do
                    cand+=("${history[$i]}")
                    cand_color+=("$NSH_COLOR_TXT")
                done
            else
                local param='-c'
                local str="${STRING:0:$cursor}" && [[ "$str" == sudo\ * ]] && str="${str#*\ }"
                str="${str#\"}"
                if [[ "$str" == cd\ * || "$str" == ls\ * ]]; then #|| $word == *\/ ]]; then
                    param='-d'
                elif [[ $word_idx -gt 0 || " $word " == *\/* ]]; then
                    param='-f'
                fi
                if [[ $word = -* ]]; then
                    cand=()
                elif [[ $word == \$* ]]; then
                    IFS=$'\n' read -d "" -ra cand < <(compgen -v "${word#?}" | sort -u)
                    cand=("${cand[@]/#/$}")
                    local v="$(eval echo \"$word\" 2>/dev/null)"
                    [[ -n $v ]] && cand=("> $v" "${cand[@]}")
                elif [[ $str == *\ * && ${str% *} == git ]]; then
                    fuzzy="$(fuzzy_word "$word")"
                    IFS=$'\n' read -d "" -ra cand < <(printf "%s\n" "${GIT_COMMANDS[@]}" | grep -iE "${fuzzy//\*/.*}" 2>/dev/null)
                elif [[ $param != *c* ]]; then
                    fuzzy="$(fuzzy_word "$word")"
                    fuzzy="${fuzzy/#$tilde\//$HOME/}"
                    if [[ $param == *d* ]]; then
                        if [[ "$word" == */ && -d "$abword" ]]; then
                            IFS=$'\n' read -d "" -ra cand < <(eval ls -d "$word*/" 2>/dev/null | sed 's#/$##')
                        else
                            [[ $word == */ ]] && fuzzy="${fuzzy%/*}/"
                            IFS=$'\n' read -d "" -ra cand < <(eval ls -d "$fuzzy*/" 2>/dev/null | sed 's#/$##')
                        fi
                    else
                        IFS=$'\n' read -d "" -ra cand < <(eval ls -d "$abword*" "$fuzzy*" 2>/dev/null | sort -u)
                    fi
                    if [[ "${STRING:0:$cursor}" =~ git[\ ]+[^\ ]+[\ ]+ ]]; then
                        IFS=$'\n' read -d "" -ra str < <(git_branch | grep -iE "${fuzzy//\*/.*}" 2>/dev/null)
                        [[ ${#str[@]} -gt 0 ]] && cand=("${str[@]}" "${cand[@]}")
                    fi
                else
                    fuzzy="$(fuzzy_word "$word")"
                    #IFS=$'\n' read -d "" -ra cand < <(compgen $param "$abword" | sort -u)
                    IFS=$'\n' read -d "" -ra cand < <(compgen $param | grep -iE "${fuzzy//\*/.*}" 2>/dev/null | sort -u)
                    if [[ -n $git_stat && $word == g* ]]; then
                        if [[ $word == gl ]]; then
                            cand=("git log ." "${cand[@]}")
                        elif [[ $word == gk ]]; then
                            cand=("git checkout" "${cand[@]}")
                        elif [[ $word == gp ]]; then
                            cand=("git pull origin $(git_branch_name)" "${cand[@]}")
                        elif [[ $word == gh ]]; then
                            cand=("git push origin $(git_branch_name)" "${cand[@]}")
                        elif [[ $word == gc ]]; then
                            cand=("git commit" "${cand[@]}")
                        elif [[ $word == gm ]]; then
                            cand=("git merge" "${cand[@]}")
                        fi
                    fi
                fi
            fi
            [[ -n $word && ${#cand[@]} -eq 0 ]] && cand=("> Ctrl+F for Deep Search")
            get_key -t $get_key_eps NEXT_KEY
            [[ $1 != force ]] && show_cand
        }
        hide_usage() {
            usage=()
            get_cursor_pos
            [[ $ROW -ge $LINES ]] && return
            local i= && for ((i=$ROW; i<$LINES; i++)); do
                printf '\e[K\n'
            done
            printf '\e[K'
            move_cursor "$ROW;$COL"
        }
        show_cand() {
            local size=$((${#cand[@]}+${#usage[@]}))
            [[ $size -eq 0 ]] && return
            [[ "${cand[0]}" == \>\ * ]] && size=$((size-1))
            if [[ $first != 0 && $size > 0 && -n $STRING ]]; then
                first=0
                reserve_margin
            fi
            num_cand=${#cand[@]}
            x_cand=0
            w_cand=0
            local abword="${word/#$tilde\//$HOME/}"
            last_word="$word"
            get_cursor_pos
            local path="${abword%/*}"
            local c
            if [ $num_cand -gt 0 ]; then
                local c= && for c in "${cand[@]}"; do
                    if [[ ! -z "$path" ]]; then
                        c1="${c/#$path\//}"
                    else
                        c1="${c/#$HOME\//$tilde/}"
                    fi
                    local w=${#c1}
                    [[ -d "$c" ]] && ((w++))
                    [[ $w -gt $w_cand ]] && w_cand=$w
                    [[ $word == *\** || $c != $path/* ]] && path=
                done
                local w="$abword"
                [[ ! -z "$path" ]] && w="${w/#$path\//}"
                x_cand=$((COL-${#w}))
                [[ $((x_cand+w_cand)) -gt $COLUMNS ]] && x_cand=$((COLUMNS-w_cand))
                [[ $x_cand < 0 ]] && x_cand=0
            fi

            disable_line_wrapping
            if [ $c_cand -ge 0 ]; then
                [[ $c_cand -lt $y_cand ]] && y_cand=$c_cand
                [[ $c_cand -gt $((y_cand+LINES-ROW-1)) ]] && y_cand=$((c_cand-LINES+ROW+1))
                [[ $c_cand == 0 && ${cand[0]} == \>\ * ]] && c_cand=1
            fi
            local margin_ch=' '
            w_cand=$((w_cand+${#margin_ch}))
            [[ $x_cand -ge ${#margin_ch} ]] && x_cand=$((x_cand-${#margin_ch}))
            local row= && for ((row=$((ROW+1)); row<=$LINES; row++)); do
                local i=$((y_cand+row-ROW-1))
                if [ $cand_scroll -eq 0 ]; then
                    move_cursor $row
                    if [[ ${#word} -gt 0 && $row -eq $LINES ]]; then
                        draw_shortcut 'F1' '--help' '^F' 'DeepSearch' 'PgDn' 'Expand' 'v' 'Edit'
                    elif [ $i -lt ${#usage[@]} ]; then
                        printf '\e[33m%s\e[0m\e[K' "${usage[$((i-y_cand))]}"
                    else
                        printf '\e[K'
                    fi
                fi
                if [ $i -lt ${#cand[@]} ]; then
                    local c="${cand[$i]}"
                    if [[ ! -z "$path" ]]; then
                        c="${c/#$path\//}"
                    else
                        c="${c/#$HOME\//$tilde/}"
                    fi
                    [[ -d "${cand[$i]}" && ${cand[$i]} != */ ]] && c+='/'
                    move_cursor "$row;$x_cand"
                    local dlen=0
                    if [ $i -eq $c_cand ]; then
                        printf "\e[37;44m$margin_ch"
                    elif [[ $i == 0 && $c == \>\ * ]]; then
                        c="${c#* }$margin_ch"
                        dlen=2
                        printf $'\e'"[31;${NSH_COLOR_BKG}m$margin_ch> \e[33m"
                    else
                        printf $'\e'"[${NSH_COLOR_BKG}m$margin_ch"
                        if [[ "$c" == */* ]]; then
                            local d="${c%/*}/"
                            if [[ -d "$d" ]]; then
                                dlen=${#d}
                                printf '%b%s' "$NSH_COLOR_DIR" "$d"
                                c="${c##*/}"
                            fi
                        fi
                        [[ -z "${cand_color[$i]}" ]] && cand_color[$i]="$(put_file_color "${cand[$i]}")"
                        printf '%b' "${cand_color[$i]}"
                    fi
                    local l=$((w_cand-dlen)) && [[ $l -gt $COLUMNS ]] && l=$COLUMNS
                    printf "%-*s\e[0m" "$l" "$c"
                fi
            done
            move_cursor "$ROW;$COL"
            enable_line_wrapping
            show_cand_delayed=
            [[ -z $NEXT_KEY ]] && get_key -t $get_key_eps NEXT_KEY
        }
        update_usage() {
            local str="$STRING"
            [[ $STRING == type\ * ]] && return
            [[ $STRING == python\ * ]] && str="${STRING#* }"
            fname="${str%% *}"
            fname="${fname/#$tilde\//$HOME/}"
            if [[ $str == git\ *\ * ]]; then
                fname=($str)
                fname="$(echo "${fname[@]:0:2}")"
            fi
            if [[ $1 == help ]]; then
                usage=()
                if [[ -n "$STRING" ]]; then
                    IFS=$'\n' read -d "" -ra usage < <(eval $STRING --help 2>&1)
                    usage+=(' ')
                    fname_old="$fname"
                fi
            elif [[ $fname != $fname_old ]]; then
                usage=()
                #type "$fname" &>/dev/null
                [[ $fname == "vi" || $fname == exit || $fname == echo ]] && return
                if is_binary $(which "$fname" 2>/dev/null) &>/dev/null; then
                    IFS=$'\n' read -d "" -ra usage < <("$(which "$fname")" --help 2>&1)
                elif [[ $fname == git\ * ]]; then
                    IFS=$'\n' read -d "" -ra usage < <("$fname" --help 2>&1 | tail -n +4)
                elif [ -f "$fname" ]; then
                    if [[ $STRING == python\ * ]]; then
                        format_argparse() {
                            local line=
                            local def=
                            local nargs= && [[ "$@" == *nargs* ]] && nargs='...'
                            while [ $# -gt 0 ]; do
                                if [[ $1 == -* ]]; then
                                    if [[ -n "$line" ]]; then
                                        line="$line "
                                    elif [[ $1 == --* ]]; then
                                        line='    '
                                    fi
                                    line="$line$1"
                                else
                                    if [[ $1 == *=* ]]; then
                                        [[ $1 == choices* ]] && line="${line%?} ${1##*=}"
                                        [[ $1 == default* ]] && def="${1%,}" && def=$' \e[37m('"${def#*=})"
                                        if [[ $1 == help* ]]; then
                                            line="${line%,}"
                                            #[[ ${#line} -lt 20 ]] && line="$line$(printf '%*s' $((20-${#line})) ' ')"
                                            line="$line$def"$'\e[0m'"  ${1##*=}" && def=
                                        fi
                                    else
                                        [[ -n "$line" ]] && line="$line "
                                        line="$line$1"
                                    fi
                                    [[ -n "$nargs" ]] && line="${line%,}..." && nargs=
                                fi
                                shift
                            done
                            printf '%s' "${line%,}$def"
                        }
                        local mand=
                        while IFS='\n' read line; do
                            line="${line#*(}"
                            line="${line%)*}"
                            local u="$(format_argparse $line)"
                            if [[ $line == *required=True* && $line != *=store_true* ]]; then
                                local m="$(strip_escape "$u")"
                                local a0="$(sed -e 's/^[ ]*//' -e 's/[ ,].*$//' <<< "$m")"
                                local a1="$(sed -e 's/^.*-//' -e 's/[ ,].*$//' <<< "$a0")"
                                mand="$mand $a0 ${a1^^}"
                            fi
                            usage+=("$u")
                        done < <(grep add_argument "$fname" 2>/dev/null | tr -d '\r' 2>/dev/null | sed -e "s/'//g" -e 's/"//g' -e "s/.*add_argument[^(]*(//")
                        local _t="Usage: python $fname$mand"
                        local i= && for i in "${usage[@]}"; do
                            [[ $i == -* || "$i" == \ \ \ \ --* ]] && _t="$_t [option]..." && break
                        done
                        for i in "${usage[@]}"; do
                            [[ $i != -* && $i != \ * ]] && _t="$_t ${i%% *}"
                        done
                        [[ ${#usage[@]} -gt 0 ]] && usage=("$_t" "" "${usage[@]}")
                    else
                        IFS=$'\n' read -d "" -ra usage < <(head -n $((LINES-ROW)) "$fname" 2>/dev/null | tr -d '\r' 2>/dev/null | sed -e "s/\t/    /g")
                    fi
                fi
                usage+=(' ')
                fname_old="$fname"
            fi
        }
        select_history() {
            if [ ${#history[@]} -gt 0 ]; then
                echo
                local tmp="$STRING"
                local f="+ $(draw_shortcut z Zoom \/ Search)"
                if [[ -n "$STRING" ]]; then
                    STRING="$(printf '%s\n' "${history[@]}" | grep "$STRING" | menu -r --popup -i 9999 --key $'\b\177' "echo \"\$1 \"$'\\b'" --key ' l'$'\e[C' 'echo "$1 "' --searchable --footer "$f")"
                else
                    STRING="$(printf '%s\n' "${history[@]}" | menu -r --popup -i 9999 --key $'\b\177' "echo \"\$1 \"$'\\b'" --key ' l'$'\e[C' 'echo "$1 "' --searchable --footer "$f")"
                fi
                STRING="$(strip_escape "$STRING")"
                [[ -z "$STRING" ]] && STRING="$tmp"
                [[ "$STRING" != "$tmp" && "$STRING" != *\  && $STRING != *$'\b' ]] && NEXT_KEY=$'\n'
                [[ $STRING == *$'\b' ]] && STRING="${STRING%? *}"
                cursor=${#STRING}
                row0=$(($(get_cursor_row)-1))
                update_usage
                print_prompt
                fill_cand
            fi
        }
        select_all() {
            [[ ${#cand[@]} -eq 0 ]] && return
            local pre="${STRING:0:$cursor}" && pre="${pre%$word}"
            local post="${STRING:$cursor}"
            local c= && for c in "${cand[@]}"; do
                [[ $c == \>* ]] && continue
                pre="$pre$c "
            done
            STRING="$pre$post"
            cursor="${#pre}"
            word=
            print_prompt
            cand_scroll=0
            c_cand=-1
            fill_cand
        }
        nsheval() {
            [[ $# -gt 0 ]] && STRING="$@"
            [[ "$STRING" == \~ ]] && STRING="cd ~"
            [[ "$STRING" =~ ^[\.]+$ ]] && STRING="${STRING#?}" && STRING="${STRING//./../}"
            [[ -d "$STRING" ]] && STRING="cd $STRING"
            [[ -z $STRING ]] && return
            [[ $STRING == cd\ * ]] && STRING="$STRING && ls $LS_COLOR_PARAM && pwd >~/.cache/nsh/lastdir"
            [[ $STRING == git\ checkout\ * && $(get_num_words $STRING) -eq 3 && $STRING == *\ origin/* ]] && STRING="git checkout ${STRING##*origin/}"
            if [[ $STRING == exit ]]; then
                quit
            elif [[ $STRING == jobs ]]; then
                __i="$(jobs -l | menu)"
                [[ -n "$__i" ]] && __i="${__i#[}" && fg "%${__i%%]*}"
            elif [[ $STRING == ps ]]; then
                local param="-o pid,command"
                while true; do
                    local pid=$(ps -x $param | menu --header - --footer "+ $(draw_shortcut ENTER Kill a ShowAll \/ Search z Zoom q Quit)" --searchable --popup --key a 'echo all' | awk '{print $1}')
                    if [[ $pid == all ]]; then
                        if [[ $param == *\ -a\ * ]]; then
                            param="-o pid,command"
                        else
                            param="-a -o pid,user,command"
                        fi
                    else
                        [[ -z $pid ]] && break
                        kill -9 $pid
                    fi
                done
            elif [[ "$STRING" == git\ remote\ add ]]; then
                echo -en "$NSH_PROMPT Repository name: "
                read_string 'upstream'
                [[ -z $STRING ]] && echo '^C' && return
                local reponame="$STRING" && echo
                echo -en "$NSH_PROMPT Repository address: "
                read_string
                [[ -z $STRING ]] && echo '^C' && return
                local repoaddr="$STRING" && echo
                git remote add "$reponame" "$repoaddr"
                echo
                git remote -v
            elif [[ $STRING == help || $STRING == \? ]]; then
                show_help
            elif [[ $STRING == 2048 ]]; then
                play2048
            else
                NSH_EXIT_CODE=0
                local __temp="$STRING"
                local __row=$(get_cursor_row)

                enable_echo
                local tbeg=$(get_timestamp)
                trap 'abcd &>/dev/null' INT
                if [[ $STRING == *\ \& ]]; then
                    set -m
                else
                    set +m # ctrl-z does not work
                fi
                [[ -n $STRINGBUF ]] && STRING="$STRINGBUF"$'\n'"$STRING"
                eval "$STRING 2>&1"$'\n'"$(echo NSH_EXIT_CODE=\$?)" #2>/dev/null
                if [[ $? -ne 0 || -z "$__temp" ]]; then
                    if [[ -z $STRINGBUF ]]; then
                        move_cursor $row0 && echo -ne "$subprompt"
                        hide_usage
                        echo
                        echo -ne "$NSH_PROMPT "
                        syntax_highlight "$STRING"
                        echo
                    else
                        move_cursor $__row
                        echo -ne '\e[K'
                    fi
                    STRINGBUF="$STRING"
                    return
                fi
                STRINGBUF=
                local report=
                [[ $NSH_EXIT_CODE -ne 0 ]] && report+="\033[31m[$NSH_EXIT_CODE returned]"
                local telapsed=$((($(get_timestamp)-tbeg+500)/1000))
                [[ $(get_cursor_col) -gt 1 ]] && echo $'\e[0;30;43m'"\\n"$'\e[0m'
                if [[ "$NSH_DO_NOT_SHOW_ELAPSED_TIME," != *"${STRING%% *},"* ]]; then
                    if [ $telapsed -gt 0 ]; then
                        local h=$((telapsed/3600))
                        local m=$(((telapsed%3600)/60))
                        local s=$((telapsed%60))
                        report+=$'\e[33m['
                        [[ $h > 0 ]] && report+="${h}h "
                        [[ $h > 0 || $m > 0 ]] && report+="${m}m "
                        report+="${s}s elapsed]"
                    fi
                fi
                [[ ! -z $report ]] && echo -e "$report\033[0m"
                if [[ $NSH_EXIT_CODE -ne 0 && $STRING == git\ * ]]; then
                    git_fix_conflicts "Conflicts were found. Fix them and commit the changes" # if there are no conflicts, this doesn't do anything
                fi
                set -m
                trap - INT
                #unset NSH_EXIT_CODE
                disable_echo
                [[ "$STRING" == cd\ * ]] && add_visited
            fi
        }

        #NEXT_KEY=
        while [ $running -ne 0 ]; do
            first=1
            last_word=
            fname_old=
            cursor=${#STRING}
            [[ -z $NEXT_KEY && $STRING == \ * ]] && cursor=0
            cand=()
            usage=()

            get_terminal_size
            row0=$(get_cursor_row)
            update_git_stat
            print_prompt

            while true; do
                if [ ! -z "$NEXT_KEY" ]; then
                    KEY="$NEXT_KEY"
                    NEXT_KEY=
                elif [[ $fuzzy_idx -ge 0 || -n $show_cand_delayed ]]; then
                    get_key -t 1 KEY
                    if [[ -z "$KEY" ]]; then
                        fill_cand force
                        show_cand
                        continue
                    fi
                elif [[ ! -z $git_stat ]]; then
                    get_key -t 10 KEY
                    if [[ -z "$KEY" ]]; then
                        update_git_stat || print_prompt
                        show_cand
                        continue
                    fi
                else
                    get_key KEY
                    NEXT_KEY=
                fi
                case $KEY in
                    $'\e[11~'|$'\eOP') # F1
                        update_usage help
                        cand=() && show_cand
                        ;;
                    $'\01')
                        select_all
                        ;;
                    $'\04')
                        if [[ -n $STRINGBUF ]]; then
                            STRINGBUF=
                            STRING=
                            subprompt=
                            echo '^C'
                            break
                        elif [[ -z "$STRING" ]]; then
                            STRING='exit'
                            NEXT_KEY=$'\n'
                        fi
                        ;;
                    $'\07')
                        STRING='nshgrep'
                        NEXT_KEY=$'\n'
                        ;;
                    $'\e')
                        if [ ${#cand[@]} -gt 0 ]; then
                            print_prompt
                            cand=() && show_cand
                        elif [ ${#STRING} -eq 0 ]; then
                            move_cursor $row0
                            running=0
                            break
                        else
                            INDENT=
                            STRING=
                            STRING_SUGGEST=
                            cursor=0
                            cand=() && usage=()
                            local i= && for ((i=$((row0+1)); i<=$LINES; i++)); do
                                move_cursor $i; printf '\e[K'
                            done
                            move_cursor $row0
                            print_prompt
                        fi
                        ;;
                    $'\n')
                        cursor=${#STRING}
                        local prefix="$(date +%F\ %T)"
                        [[ $NSH_PROMPT_SHOW_TIME -eq 0 ]] && prefix=
                        cursor=-1
                        subprompt= && print_prompt "$prefix"
                        hide_usage
                        echo
                        STRING="$(echo "$STRING" | sed -e 's/^[ ]*//' -e 's/[ ]*$//')"
                        local history_size=${#history[@]}
                        if [[ ! -z $STRING ]] && [[ $history_size -eq 0 || "${history[$((history_size-1))]}" != "$STRING" ]]; then
                            [[ "$STRING" != exit ]] && history+=("$STRING")
                        fi
                        local li=$((${#history[@]}-1))
                        if [[ $li -ge 3 && "${history[$li]}" == "${history[$((li-2))]}" && "${history[$((li-1))]}" == "${history[$((li-3))]}" ]]; then
                            history=("${history[@]:0:$((${#history[@]}-2))}")
                        fi
                        if [ ${#history[@]} -ge $HISTSIZE ]; then
                            history=("${history[@]:$((${#history[@]}-HISTSIZE))}")
                            history_idx=$((history_idx-${#history[@]}+HISTSIZE))
                            [[ $history_idx -lt 0 ]] && history_idx=0
                        fi
                        nsheval
                        col0=$(get_cursor_col)
                        break
                        ;;
                    $'\177'|$'\b')
                        if [ $cursor -gt 0 ]; then
                            STRING="${STRING:0:$((cursor-1))}${STRING:$cursor}"
                            ((cursor--))
                            update_usage
                            print_prompt
                            #fill_cand
                            cand=(); show_cand_delayed=FILL
                        elif [[ -n $INDENT ]]; then
                            INDENT="$(printf "%*s" $(((${#INDENT}-1)/4*4)) '')"
                            print_prompt
                        fi
                        ;;
                    $'\e[3~') # Del
                        if [ ${#STRING} -gt 0 ]; then
                            STRING="${STRING:0:$cursor}${STRING:$((cursor+1))}"
                            update_usage
                            print_prompt
                        fi
                        ;;
                    $'\e[A') # Up
                        select_history
                        ;;
                    $'\e[B') # Down
                        NEXT_KEY=$'\t'
                        ;;
                    $'\e[C') # right
                        if [ $cursor -lt ${#STRING} ]; then
                            cursor=$((cursor+1))
                            print_prompt
                            fill_cand
                        elif [[ -n $STRING_SUGGEST ]]; then
                            STRING="$STRING_SUGGEST"
                            cursor=${#STRING}
                            print_prompt
                        fi
                        ;;
                    $'\e[D') # left
                        if [ $cursor -gt 0 ]; then
                            ((cursor--))
                            print_prompt
                            fill_cand
                        fi
                        ;;
                    $'\e[1~'|$'\e[H') # home
                        cursor=0
                        print_prompt
                        fill_cand
                        ;;
                    $'\e[4~'|$'\e[F') # end
                        cursor=${#STRING}
                        update_usage
                        print_prompt
                        fill_cand
                        ;;
                    $'\e[6~') # page down
                        while [ $row0 -gt 1 ]; do
                            move_cursor "$LINES;9999"
                            printf '\n'
                            ((row0--))
                        done
                        print_prompt
                        fill_cand
                        ;;
                    $'\t')
                        fill_cand force
                        num_cand=${#cand[@]}
                        c_cand=0 && [[ $num_cand -gt 1 ]] && show_cand
                        local pre="${STRING:0:$cursor}" && pre="${pre%$word}"
                        local post="${STRING:$cursor}"
                        [[ $pre == "$STRING " ]] && pre=''
                        if [[ $cursor == 0 ]]; then
                            INDENT="$INDENT    "
                            print_prompt
                        elif [ $num_cand -eq 0 ]; then
                            show_cand
                        else
                            local idx0=0
                            [[ ${cand[0]} == \>\ * ]] && idx0=1
                            if [[ $num_cand -eq $((1+idx0)) && $fuzzy_idx < 0 ]]; then
                                local c="${cand[$idx0]}"
                                if [[ -e "$c" ]]; then
                                    pre="${pre%\"}"
                                    eval "[[ -e $c ]] && echo" &>/dev/null || c="\"$c\""
                                fi
                                STRING="$pre${c/#$HOME\//$tilde/}"
                                [[ ! -d "${cand[$idx0]}" ]] && STRING+=' '
                                [[ -d "${cand[$idx0]}" ]] && STRING+='/'
                                cursor=${#STRING}
                                STRING="$STRING$post"
                            else
                                if [ $idx0 -eq 0 ]; then
                                    local common="$(get_common_string "${cand[@]}")"
                                    common="${common/#$HOME\//$tilde/}"
                                    if [[ "$common" == "$word"* ]]; then
                                        STRING="$pre$common"
                                        cursor=${#STRING}
                                        STRING="$STRING$post"
                                    fi
                                fi
                                c_cand=$idx0
                            fi
                            update_usage
                            print_prompt
                            if [[ $num_cand -gt 1 ]]; then
                                fill_cand
                                cand_scroll=1
                                hide_cursor
                                if [ $c_cand -ge 0 -a $c_cand -lt $num_cand ]; then
                                    while true; do
                                        get_key KEY
                                        case $KEY in
                                            $'\e')
                                                c_cand=-1
                                                show_cand
                                                NEXT_KEY=
                                                break
                                                ;;
                                            $'\177'|$'\b')
                                                c_cand=-1
                                                show_cand
                                                NEXT_KEY=$'\b'
                                                break
                                                ;;
                                            $'\01')
                                                select_all
                                                NEXT_KEY=
                                                break
                                                ;;
                                            $'\n'|'l'|' ')
                                                local c="${cand[$c_cand]}"
                                                local d=' ' && [[ -d "$c" ]] && c="${c%/}" && d='/'
                                                if [[ -e "$c" ]]; then
                                                    pre="${pre%\"}"
                                                    if ! eval "[[ -e $c ]] && echo" &>/dev/null; then
                                                        [[ $d == / ]] && c="$c$d" && d=' '
                                                        c="\"$c\""
                                                    fi
                                                fi
                                                STRING="$pre${c/#$HOME\//$tilde/}$d"
                                                cursor=${#STRING}
                                                STRING="$STRING$post"
                                                cand_scroll=0
                                                last_word=aaaaaaaaaaa
                                                update_usage
                                                print_prompt
                                                fill_cand
                                                NEXT_KEY=
                                                [[ $KEY == $'\n' ]] && { NEXT_KEY=$KEY; break; }
                                                [[ $word == \.\/ ]] && break
                                                [[ $num_cand == 1 && ${cand[0]} == \>\ * ]] && break
                                                [[ $d == \  ]] && break
                                                c_cand=0
                                                show_cand
                                                hide_cursor
                                                NEXT_KEY=
                                                ;;
                                            'j'|$'\e[B')
                                                if [ $c_cand -lt $((num_cand-1)) ]; then
                                                    ((c_cand++))
                                                    show_cand
                                                fi
                                                ;;
                                            'k'|$'\e[A')
                                                if [ $c_cand -gt 0 ]; then
                                                    ((c_cand--))
                                                    show_cand
                                                fi
                                                ;;
                                            'g')
                                                c_cand=0
                                                show_cand
                                                ;;
                                            'G')
                                                c_cand=$((num_cand-1))
                                                show_cand
                                                ;;
                                            'v')
                                                "$NSH_DEFAULT_EDITOR" "${cand[$c_cand]}"
                                                ;;
                                        esac
                                    done
                                fi
                            fi
                            cand_scroll=0
                            c_cand=-1
                            show_cursor
                        fi
                        ;;
                    [[:print:]])
                        STRING="${STRING:0:$cursor}$KEY${STRING:$cursor}"
                        ((cursor++))
                        [[ $KEY == \  ]] && update_usage
                        print_prompt
                        [[ -z $NEXT_KEY ]] && t_cand=$(get_timestamp)
                        show_cand_delayed=FILL
                        ;;
                    $'\06') # ctrl+F
                        local pre="${STRING:0:$cursor}" && pre="${pre%$word}"
                        local post="${STRING:$cursor}"
                        STRING=
                        local cur="$(pwd)/"
                        local res=
                        while read line; do
                            [[ -n $line ]] && res+=" \"${line/#$cur/}\""
                        done < <(search "$word" --prestring "$pre")
                        STRING="${pre% }$res$post "
                        cursor="${#STRING}"
                        print_prompt
                        fill_cand
                        ;;
                esac
                KEY=
                [[ -z $NEXT_KEY ]] && get_key -t 0.1 NEXT_KEY
            done
            INDENT=
            STRING=
            STRING_SUGGEST=
            subprompt=
            [[ $oneshot -ne 0 && $NSH_EXIT_CODE -eq 0 ]] && break
        done

        hide_cursor
        open_pane
        update
    }
    scroll_down() {
        local i= && for ((i=0; i<${1:-1}; i++)); do
            if [ $focus -lt $((${#list[@]}-1)) ]; then
                ((focus++))
                if [ $((focus-y)) -eq $max_lines ]; then
                    ((y++))
                    move_cursor $((LINES-1))
                    draw_line $((focus-1))
                    move_cursor "$((LINES-1));9999"
                else
                    move_cursor $((focus-y+1))
                    draw_line $((focus-1))
                fi
                printf '\n'
                draw_line $focus
            else
                break
            fi
        done
        [[ -z $NEXT_KEY ]] && get_key -t $get_key_eps NEXT_KEY
        [[ -z $NEXT_KEY ]] && list2=() && draw_list2
        [[ ${#selected[@]} -eq 0 ]] && draw_filestat
    }
    scroll_up() {
        local i= && for ((i=0; i<${1:-1}; i++)); do
            if [ $focus -gt 0 ]; then
                ((focus--))
                if [ $focus -lt $y ]; then
                    move_cursor 2
                    printf '\e[1L' #insert a line above the cursor
                    ((y--))
                    draw_line $y
                else
                    move_cursor $((focus-y+2))
                    draw_line $focus
                fi
                echo
                draw_line $((focus+1))
            else
                break
            fi
        done
        [[ -z $NEXT_KEY ]] && get_key -t $get_key_eps NEXT_KEY
        [[ -z $NEXT_KEY ]] && list2=() && draw_list2
        [[ ${#selected[@]} -eq 0 ]] && draw_filestat
    }
    select_bookmark() {
        KEY= && [[ $1 == \' ]] && get_key -t 1 KEY
        if [ -z "$KEY" ]; then
            move_cursor 2 >&2
            local f="$(printf '%*s' $COLUMNS '')" && f="${f//?/-}"
            local i="$( (for ((i=0; i<${#bookmarks[@]}; i++)); do
                local val="${bookmarks[$i]#* }"
                echo "${bookmarks[$i]%% *}   ${val/#$HOME\//$tilde\/}"
            done; for ((i=$((${#visited[@]}-1)); i>=0; i--)); do
                echo "    ${visited[$i]}"
            done) | menu -h $max_lines --popup --header 'Key  Address' --footer "$(draw_shortcut / Search r Reload v Edit)" --searchable --key r 'echo \!reload' --key v 'echo \!edit')"
            if [[ $opened == yes ]]; then
                disable_line_wrapping >&2
                hide_cursor >&2
            fi
            if [[ $i == \!* ]]; then
                echo "$i"
            elif [[ -n "$i" ]]; then
                echo "${i#?}" | sed 's/^\ *//'
            fi
        else
            local i= && for ((i=0; i<${#bookmarks[@]}; i++)); do
                [[ "${bookmarks[$i]}" == "$KEY"\ * ]] && echo "${bookmarks[$i]#* }" && return
            done
        fi
    }

    nsh_main_loop() {
        if [[ $1 == -h || $1 == --help || $1 == help ]]; then
            echo "Usage: $0 [option]"
            echo
            echo "Options:"
            echo "  -h, --help, help   show this help message and exit"
            echo "  -v, -V, --version  show version and exit"
            echo "  search [WORD]      start in search mode"
            echo "  shell              start in shell mode"
            return
        elif [[ $1 == -v || $1 == -V || $1 == --version ]]; then
            echo "nsh $version"
            return
        elif [[ $1 == shell ]]; then
            subshell
        fi
        open_pane
        if [[ -e "$1" ]]; then
            command cd "$1" &>/dev/null
            update
        elif [[ $1 == search ]]; then
            nsh_mode=search
            if [[ $# -gt 1 ]]; then
                shift
                search "$@"
            else
                update
                NEXT_KEY=/
            fi
        else
            update
        fi
        while true; do
            while true; do
                if [[ -n "$NEXT_KEY" ]]; then
                    KEY="$NEXT_KEY"
                    NEXT_KEY=
                else
                    get_key -t 1 KEY
                fi
                [[ ! -z "$KEY" ]] && break
                draw_title
                update_side_info
                if [[ -n "$update_list2" ]]; then
                    draw_list2
                    draw_filestat
                fi
            done
            case $KEY in
                $'\e') # ESC
                    if [[ ${#selected[@]} -gt 0 ]]; then
                        selected=()
                        redraw
                    elif [[ -n "$filter" || -n $PRESTRING ]]; then
                        filter=
                        PRESTRING=
                        last_item="$PWD/${list[$focus]}"
                        [[ $nsh_mode == search ]] && break
                        update
                    elif [ $git_mode -ne 0 ]; then
                        git_mode=0
                        last_item="$PWD/${list[$focus]}"
                        update
                    elif [[ -n $nsh_mode ]]; then
                        break
                    else
                        draw_filestat
                    fi
                    ;;
                $'\n') # enter
                    NEXT_KEY=
                    PRESTRING=
                    last_item="$PWD/${list[$focus]}"
                    if [[ -z $nsh_mode && ${#selected[@]} -eq 0 ]]; then
                        open_file "${list[$focus]}"
                    else
                        [[ ${#selected[@]} -eq 0 ]] && selected[$focus]="$PWD/${list[$focus]}"
                        if [[ -n $nsh_mode ]]; then
                            break
                        else
                            local sel=
                            local i= && for ((i=0; i<${#list[@]}; i++)); do
                                [[ -n ${selected[$i]} ]] && sel="$sel \"${list[$i]}\""
                            done
                            subshell " ${sel# } "
                        fi
                    fi
                    ;;
                ' ') # space
                    if [ -z "${selected[$focus]}" ]; then
                        if [[ ${list[$focus]} != ".." ]]; then
                            selected[$focus]="$PWD/${list[$focus]}"
                        fi
                    else
                        selected[$focus]=''
                    fi
                    if [ $focus -lt $((${#list[@]}-1)) ]; then
                        ((focus++))
                        if [ $((focus-y)) -eq $max_lines ]; then
                            ((y++))
                            move_cursor $((LINES-1))
                            draw_line $((focus-1))
                            move_cursor "$((LINES-1));9999"
                        else
                            move_cursor $((focus-y+1))
                            draw_line $((focus-1))
                        fi
                        printf '\n'
                        draw_line $focus
                        list2=()
                        draw_list2
                        draw_filestat
                    else
                        draw_list
                    fi
                    ;;
                'j'|$'\e[B') # down
                    scroll_down
                    ;;
                'k'|$'\e[A') # up
                    scroll_up
                    ;;
                $'\01')
                    selected=()
                    local i= && for ((i=0; i<${#list[@]}; i++)); do
                        f="${list[$i]}"
                        [[ $f != '..' ]] && selected[$i]="$PWD/$f"
                    done
                    redraw
                    ;;
                $'\04')
                    scroll_down $((max_lines/2))
                    ;;
                $'\06'|'/')
                    PRESTRING=
                    STRING=
                    search
                    ;;
                $'\07')
                    subshell --oneshot nshgrep
                    ;;
                $'\25')
                    scroll_up $((max_lines/2))
                    ;;
                'g'|$'\e[1~'|$'\e[H')
                    move_cursor $LINES
                    local sc=()
                    [[ -n "$git_stat" ]] && sc+=('p' 'pull  ' 'h' 'push  ' 'k' 'checkout' 'm' 'merge ' 'r' 'rebase' 'f' 'fetch ' 'c' 'commit' 'u' 'revert' 'l' 'log   ' 'b' 'blame ' 'a' 'add   ' 'd' 'rm    ')
                    [[ -n "$git_stat" && $git_mode -eq 0 ]] && sc+=('s' 'Show modified only')
                    [[ ${#sc[@]} -eq 0 ]] && sc+=('g' 'GoTop')
                    draw_shortcut "${sc[@]}"
                    NEXT_KEY=
                    get_key -t 1 KEY
                    [[ -z "$KEY" ]] && KEY=':'
                    local sel= && local i= && for ((i=0; i<${#list[@]}; i++)); do
                        [[ -n ${selected[$i]} ]] && sel="$sel \"${list[$i]}\""
                    done
                    [[ -z "$sel" ]] && sel=' .'
                    git_op() {
                        case "$1" in
                        p|pull)
                            dialog "git: pulll from $(git_branch_name)?" && subshell "nshgit pull"
                            ;;
                        h|push)
                            dialog "git: push to $(git_branch_name)?" && subshell "nshgit push"
                            ;;
                        'create a branch')
                            subshell 'git checkout -b '
                            ;;
                        'list branches')
                            subshell 'nshgit branch'
                            ;;
                        k|checkout|'switch branch')
                            subshell 'nshgit branch'
                            ;;
                        m|'merge a branch')
                            NEXT_KEY=$'\t'
                            subshell 'git merge '
                            ;;
                        r|rebase|'move this branch to another')
                            NEXT_KEY=$'\t'
                            subshell 'git rebase -i '
                            ;;
                        'delete a branch')
                            NEXT_KEY=$'\t'
                            subshell 'git branch -d '
                            ;;
                        f|fetch)
                            subshell 'git fetch '
                            ;;
                        'add a remote repository')
                            subshell 'git remote add'
                            ;;
                        c|commit)
                            subshell "git commit$sel"
                            ;;
                        u|revert)
                            subshell --oneshot nshgit revert "$sel"
                            ;;
                        l|log)
                            subshell --oneshot "nshgit log$sel"
                            ;;
                        b|blame)
                            if [[ ${#selected[@]} -eq 1 ]]; then
                                subshell --oneshot "nshgit blame$sel"
                            elif [[ ${#selected[@]} -eq 0 ]]; then
                                subshell --oneshot "nshgit blame \"${list[$focus]}\""
                            else
                                dialog 'Select one file'
                            fi
                            ;;
                        a|add|'add files')
                            if [[ ${#selected[@]} -eq 1 ]]; then
                                dialog "add$sel to repo?" && subshell "nshgit add$sel"
                            else
                                dialog "add ${#selected[@]} files to repo?" && subshell "nshgit add$sel"
                            fi
                            ;;
                        d|delete|rm|'delete files')
                            if [[ ${#selected[@]} -eq 1 ]]; then
                                dialog "delete$sel from repo?" && subshell "git rm$sel"
                            else
                                dialog "delete ${#selected[@]} files from repo?" && subshell "git rm$sel"
                            fi
                            ;;
                        s|'show modified files only')
                            git_mode=1
                            update
                            ;;
                        'fix conflicts')
                            subshell 'git_fix_conflicts'
                            ;;
                        i)
                            subshell --oneshot 'nshgit'
                            ;;
                        esac
                    }
                    case $KEY in
                        'g')
                            if [ $focus -ne 0 ]; then
                                focus=0
                                y=0
                                redraw
                            fi
                            ;;
                        ':')
                            if [ -n "$git_stat" ]; then
                                move_cursor 2
                                local f="$(printf '%*s' $COLUMNS ' ')" && f="${f//\ /-}"
                                i=$(menu "Key   Command" 'p    pull' 'h    push' '     create a branch' '     delete a branch' '     list branches' 'k    switch branch' 'm    merge a branch' 'r    move this branch to another' 'f    fetch' '     add a remote repository' 'c    commit' 'u    revert' 'a    add files' 'd    delete files' 'l    log' 'b    blame' 's    show modified files only' '     fix conflicts' 'i    nshgit' -h $max_lines --popup --header - --footer $f)
                                disable_line_wrapping
                                hide_cursor
                                [[ -n "$i" ]] && git_op "${i#?????}" || redraw
                            fi
                            ;;
                        *)
                            git_op $KEY
                            ;;
                    esac
                    draw_filestat
                    ;;
                'G'|$'\e[4~'|$'\e[F')
                    focus=$((${#list[@]}-1))
                    [[ $((y+max_lines)) -lt ${#list[@]} ]] && y=$((${#list[@]}-max_lines))
                    redraw
                    ;;
                'h'|$'\e[D')
                    [[ ! -z "$PWD" ]] && git_mode=0 && open_file ..
                    ;;
                'v')
                    close_pane
                    "$NSH_DEFAULT_EDITOR"  "${list[$focus]}"
                    open_pane
                    update_git_stat
                    redraw
                    ;;
                $'\e[3~') # rm
                    local implicit=0
                    if [ ${#selected[@]} -eq 0 ]; then
                        if [[ "${list[$focus]}" == '..' ]]; then
                            dialog "cannot delete ../"
                        else
                            selected[$focus]="$PWD/${list[$focus]}"
                            implicit=1
                        fi
                    fi
                    cnt=${#selected[@]}
                    if [ $cnt -gt 0 ]; then
                        if [ $cnt -eq 1 ]; then
                            local f= && for f in "${selected[@]}"; do
                                dialog "Delete $(basename "$f")?" " Yes " " No "
                            done
                        else
                            dialog "Delete $cnt files?" " Yes " " No "
                        fi
                        if [ $? -eq 0 ]; then
                            while [[ "${selected[$focus]}" == "$PWD/${list[$focus]}" ]]; do
                                ((focus--))
                                if [ $focus -eq 0 ]; then
                                    break
                                fi
                            done
                            last_item="$PWD/${list[$focus]}"
                            local idx=0
                            local cnt=${#selected[@]}
                            local f= && for f in "${selected[@]}"; do
                                dialog --notice "Deleting...\n$f"
                                rm -rf "$f"
                                ((idx++))
                            done
                            update
                        else
                            [[ $implicit -ne 0 ]] && selected=()
                        fi
                    fi
                    ;;
                'y'|$'\e[15~') # cp
                    yank cp
                    ;;
                'd'|$'\e[17~')
                    yank mv
                    ;;
                P)
                    yank bring
                    ;;
                $'\e[12~'|$'\eOQ'|'i') # F2
                    f="${list[$focus]}"
                    if [[ ${#f} > 0 && "$f" != ".." ]]; then
                        while true; do
                            move_cursor $((focus-y+2))
                            printf '%*s' "$list_width" ' '
                            local c=2 && [[ ${#git_mark[@]} -gt 0 ]] && ((c++))
                            move_cursor "$((focus-y+2));$c"
                            read_string "$f"
                            hide_cursor
                            if [[ -n $STRING && "$f" != "$STRING" ]]; then
                                if [[ -e "$STRING" ]]; then
                                    dialog "$STRING\nalready exists"
                                else
                                    command mv "$f" "$STRING"
                                    last_item="$PWD/$STRING"
                                    update
                                    break
                                fi
                            else
                                draw_list
                                break
                            fi
                        done
                    fi
                    ;;
                I) # make a directory or a file
                    dialog --input 'Make a directory or a file'
                    if [[ -n $STRING ]]; then
                        if [[ $STRING == */ ]]; then
                            local err="$(mkdir "$STRING" 2>&1)"
                        else
                            local err="$(touch "$STRING" 2>&1)"
                        fi
                        [[ -n $err ]] && dialog "$err"
                        last_item="$PWD/${STRING%/}"
                        update
                    fi
                    ;;
                'r') # refresh
                    last_item="$PWD/${list[$focus]}"
                    update
                    ;;
                's') # sort
                    if [[ -z $filter ]]; then
                        dialog "Sort option:" "Name" "Time" "Size"
                        __x=$?
                        __y="$lssort"
                        if [[ $__x == 0 ]]; then
                            lssort=
                        elif [[ $__x == 1 ]]; then
                            lssort=-t
                        elif [[ $__x == 2 ]]; then
                            lssort=-S
                        fi
                        [[ "$lssort" != "$__y" ]] && update
                    fi
                    ;;
                'o')
                    if [[ -d "${list[$focus]}" ]]; then
                        git_mode=0
                        open_file "${list[$focus]}"
                    elif [[ ${list[$focus]} == */* ]]; then
                        git_mode=0
                        last_item="$PWD/${list[$focus]}"
                        open_file "${list[$focus]%/*}"
                    elif [[ -h "${list[$focus]}" ]]; then
                        git_mode=0
                        d="${sideinfo[$focus]/#$tilde/$HOME}"
                        open_file "${d%/*}"
                    elif [[ $git_mode -ne 0 ]]; then
                        git_mode=0
                        update
                    fi
                    ;;
                $'\t'|'l'|$'\e[C')
                    __x=$list_width
                    __y=0
                    __v=1
                    __g=1
                    list2=()
                    if [[ ! -d "${list[$focus]}" || $KEY == $'\t' ]]; then
                        git_diff_list2
                    fi
                    if [ ${#list2[@]} -eq 0 ]; then
                        __g=0
                        if [ -d "${list[$focus]}" ]; then
                            if [[ $PRESTRING == search\  ]]; then
                                # terminate search mode
                                filter=
                                STRING=
                                PRESTRING=
                            fi
                            open_file "${list[$focus]}"
                            __v=0
                        else
                            draw_list2 full
                        fi
                    fi
                    if [[ $__v -ne 0 && -n "$NSH_IMAGE_PREVIEW" && $(is_image "${list[$focus]}") == YES ]]; then
                        local i= && for ((i=0; i<=$max_lines; i++)); do
                            move_cursor $((i+2))
                            printf "${list2[$i]}\e[K"
                        done
                        move_cursor 1; printf "${list[$focus]}\e[K"
                        get_key
                        redraw
                    elif [ $__v -ne 0 ]; then
                        draw_title show_filename
                        list_width=8
                        local ll=${#list2[@]} && ll=${#ll}
                        local sel0=0
                        local sel1=-1
                        local sel=
                        local shortcuts=(' v' 'Edit ')
                        [[ "${list[$focus]}" == */* ]] && shortcuts+=(' o' 'Open Directory')
                        [[ $__g -ne 0 ]] && shortcuts+=('Tab' 'Next change' ' c' 'git commit ' ' u' 'git revert ')
                        move_cursor $LINES
                        echo -n '       |' && draw_shortcut "${shortcuts[@]}"
                        while true; do
                            __y_max=$((${#list2[@]}-max_lines-0))
                            [[ $__y -gt $__y_max ]] && __y=$__y_max
                            [[ $__y -lt 0 ]] && __y=0
                            local i= && for ((i=0; i<$max_lines; i++)); do
                                move_cursor "$(($i+2));$list_width"
                                local ln=$((i+__y))
                                local str="${list2[$ln]//$'\t'/    }"
                                if [ $__g -eq 0 ]; then
                                    [[ $ln -lt ${#list2[@]} ]] && printf '\e[0m| \e[33m%*s\e[0m %s\e[K' $ll $((ln+1)) "$str" || printf '\e[0m|\e[K'
                                else
                                    local c= && [[ -n $sel && $ln -ge $sel0 && $ln -le $sel1 ]] && c=$'\e'"[$NSH_COLOR_BKG;1m"
                                    [[ $__g -ne 0 && $str == @* ]] && c=$'\e[1;4m'
                                    [[ $ln -lt ${#list2[@]} ]] && printf '\e[0m| %s\e[K' "$c$str" || printf '\e[0m|\e[K'
                                fi
                            done
                            while true; do
                                [[ -z "$NEXT_KEY" ]] && get_key -t 1 KEY || KEY="$NEXT_KEY"
                                NEXT_KEY=
                                [[ -n $KEY ]] && break
                                draw_title show_filename
                            done
                            case $KEY in
                                $'\e'|'h'|'q')
                                    [[ -z $sel ]] && break
                                    sel=
                                    ;;
                                'j'|$'\e[B') ((__y++));;
                                'k'|$'\e[A') ((__y--));;
                                $'\04') __y=$((__y+(max_lines/2)));;
                                $'\25') __y=$((__y-(max_lines/2)));;
                                'g') __y=0;;
                                'G') __y=$__y_max;;
                                'o')
                                    local dir="${list[$focus]%/*}"
                                    if [[ -d "$dir" ]]; then
                                        last_item="$PWD/${list[$focus]}"
                                        open_file "$dir"
                                        break
                                    fi
                                    ;;
                                'v')
                                    if [ -z $sel ]; then
                                        if [ -d "${list[$focus]}" ]; then
                                            open_file "${list[$focus]}"
                                        else
                                            close_pane
                                            "$NSH_DEFAULT_EDITOR" "${list[$focus]}"
                                            open_pane
                                            update_git_stat
                                            redraw
                                        fi
                                    else
                                        local i= && for ((i=$sel0; i>=0; i--)); do
                                            if [[ "${list2[$i]}" == @* ]]; then
                                                local fname="${list2[$i]}" && fname="${fname#?}"
                                                [[ -d "${list[$focus]}" ]] && fname="$(cd ${list[$focus]} && git_root)/$fname"
                                                close_pane
                                                "$NSH_DEFAULT_EDITOR" "$fname"
                                                open_pane
                                                update_git_stat
                                                redraw
                                                break
                                            fi
                                        done
                                    fi
                                    break
                                    ;;
                                'c'|'u')
                                    local fname="${list[$focus]}"
                                    if [ -n $sel ]; then
                                        local i= && for ((i=$sel0; i>=0; i--)); do
                                        [[ ${list2[$i]} == @* ]] && fname="${list2[$i]}" && fname="$(git_root)/${fname#?}"
                                        done
                                    fi
                                    last_item="$PWD/${list[$focus]}"
                                    if [[ $KEY == c ]]; then
                                        dialog "Commit\n$fname" "OK" "Cancel" && subshell "git commit $fname" && update && break
                                    else
                                        if [ -z $sel ]; then
                                            dialog "Revert\n$fname" "OK" "Cancel" && subshell "git checkout -- $fname" && update && break
                                        else
                                            local tmpfile=~/.config/nsh/tmpfile
                                            cp "$fname" "$tmpfile"
                                            local ln="${list2[$((sel0-1))]}"
                                            if [[ "$ln" == $'\e[33m'* ]]; then
                                                ln="$(strip_escape "$ln" | sed 's/^[ ]*//')" && ln="${ln%% *}"
                                            else
                                                ln=0
                                            fi
                                            (head -n "$ln" "$fname" 2>/dev/null) > "$tmpfile"
                                            local i= && for ((i=$sel0; i<=$sel1; i++)); do
                                                local l="${list2[$i]}"
                                                if [[ "$l" == $'\e[31m'* ]]; then
                                                    echo "${l#*-}" >> "$tmpfile"
                                                fi
                                            done
                                            if [[ $((sel1+1)) -lt ${#list2[@]} ]]; then
                                                ln="${list2[$((sel1+1))]}"
                                                if [[ $ln == $'\e[33m'* ]]; then
                                                    ln="$(strip_escape "$ln" | sed 's/^[ ]*//')" && ln="${ln%% *}"
                                                    if [[ $ln -gt 1 ]]; then
                                                        sed "1,$((ln-1))d" "$fname" >> "$tmpfile"
                                                    else
                                                        cat "$fname" >> "$tmpfile"
                                                    fi
                                                fi
                                            fi
                                            mv "$tmpfile" "$fname"
                                            sel= && sel1=$((sel0-1))
                                            git_diff_list2
                                            NEXT_KEY=$'\t'
                                            [[ ${#list2[@]} -eq 0 ]] && update_git_stat && break
                                        fi
                                    fi
                                    ;;
                                $'\t')
                                    sel= && for ((sel0=$((sel1+1)); sel0<${#list2[@]}; sel0++)); do
                                        if [[ ${list2[$sel0]} == $'\e[31m'* || ${list2[$sel0]} == *$'\e[33m'*$'\e[32m+'* ]]; then
                                            sel=- && for ((sel1=$sel0; sel1<${#list2[@]}; sel1++)); do
                                                [[ ${list2[$sel1]} != $'\e[31m'* && ${list2[$sel1]} != *$'\e[33m'*$'\e[32m+'* ]] && ((sel1--)) && break
                                            done
                                            break
                                        fi
                                    done
                                    if [ -z $sel ]; then
                                        sel0=-1 && sel1=-1 && sel=
                                    else
                                        [[ $((sel1-__y)) -ge $max_lines ]] && __y=$((sel1-max_lines+1))
                                        [[ $((sel0-__y)) -le 0 ]] && __y=$sel0
                                    fi
                                    ;;
                                $'\e[Z')
                                    sel= && for ((sel1=$((sel0-1)); sel1>=0; sel1--)); do
                                        if [[ ${list2[$sel1]} == $'\e[31m'* || ${list2[$sel1]} == *$'\e[33m'*$'\e[32m+'* ]]; then
                                            sel=- && for ((sel0=$sel1; sel0>=0; sel0--)); do
                                                [[ ${list2[$sel0]} != $'\e[31m'* && ${list2[$sel0]} != *$'\e[33m'*$'\e[32m+'* ]] && ((sel0++)) && break
                                            done
                                            break
                                        fi
                                    done
                                    if [ -z $sel ]; then
                                        sel0=${#list2[@]} && sel1=${#list2[@]} && sel=
                                    else
                                        [[ $((sel1-__y)) -ge $max_lines ]] && __y=$((sel1-max_lines+1))
                                        [[ $((sel0-__y)) -le 0 ]] && __y=$sel0
                                    fi
                                    ;;
                            esac
                        done
                        list_width=$__x
                        redraw
                    fi
                    ;;
                $'\e[18~'|I) # F7
                    dialog --input "Make a directory"
                    if [ -n $STRING ]; then
                        local err="$(mkdir -p $STRING 2>&1)"
                        [[ ! -z "$err" ]] && dialog "$err"
                        last_item="$PWD/$STRING"
                        update
                    fi
                    ;;
                $'\e[21~') # F10
                    close_pane
                    config
                    open_pane
                    redraw
                    ;;
                '~')
                    open_file ~
                    ;;
                '-'|'H')
                    [[ -d "$OLDPWD" ]] && open_file "$OLDPWD"
                    ;;
                ':')
                    # user command
                    if [[ -z $nsh_mode ]]; then
                        last_item="$PWD/${list[$focus]}"
                        local tmp=
                        local i= && for ((i=0; i<${#list[@]}; i++)); do
                            [[ -n ${selected[$i]} ]] && tmp="$tmp\"${list[$i]}\" " && [[ -d "${list[$i]}" ]] && tmp="${tmp%??}/\" "
                        done
                        [[ -n "$tmp" ]] && tmp=" $tmp"
                        NEXT_KEY=$'\e[H'
                        subshell "$tmp"
                    fi
                    ;;
                ';')
                    last_item="$PWD/${list[$focus]}"
                    move_cursor 2 >&2
                    STRING="$(printf '%s\n' "${history[@]}" | menu -r -h $max_lines --popup -i 9999 --key ' l' 'echo "$1 "' --searchable --footer "+ $(draw_shortcut / Search)")"
                    disable_line_wrapping >&2
                    hide_cursor >&2
                    if [ -n "$STRING" ]; then
                        subshell "$STRING"
                    else
                        redraw
                    fi
                    ;;
                '2')
                    move_cursor "$((LINES/2-2));$((COLUMNS/2-13))"
                    play2048; hide_cursor
                    redraw
                    ;;
                $'\e[11~'|$'\eOP'|'?')
                    show_help
                    ;;
                'm')
                    get_key KEY
                    if [[ $KEY =~ [a-zA-Z0-9] ]]; then
                        local addr="$(pwd)" && [[ "$addr" != */ ]] && addr="$addr/"
                        local i= && for ((i=0; i<${#bookmarks[@]}; i++)); do
                            if [[ "${bookmarks[$i]}" == "$KEY"* ]]; then
                                local t="${bookmarks[$i]/$KEY\ /}"
                                dialog "$KEY was already assigned for\n  ${t/$HOME\//$tilde\/}" Replace Cancel || KEY=
                                break
                            fi
                        done
                        if [[ -n "$KEY" ]]; then
                            bookmarks[$i]="$KEY $addr"
                            i=0 && while read line; do
                                bookmarks[$i]="$line" && ((i++))
                            done < <(printf '%s\n' "${bookmarks[@]}" | sort)
                            printf '%s\n' "${bookmarks[@]}" > ~/.config/nsh/bookmarks
                            dialog "Bookmarked:\n[$KEY] $addr"
                        fi
                    else
                        dialog "This KEY cannot be used for bookmarks"
                    fi
                    ;;
                "'"|'"')
                    local addr="$(select_bookmark "$KEY")"
                    if [[ "$addr" == \!reload ]]; then
                        load_bookmarks
                        NEXT_KEY=\"
                    elif [[ "$addr" == \!edit ]]; then
                        close_pane
                        "$NSH_DEFAULT_EDITOR" ~/.config/nsh/bookmarks
                        load_bookmarks
                        open_pane
                        update
                    elif [[ -n "$addr" ]]; then
                        open_file "$addr" || redraw
                    else
                        redraw
                    fi
                    ;;
                'q')
                    quit 0
                    ;;
                '.')
                    [[ $show_all -eq 0 ]] && show_all=1 || show_all=0
                    update_lsparam
                    last_item="$PWD/${list[$focus]}"
                    update
                    ;;
                *)
                    echo -ne '\007'
                    ;;
            esac
        done
        if [[ -z $nsh_mode ]]; then
            quit
        else
            if false; then
                close_pane # close_pane cannot be called on mac since enable_echo hangs
            else
                show_cursor
                enable_line_wrapping
                close_screen
                restore_cursor_pos
                printf '\e[0m\e[K'
            fi
        fi
    }
    nsh_main_loop "$@" 1>&2
    if [[ $nsh_mode == search ]]; then
        for s in "${selected[@]}"; do
            [[ -n $s ]] && echo "$s"
        done
    fi
}

# check if this file is sourced
(return 0 2>/dev/null) || nsh "$@"


