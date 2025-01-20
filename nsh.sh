#!/usr/bin/env bash
__NSH_VERSION__='0.2.0'

##############################################################################
# configs
NSH_DEFAULT_CONFIG="
HISTSIZE=1000
NSH_MENU_HEIGHT=20%
NSH_SHOW_HIDDEN_FILES=0
NSH_PROMPT=$'\e[31m>\e[33m>\e[32m>\e[0m'

NSH_COLOR_TXT=$'\e[37m'
NSH_COLOR_CMD=$'\e[32m'
NSH_COLOR_VAR=$'\e[36m'
NSH_COLOR_VAL=$'\e[33m'
NSH_COLOR_ERR=$'\e[31m'
NSH_COLOR_DIR=$'\e[94m'
NSH_COLOR_EXE=$'\e[32m'
NSH_COLOR_IMG=$'\e[95m'
NSH_COLOR_LNK=$'\e[96m'

# aliases
alias ls='command ls --color=auto'
"
eval "$NSH_DEFAULT_CONFIG"

nsh_print_prompt() {
    local NSH_PROMPT_SEPARATOR='\xee\x82\xb0'
    local git_color
    IFS=$'\n' read -sdR __GIT_STAT__ git_color __GIT_CHANGES__ < <(git_status)
    if [[ -z $__GIT_STAT__ ]]; then
        echo -ne "\e[0;7m$NSH_COLOR_DIR $(dirs) \e[0m$NSH_COLOR_DIR$NSH_PROMPT_SEPARATOR\e[0m "
    else
        local c2=$((git_color+10))
        echo -ne "\e[0;7m$NSH_COLOR_DIR $(dirs) \e[0m$NSH_COLOR_DIR\e[${c2}m$NSH_PROMPT_SEPARATOR\e[30;${c2}m$__GIT_STAT__\e[0;${git_color}m$NSH_PROMPT_SEPARATOR\e[0m "
    fi
}

nsh_preview() {
    vi "$1"
}

show_logo() {
    disable_line_wrapping
    echo -e '                   _
 __               | |
 \ \     ____  ___| |__
  \ \   |  _ \/ __|  _ \
  / /   | | | \__ \ | | |
 /_/    |_| |_|___/_| |_| ' $__NSH_VERSION__
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
    IFS=\  read -r LINES COLUMNS < <(stty size)
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

strip_spaces() {
    sed -e 's/^[ ]*//g' -e 's/[ ]*$//' <<< "$1"
}

pipe_context() {
    local c='>>'
    [[ -t 0 ]] && c='->'
    [[ -t 1 ]] && c="${c%?}-"
    echo "$c"
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

put_filecolor() {
    local f="${1/#\~\//$HOME\/}"
    if [[ -h "${f%/}" ]]; then
        echo "$NSH_COLOR_LNK"
    elif [[ -d "$f" ]]; then
        echo "$NSH_COLOR_DIR"
    elif [[ -x "$f" ]]; then
        echo "$NSH_COLOR_EXE"
    fi
}

menu() {
    local list disp colors markers selected list_size
    local list_org disp_org colors_org markers_org
    local item trail
    local len w=0
    local cols rows max_cols max_rows c r i j
    local x=0 y=0 icol=0 irow=0 idx
    local wcparam=-L && [[ "$(wc -L <<< "가나다" 2>/dev/null)" != 6 ]] && wcparam=-c
    local color_func marker_func initial=0
    local return_key=() return_fn=() keys
    local start_col avail_rows
    local can_select=0 show_footer=1
    local search

    get_terminal_size </dev/tty
    get_cursor_pos </dev/tty && start_col=$__COL__ && [[ $__COL__ -gt 1 ]] && printf "%$((COLUMNS-__COL__+3))s" ' '$'\r' >&2

    max_rows=$NSH_MENU_HEIGHT
    avail_rows=$((LINES-__ROW__+1))

    while [[ $# -gt 0 ]]; do
        if [[ $1 == --color-func ]]; then
            color_func="$2"
            shift
        elif [[ $1 == -r || $1 == --max-rows ]]; then
            max_rows=$2
            shift
        elif [[ $1 == -c || $1 == --max-cols ]]; then
            max_cols=$2
            shift
        elif [[ $1 == --initial ]]; then
            initial=$2
            shift
        elif [[ $1 == --select ]]; then
            can_select=1
        elif [[ $1 == --marker-func ]]; then
            marker_func="$2"
            shift
        elif [[ $1 == --key ]]; then
            shift && return_key+=("$1")
            shift && return_fn+=("$1") # if fn ends with '...', menu will not end after running the function
        elif [[ $1 == --no-footer ]]; then
            show_footer=0
        else
            item="${1//\\n/}"
            [[ -n "$item" ]] && list+=("$item")
        fi
        shift
    done
    if [[ $(pipe_context) == \>* ]]; then
        while IFS= read line; do
            [[ -n $line ]] && list+=("$line")
        done
    fi
    list_size=${#list[@]}
    [[ $list_size -eq 0 ]] && return 0
    colors=() markers=() selected=()
    if [[ -n $color_func ]]; then
        for ((i=0; i<list_size; i++)); do
            colors[$i]="$($color_func "${list[$i]}")"
        done
    fi
    if [[ -n $marker_func ]]; then
        local marker_exists=0
        for ((i=0; i<list_size; i++)); do
            markers[$i]="$($marker_func "${list[$i]}")"
            [[ -n ${markers[$i]} ]] && marker_exists=1
        done
        if [[ $marker_exists -ne 0 ]]; then
            for ((i=0; i<list_size; i++)); do
                [[ -z ${markers[$i]} ]] && markers[$i]=' '
            done
        fi
    fi

    hide_cursor >&2
    disable_echo >&2 </dev/tty
    disable_line_wrapping >&2

    [[ $max_rows == *% ]] && max_rows=$((LINES*${max_rows%?}/100))
    if [[ $max_rows -lt $avail_rows || # when we have plenty of empty rows below the cursor
          $avail_rows -gt 1 ]]; then   # or we don't need to add empty rows
        max_rows=$avail_rows
    fi
    [[ $list_size -le $max_rows ]] && max_cols=1

    disp=()
    if [[ $list_size -lt 100 && ${max_cols:-100} -gt 1 ]]; then
        for ((i=0; i<list_size; i++)); do
            disp[$i]="$(wc "$wcparam" <<< "${list[$i]}")"
            [[ $wcparam == -c ]] && disp[$i]=$((${disp[$i]-1}))
            len="$((${disp[$i]}+3))"
            [[ $len -gt $w ]] && w=$len
        done
        cols=$((COLUMNS/w))
        [[ -n $max_cols && $cols -gt $max_cols ]] && cols=$max_cols
        [[ $cols -lt 1 ]] && cols=1
    else
        # too many items to calculate the width of each item
        cols=1
    fi
    rows=$(((list_size+cols-1)/cols))
    [[ $rows -ge $max_rows ]] && rows=$max_rows
    [[ $(((cols-1)*rows)) -ge $list_size ]] && cols=$((cols-1))
    if [[ $cols -eq 1 ]]; then
        max_cols=1
        max_rows=$list_size
    else
        max_rows=$rows
        max_cols=$(((list_size+rows-1)/rows))
    fi
    w=$((COLUMNS/cols))
    [[ $cols -gt 1 && $rows -lt $avail_rows ]] && rows=$avail_rows
    [[ ${#markers[@]} -gt 0 ]] && w=$((w-2))
    if [[ $cols -gt 1 ]]; then
        for ((i=0; i<list_size; i++)); do
            trail="$(printf "%$((w-${disp[$i]}))s" ' ')"
            disp[$i]="${list[$i]}$trail"
        done
    else
        if [[ $__WRAP_OPTION_SUPPORTED__ -eq 0 ]]; then
            for ((i=0; i<list_size; i++)); do
                disp[$i]="${list[$i]:0:$((w-1))}"
            done
        else
            disp=("${list[@]}")
        fi
    fi

    draw_line() {
        local i j c
        if [[ $1 -lt $list_size ]]; then
            for ((i=0; i<cols; i++)); do
                idx=$((($1+irow)+(i+icol)*rows))
                c=$'\e[0m'"${colors[$idx]}" && [[ $x == $i && $y == $1 ]] && c=$'\e[0;7m'"${colors[$idx]}"
                if [[ -n ${selected[$idx]} ]]; then
                    echo -ne $'\e[0m'"${markers[$idx]}$c*\e[33;48;5;239m" >&2
                    if [[ $cols -gt 1 ]]; then
                        echo -n "${disp[$idx]%?}"$'\e[0m' >&2
                    else
                        echo -n "${disp[$idx]}"$'\e[0m' >&2
                    fi
                elif [[ -n ${markers[$idx]} ]]; then
                    echo -ne $'\e[0m'"${markers[$idx]}$c" >&2
                    echo -n "${disp[$idx]}"$'\e[0m' >&2
                else
                    echo -ne "$c" >&2
                    echo -n "${disp[$idx]}"$'\e[0m' >&2
                fi
            done
        fi
        if [[ $1 -eq $((rows-1)) ]]; then
            get_cursor_pos
            [[ $__COL__ -lt $COLUMNS ]] && printf "%$((COLUMNS-__COL__+1))s" ' ' >&2
            echo -ne "$__NSH_DRAWLINE_END__" >&2
            draw_footer
            echo -ne "\e[${COLUMNS}D" >&2
            [[ $rows -gt 1 ]] && echo -ne "\e[$((rows-1))A" >&2
        else
            echo -e '\e[K' >&2
        fi
    }
    draw_footer() {
        local idx=$(((y+irow)+(x+icol)*rows))
        local lls=${#list_size}
        local lbs=$((lls*2+2))
        local bs="$(printf "%${lbs}s" ' ')" && bs="${bs//?/\\b}"
        local num_selected=${#selected[@]}
        if [[ -n $search ]]; then
            echo -ne "\e[${COLUMNS}D" >&2
            echo -ne "\e[0;39;41m$search" >&2
            printf "%$((COLUMNS-${#search}))s\e[0m" "[$list_size]" >&2
        elif [[ $show_footer -ne 0 && $idx -ge 0 && $idx -lt $list_size ]]; then
            if [[ $num_selected -gt 0 ]]; then
                local bs2="$(printf "%$((${#num_selected}+3))s" ' ')" && bs="$bs${bs2//?/\\b}"
                bs="$bs"$'\e[0;30;43m'"[*$num_selected]"
            fi
            printf "$bs\e[0;30;48;5;248m[%${lls}s/%${lls}s]\e[0m" $((idx+1)) $list_size >&2
        fi
    }
    print_selected() {
        local idx=$(((y+irow)+(x+icol)*rows))
        if [[ ${#selected[@]} -gt 0 ]]; then
            for ((i=0; i<list_size; i++)); do
                [[ -n ${selected[$i]} ]] && echo "${list[$i]}"
            done
        elif [[ $1 == force ]]; then
            echo "${list[$idx]}"
        fi
    }
    quit() {
        x=9999 y=9999
        for ((i=0; i<rows; i++)); do
            draw_line $i
        done
        [[ $rows -gt 1 ]] && echo -ne "\e[$((rows-1))B" >&2
        echo >&2
        return
    }

    echo -ne '\e[J' >&2
    for ((j=0; j<rows; j++)); do
        draw_line $j
    done

    move_cursor() {
        local xpre=$x ypre=$y icolpre=$icol irowpre=$irow
        x=$((x+$1))
        y=$((y+$2))
        if [[ $1 -lt 0 ]]; then
            [[ $x -lt 0 ]] && icol=$((icol+x)) && x=0 && [[ $icol -lt 0 ]] && icol=0
        else
            [[ $x -ge $cols ]] && icol=$((icol+cols-x+1)) && x=$((cols-1)) && [[ $icol -gt $((max_cols-cols)) ]] && icol=$((max_cols-cols))
        fi
        if [[ $y -lt 0 ]]; then
            if [[ $((icol+x)) -gt 0 ]]; then
                x=$((x-1)) && y=$((rows-1))
                [[ $x -lt 0 ]] && x=0 && icol=$((icol-1)) && [[ $icol -lt 0 ]] && icol=0
            else
                irow=$((irow+y)) && y=0 && [[ $irow -lt 0 ]] && irow=0
            fi
        elif [[ $y -ge $rows ]]; then
            if [[ $cols -eq 1 ]]; then
                y=$((irow+y)) && [[ $y -ge $max_rows ]] && y=$((max_rows-1))
                irow=$((y-rows+1)) y=$((rows-1))
            else
                if [[ $((icol+x+1)) -lt $max_cols ]]; then
                    x=$((x+1)) && y=0
                    [[ $x -ge $cols ]] && x=$((cols-1)) && icol=$((icol+1)) && [[ $icol -gt $((max_cols-cols)) ]] && icol=$((max_cols-cols))
                else
                    irow=$((irow+rows-y+1)) && y=$((rows-1)) && [[ $irow -gt $((max_rows-rows)) ]] && irow=$((max_rows-rows))
                fi
            fi
        fi

        local newidx=$((irow+y+(icol+x)*rows))
        if [[ -n ${list[$newidx]} ]]; then
            if [[ $icolpre -ne $icol || irowpre -ne $irow ]]; then
                for ((i=0; i<rows; i++)); do
                    draw_line $i
                done
            else
                if [[ $y -ne $ypre ]]; then
                    [[ $ypre -gt 0 ]] && echo -ne "\e[${ypre}B" >&2
                    draw_line $ypre
                    if [[ $ypre -ne $((rows-1)) ]]; then
                        echo -ne "\e[${COLUMNS}D" >&2
                        echo -ne "\e[$((ypre+1))A" >&2
                    fi
                fi
                [[ $y -gt 0 ]] && echo -ne "\e[${y}B" >&2
                draw_line $y
                if [[ $y -lt $((rows-1)) ]]; then
                    [[ $((rows-2-y)) -gt 0 ]] && echo -ne "\e[$((rows-2-y))B" >&2
                    echo -ne "\e[${COLUMNS}C" >&2
                    draw_footer
                    echo -ne "\e[${COLUMNS}D\e[$((rows-1))A" >&2
                fi
            fi
        else
            x=$xpre y=$ypre icol=$icolpre irow=$irowpre
        fi
    }

    if [[ $initial -gt 0 ]]; then
        if [[ $cols -gt 1 ]]; then
            for ((i=0; i<initial; i++)); do move_cursor 0 1; done
        else
            move_cursor 0 $initial
        fi
    fi
    keys="${return_key[@]}"

    while true; do
        KEY="$NEXT_KEY" && NEXT_KEY= && [[ -z $KEY ]] && get_key KEY </dev/tty
        local found=0
        if [[ "$keys" == *$KEY* ]]; then
            idx=$(((y+irow)+(x+icol)*rows))
            item="${list[$idx]}"
            local quit=yes
            for ((i=0; i<${#return_key[@]}; i++)); do
                if [[ "${return_key[$i]}" == *"$KEY"* ]]; then
                    if [[ $(type -t "${return_fn[$i]}") == function ]]; then
                        "${return_fn[$i]}" "$item"
                    else
                        [[ ${return_fn[$i]} == *\.\.\. ]] && quit=no
                        eval "TEMPFUNC() { ${return_fn[$i]%\.\.\.}; }" >&2
                        TEMPFUNC "$item"
                    fi
                    found=1
                    break
                fi
            done
            hide_cursor >&2
            disable_echo >&2 </dev/tty
            [[ $found -ne 0 && $quit == yes ]] && break
        fi
        if [[ $found -eq 0 ]]; then
            case $KEY in
                l|$'\e[C')
                    move_cursor 1 0
                    ;;
                h|$'\e[D')
                    move_cursor -1 0
                    ;;
                j|$'\e[B')
                    move_cursor 0 1
                    ;;
                k|$'\e[A')
                    move_cursor 0 -1
                    ;;
                0)
                    move_cursor -$max_cols 0
                    ;;
                g)
                    x=0 y=0 icol=0 irow=0
                    for ((i=0; i<rows; i++)); do draw_line $i; done
                    ;;
                G)
                    if [[ $cols -gt 1 ]]; then
                        for ((i=0; i<max_cols; i++)); do move_cursor 1 0; done
                        for ((i=0; i<max_rows; i++)); do move_cursor 0 1; done
                    else
                        move_cursor 0 $max_rows
                    fi
                    ;;
                ' ')
                    if [[ $can_select -ne 0 ]]; then
                        idx=$(((y+irow)+(x+icol)*rows))
                        if [[ -z "${selected[$idx]}" ]]; then
                            selected[$idx]="${list[$idx]}"
                        else
                            unset selected[$idx]
                            if [[ ${#selected[@]} -eq 0 ]]; then
                                # need to erase #selected from the footer
                                [[ $rows -gt 1 ]] && echo -ne "\e[$((rows-1))B" >&2
                                draw_line $((rows-1))
                            fi
                        fi
                        if [[ $idx -lt $((list_size-1)) ]]; then
                            NEXT_KEY=j
                        else
                            # when idx == list_size-1, j key doesn't do anything
                            [[ $y -gt 0 ]] && echo -ne "\e[${y}B" >&2
                            draw_line $y
                            [[ $y -lt $((rows-1)) ]] && echo -ne "\e[$((y+1))A" >&2
                        fi
                    fi
                    ;;
                $'\n')
                    print_selected force
                    break
                    ;;
                q|$'\e')
                    if [[ $KEY == $'\e' && ${#selected[@]} -gt 0 ]]; then
                        selected=()
                        NEXT_KEY=g
                    elif [[ $KEY == $'\e' && -n $search ]]; then
                        search=
                        list=("${list_org[@]}")
                        disp=("${disp_org[@]}")
                        colors=("${colors_org[@]}")
                        markers=("${markers_org[@]}")
                        list_size=${#list[@]}
                        x=0 y=0 icol=0 irow=0
                        for ((i=0; i<rows; i++)); do
                            draw_line $i
                        done
                    else
                        x=-1 # to lose focus
                        break
                    fi
                    ;;
                /)
                    list_org=("${list[@]}")
                    disp_org=("${disp[@]}")
                    colors_org=("${colors[@]}")
                    markers_org=("${markers[@]}")
                    list_size_org=${#list[@]}
                    x=99999 y=99999 icol=0 irow=0
                    search=/
                    while true; do
                        for ((i=0; i<rows; i++)); do
                            draw_line $i
                        done
                        get_key KEY </dev/tty
                        case $KEY in
                            $'\e'*|$'\t')
                                [[ $search == / ]] && search=
                                break
                                ;;
                            $'\177'|$'\b')
                                search="${search%?}"
                                [[ -z $search ]] && search=/
                                ;;
                            [[:print:]])
                                search="$search$KEY"
                                ;;
                        esac
                        item="${search#/}" && item="${item,,}"
                        item="$(fuzzy_word "${item//\ /}")"
                        list=() disp=() colors=() markers=()
                        for ((i=0; i<$list_size_org; i++)); do
                            if [[ "${list_org[$i],,}" == *$item* ]]; then
                                list+=("${list_org[$i]}")
                                disp+=("${disp_org[$i]}")
                                colors+=("${colors_org[$i]}")
                                markers+=("${markers_org[$i]}")
                            fi
                        done
                        list_size=${#list[@]}
                    done
                    x=0 y=0 icol=0 irow=0
                    for ((i=0; i<rows; i++)); do
                        draw_line $i
                    done
                    ;;
            esac
        fi
    done

    [[ $start_col -gt 1 ]] && echo -ne "\e[A\e[$((start_col-1))C" >&2
    echo -ne '\e[0m\e[J' >&2
    show_cursor >&2
    enable_echo >&2 </dev/tty
    enable_line_wrapping >&2
}

cpmv() {
    local src dst src_name dst_name i
    local op='cp -r' && [[ $1 == --mv ]] && op='mv'
    while true; do
        if [[ $1 == --cp ]]; then
            op='cp -r'
        elif [[ $1 == --mv ]]; then
            op=mv
        else
            break
        fi
        shift
    done
    for dst in "$@"; do :; done
    while [[ $# -gt 1 ]]; do
        if [[ -e "$1" ]]; then
            src="$(sed 's/\/*$//' <<< "$1")"
            src_name="${src##*/}" && dst_name="$dst"
            if [[ -e "$dst" && -e "$dst/$src_name" ]]; then
                for i in {2..999999}; do
                    if [[ ! -e "$dst/$src_name($i)" ]]; then
                        dst_name="$dst/$src_name($i)"
                        break
                    fi
                done
            fi
            echo -e "[${op%% *}] $(put_filecolor "$src")${src/#$HOME\//\~\/}\e[0m --> $dst_name"
            command $op "$src" "$dst_name"
        else
            echo "$1 does not exist" >&2
        fi
        shift
    done
}

ps() {
    local param pid line
    if [[ $# -gt 0 || ! -t 0 || ! -t 1 ]]; then
        command ps "$@"
    else
        while true; do
            #param="-o pid,command"
            param="-a -o pid,user,command"
            pid=$((command ps -x $param 2>/dev/null || command ps -a || command ps -ef) | menu -c 1 | awk '{print $1}')
            [[ -z $pid ]] && break
            echo -e "$NSH_PROMPT Kill the process $pid?"
            echo -n '  ' && command ps -p "$pid"
            [[ $(menu OK Cancel) == OK ]] && kill -9 $pid
        done
    fi
}

git_status()  {
    local line str= color=0
    local filenames=;
    while read line; do
        case "$line" in
            *not\ a\ git*|*Not\ a\ git*|*Untracked*)
                break
                ;;
            *On\ branch*|*HEAD\ detached\ at*)
                str="${line##* }"
                color=32
                ;;
            *rebase\ in\ progress*)
                str="rebase-->${line##* }"
                color=31
                ;;
            *modified:*|*deleted:*|*new\ file:*|*renamed:*)
                color=91
                if [[ "$line" == *modified:* ]]; then
                    fname="$(echo $line | sed 's/.*modified:[ ]*//')"
                    [[ "$line" == *both\ modified:* ]] && fname="!!$fname"
                    filenames="$filenames;${fname%%/*}"
                fi
                #break
                ;;
            *Your\ branch*ahead*)
                line="${line% *}"
                line="${line##* }"
                str="$str +$line"
                color=33
                ;;
            *Your\ branch\ is\ behind*)
                line="${line#*by }"
                line="${line%% *}"
                str="$str -$line"
                color=33
                ;;
            *all\ conflicts*fixed*git\ rebase\ --continue*)
                str="run 'git rebase --continue'"
                ;;
            @@@ERROR@@@)
                return
                ;;
        esac
    done < <(LANGUAGE=en_US.UTF-8 command git status 2>&1 || echo @@@ERROR@@@)
    while read line; do
        filenames="$filenames;??$line"
    done < <(command git ls-files --others --exclude-standard 2>/dev/null | awk -F / '{print $1}' | uniq)
    if [[ -n $str ]]; then
        echo "$str"
        echo "$color"
        echo "$filenames;"
    fi
}

git() {
    local line op files remote file branch hash p skip_resolve=0
    git_branch_name() {
        command git rev-parse --abbrev-ref HEAD 2>/dev/null
    }
    paint_cyan() {
        echo -e '\e[36m'
    }
    run() {
        [[ $1 == git ]] && shift
        echo -e "\r$(nsh_print_prompt)\e[0m\e[Kgit $@"
        eval command git "$@"
    }
    if [[ $# -gt 0 ]]; then
        command git "$@"
        echo -e "\r$(nsh_print_prompt)git"
        git
        return
    fi
    while true; do
        IFS=$'\n' read -sdR __GIT_STAT__ git_color __GIT_CHANGES__ < <(git_status)
        if [[ -z $__GIT_STAT__ ]]; then
            echo "$NSH_PROMPT This is not a git repository."
            echo -n "$NSH_PROMPT To clone, enter the url: "
            read_string line
            [[ -z $line ]] && return 1
            op=clone
            files=("$line")
        elif [[ "$__GIT_STAT__" == run*git\ rebase\ --continue* ]]; then
            run rebase --continue
        elif [[ $__GIT_CHANGES__ == *\;\!\!* && $skip_resolve -eq 0 ]]; then
            # having conflicts
            echo "$NSH_PROMPT Resolve conflicts first"
            while true; do
                files=()
                while read file; do
                    [[ $file == \!\!* ]] && files+=("${file#??}")
                done <<< "${__GIT_CHANGES__//;/$'\n'}"
                file="$(menu "${files[@]}" --color-func put_filecolor --marker-func git_marker)"
                [[ -z "$file" ]] && skip_resolve=1 && break
                nsh_preview "$file"
                if [[ $(grep -c '^<\+ HEAD' "$file" 2>/dev/null) -eq 0 ]]; then
                    echo -n "$NSH_PROMPT $file was resolved. Stage the file? (y/n) "
                    get_key KEY; echo "$KEY"
                    [[ Yy == *$KEY* ]] && command git add "$file"
                    IFS=$'\n' read -sdR __GIT_STAT__ git_color __GIT_CHANGES__ < <(git_status)
                fi
            done
            if [[ $__GIT_CHANGES__ == *\!\!* ]]; then
                echo "$NSH_PROMPT Resolving conflicts was stopped"
                command git status
            else
                echo "$NSH_PROMPT All conflicts were resolved"
                command git commit
            fi
        else
            local dst=
            if [[ -z "$files" ]]; then
                if [[ -n $__GIT_CHANGES__ ]]; then
                    IFS=\;$'\n' read -d '' -a files <<< "${__GIT_CHANGES__//\;[\?\!][\?\!]/\;}"
                    IFS=$'\n' read -d '' -a files < <(menu "${files[@]}" --select --color-func put_filecolor --marker-func git_marker)
                fi
                if [[ ${#files[@]} -gt 0 ]]; then
                    files="$(printf '\"%s\" ' "${files[@]}")"
                else
                    files=
                fi
            fi
            dst="${files/#\"/ }" && dst="${dst%%\"*}" && [[ "$files" == *\"\ \"* ]] && dst="$dst..."
            if [[ -n "$files" && "$files" != \. ]]; then
                op="$(menu "diff$dst" "commit$dst" "revert$dst" "log$dst" --color-func paint_cyan --no-footer)"
                [[ -z "$op" ]] && files= && continue
            else
                files=.
                op="$(menu diff pull commit push revert log branch --color-func paint_cyan --no-footer)"
                [[ -z "$op" ]] && return
            fi

            if [[ "$op" == clone ]]; then
                command git clone "${files[@]}"
                local dir="${files[1]}"
                [[ -z "$dir" ]] && dir="${files[0]##*/}" && dir="${dir%.git}"
                [[ -d "$dir" ]] && command cd "$dir"
                return
            elif [[ "$op" == diff ]]; then
                run diff "$files"
            elif [[ "$op" == pull ]]; then
                run pull origin "$(git_branch_name)"
            elif [[ "$op" == commit ]]; then
                run commit "$files"
            elif [[ "$op" == push ]]; then
                run push origin "$(git_branch_name)" -f
            elif [[ "$op" == revert ]]; then
                run checkout -- "$files"
            elif [[ "$op" == log ]]; then
                p= && [[ $__WRAP_OPTION_SUPPORTED__ -ne 0 ]] && p='--color=always --graph'
                line="$(eval "command git log $p --decorate --oneline $files" | menu -c 1 | strip_escape)"
                if [[ -n "$line" ]]; then
                    hash="${line%% *}"
                    hash="$(sed 's/^[^0-9^a-z^A-Z]*//' <<< "$line")" && hash="${hash%% *}"
                    command git log --color=always -n 1 --stat "$hash"
                    op="$(menu -c 1 'Checkout this commit' 'Roll back to this commit' 'Roll back but keep the changes' 'Edit commit' --color-func paint_cyan --no-footer)"
                    if [[ "$op" == Checkout* ]]; then
                        run checkout "$hash"
                    elif [[ "$op" == Roll\ back\ to* ]]; then
                        echo -n "$NSH_PROMPT You will lose the commits. Continue? (y/n) "
                        get_key KEY; echo "$KEY"
                        [[ yY == *$KEY* ]] && run reset --hard "$hash"
                    elif [[ "$op" == Roll\ back\ * ]]; then
                        echo -n "$NSH_PROMPT Roll back to this commit? You can cancel rollback by run "git restore FILE" and git pull (y/n) "
                        get_key KEY; echo "$KEY"
                        [[ yY == *$KEY* ]] && run reset --soft $hash && run restore --staged .
                    elif [[ "$op" == Edit* ]]; then
                        hash="$(command git log --oneline | grep -n "$hash")" && hash="${hash%%:*}"
                        run rebase -i "@~$hash"
                    else
                        op=log
                    fi
                    continue
                else
                    op=
                fi
            elif [[ "$op" == branch ]]; then
                git_branch() {
                    while IFS=$'\n' read line; do
                        [[ "$line" != \(HEAD\ *detached\ * ]] && echo "$line"
                    done < <(LANGUAGE=en_US.UTF-8 command git branch 2>/dev/null | sed 's/[ *]*//')
                    for remote in $(command git remote 2>/dev/null); do
                        echo "$remote"
                        command git branch -r 2>/dev/null | sed 's/^[ *]*//' | grep "^$remote/" | sed -n '/ -> /!p'
                    done
                }
                branch="$((echo '+ New branch'; git_branch) | menu -c 1)"
                if [[ "$branch" == '+ New branch' ]]; then
                    echo -n "$NSH_PROMPT New branch name: "
                    read_string line
                    [[ -n "$line" ]] && run checkout -b "$line"
                elif [[ -n "$branch" ]]; then
                    line="$(menu checkout merge delete --color-func paint_cyan --no-footer)"
                    if [[ "$line" == checkout ]]; then
                        run checkout "${branch#origin\/}"
                    elif [[ "$line" == merge ]]; then
                        run merge "${branch#origin\/}"
                    elif [[ "$line" == delete ]]; then
                        if [[ "$branch" == origin\/* ]]; then
                            echo -ne "$NSH_PROMPT \e[31m${branch#*/} branch will be deleted from repository. Continue? (y/n)\e[0m "
                            get_key KEY; echo "$KEY"
                            [[ yY == *$KEY* ]] && run push origin --delete "${branch#*/}"
                        else
                            echo -n "$NSH_PROMPT local branch ${branch#*/} will be deleted. Continue? (y/n) "
                            get_key KEY; echo "$KEY"
                            [[ yY == *$KEY* ]] && run branch -D "$branch"
                        fi
                    fi
                fi
            else
                run $op "$files" 
            fi
        fi
    done
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

read_string() {
    local str= && [[ $1 == --initial ]] && str="$2" && shift && shift
    local cursor=${#str}
    get_cursor_pos
    show_cursor
    while true; do
        local cx=$((cursor%COLUMNS))
        local cy=$((cursor/COLUMNS))
        hide_cursor
        move_cursor "$((__ROW__+cy));$__COL__"
        if [[ $cursor -lt ${#str} ]]; then
            echo "$str"
            move_cursor "$((__ROW__+cy));$__COL__"
        fi
        echo -n "${str:0:$cursor}"
        show_cursor
        get_key KEY </dev/tty
        case $KEY in
        $'\e'|$'\04')
            str=
            break
            ;;
        $'\t')
            local pre="${str:0:$cursor}"
            local post="${str:$cursor}"
            str="$pre    $post"
            cursor=$((cursor+4))
            ;;
        $'\177'|$'\b') # backspace
            if [ $cursor -gt 0 ]; then
                local pre="${str:0:$cursor}"
                local post="${str:$cursor}"
                str="${pre%?}$post"
                move_cursor "$((__ROW__+cy));$__COL__"
                echo -n "$str "
                ((cursor--))
            fi
            ;;
        $'\e[3~') # del
            local pre="${str:0:$cursor}"
            local post="${str:$cursor}"
            str="$pre${post:1}"
            echo -n "$str "
            ;;
        $'\e[D')
            [[ $cursor -gt 0 ]] && ((cursor--))
            ;;
        $'\e[C')
            [[ $cursor -lt ${#str} ]] && ((cursor++))
            ;;
        $'\e[1~'|$'\e[H')
            cursor=0
            ;;
        $'\e[4~'|$'\e[F')
            cursor=${#str}
            ;;
        $'\n')
            cursor=-1
            break
            ;;
        [[:print:]])
            local pre="${str:0:$cursor}"
            local post="${str:$cursor}"
            str="$pre$KEY$post"
            ((cursor++))
            ;;
        esac
    done
    printf -v "${1:-str}" "%s" "$str"
}

read_command() {
    local prefix=
    local cmd=
    local cur=0
    local pre post cand word chunk
    local iword ichunk
    local KEY
    shopt -s nocaseglob
    update_dotglob() 
    {
        if [[ $NSH_SHOW_HIDDEN_FILES -ne 0 ]]; then
            shopt -s dotglob
        else
            shopt -u dotglob
        fi
    }
    toggle_dotglob() {
        [[ $NSH_SHOW_HIDDEN_FILES -ne 0 ]] && NSH_SHOW_HIDDEN_FILES=0 || NSH_SHOW_HIDDEN_FILES=1
        update_dotglob
    }
    update_dotglob

    [[ $1 == --prefix ]] && prefix="$2" && shift && shift && echo -ne "\r\e[0m$prefix" >&2
    [[ $1 == --cmd ]] && cmd="$2" && cur=${#cmd} && shift && shift && echo -n "$cmd" >&2
    iword=$cur && [[ "$cmd" == *\ * ]] && iword="${cmd% *} " && iword=${#iword}
    ichunk=$iword

    echo -ne '\e[J'
    while true; do
        pre="${cmd:0:$cur}"
        post="${cmd:$cur}"
        KEY="$NEXT_KEY" && NEXT_KEY= && [[ -z $KEY ]] && get_key KEY
        case $KEY in
            $'\e') # ESC
                if [[ -n $cmd ]]; then
                    echo -ne "\e[$((${#prefix}+${#cmd}))D\e[J$prefix" >&2
                    cmd=
                    cur=0
                else
                    NEXT_KEY=$'\t'
                fi
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
                    echo -n $'\b \b'"$post ${post//?/$'\b'}"$'\b' >&2
                    cmd="${pre%?}$post"
                    cur=$((cur-1))
                    # update iword
                    if [[ $cur -le $iword ]]; then
                        pre="${cmd:0:$cur}"
                        if [[ $pre == *\ * ]]; then
                            pre="${pre% *} "
                            iword=${#pre}
                        else
                            iword=0
                        fi
                    fi
                fi
                ;;
            $'\t') # tab completion
                # ls abc/def/g
                #    ^       ^
                #    iword   ichunk
                if [[ -z $cmd ]]; then
                    NEXT_KEY=$'\e[B'
                else
                    local quote=
                    while true; do
                        chunk="${pre:$ichunk}"
                        local p='-p' && [[ "$chunk" == */ ]] && p=  # to avoid //
                        cand="$(eval command ls $p -d "${pre:$iword:$((ichunk-iword))}$(fuzzy_word "${chunk:-*}")" 2>/dev/null | sed "s@^$HOME/@~/@" | sort --ignore-case --version-sort)"
                        if [[ "$cand" == *$'\n'* ]]; then
                            IFS=$'\n' read -d '' -a cand < <(echo -e "$cand" | menu --color-func put_filecolor --select --key '.' 'echo "%&\$#!@"' --key $'\t' 'echo "$1"' --key $'\n' 'echo "////done////$1"')
                            echo -ne "${prefix//?/\\b}${pre//?/\\b}$prefix$pre" >&2
                        fi
                        if [[ ${#cand[@]} -le 1 ]]; then
                            cand="${cand[0]}"
                            if [[ $cand == "%&\$#!@" ]]; then
                                toggle_dotglob
                            elif [[ -n "$cand" ]]; then
                                local enter=0 && [[ "$cand" == ////done////* ]] && enter=1 && cand="${cand:12:$((${#cand}-12))}"
                                cand="${cand/#$HOME\//\~\/}"
                                word="${pre:$iword}"
                                echo -ne "${word//?/\\b}$cand" >&2
                                pre="${pre:0:$iword}$cand"
                                cmd="$pre$post"
                                cur=${#pre}
                                ichunk=$cur
                                [[ $enter -ne 0 ]] && NEXT_KEY=$'\n' && break
                                [[ -f "${word/#\~/$HOME}" ]] && NEXT_KEY=\  && break
                            else
                                break
                            fi
                        else
                            cand="$(printf '"%s" ' "${cand[@]}")"
                            word="${pre:$iword}"
                            echo -ne "${word//?/\\b}$cand" >&2
                            pre="${pre:0:$iword}$cand"
                            cmd="$pre$post"
                            cur=${#pre}
                            ichunk=$cur
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
                fi
                ;;
            $'\e[A') # Up
                if [[ ${#history[@]} -gt 0 ]]; then
                    echo -ne "${pre//?/\\b}\r$(nsh_print_prompt)\e[J" >&2
                    cmd="$(menu "${history[@]}" -c 1 --initial "$HISTSIZE" --key ' ' 'echo "$1 "' --key $'\n' 'echo "////////$1"' --key $'\177'$'\b ' 'echo "${1%?}"')"
                    [[ "$cmd" == ////////* ]] && cmd="${cmd:8:$((${#cmd}-8))}" && NEXT_KEY=$'\n'
                    cur=${#cmd}
                    echo -n "$cmd" >&2
                fi
                ;;
            $'\e[B') # Down
                if [[ -z $cmd ]]; then
                    cmd=$'\t'
                    break
                else
                    cmd=
                    cur=0
                fi
                ;;
            $'\e[C') # right
                if [[ $cur -lt ${#cmd} ]]; then
                    echo -ne "${cmd:$cur:1}" >&2
                    cur=$((cur+1))
                fi
                ;;
            $'\e[D') # left
                if [[ $cur -gt 0 ]]; then
                    echo -ne '\b' >&2
                    cur=$((cur-1))
                fi
                ;;
            $'\e[1~'|$'\e[H') # home
                echo -ne "\e[$((${#prefix}+${#cmd}))D$prefix" >&2
                cur=0
                ;;
            $'\e[4~'|$'\e[F') # end
                echo -ne "\e[$((${#prefix}+${#cmd}))D$prefix$cmd" >&2
                cur=${#cmd}
                ;;
            *)
                cmd="$pre$KEY$post"
                cur=$((cur+1))
                if [[ $KEY == \  ]]; then
                    iword=$cur
                    ichunk=$cur
                fi
                echo -n "$KEY$post${post//?/$'\b'}" >&2
                ;;
        esac
    done
    shopt -u nocaseglob
    printf -v "${1:-cmd}" "%s" "$cmd"
}

# init
disable_line_wrapping
get_terminal_size
printf "%${COLUMNS}s" ' '
printf '\b\b\b    '
get_cursor_pos
echo -ne "\e[${COLUMNS}D"
__NSH_DRAWLINE_END__= && [[ $__COL__ -lt $COLUMNS ]] && __NSH_DRAWLINE_END__=$'\b'
printf "%$((COLUMNS+3))s" ' '
get_cursor_pos
if [[ $__COL__ -lt 5 ]]; then
    # terminal doesn't support disable_line_wrapping
    __WRAP_OPTION_SUPPORTED__=0
    echo -ne '\r\e[A'
else
    __WRAP_OPTION_SUPPORTED__=1
    echo -ne '\r'
fi
enable_line_wrapping

############################################################################
# main loop
############################################################################
nsh() {
    local history=() history_sizse=0
    local command ret
    local regsiter register_mode
    local trash_path=~/.cache/nsh/trash
    local tbeg telapsed
    local NEXT_KEY

    show_cursor
    enable_line_wrapping

    # load config
    config() {
        local config_file=~/.config/nsh/nshrc
        if [[ $1 == load ]]; then
            mkdir -p ~/.config/nsh
            [[ ! -e $config_file ]] && echo "$NSH_DEFAULT_CONFIG" > $config_file
        elif [[ $1 == default ]]; then
            echo "$NSH_DEFAULT_CONFIG" > $config_file
        else
            nsh_preview "$config_file"
        fi
        source "$config_file"
    }
    config load

    git_marker() {
        local m tmp p
        name="${1%/}"
        if [[ -z $__GIT_STAT__ ]]; then
            # not a git repository
            if [[ -d "$name" && -d "$name/.git" ]]; then
                m=$'\e[42m '
                if ! (command cd "$name"; command git diff --quiet 2>/dev/null); then
                    m=$'\e[41m '
                else
                    tmp="$(command cd "$name"; LANGUAGE=en_US.UTF-8 command git status -sb | head -n 1)"
                    p='\[(ahead|behind) [0-9]+\]$'
                    [[ "$tmp" =~ $p ]] && m=$'\e[43m '
                fi
                echo "$m"
            fi
        elif [[ $__GIT_CHANGES__ == *?\;* ]]; then
            if [[ "$__GIT_CHANGES__;" == *";$name;"* ]]; then
                echo -e '\e[0;41m '
            elif [[ "$__GIT_CHANGES__;" == *";!!$name;"* ]]; then
                echo -e '\e[37;41m!'
            elif [[ "$__GIT_CHANGES__;" == *";??$name;"* ]]; then
                echo -e '\e[30;48;5;248m?'
            else
                echo \ 
            fi
        fi
    }
    nsheval() {
        [[ $# -gt 0 ]] && command="$@"
        [[ "$command" == '~' || "$command" == '~/'* ]] && command="$HOME/${commnad#?}"
        if [[ -d "$command" ]]; then
            command="cd $command"
        elif [[ -e "$command" ]]; then
            if [[ "$command" == *.py ]]; then
                command="python $command"
            elif [[ -x "$command" ]]; then
                [[ "$command" != './'* ]] && command="./$command"
            fi
        fi
        tbeg=$(get_timestamp)
        trap 'abcd &>/dev/null' INT
        eval "$command"
        ret=$?
        telapsed=$((($(get_timestamp)-tbeg+500)/1000))
        command="$(strip_spaces "$command")"
        get_cursor_pos
        [[ $__COL__ -gt 1 ]] && echo $'\e[0;30;43m'"\n"$'\e[0m'
        [[ $ret -ne 0 ]] && ret=$'\e[0;31m'"[$ret returned]"$'\e[0m' || ret=
        if [[ $telapsed -gt 0 && "$command" != git ]]; then
            local h=$((telapsed/3600))
            local m=$(((telapsed%3600)/60))
            local s=$((telapsed%60))
            ret+=$'\e[0;33m['
            [[ $h > 0 ]] && ret+="${h}h "
            [[ $h > 0 || $m > 0 ]] && ret+="${m}m "
            ret+="${s}s elapsed]"$'\e[0m'
        fi
        [[ -n $ret ]] && echo "$ret"$'\e[J'
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
        command=
        trap - INT
    }
    trash() {
        [[ -n "$(ls -A "$trash_path" 2>/dev/null)" ]] && rm -rf "$trash_path"
        mkdir -p "$trash_path"
        mv "$@" "$trash_path" 2>/dev/null
        IFS=$'\n' read -d '' -a register < <(ls -d "$trash_path"/*)
        register_mode=--mv
    }

    while true; do
        read_command --prefix "$(nsh_print_prompt)" --cmd "$command" command

        if [[ "$command" == $'\t' ]]; then
            # explore
            local line dirs files ret
            local git_color
            while true; do
                IFS=$'\n' read -sdR __GIT_STAT__ git_color __GIT_CHANGES__ < <(git_status)
                [[ -n $__GIT_STAT__ ]] && __GIT_STAT__=$' \e[30;'"$((git_color+10))m($__GIT_STAT__)"$'\e[0m'
                echo -e "\r\e[0;30;48;5;248m$(dirs)$__GIT_STAT__\e[30;48;5;248m\e[K\e[0m" >&2
                dirs=() files=()
                [[ "$(pwd)" != / ]] && dirs+=("../")
                while IFS= read line; do
                    if [[ -d "$line" ]]; then
                        dirs+=("$line/")
                    else
                        files+=("$line")
                    fi
                done < <(command ls -d * 2>/dev/null | sort --ignore-case --version-sort)
                IFS=$'\n' read -d '' -a ret < <(menu "${dirs[@]}" "${files[@]}" --color-func put_filecolor --marker-func git_marker --select --key $'\t' 'nsh_preview $1 >&2...' --key '.' 'echo "////dotglob////"' --key '~' 'echo $HOME' --key r 'echo ./' --key ':' 'echo "////////"; print_selected; quit; echo >&2' --key H 'echo ../' --key y 'echo "////yank////"; print_selected force; quit' --key p 'echo "////paste////"' --key d 'echo "////delete////"; print_selected force' --key i 'echo "////rename////"; echo "$1"; quit' --key $'\07' 'echo "////git////"' --key - 'echo "////back////"')
                [[ ${#ret[@]} -eq 0 ]] && break
                if [[ ${#ret[@]} -gt 1 || "${ret[0]}" == '////'* ]]; then
                    if [[ "${ret[0]}" == '////dotglob////' ]]; then
                        toggle_dotglob
                        ret=
                    else
                        if [[ "${ret[0]}" == '////yank////' ]]; then
                            if [[ ${#ret[@]} -gt 1 ]]; then
                                local d="$(pwd)" && [[ $d == / ]] && d=
                                for ((i=1; i<${#ret[@]}; i++)); do
                                    ret[$i]="$d/${ret[$i]}"
                                done
                                unset ret[0]
                                register=("${ret[@]}")
                                register_mode=--cp
                                if [[ ${#register[@]} -gt 1 ]]; then
                                    echo "$NSH_PROMPT yanked ${#register[@]} files"
                                else
                                    echo "$NSH_PROMPT yanked: ${register[0]/#$d\//}"
                                fi
                                echo
                            fi
                        elif [[ "${ret[0]}" == '////paste////' ]]; then
                            if [[ -n $register_mode ]]; then
                                cpmv $register_mode "${register[@]}" .
                                echo
                                register=()
                                register_mode=
                            fi
                        elif [[ "${ret[0]}" == '////delete////' ]]; then
                            unset ret[0]
                            echo -e "\e[A\e[0;30;46m\e[KDelete ${#ret[@]} file(s)? (yd/n)\e[0m " >&2
                            get_key KEY
                            echo -e "\e[A\r\e[0;30;48;5;248m$(dirs)$__GIT_STAT__\e[30;48;5;248m\e[K\e[0m" >&2
                            [[ yYd == *$KEY* ]] && trash "${ret[@]}"
                        elif [[ "${ret[0]}" == '////rename////' ]]; then
                            echo -n "$NSH_PROMPT rename: "
                            read_string --initial "${ret[1]}" line
                            [[ -n "$line" ]] && mv "${ret[1]}" "$line"
                        elif [[ "${ret[0]}" == '////git////' ]]; then
                            echo -ne "\e[A\e[J$(nsh_print_prompt)git"
                            nsheval git
                            echo
                        elif [[ "${ret[0]}" == '////back////' ]]; then
                            cd - &>/dev/null
                        else
                            [[ "${ret[0]}" == '////////' ]] && unset ret[0]
                            [[ ${#ret[@]} -gt 0 ]] && ret="$(printf '"%s" ' "${ret[@]}")" && ret="${ret% }"
                            break
                        fi
                    fi
                else
                    ret="$(strip_escape "$ret")"
                    if [[ -d "$ret" ]]; then
                        cd "$ret"
                    else
                        if [[ $ret == *.py ]]; then
                            ret="python $ret"
                        elif [[ -x "$ret" ]]; then
                            ret="./$ret"
                        fi
                        break
                    fi
                fi
                echo -ne '\e[A\e[0m\e[J' >&2
            done
            echo -ne '\e[A\e[0m\e[J' >&2
            [[ -n $ret ]] && command="$ret " || command=
        elif [[ -n $command ]]; then
            nsheval
        fi
    done
}

(return 0 2>/dev/null) || (show_logo && nsh)

