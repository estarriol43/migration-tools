
ROUNDS=10

# directory to store output file for each round
OUTPUT_DIR="./x86-sev-idle-ramfs"
# skip round when output file exists in OUTPUT_DIR
USE_PREV_FILE="false"
# file for final statistic result of all rounds
OUTPUT_FILE="./x86-sev-idle-ramfs/eval_result.txt"

SRC_IP="10.10.1.1"
DST_IP="10.10.1.2"
GUEST_IP="10.10.1.5"

QEMU_PATH="/proj/ntucsie-PG0/estarriol/qemu-sev"
#VM_KERNEL="/mydata/some-tutorials/files/sekvm/Image.sekvm.guest"
VM_KERNEL="/proj/ntucsie-PG0/estarriol/bzImage"
VM_DISK_IMAGE="/proj/ntucsie-PG0/estarriol/cloud-2004.img"
NFS_PATH="/proj/ntucsie-PG0/estarriol/cloud-2004-nfs.img"
RAMFS_IMAGE="/proj/ntucsie-PG0/estarriol/ramdisk.img"
UEFI_BIOS_CODE="/proj/ntucsie-PG0/estarriol/OVMF_CODE_SEV.fd"
UEFI_BIOS_VARS="/proj/ntucsie-PG0/estarriol/OVMF_VARS_SEV.fd"
SEV_CERT="/proj/ntucsie-PG0/estarriol/ask_ark_rome.cert"

MEM="512"
SMP="1"
MONITOR_PORT="1234"
QMP="1235"
CMDLINE=""
MIGRATION_PORT="8888"

QEMU_CMD="$QEMU_PATH/build/qemu-system-x86_64 \
    -kernel $VM_KERNEL \
    -append \"console=ttyS0 nokaslr $CMDLINE\" \
    -initrd $RAMFS_IMAGE \
    -m $MEM \
    --enable-kvm \
    -cpu host \
    -smp $SMP \
    -qmp tcp:0:$QMP,server=on,wait=off \
    -drive if=pflash,format=raw,unit=0,file=$UEFI_BIOS_CODE,readonly=on \
    -drive if=pflash,format=raw,unit=1,file=$UEFI_BIOS_VARS \
    -object sev-guest,id=sev0,policy=0x00000,cbitpos=47,reduced-phys-bits=1 -machine confidential-guest-support=sev0 \
    -display none \
    -daemonize"
SRC_QEMU_CMD="$QEMU_CMD \
    -monitor telnet:0:$MONITOR_PORT,server,nowait"
DST_QEMU_CMD="$QEMU_CMD \
    -monitor telnet:0:$MONITOR_PORT,server,nowait \
    -incoming tcp:0:$MIGRATION_PORT"
MIGRATION_PROPERTIES=(
    "migrate_set_parameter downtime-limit 100"
    "migrate_set_parameter max-bandwidth 1024000"
    # "migrate_set_parameter multifd-channels 1"
    # "migrate_set_capability multifd off"
    #"migrate_set_capability postcopy-ram off"
)
MIGRATION_TIMEOUT=150
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
    log_msg "Skip checking VM status since it's ramfs"
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
    log_msg "Setting up SEV"
    python3 /proj/ntucsie-PG0/estarriol/some-tutorials/files/migration/sev-setup.py \
        --sev $SEV_CERT
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

