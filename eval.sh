#! /bin/bash

# set -x

NEED_REBOOT=1
RETRY=2
ABORT=3

BGREEN='\033[1;32m'
BCYAN='\033[1;36m'
BRED='\033[1;31m'
NC='\033[0m'

function trap_ctrlc () {
    # perform cleanup here
    err_msg "Ctrl-C caught...performing clean up"

    err_msg "Doing cleanup"

    clean_up $SRC_IP
    clean_up $DST_IP

    # exit shell script with error code 2
    # if omitted, shell script will continue execution
    exit 2
}

function log_msg() {
    echo -e "${BCYAN}$1${NC}" >&2
}

function err_msg() {
    echo -e "${BRED}$1${NC}" >&2
}

function boot_vm() {
    log_msg "Booting VM on $1"

    local ret=$( { ssh $(whoami)@$1 << EOF
    sudo /proj/ntucsie-PG0/estarriol/some-tutorials/files/migration/net.sh; sudo nohup $2
EOF
    } 2>&1 > /dev/null)

    err_msg "$ret"

    # We have to check for error manually to decide return value
    local err="Failed to retrieve host CPU features"
    if echo "$ret" | grep -q "$err"; then
        err_msg "$err"
        return "$NEED_REBOOT"
    fi
    local err="Address already in use"
    if echo "$ret" | grep -q "$err"; then
        err_msg "$err"
        return $RETRY
    fi
    local err="No such file or directory"
    if echo "$ret" | grep -q "$err"; then 
        err_msg "$err"
        return $ABORT
    fi
    local err="qemu-system-x86_64:"
    if echo "$ret" | grep "$err"; then 
        local out=$(echo "$ret" | grep "$err")
        err_msg "$out"
        return $ABORT
    fi
    return 0
}


# qemu_monitor_send(ip, port, cmd)
# * We only allow idle timeout error
function qemu_monitor_send() {
    { local err=$(echo "$3" | ncat -w 2 -i 1 $1 $2 2>&1 >&3 3>&-); } 3>&1
    if [[ "$err" != *"Ncat: Idle timeout expired"* ]]; then
        return $RETRY
    fi
    echo ""
    return 0
}

function start_migration() {
    log_msg "Starting migration"
    for cmd in "${MIGRATION_PROPERTIES[@]}"; do
        if ! qemu_monitor_send $SRC_IP $MONITOR_PORT "$cmd"; then
            return $RETRY
        fi
        if ! qemu_monitor_send $DST_IP $MONITOR_PORT "$cmd"; then
            return $RETRY
        fi
    done

    local cmd="migrate_incoming tcp:$DST_IP:$MIGRATION_PORT"
    if ! qemu_monitor_send $DST_IP $MONITOR_PORT "$cmd"; then
        return $RETRY
    fi

    local cmd="migrate -d tcp:$DST_IP:$MIGRATION_PORT"
    if ! qemu_monitor_send $SRC_IP $MONITOR_PORT "$cmd"; then
        return $RETRY
    fi
    return 0
}

# * We don't apply error check here,
# * let the function that use the info to detect failure
function qemu_migration_info_fetch() {
    echo "info migrate" | \
    ncat -w 1 -i 1 $SRC_IP $MONITOR_PORT 2> /dev/null | \
    strings | \
    tail -n +14 | \
    head -n -1
}

# qemu_migration_info_get_field(info, field_name)
function qemu_migration_info_get_field() {
    local val=$(echo "$1" | grep "^$2:")
    local val=${val#$2: }
    local val=${val%\ *}
    echo "$val"
}

function migration_is_completed() {
    local info=$(qemu_migration_info_fetch)
    local status=$(qemu_migration_info_get_field "$info" "Migration status" | cut -d " " -f 1)
    local cnt=$(qemu_migration_info_get_field "$info" "dirty sync count" | cut -d " " -f 1)
    local transferred=$(qemu_migration_info_get_field "$info" "transferred ram" | cut -d " " -f 1)
    local remaining=$(qemu_migration_info_get_field "$info" "remaining ram" | cut -d " " -f 1)
    local expected=$(qemu_migration_info_get_field "$info" "expected downtime" | cut -d " " -f 1)
    local total=$(qemu_migration_info_get_field "$info" "total time" | cut -d " " -f 1)
    log_msg "status: $status"
    log_msg "count: $cnt, transferred: $transferred, remaining: $remaining, expected: $expected, total: $total"
    if [[ $cnt -gt 80 ]]; then
        return $ABORT
    fi
    if [[ $status == "failed" ]]; then
        return $ABORT
    fi
    # if [[ $status == "" ]]; then
    #     return $ABORT
    # fi
    if [[ $status != "completed" ]]; then
        return $RETRY
    fi
    return 0
}


# qemu_migration_info_save(file_path)
# * We still don't check data validity here
function qemu_migration_info_save() {
    log_msg "Saving migration outcome"
    local info=$(qemu_migration_info_fetch)
    for field in "${DATA_FIELDS[@]}"; do
        local val=$(qemu_migration_info_get_field "$info" "$field")
        log_msg "$field: $val"
    done
    echo "$info" > $1
    echo "${MIGRATION_PROPERTIES[0]}" >> $1
    dos2unix $1
    return 0
}

function force_clean_up() {
    log_msg "Cleaning up w/ pkill"
    local cmd="sudo pkill -9 qemu"
    echo "$cmd" | ssh -q $(whoami)@$1 >/dev/null
    if [[ $? -eq 255 ]]; then
        err_msg "Failed to force clean up"
        exit 1
    fi
    return 0
}

function clean_up() {
    log_msg "Cleaning up"
    if ! qemu_monitor_send $1 $MONITOR_PORT "quit"; then
        err_msg "Failed to clean up"
        force_clean_up $1
    fi
    return 0
}

function do_migration_eval() {
    log_msg "Migration $1"

    setup_vm_env; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to setup environment"
        return $ret
    fi
    boot_vm "$SRC_IP" "$SRC_QEMU_CMD"; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to boot at src"
        return $ret
    fi
    boot_vm "$DST_IP" "$DST_QEMU_CMD"; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to boot at dst"
        return $ret
    fi
    sleep 10s
    if ! check_guest_status; then
        # second chance
        if ! check_guest_status; then
            err_msg "VM status broken"
            return $RETRY
        fi
    fi
    benchmark_setup $1; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to setup benchmark"
        return $ret
    fi
    pre_migration; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "pre_migration() failed"
        return $ret
    fi
    start_migration; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to start migration"
        return $ret
    fi
    post_migration; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "post_migration() failed"
        return $ret
    fi
    local elapsed=0
    migration_is_completed; ret=$?
    while [[ $ret != 0 ]]; do
        if [[ $ret == $ABORT ]]; then
            benchmark_clean_up $1; ret=$?
            return $RETRY
        elif [[ $ret == $RETRY ]]; then
            if [[ $elapsed -gt $MIGRATION_TIMEOUT ]]; then
                benchmark_clean_up $1; ret=$?
                err_msg "Migration timout"
                return $RETRY
            fi
        fi
        sleep 5s
        (( elapsed += 5 ))
        migration_is_completed; ret=$?
    done
    qemu_migration_info_save "$OUTPUT_DIR/$1"; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to save data"
        return $ret
    fi
    benchmark_clean_up $1; ret=$?
    if [[ $ret != 0 ]] ; then
        err_msg "Failed to clean up benchmark"
        return $ret
    fi
    if ! check_guest_status; then
        # second chance
        if ! check_guest_status; then
            err_msg "VM status broken after migration"
            return $RETRY
        fi
    fi
}

function search_downtime() {
    if [[ $POSTCOPY == "y" ]]; then
        err_msg "postcopy, don't search"
        return
    fi
    local upper=14000
    local lower=300
    local downtime=1000
    local success=0
    while true; do
        MIGRATION_PROPERTIES[0]="migrate_set_parameter downtime-limit $downtime"
        do_migration_eval "test_${downtime}"
        case $? in
            $RETRY | $ABORT | $NEED_REBOOT)
                err_msg "downtime: $downtime failed"
                clean_up $SRC_IP
                clean_up $DST_IP
                if [[ $success -gt 0 ]]; then
                    (( success -= 1 ))
                else
                    (( success = 0))
                    (( lower = downtime))
                    (( downtime = (upper + downtime) / 2 ))
                fi
                ;;
            *)
                err_msg "downtime: $downtime passed"
                clean_up $SRC_IP
                clean_up $DST_IP
                if [[ $success -lt 0 ]]; then
                    (( success += 1 ))
                else
                    (( success = 0))
                    (( upper = downtime))
                    (( downtime = (lower + downtime) / 2 ))
                fi
                ;;
        esac

        if ((upper - lower < 200 )); then
            break
        fi
    done
}

# reboot_m400(ip)
function reboot_m400() {
#     log_msg "Rebooting m400"
#     local ret=$( { ssh $(whoami)@$1 << EOF
#         sudo reboot $2
# EOF
#     } 2>&1 > /dev/null)
#     local expected="Connection to $1 closed by remote host."
#     if ! echo "$ret" | grep -q "$expected"; then
#         err_msg "Failed to reboot m400 at $1"
#         exit 1
#     fi
    return 0
}

# wait_for(ip)
function wait_for() {
    while ! ssh -q $(whoami)@$1 exit; do
        err_msg "$1 not up yet"
        sleep 30s
    done
    return 0
}

function result() {
    declare -A values
    for field in "${DATA_FIELDS[@]}"; do
        values["$field"]=0
    done
    for (( n = 0; n < $ROUNDS; n++ )); do
        local file="$OUTPUT_DIR/$n"
        if ! [[ -e "$file" ]]; then
            err_msg "$file does not exist!"
            return $ABORT
        fi
        local info=$(cat "$file")
        for field in "${DATA_FIELDS[@]}"; do
            local val=$(qemu_migration_info_get_field "$info" "$field")
            if [[ -z "$val" ]]; then
                err_msg "$file has no $field value"
                return $ABORT
            else
                values["$field"]=$(echo "$val" + ${values["$field"]}|bc)
            fi
        done
    done
    for field in "${DATA_FIELDS[@]}"; do
        local avg=$(echo "scale=4; ${values[$field]} / $ROUNDS"|bc)
        echo -n "$avg "
    done
    echo ""
}


# * Main *
source $1
mkdir $OUTPUT_DIR
trap "trap_ctrlc" 2

# log_msg "Search downtime"
# search_downtime

i=0
while [[ $i -lt $ROUNDS ]]; do

    if [[ "$USE_PREV_FILE" == "true" ]]; then
        # Skip round if we have previous output
        if [[ -e "$OUTPUT_DIR/$i" ]]; then
            log_msg "Skipping round $i"
            (( i += 1 ))
            continue
        fi
    fi

    log_msg "Evaluation round: $i"
    do_migration_eval $i

    case $? in
        $NEED_REBOOT)
            reboot_m400 $SRC_IP
            reboot_m400 $DST_IP
            wait_for $SRC_IP
            wait_for $DST_IP
            sleep 20s
            ;;
        $ABORT)
            exit 1
            ;;
        $RETRY)
            clean_up $SRC_IP
            clean_up $DST_IP
            rm $OUTPUT_DIR/$i
            ;;
        *)
            clean_up $SRC_IP
            clean_up $DST_IP
            (( i += 1 ))
            ;;
    esac
    sleep 10s
done

result >> $OUTPUT_FILE

