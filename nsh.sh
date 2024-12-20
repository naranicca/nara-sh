#!/usr/bin/env bash

##############################################################################
# configs
__NSH_VERSION__='0.2.0'
__NSH_BOTTOM_MARGIN__=20%
__NSH_MENU_DEFAULT_CURSOR__=$'\e[31;40m>'
__NSH_MENU_DEFAULT_SEL_COLOR__='32;40'
__NSH_SHOW_HIDDEN_FILES__=0

HISTSIZE=1000

NSH_COLOR_TXT=$'\e[37m'
NSH_COLOR_CMD=$'\e[32m'
NSH_COLOR_VAR=$'\e[36m'
NSH_COLOR_VAL=$'\e[33m'
NSH_COLOR_ERR=$'\e[31m'
NSH_COLOR_DIR=$'\e[94m'
NSH_COLOR_EXE=$'\e[32m'
NSH_COLOR_IMG=$'\e[95m'
NSH_COLOR_LNK=$'\e[96m'

print_prompt() {
    local NSH_PROMPT_SEPARATOR='\xee\x82\xb0'
    echo -ne "\e[0;7m$NSH_COLOR_DIR $(dirs) \e[0m$NSH_COLOR_DIR$NSH_PROMPT_SEPARATOR\e[0m "
}

show_logo() {
    disable_line_wrapping
    echo -e '                   _
 __               | |
 \ \     ____  ___| |__
  \ \   |  _ \/ __|  _ \
  / /   | | | \__ \ | | |
 /_/    |_| |_|___/_| |_| ' $__NSH_VERSION__
    echo "        nsh is Not a SHell"
    echo " designed by naranicca"
    echo
    enable_line_wrapping
}

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
        IFS=';' read -sdR -p $'\E[6n' __ROW__ __COL__ </dev/tty; __ROW__=${__ROW__#*[};
        [[ $__ROW__ =~ ^[0-9]*$ ]] && return # sometimes ROW has weird values
    done
}

get_cursor_row() {
    IFS=';' read -sdR -p $'\E[6n' __ROW__ __COL__ </dev/tty; echo ${__ROW__#*[};
}

get_cursor_col() {
    IFS=';' read -sdR -p $'\E[6n' __ROW__ __COL__ </dev/tty; echo $__COL__;
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

get_key() {
    _key=
    local k
    local param=''
    while [ $# -gt 1 ]; do
        param="$param $1"
        shift
    done
    [[ "$__eps_get_key__" == 1 && "$param" == *-t\ 0\.* ]] && printf -v "${1:-_key}" "%s" "$_key" && return
    IFS= read -srn 1 $param _key 2>/dev/null
    __ret=$?
    if [[ $__ret -eq 0 && "$_key" == '' ]]; then
        _key=$'\n'
    elif [[ "$_key" == $'\e' ]]; then
        while IFS= read -sn 1 -t $__eps_get_key__ k; do
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
__eps_get_key__=0.1
read -sn 1 -t $__eps_get_key__ _key &>/dev/null
[[ $? -ne 142 ]] && __eps_get_key__=1

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

ls() {
    local line dirs files
    if [[ $# -gt 0 ]]; then
        command ls "$@"
    else
        while true; do
            dirs=() files=()
            [[ "$(pwd)" != / ]] && dirs+=($'\e[94m../')
            while IFS= read line; do
                if [[ -d "$line" ]]; then
                    dirs+=($'\e[94m'"$line/")
                else
                    files+=("$line")
                fi
            done < <(command ls)
            local ret="$(menu2d "${dirs[@]}" "${files[@]}")"
            [[ -z "$ret" ]] && break
            ret="$(strip_escape "$ret")"
            [[ ! -d "$ret" ]] && break
            cd "$ret"
            print_prompt; echo ls
        done
    fi
}

menu2d() {
    local list disp list_size
    local item trail
    local len w=0 acclen=0
    local cols rows c r c2 r2 i j
    local x=0 y=0

    while [[ $# -gt 0 ]]; do
        list+=("$1")
        shift
    done
    list_size=${#list[@]}

    hide_cursor >&2
    disable_echo >&2

    disp=()
    for ((i=0; i<list_size; i++)); do
        item="$(strip_escape "${list[$i]}")"
        disp[$i]=${#item}
        len="$((${disp[$i]}+2))"
        acclen=$((acclen+len))
        [[ $len -gt $w ]] && w=$len
    done
    get_terminal_size
    if [[ $acclen -le $COLUMNS ]]; then
        cols=$list_size
        rows=1
    else
        cols=$((COLUMNS/w)) && [[ $cols -lt 1 ]] && cols=1
        rows=$(((list_size+cols-1)/cols))
        [[ $(((cols-1)*rows)) -ge $list_size ]] && cols=$((cols-1))
    fi
    [[ $rows -ge $((LINES-1)) ]] && rows=$((LINES-1))
    w=$((COLUMNS/cols))
    for ((i=0; i<list_size; i++)); do
        trail="$(printf "%$((w-${disp[$i]}))s" ' ')"
        disp[$i]="${list[$i]}$trail"
    done

    draw_line() {
        local i j
        if [[ $rows -gt 1 ]]; then
            for ((i=0; i<cols; i++)); do
                local idx=$(($1+i*rows))
                [[ $x == $i && $y == $1 ]] && echo -ne '\e[7m' >&2
                if [[ -n "${disp[$idx]}" ]]; then
                    echo -ne "${disp[$idx]}" >&2
                else
                    get_cursor_pos && r=$__ROW__ && c=$__COL__ && [[ $c -ge $COLUMNS ]] && c=1 && r=$((r+1))
                    echo -ne "${list[$idx]:0:$w}" >&2
                    get_cursor_pos && r2=$__ROW__ && c2=$__COL__
                    len=$((c2-c))
                    if [[ $r2 -gt $r || $len -gt $w ]]; then
                        trail="$(printf "%$((len-w))s" ' ')"
                        trail="${trail//?/\\b}"
                        echo -ne "$trail" >&2
                    else
                        trail="$(printf "%$((w-len))s" ' ')"
                        echo -ne "$trail" >&2
                    fi
                fi
                echo -ne '\e[0m' >&2
            done
        else
            for ((i=0; i<cols; i++)); do
                [[ $x == $i && $y == $1 ]] && echo -ne '\e[7m' >&2
                echo -ne "${list[$i]}  \e[0m" >&2
            done
        fi
        get_cursor_pos
        if [[ $__COL__ -lt $COLUMNS ]]; then
            printf "%$((COLUMNS-__COL__+1))s" ' ' >&2
        fi
    }

    for ((j=0; j<rows; j++)); do
        draw_line $j
    done

    echo -ne $'\e'"[${COLUMNS}D" >&2
    for ((i=1; i<rows; i++)); do echo -ne $'\e[A' >&2 ; done
    while true; do
        get_key KEY
        case $KEY in
            l)
                if [[ $x -lt $((cols-1)) ]]; then
                    x=$((x+1))
                    draw_line $y
                    echo -ne $'\e'"[${COLUMNS}D" >&2
                fi
                ;;
            h)
                if [[ $x -gt 0 ]]; then
                    x=$((x-1))
                    draw_line $y
                    echo -ne $'\e'"[${COLUMNS}D" >&2
                fi
                ;;
            j)
                if [[ $y -lt $((rows-1)) ]]; then
                    y=$((y+1))
                    draw_line $((y-1))
                    draw_line $y
                    echo -ne $'\e'"[${COLUMNS}D" >&2
                elif [[ $x -lt $((cols-1)) ]]; then
                    y=0 x=$((x+1))
                    draw_line $((rows-1))
                    echo -ne $'\e['"${COLUMNS}D" >&2
                    echo -ne $'\e['"$((rows-1))A" >&2
                    draw_line 0
                    echo -ne $'\e'"[${COLUMNS}D" >&2
                fi
                ;;
            k)
                if [[ $y -gt 0 ]]; then
                    y=$((y-1))
                    draw_line $((y+1))
                    echo -ne $'\e['"${COLUMNS}D"$'\e[A' >&2
                    draw_line $y
                    echo -ne $'\e'"[${COLUMNS}D" >&2
                elif [[ $x -gt 0 ]]; then
                    x=$((x-1)) y=$((rows-1))
                    draw_line 0
                    echo -ne $'\e'"[${COLUMNS}D" >&2
                    for ((i=1; i<rows; i++)); do echo -ne $'\e[B' >&2 ; done
                    draw_line $((rows-1))
                    echo -ne $'\e'"[${COLUMNS}D" >&2
                fi
                ;;
            $'\n')
                idx=$((y+x*rows))
                enable_echo >&2
                echo "${list[$idx]}"
                break
                ;;
            q|$'\e')
                x=-1 # to lose focus
                break
                ;;
        esac
    done

    for ((j=$y; j<rows; j++)); do
        draw_line $j
    done
    show_cursor >&2
    enable_echo >&2
}

menu() {
    pipe_context() {
        local c='>>'
        [[ -t 0 ]] && c='->'
        [[ -t 1 ]] && c="${c%?}-"
        echo "$c"
    }

    disable_line_wrapping >&2
    hide_cursor >&2

    get_terminal_size </dev/tty
    local max_height=$((LINES-1))
    local min_height=${__NSH_BOTTOM_MARGIN__:-20%}
    local toprow=

    local cursor0="$__NSH_MENU_DEFAULT_CURSOR__"
    local items=()
    local cur=-1 cur_bak=0
    local popup=0
    local hscroll=-1
    local return_idx=0
    local sel_color="$__NSH_MENU_DEFAULT_SEL_COLOR__"
    local readparam=
    local header=
    local footer=
    local preview=
    local header_wrap=off
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
            --header-wrap)
                header_wrap=on
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

        if [[ -n "$header" ]]; then
            [[ $header_wrap == on ]] && enable_line_wrapping >&2
            printf "\r\e[0m\e[K$header\n" >&2 && ((height--))
            disable_line_wrapping >&2
        fi
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
            toprow=$((__ROW__-lines))
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
                        get_key -t $__eps_get_key__ NEXT_KEY </dev/tty
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

play2048() {
    local board=()
    local board_prev=()
    local board_hist=()
    local hlpos=()
    local buf=()
    local __COL__=$(get_cursor_col)
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
            move_cursor "$((r0+j));$__COL__"
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

read_command() {
    local prefix=
    local cmd=
    local cur=0
    local pre post cand word chunk
    local iword=0 ichunk=0
    shopt -s nocaseglob
    [[ $1 == "--prefix" ]] && prefix="$2" && shift && shift && echo -ne "$prefix" >&2
    update_dotglob() 
    {
        if [[ $__NSH_SHOW_HIDDEN_FILES__ -ne 0 ]]; then
            shopt -s dotglob
        else
            shopt -u dotglob
        fi
    }
    update_dotglob
    while true; do
        pre="${cmd:0:$cur}"
        post="${cmd:$cur}"
        KEY="$NEXT_KEY" && NEXT_KEY= && [[ -z $KEY ]] && get_key KEY
        case $KEY in
            $'\e') # ESC
                echo -ne "${pre//?/\\b}" >&2
                echo -ne "${cmd//?/ }" >&2
                echo -ne "${cmd//?/\\b}" >&2
                cmd=
                cur=0
                ;;
            $'\04')
                if [[ -n $cmd ]]; then
                    echo '^C' >&2
                    cmd=
                else
                    cmd='exit'
                    echo "$cmd" >&2
                fi
                break
                ;;
            $'\n') # enter
                echo >&2
                break
                ;;
            $'\177'|$'\b') # backspace
                if [[ $cur -gt 0 ]]; then
                    echo -ne "\b \b$post ${post//?/\\b}\b" >&2
                    cmd="${pre%?}$post"
                    cur=$((cur-1))
                fi
                ;;
            $'\t') # tab
                # ls abc/def/g
                #    ^       ^
                #    iword   ichunk
                local quote=
                while true; do
                    chunk="${pre:$ichunk}"
                    cand="$(eval command ls -p -d "${pre:$iword:$((ichunk-iword))}$(fuzzy_word "${chunk:-*}")" 2>/dev/null)"
                    if [[ "$cand" == *$'\n'* ]]; then
                        echo -ne "${prefix//?/\\b}${pre//?/\\b}" >&2
                        cand="$(echo "$cand" | menu --popup --header-wrap --header "$prefix${pre:0:$iword}\e[32m${pre:$iword}\e[0m" --key '.' 'echo "%&\$#!@"')"
                        echo -ne "$prefix$pre" >&2
                    fi
                    if [[ $cand == "%&\$#!@" ]]; then
                        [[ $__NSH_SHOW_HIDDEN_FILES__ -ne 0 ]] && __NSH_SHOW_HIDDEN_FILES__=0 || __NSH_SHOW_HIDDEN_FILES__=1
                        update_dotglob
                    elif [[ -n "$cand" ]]; then
                        word="${pre:$iword}"
                        echo -ne "${word//?/\\b}$cand" >&2
                        pre="${pre:0:$iword}$cand"
                        cmd="$pre$post"
                        cur=${#pre}
                        ichunk=$cur
                        [[ -f "$word" ]] && NEXT_KEY=\  && break
                    else
                        break
                    fi
                done
                word="${pre:$iword}"
                if [[ -e "$word" ]]; then
                    eval "[[ -e $word ]] && echo" &>/dev/null || quote=\"
                fi
                if [[ -n "$word" && -n $quote ]]; then
                    echo -ne "${word//?/\\b}$quote$word$quote$post" >&2
                    echo -ne "${post//?/\\b}" >&2
                    pre="${pre:0:$iword}$quote${pre:$iword}$quote"
                    cmd="$pre$post"
                    cur=${#pre}
                    NEXT_KEY=\ 
                fi
                ;;
            $'\e[A') # Up
                echo -ne "${prefix//?/\\b}${pre//?/\\b}" >&2
                cmd="$(printf '%s\n' "${history[@]}" | menu --popup --header "$prefix" --initial "$HISTSIZE")"
                cur=${#cmd}
                echo -ne "$prefix$cmd" >&2
                ;;
            $'\e[B') # Down
                ;;
            $'\e[C') # right
                echo -ne "${cmd:$cur:1}" >&2
                cur=$((cur+1))
                ;;
            $'\e[D') # left
                echo -ne '\b' >&2
                cur=$((cur-1))
                ;;
            *)
                cmd="$pre$KEY$post"
                cur=$((cur+1))
                if [[ $KEY == \  ]]; then
                    iword=$cur
                    ichunk=$cur
                fi
                echo -ne "$KEY$post${post//?/\\b}" >&2
                ;;
        esac
    done
    shopt -u nocaseglob
    printf -v "${1:-cmd}" "%s" "$cmd"
}

############################################################################
# main loop
############################################################################
nsh() {
    show_cursor
    enable_line_wrapping

    local history=() history_sizse=0
    while true; do
        local command=
        read_command --prefix "$(print_prompt)" command

        if [[ -n $command ]]; then
            eval "$command"
            # save command to history
            history_size=${#history[@]}
            if [[ $history_size -eq 0 || "${history[$((history_size-1))]}" != "$command" ]]; then
                history+=("$command")
                local li=$((${#history[@]}-1))
                if [[ $li -ge 3 && "${history[$li]}" == "${history[$((li-2))]}" && "${history[$((li-1))]}" == "${history[$((li-3))]}" ]]; then
                    history=("${history[@]:0:$((${#history[@]}-2))}")
                fi
                if [ ${#history[@]} -ge $HISTSIZE ]; then
                    history=("${history[@]:$((${#history[@]}-HISTSIZE))}")
                    history_idx=$((history_idx-${#history[@]}+HISTSIZE))
                    [[ $history_idx -lt 0 ]] && history_idx=0
                fi
            fi
        fi
    done
}

(return 0 2>/dev/null) || (show_logo && nsh)

