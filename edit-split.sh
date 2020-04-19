#!/bin/bash

wav="$1"

mplayer=${MPLAYER:-mplayer}

tty=`tty`

parse_time () {
    # 0:09:24.300
    echo "$1" | tr '.:' '\t'
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

ms_to_s () {
    input="$(cat)"
    printf "%04d\n" "$input" | sed -r 's/([0-9])([0-9]{3})$/\1.\2/'
}

play_ms_start_duration () {
    start_ms="$1"
    duration_ms="$2"
    #echo "Doing: " ${mplayer} -really-quiet -ss $( echo $start_ms | ms_to_s ) \
    #  -endpos $( echo $duration_ms | ms_to_s ) \
    #  "$wav" 1>&2
    ${mplayer} -really-quiet -ss $( echo $start_ms | ms_to_s ) \
      -endpos $( echo $duration_ms | ms_to_s ) \
      "$wav" <"$tty"
}

declare -a starts
declare -a ends

while read line; do
    case "$line" in
        ('#'*) ;;
        ('[Tracks]') ;;
        ('') ;;
        (Track*)
            num="$( echo "$line" | sed -rn '/Track([0-9]+)(start|end)=.*/ {s//\1/;p}' )"
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

echo "Count is $count"

if [[ $count -gt 1 ]]; then
# HACK the ends to go up to the next 
for n in `seq 1 $(( $count - 1 ))`; do
    echo "Bumping the end of $n (${ends[$n]}) up to the start of $(($n + 1)) (${starts[$(($n + 1))]})" 1>&2
    ends[$n]="${starts[$(($n + 1))]}"
done
fi
echo "Bumping the end of $(($count)) (${ends[$(($count - 1))]}) up to the file end ($fileend)" 1>&2
ends[$(($count))]="$fileend"

print_state () {
    for n in `seq 1 $count`; do
        echo "$n starts at ${starts[$n]}" 1>&2
        echo "$n ends   at ${ends[$n]}" 1>&2
    done
}
print_state

for n in `seq 1 $count`; do
    if [[ "$program" == "" ]]; then
        sep=''
    else
        sep=$'\n'
    fi
    program="${program}${sep}p${n}+5 Playing $n from start, 5s; OK?"
    sep=$'\n'
    program="${program}${sep}p${n}-5 Playing $n to end, 5s; OK?"
done
program="${program}${sep}w"

#echo "Program is:" 1>&2
#echo "$program" 1>&2

parse () {
    input="$1"
    regex="([a-z])([0-9]+)?([-\+])?([0-9]+)?"
    ins="$( echo "$input" | sed -rn "/$regex/ {s//\1/;p}" )"
    tgt="$( echo "$input" | sed -rn "/$regex/ {s//\2/;p}" )"
    dir="$( echo "$input" | sed -rn "/$regex/ {s//\3/;p}" )"
    arg="$( echo "$input" | sed -rn "/$regex/ {s//\4/;p}" )"
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
            echo "Doing play" 1>&2
            case "$dir" in
                ('-')
                    # play from end - Ns, for Ns
                    play_ms_start_duration $(( $(time_in_ms $(parse_time ${ends[$tgt]}) ) - ($arg * 1000) )) $(($arg * 1000))
                ;;
                ('+')
                    # play from start, for Ns
                    play_ms_start_duration $(time_in_ms $(parse_time ${starts[$tgt]}) ) $(($arg * 1000))
                ;;
                (*)
                    echo "Did not understand play dir: $dir"
                    false
                ;;
            esac
        ;;
        ('l') # visualize it
            echo "Doing viz" 1>&2
        ;;
        ('m') # merge
            echo "Doing merge" 1>&2
        ;;
        ('s') # split
            echo "Doing split" 1>&2
        ;;
        ('d') # drop
            echo "Doing drop" 1>&2
            # HOW can we easily do drop?
            # We need to
            # - shuffle the starts and ends of later tracks along
            # - delete any pending commands on the dropped track
            # - in-place-rewrite any pending commands so that track numbers in them are rewritten
            # The command stuff may be easier if the commands
            # are kept in an array
            # and we have a "program counter" that is the next-to-execute array index
        ;;
        ('n') # nudge
            echo "Doing nudge" 1>&2
            # nN-5 means move the end of track N back 5s
            # i.e. also move the start of track N+1 back 5s
            # nN+5 means move the start of track N forward 5s
            # i.e. also move the end of track N-1 forward 5s
            case "$dir" in
                ('-')
                    new_boundary="$(print_time_ms $(( $(time_in_ms $(parse_time ${ends[$tgt]}) ) - ($arg * 1000) )) )"
                    ends[$tgt]="$new_boundary"
                    starts[$(($tgt +1))]="$new_boundary"
                    print_state
                ;;
                ('+')
                    new_boundary="$(print_time_ms $(( $(time_in_ms $(parse_time ${starts[$tgt]}) ) + ($arg * 1000) )) )"
                    starts[$tgt]="$new_boundary"
                    ends[$(($tgt -1))]="$new_boundary"
                    print_state
                ;;
                (*)
                    echo "Did not understand nudge dir: $dir"
                    false
                ;;
            esac
        ;;
        ('q') # quit
            echo "Doing quit" 1>&2
            exit 0
        ;;
        ('w') # write out files
            echo "Doing write" 1>&2
            # use mplayer -ao pcm
        ;;
        (*)
            echo "Did not understand command $cmd: $resp"
            false
        ;;
    esac
}

while read cmd prompt; do
    program_cmd="$cmd"
    while true; do
        echo -n "[$cmd] ${prompt} "
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
            ;;
        esac
    done
done<<<"$program"
