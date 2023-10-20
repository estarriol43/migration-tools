ROUNDS=10

# directory to store output file for each round
OUTPUT_DIR="./x86-pseudo-apache-precopy"
# skip round when output file exists in OUTPUT_DIR
USE_PREV_FILE="false"
# file for final statistic result of all rounds
OUTPUT_FILE="$OUTPUT_DIR/eval_result.txt"

SRC_IP="10.10.1.1"
DST_IP="10.10.1.2"
GUEST_IP="10.10.1.5"

QEMU_PATH="/mydata/qemu-sev"
VM_KERNEL="/mydata/nfs/bzImage"
VM_DISK_IMAGE="/mydata/cloud-1804.img"
NFS_PATH="/mydata/nfs/cloud-1804.img"
RAMFS_IMAGE="/mydata/nfs/ramdisk.img"
UEFI_BIOS_CODE="/mydata/nfs/OVMF_CODE.fd"
UEFI_BIOS_VARS="/mydata/nfs/OVMF_VARS.fd"
SEV_CERT="/mydata/nfs/ask_ark_rome.cert"

MEM="1024"
SMP="4"
MONITOR_PORT="1234"
QMP="1235"
CMDLINE=""
MIGRATION_PORT="8888"

QEMU_CMD="$QEMU_PATH/build/qemu-system-x86_64 \
    -kernel $VM_KERNEL \
    -append \"console=ttyS0 nokaslr root=/dev/vda rw $CMDLINE\" \
    -drive if=none,file=$NFS_PATH,id=vda,cache=none,format=raw \
    -device virtio-blk-pci,drive=vda \
    -netdev tap,id=net1,helper=$QEMU_PATH/build/qemu-bridge-helper,vhost=on \
    -device virtio-net-pci,netdev=net1,mac=de:ad:be:ef:f6:5f \
    -m $MEM \
    -machine q35 \
    -enable-kvm \
    -cpu host \
    -smp $SMP \
    -monitor telnet:0:$MONITOR_PORT,server,nowait \
    -qmp tcp:0:$QMP,server=on,wait=off \
    -drive if=pflash,format=raw,unit=0,file=$UEFI_BIOS_CODE,readonly=on \
    -drive if=pflash,format=raw,unit=1,file=$UEFI_BIOS_VARS \
    -display none \
    -daemonize"
SRC_QEMU_CMD="$QEMU_CMD"
DST_QEMU_CMD="$QEMU_CMD \
    -incoming defer"
MIGRATION_PROPERTIES=(
    "migrate_set_parameter downtime-limit 16000"
    "migrate_set_parameter max-bandwidth 10g"
    # "migrate_set_parameter multifd-channels 1"
    # "migrate_set_capability multifd on"
    # "migrate_set_capability postcopy-ram off"
)
MIGRATION_TIMEOUT=800
# Fields to record and count for
DATA_FIELDS=(
    "downtime"
    "total time"
    "throughput"
    "setup"
    "transferred ram"
)

# return values for callback functions,
NEED_REBOOT=1
RETRY=2
ABORT=3

# Will be called at the start of each round
function setup_vm_env() {
    log_msg "Setting up environment"
    if ! sudo cp $VM_DISK_IMAGE $NFS_PATH; then
        err_msg "Cannot setup disk image"
        return $RETRY
    fi 
    return 0
}

# Will be called after the guest booted,
# and after the migration
function check_guest_status() {
    log_msg "Checking vm's status"
    if ! ping -c 1 "$GUEST_IP" >&2 ; then
        return $RETRY
    fi
    return 0
}

# Will be called before migration started,
# with current round as argument ($1)
function benchmark_setup() {

    log_msg "Setting up benchmark"
    #
    # Exmaple usage: Apache benchmark
    #
    AB_BIN="/mydata/httpd-2.4.54/support/ab"
    AB_PID=-1
    local cnt=0
    while ! curl -m 10 "http://$GUEST_IP/" > /dev/null 2>&1; do
        log_msg "waiting for guest's apache server"
        (( cnt += 1))
        if [[ cnt -ge 6 ]]; then
            err_msg "Guest's apache server broken"
            return $RETRY
        fi
    done
    $AB_BIN -c 100 -n 800000000000 -s 30 -g "$OUTPUT_DIR/ab$1" http://$GUEST_IP/ >&2 & 
    AB_PID=$!

    return 0	
}

function pre_migration() {
    log_msg "pre_migration()"
    python3 sev-setup.py --sev /proj/ntucsie-PG0/estarriol/ask_ark_rome.cert
    return $?
}

# Will be called just after migration started
function post_migration() {

    log_msg "post_migration()"
    #
    # Example usage: postcopy 
    #
    #sleep 5s
    #if ! qemu_monitor_send $SRC_IP $MONITOR_PORT "migrate_start_postcopy"; then
    #    return $RETRY
    #fi

    return 0
}

# Will be called after migration completed,
function benchmark_clean_up() {

    log_msg "Cleaning up benchmark"

    #
    # Exmaple usage: Apache benchmark
    #
    AB_PYTHON_SCRIPT="./ab-plot.py"
    log_msg "Checking ab validity"
    if ! ps -p $AB_PID > /dev/null; then
        err_msg "Ab stopped early, but I don't fucking care"
        return 0
    fi
    log_msg "Stopping ab"
    sudo kill -SIGINT "$AB_PID"; sleep 20s
	if [[ ! -f "$OUTPUT_DIR/ab$1" ]]; then
        err_msg "Ab output missing"
        return $RETRY
	fi 
    if ! curl -m 10 "http://$GUEST_IP/" > /dev/null 2>&1 ; then
        err_msg "Guest's apache server downed after migration"
        return $RETRY
    fi
    dt=$(echo "$OUTPUT_DIR/$1.png" | python3 $AB_PYTHON_SCRIPT $OUTPUT_DIR/ab$1 | awk '{print $2}')
    if [[ -z $dt ]]; then
        err_msg "Ab python script failed"
        return $RETRY
    fi
    zip "$OUTPUT_DIR/ab$1".zip "$OUTPUT_DIR/ab$1"
    rm "$OUTPUT_DIR/ab$1"
    log_msg "ab downtime: $dt ms"
    echo "ab downtime: $dt ms" >> $OUTPUT_DIR/$1

    return 0
}
# with current round as argument ($1)
