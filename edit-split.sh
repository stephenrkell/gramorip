#!/bin/bash

TEMP=`getopt -q -o n -n $(basename $0) -- "$@"`
#echo "TEMP is $TEMP" 1>&2
eval set -- "$TEMP"
while true; do case "$1" in
    (-n)
        #echo "Setting no-bump" 1>&2
        NO_BUMP=1
        ;;
    (--)
        shift
        break
        ;;
esac; shift || break
done

#echo "\$0 is $0" 1>&2
#echo "\$1 is $1" 1>&2
wav="$1"

test -e "$wav".tracks || \
  (echo "Did not found tracks file: ${wav}.tracks" 1>&2; false) || \
  exit 1

# sometimes sox generates a WAV file that confuses mplayer's default (lavcpref)
# demuxer... amazing really
mplayer=${MPLAYER:-mplayer -really-quiet -demuxer lavf}
mplayer_playback_opts=${MPLAYER_OPTS:-}

tty=`tty`

parse_time () {
    # 0:09:24.300
    output="$( echo "$1" | tr '.:[[:blank:]]' '\n' | sed -r 's/^0*([^0]+)$/\1/' | tr '\n' '\t' )"
    # now CHECK for sanity
    read h m s ms <<<"$output"
    (test -n "$h" && test -n "$m" && test -n "$s" && test -n "$ms") || \
        echo "Couldn't parse time '$1': got hour $h min $m sec $s msec $ms" 1>&2
    echo "$output"
}

print_time_ms () {
    printf "%01d:%02d:%02d.%03d" \
        $(( $1 / ( 60 * 60 * 1000 ) )) \
        $(( ( $1 / ( 60 * 1000 ) ) % 60 )) \
        $(( ( $1 / ( 1000 ) ) % 60 )) \
        $(( $1 % 1000 ))
}

time_in_ms () {
    #echo "Got time: $@" 1>&2
    h="$1"
    m="$2"
    s="$3"
    ms="$4"
    echo $(( ( $h * 60 * 60 * 1000 ) + ($m * 60 * 1000) + ($s * 1000) + $ms ))
}

ms_to_s_decimal () {
    input="$(cat)"
    #printf "%04d\n" "$input" | sed -r 's/([0-9])([0-9]{3})$/\1.\2/'
    echo "$input" | awk '{print $0 / 1000.0}'
}
s_decimal_to_ms () {
    input="$(cat)"
    echo "$input" | awk '{print $0 * 1000}'
}

sox_extract_wav_ms_start_duration () {
    start_ms="$1"
    duration_ms="$2"
    if [[ -n "$TRACE_SOX" ]]; then
        echo sox "$wav" -t wav - trim $( echo $start_ms | ms_to_s_decimal ) \
            $( echo $duration_ms | ms_to_s_decimal ) 1>&2
    fi
    sox "$wav" -t wav - trim $( echo $start_ms | ms_to_s_decimal ) \
        $( echo $duration_ms | ms_to_s_decimal )
}

play_ms_start_duration () {
    start_ms="$1"
    duration_ms="$2"
    #echo "Doing: "
    #"${mplayer}" ${mplayer_playback_opts} -ss $( echo $start_ms | ms_to_s_decimal ) \
    #  -endpos $( echo $duration_ms | ms_to_s_decimal ) \
    #  "$wav" <"$tty"
    #sox "$wav" - trim "$( echo "$start_ms" | ms_to_s_decimal )" "$( echo "$duration_ms" | ms_to_s_decimal )" \
    #   "${mplayer}" ${mplayer_playback_opts} -
    tmpfile="$(mktemp --suffix ".wav" )"
    sox_extract_wav_ms_start_duration "$start_ms" "$duration_ms" >"$tmpfile"
    #echo "tmpfile is $tmpfile" 1>&2
    ${mplayer} ${mplayer_playback_opts} \
      "$tmpfile" <"$tty"
# -ss $( echo $start_ms | ms_to_s_decimal ) \
#      -endpos $( echo $duration_ms | ms_to_s_decimal ) \
    rm -f "$tmpfile" 1>&2
}

save_ms_start_duration () {
    destfile="$1"
    start_ms="$2"
    duration_ms="$3"
    sox_extract_wav_ms_start_duration "$start_ms" "$duration_ms" > "$destfile"
}

declare -a starts
declare -a ends

while read line; do
    case "$line" in
        ('#'*) ;;
        ('[Tracks]') ;;
        ('') ;;
        (Track*)
            num="$( echo "$line" | sed -rn '/Track([0-9]+)(start|end)=.*/ {s//\1/;p}' | sed 's/^0*//' )"
            which="$( echo "$line" | sed -rn '/Track([0-9]+)(start|end)=.*/ {s//\2/;p}' )"
            time="$( echo "$line" | sed -rn '/Track([0-9]+)(start|end)=(.*)/ {s//\3/;p}' )"
            case "$which" in
                (start)
                    echo "$(($num)) starts at $time" 1>&2
                    starts[$(($num))]="$time"
                ;;
                (end)
                    echo "$(($num)) ends at $time" 1>&2
                    ends[$(($num))]="$time"
                ;;
                (*) echo "Did not understand: $line" 1>&2; exit 1 ;;
            esac
        ;;
        ('Number_of_tracks='*)
            count="$( echo "$line" | sed 's/^Number_of_tracks=//' )"
        ;;
        ('Fileend='*)
            fileend="$( echo "$line" | sed 's/^Fileend=//' )"
        ;;
    esac
done < "$wav".tracks

save_state () {
    # comment any uncommented track boundary/count lines
    # (we leave Fileend alone)
    tracksfile="${1:-"$wav".tracks}"
	sed -ri '/^[^#]*(Track([0-9]+)(start|end)|Number_of_tracks)=/ s//# &/' "$tracksfile"
    # append our actual state
    (for n in `seq 1 $count`; do
       printf "Track%02dstart=${starts[$n]}\n" "$n"
       printf "Track%02dend=${ends[$n]}\n" "$n"
    done; printf "Number_of_tracks=%d\n" "$count") >> "$tracksfile"
}

echo "Count is $count"

if [[ -z "$NO_BUMP" ]]; then
if [[ $count -gt 1 ]]; then
# hack the ends to go up to the next track's beginning
for n in `seq 1 $(( $count - 1 ))`; do
    echo "Bumping the end of $n (${ends[$n]}) up to the start of $(($n + 1)) (${starts[$(($n + 1))]})" 1>&2
    ends[$n]="${starts[$(($n + 1))]}"
done
fi
echo "Bumping the end of $(($count)) (${ends[$(($count - 1))]}) up to the file end ($fileend)" 1>&2
ends[$(($count))]="$fileend"
fi

print_state () {
    for n in `seq 1 $count`; do
        echo    "$n starts at ${starts[$n]}" 1>&2
        echo -n "$n ends   at ${ends[$n]} " 1>&2
        local length=$(( $(time_in_ms $(parse_time ${ends[$n]}) ) - $(time_in_ms $(parse_time ${starts[$n]}) ) ))
        echo "(length: $(print_time_ms "$length"))" 1>&2
    done
}
print_state

for n in `seq 1 $count`; do
    if [[ "$program" == "" ]]; then
        sep=''
    else
        sep=$'\n'
    fi
    # Prompts shouldn't mention tracks by name, as w don't try to rewrite them
    # when track numbers change. Instead we shell-expand them, so just say '$tgt'
    program="${program}${sep}p${n}+10 Playing "'$tgt'" from start, 10s; OK?"
    sep=$'\n'
    program="${program}${sep}p${n}-10 Playing "'$tgt'" to end, 10s; OK?"
done
program="${program}${sep}w Writing the output .wav files; OK?"

#echo "Program is:" 1>&2
#echo "$program" 1>&2

parse_into () {
    local input="$1"
    # echo "parsing: $input (into vars: $2 $3 $4 $5)" 1>&2
    regex="([a-z])([0-9]+)?(([-\+])([-\+]?[0-9]+(\.[0-9]+)?)?)?"
    # FIXME: why does 'declare' not work here?
    eval "${2}='$( echo "$input" | sed -rn "/$regex/ {s//\1/;p}" )'"
    eval "${3}='$( echo "$input" | sed -rn "/$regex/ {s//\2/;p}" )'"
    eval "${4}='$( echo "$input" | sed -rn "/$regex/ {s//\4/;p}" )'"
    eval "${5}='$( echo "$input" | sed -rn "/$regex/ {s//\5/;p}" )'"
}
# "last target" is really "the current track", so initially 1
last_tgt=1
parse () {
    parse_into "$1" ins tgt dir arg
    # remember which track we're acting on
    if [[ -n "$tgt" ]]; then last_tgt="$tgt"; fi
}

drop_prog_instr () {
    local idx="$1"
    for n in `seq $(( $idx + 1 )) $(( $proglen - 1 ))`; do
        program_cmds[$(( $n - 1 ))]="${program_cmds[$n]}"
        program_prompts[$(( $n - 1 ))]="${program_prompts[$n]}"
    done
    proglen=$(( $proglen - 1 ))
    if [[ $cmdidx -ge $idx ]]; then
        cmdidx=$(( $cmdidx - 1 ))
        echo "cmdidx fixed up to $cmdidx" 1>&2
    fi
}
dup_prog_instr () {
    local idx="$1"
    local new_tgt="$2"
    for n in `seq $proglen -1 $(( $idx + 1 ))`; do
        program_cmds[$(( $n + 1 ))]="${program_cmds[$n]}"
        program_prompts[$(( $n + 1 ))]="${program_prompts[$n]}"
    done
    program_cmds[$(( $idx + 1 ))]="$(echo "${program_cmds[$idx]}" | sed -r "s/([a-z])($idx)(\$|[-\+])/\1${new_tgt}\2/" )"
    program_prompts[$(( $idx + 1 ))]="${program_prompts[$idx]}"
    proglen=$(( $proglen + 1 ))
    if [[ $cmdidx -gt $idx ]]; then
        cmdidx=$(( $cmdidx + 1 ))
        echo "cmdidx fixed up to $cmdidx" 1>&2
    fi
}

drop_at () {
    local to_drop=${1:-${tgt:-${last_tgt}}}
    # To drop a track, it means:
    # - shuffle the starts and ends of later tracks back 1
    # - delete any pending commands on the dropped track
    # - in-place-rewrite any pending commands so that track numbers in them are rewritten
    # The command stuff may be easier if the commands
    # are kept in an array
    # and we have a "program counter" that is the next-to-execute array index
    for n in `seq $(( $to_drop + 1 )) $count`; do
        echo "We would shuffle back track $n by one"
        starts[$(($n - 1))]=${starts[$n]}
        ends[$(($n - 1))]=${ends[$n]}
    done
    starts[$count]=""
    ends[$count]=""
    # Now rewrite the program so that
    # - any command whose target is n, for n > tgt, is renumbered
    # - any command whose target is tgt is deleted,
    #       and if cmdidx is >=
    local pos=0
    while ! [[ $pos -eq $proglen ]]; do
        local cmd="${program_cmds[$pos]}"
        parse_into "$cmd" this_ins this_tgt this_dir this_arg
        if [[ $this_tgt -eq $to_drop ]]; then
            # we need to drop this instr
            echo "Dropping instruction: $cmd" 1>&2
            drop_prog_instr $pos
            # ... and go back to the start of the program, so our pos is not out of whack
            pos=0
            continue
        elif [[ $this_tgt -gt $to_drop ]]; then
            # all track#s greater than tgt are now one less
            echo "Rewriting instruction: $cmd" 1>&2
            program_cmds[$pos]="${this_ins}$(($this_tgt - 1))${this_dir}${this_arg}"
        fi
        pos=$(( $pos + 1 ))
    done
    count=$(( $count - 1 ))
    echo "We now have $count tracks"
}

dup_at () {
    local to_dup=${1:-${tgt:-${last_tgt}}}
    echo "DEBUG: duping $to_dup" 1>&2
    # To duplicate a track, it means:
    # - shuffle the starts and ends of later tracks forward 1
    # - duplicate any pending commands on the dropped track,...
    # - ... rewriting the
    # - ... an track numbers in them are rewritten
    for n in `seq $count -1 $(( $to_dup ))`; do
        echo "We would shuffle forward track $n by one"
        starts[$(($n + 1))]=${starts[$n]}
        ends[$(($n + 1))]=${ends[$n]}
    done
    count=$(( $count + 1 ))
    # Now rewrite the program so that
    # - any command whose target is n, for n = tgt, is duplicated
    # - any command whose target is n, for n > tgt, is renumbered
    local pos=0
    while ! [[ $pos -eq $proglen ]]; do
        local cmd="${program_cmds[$pos]}"
        parse_into "$cmd" this_ins this_tgt this_dir this_arg
        if [[ $this_tgt -gt $to_dup ]]; then
            # all track#s greater than tgt are now one more
            echo "Rewriting instruction: $cmd" 1>&2
            program_cmds[$pos]="${this_ins}$(($this_tgt - 1))${this_dir}${this_arg}"
        fi
        pos=$(( $pos + 1 ))
    done
    pos=0
    while ! [[ $pos -eq $proglen ]]; do
        if [[ $this_tgt -eq $to_dup ]]; then
            # we need to duplicate this instr
            echo "Duplicating-with-renum instruction: $cmd" 1>&2
            dup_prog_instr $pos $(( $to_dup + 1 ))
            # ... and bump up our pos, to avoid infinite loop duplicating same instr
            pos=$(( $pos + 1 ))
        fi
        pos=$(( $pos + 1 ))
    done
    echo "We now have $count tracks"
}

eval_it () {
    case "$ins" in
        ('y') # we should not get here!
            echo "This should not happen!" 1>&2
            false
        ;;
        ('') # we didn't understand; go round again
            echo "Did not understand (empty command)"
            false
        ;;
        ('p') # play the track
            echo "Doing play ('q' to stop)" 1>&2
            case "$dir" in
                ('-')
                    # play from end - Ns, for Ns
                    play_ms_start_duration $(( $(time_in_ms $(parse_time ${ends[$tgt]}) ) - $(s_decimal_to_ms <<<${arg:-5}) )) $(s_decimal_to_ms<<<${arg:-5})
                ;;
                ('+')
                    # play from start, for Ns
                    play_ms_start_duration $(time_in_ms $(parse_time ${starts[$tgt]}) ) $(s_decimal_to_ms<<<${arg:-5})
                ;;
                (*)
                    echo "Did not understand play dir: $dir"
                    false
                ;;
            esac
        ;;
        ('c') # chop/cut
            echo "Doing chop" 1>&2
            dup_at "$tgt"
            echo "DEBUG: after dup" 1>&2
            print_state
            echo "DEBUG: now fixing up start/end" 1>&2
            case "$dir" in
                ('-')
                    new_boundary="$(print_time_ms $(( $(time_in_ms $(parse_time ${ends[$tgt]}) ) - $(s_decimal_to_ms<<<${arg:-5}) )) )"
                ;;
                ('+')
                    new_boundary="$(print_time_ms $(( $(time_in_ms $(parse_time ${starts[$tgt]}) ) + $(s_decimal_to_ms<<<${arg:-5}) )) )"
                ;;
                (*)
                    echo "Did not understand chop dir: $dir"
                    false
                ;;
            esac
            ends[$tgt]="$new_boundary"
            starts[$(( $tgt + 1 ))]="$new_boundary"
            print_state
        ;;
        ('d') # drop
            echo "Doing drop" 1>&2
            drop_at "$tgt"
            print_state
        ;;
        ('l') # list
            print_state
        ;;
        ('m') # merge
            # we impl this like drop, but remember+restore the dropped boundary
            case "$dir" in
                ('-')
                    echo "Doing merge backwards of $tgt" 1>&2
                    remembered_start="${starts[$(($tgt - 1))]}"
                    drop_at $(( $tgt - 1 ))
                    tgt=$(( $tgt - 1 ))
                    starts[$tgt]="${remembered_start}"
                    print_state
                ;;
                ('+')
                    echo "Doing merge forwards of $tgt" 1>&2
                    remembered_end="${ends[$(($tgt + 1))]}"
                    drop_at $(( $tgt + 1 ))
                    ends[$tgt]="${remembered_end}"
                    print_state
                ;;
                (*)
                    echo "Did not understand merge dir: $dir"
                    false
                ;;
            esac
        ;;
        ('n') # nudge
            echo "Doing nudge" 1>&2
            # nN-5 means move the end of track N back 5s
            # i.e. also move the start of track N+1 back 5s ONLY IF they are abutting
            # nN+5 means move the start of track N forward 5s
            # i.e. also move the end of track N-1 forward 5s ONLY IF they are abutting
            case "$dir" in
                ('-')
                    new_boundary="$(print_time_ms $(( $(time_in_ms $(parse_time ${ends[$tgt]}) ) - $(s_decimal_to_ms<<<${arg:-5}) )) )"
                    if [[ $tgt -lt $count ]] && \
                       [[ $(time_in_ms $(parse_time "${starts[$(($tgt +1))]}" "starts $tgt + 1 neg" ) ) -eq \
                          $(time_in_ms $(parse_time "${ends[$tgt]}" "ends $tgt neg" ) ) ]]; then
                        starts[$(($tgt +1))]="$new_boundary"
                    else
                        echo "Not nudging the start of $(( $tgt + 1 )); discontinuity detected"
                    fi
                    ends[$tgt]="$new_boundary"
                    print_state
                ;;
                ('+')
                    new_boundary="$(print_time_ms $(( $(time_in_ms $(parse_time ${starts[$tgt]}) "starts $tgt pos") + $(s_decimal_to_ms<<<${arg:-5}) )) )"
                    if [[ $tgt -gt 1 ]] && \
                       [[ $(time_in_ms $(parse_time "${ends[$(($tgt -1))]}" ) ) -eq \
                          $(time_in_ms $(parse_time "${starts[$tgt]}" ) ) ]]; then
                        ends[$(($tgt -1))]="$new_boundary"
                    else
                        echo "Not nudging the end of $(( $tgt - 1 )); discontinuity detected"
                    fi
                    starts[$tgt]="$new_boundary"
                    print_state
                ;;
                (*)
                    echo "Did not understand nudge dir: $dir"
                    false
                ;;
            esac
        ;;
        ('s')
            echo "Saving to .tracks file" 1>&2
            save_state
        ;;
        ('v') # visualize it
            echo "Doing viz" 1>&2
        ;;
        ('w') # write out files
            destdir="$( mktemp -d ./split-XXXXXX )" || (echo "Couldn't create output dir"; false) || exit 1
            echo "Doing write to $destdir" 1>&2
            for n in `seq 1 $count`; do
                save_ms_start_duration "${destdir}/track${n}.wav" \
                    $(time_in_ms $(parse_time ${starts[$n]}) ) \
                    $(( $(time_in_ms $(parse_time ${ends[$n]}) ) - $(time_in_ms $(parse_time ${starts[$n]}) ) )) 
            done
            # save a copy of the tracks file
            cp "$wav".tracks "$destdir"/disc.tracks && save_state "$destdir"/disc.tracks
        ;;
        ('x') # exit -- not 'quit' to avoid risk that a 'q' intended for mplayer will hit us
            echo "Doing exit" 1>&2
            exit 0
        ;;
        (*)
            echo "Did not understand command [$cmd]: $resp"
            false
        ;;
    esac
}

declare -a program_cmds
declare -a program_prompts
proglen=0
while read cmd prompt; do
    program_cmds[$proglen]="$cmd"
    program_prompts[$proglen]="$prompt"
    proglen=$(( $proglen + 1 ))
done<<<"$program"

cmdidx=0
while true; do
    # we might go multiple iterations without advancing
    # the program position
    while true; do
        cmd="${program_cmds[$cmdidx]}"
        program_cmd="$cmd"
        prompt="${program_prompts[$cmdidx]}"
        saved_cmdidx="$cmdidx"
        parse "$program_cmd" # so that we have ${tgt} defined
        echo -n "[$cmd] "
        eval "echo -n \"${prompt}\""
        echo -n " "
        read resp <"$tty"
        #  p1+5   
        #  p1-5   
        #  l      
        #  l1     
        #  m2+    
        #  m2-    
        #  s1+100 
        #  s1-20
        parse "$resp"
        case "$ins" in
            ('y'|'') # "y" means "do what the program says"
                echo "Taking from program: $program_cmd" 1>&2
                parse "$program_cmd" # now we've taken "cmd" from the program
                eval_it && break
            ;;
            ('k') # "k" means "skip this command straight away"
                break
            ;;
            (*) # the user entered a command, so do it
                # doing the eval_it will parse *again*
                eval_it # don't break -- we don't advance the program yet
                # Perhaps this deleted the current instruction; if so
                # we go around the outer loop again, to increment the ctr
                if [[ $cmdidx -lt $saved_cmdidx ]]; then
                    break
                fi
            ;;
        esac
    done
    cmdidx=$(( $cmdidx + 1 ))
done
