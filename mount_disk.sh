#!/bin/bash

# Single fixed mount point
MOUNT_POINT="/metashape-vol"
MOUNT_OPTIONS="noatime,nodiratime,nodev,noexec,nosuid,nofail"

log() {
    echo "$1"
}

is_partitioned() {
    OUTPUT=$(partx -s "${1}" 2>&1)
    egrep "partition table does not contain usable partitions|failed to read partition table" <<< "${OUTPUT}" >/dev/null 2>&1
    return $((! $?))
}

has_filesystem() {
    file -L -s "${1}" | grep -q filesystem
}

add_to_fstab() {
    UUID=${1}
    grep "${UUID}" /etc/fstab >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "UUID ${UUID} already exists in fstab"
    else
        echo "UUID=\"${UUID}\" ${MOUNT_POINT} ext4 ${MOUNT_OPTIONS} 1 2" >> /etc/fstab
    fi
}

do_partition() {
    DISK=${1}
    echo -e "n\np\n1\n\n\nw" | fdisk "${DISK}"
    if [ ${PIPESTATUS[1]} -ne 0 ]; then
        echo "Partitioning failed for ${DISK}" >&2
        exit 2
    fi
}

main() {
    # Find unpartitioned disks
    for DEV in /dev/sd?; do
        # Skip if the device is the root disk (e.g., /dev/sda)
        if grep -q "${DEV}" /proc/mounts; then
            continue
        fi

        is_partitioned "${DEV}"
        if [ $? -ne 0 ]; then
            log "${DEV} is not partitioned, partitioning..."
            do_partition "${DEV}"
            partx -u "${DEV}"
        fi

        PART="${DEV}1"
        has_filesystem "${PART}"
        if [ $? -ne 0 ]; then
            log "Creating ext4 filesystem on ${PART}..."
            mkfs.ext4 "${PART}"
        fi

        mkdir -p "${MOUNT_POINT}"
        read UUID _ < <(blkid -s UUID -o value "${PART}")
        add_to_fstab "${UUID}"
        log "Mounting ${PART} to ${MOUNT_POINT}"
        mount "${MOUNT_POINT}"
        return
    done

    echo "No suitable disk found."
}

main
