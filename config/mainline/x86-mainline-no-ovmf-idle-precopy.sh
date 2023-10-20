ROUNDS=10

# directory to store output file for each round
OUTPUT_DIR="./x86-mainline-no-ovmf-idle-precopy"
# skip round when output file exists in OUTPUT_DIR
USE_PREV_FILE="false"
# file for final statistic result of all rounds
OUTPUT_FILE="$OUTPUT_DIR/eval_result.txt"

SRC_IP="10.10.1.1"
DST_IP="10.10.1.2"
GUEST_IP="10.10.1.5"

QEMU_PATH="/mydata/qemu-sev"
VM_KERNEL="/proj/ntucsie-PG0/estarriol/bzImage"
VM_DISK_IMAGE="/mydata/cloud-2004.img"
NFS_PATH="/proj/ntucsie-PG0/estarriol/cloud-2004.img"
RAMFS_IMAGE="/proj/ntucsie-PG0/estarriol/ramdisk.img"
UEFI_BIOS_CODE="/proj/ntucsie-PG0/estarriol/OVMF_CODE.fd"
UEFI_BIOS_VARS="/proj/ntucsie-PG0/estarriol/OVMF_VARS.fd"
SEV_CERT="/proj/ntucsie-PG0/estarriol/ask_ark_rome.cert"

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
    -display none \
    -daemonize"
SRC_QEMU_CMD="$QEMU_CMD"
DST_QEMU_CMD="$QEMU_CMD \
    -incoming tcp:0:$MIGRATION_PORT"
MIGRATION_PROPERTIES=(
    "migrate_set_parameter downtime-limit 100"
    "migrate_set_parameter max-bandwidth 10g"
    # "migrate_set_parameter multifd-channels 1"
    # "migrate_set_capability multifd on"
    # "migrate_set_capability postcopy-ram off"
)
MIGRATION_TIMEOUT=300
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
# with current round as argument ($1)
function benchmark_clean_up() {

    log_msg "Cleaning up benchmark"

    #
    # Exmaple usage: Apache benchmark
    #
    return 0
}

