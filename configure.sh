#! /bin/bash

set -e

# Ensure that the script is executed as root
[[ $EUID -eq 0 ]] || (sudo $0 && exit)

function setup_rootfs {
  ROOTFS_ARCHIVE="rootfs.tar.gz"
  ROOTFS_SIZE_MB=1024
  ROOT="./rootfs"
  ROOT_IMG="container_root.img"

  # Cleanup
  LOOP_DEV=$(losetup | grep ${ROOT_IMG} | head -n 1 | cut -d ' ' -f 1)
  umount ${ROOT} 2>/dev/null || true
  losetup -d ${LOOP_DEV} 2>/dev/null || true
  rm -rf ${ROOT} ${ROOT_IMG}
  
  # Setup
  dd if=/dev/zero of=${ROOT_IMG} bs=1024K count=${ROOTFS_SIZE_MB}
  mkfs.ext4 ${ROOT_IMG}
  losetup -f ${ROOT_IMG}
  LOOP_DEV=$(losetup | grep ${ROOT_IMG} | head -n 1 | cut -d ' ' -f 1)
  # TODO fsck.ext4 -y ${LOOP_DEV} 1>/dev/null
  mkdir -p ${ROOT}
  mount ${LOOP_DEV} ${ROOT}
  tar -xzvf ${ROOTFS_ARCHIVE}
}


function setup_net() {
  NS_NAME="ccontainer"
  HOST_IP="192.168.20.1"
  VETH_HOSTNAME="hostveth0"
  CONTAINER_IP="192.168.20.2"
  VETH_CONTAINERNAME="ccontainer0"

  # Cleanup
  echo "cleaning network interfaces"
  ip link delete "${VETH_CONTAINERNAME}" 2>/dev/null || true
  ip link delete "${VETH_HOSTNAME}" 2>/dev/null || true
  echo "cleaning network namespace"
  ip netns delete "${NS_NAME}" 2>/dev/null || true
  
  # Setup
  echo "enabling ip forwarding"
  echo 1 > /proc/sys/net/ipv4/ip_forward
  echo "adding network namespace ${NS_NAME}"
  ip netns add ${NS_NAME}
  echo "creating virtual interfaces ${VETH_HOSTNAME} and ${VETH_CONTAINERNAME}"
  ip link add ${VETH_HOSTNAME} type veth peer name $VETH_CONTAINERNAME
  echo "moving ${VETH_CONTAINERNAME} interface to the ${NS_NAME} namespace"
  ip link set $VETH_CONTAINERNAME netns $NS_NAME
  echo "adding $CONTAINER_IP/24 IP address to the ${VETH_HOSTNAME} interface"
  ip netns exec $NS_NAME ip addr add $CONTAINER_IP/24 dev ${VETH_CONTAINERNAME}
  echo "adding $HOST_IP/24 IP address to the ${VETH_HOSTNAME} interface"
  ip addr add $HOST_IP/24 dev ${VETH_HOSTNAME}
  echo "enabling interfaces"
  ip netns exec ${NS_NAME} ip link set ${VETH_CONTAINERNAME} up
  ip link set ${VETH_HOSTNAME} up
  echo "setting ${HOST_IP} as default gateway for the container"
  ip netns exec ${NS_NAME} ip route add default via ${HOST_IP}
  
  # Host-specific configuration to enable NAT and give container access to WAN
  # sudo iptables -t nat -A POSTROUTING -s 192.168.20.0/24 -o <outbound_interface> -j MASQUERADE
}

sudo bash -c "$(declare -f setup_rootfs); setup_rootfs"
sudo bash -c "$(declare -f setup_net); setup_net"
