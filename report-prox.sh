for vmid in $(qm list | awk 'NR>1 {print $1}'); do
  echo "========================================"
  echo "VM ID      : $vmid"
  echo "----------------------------------------"
  # Nama VM
  vm_name=$(qm list | grep $vmid | awk '{print $2}')
  echo "Nama VM    : $vm_name"
  # Status VM
  vm_status=$(qm status $vmid | grep status | awk '{print $2}')
  echo "Status     : $vm_status"
  # CPU dan Memori
  cpu_info=$(qm config $vmid | grep -E '(cpu|cores)' | awk -F ': ' '{print $2}')
  mem_info=$(qm config $vmid | grep memory | awk -F ': ' '{print $2}')
  echo "CPU        : $cpu_info"
  echo "Memory     : $mem_info MB"
  # Storage
  storage_info=$(qm config $vmid | grep disk)
  if [ -z "$storage_info" ]; then
    echo "Storage    : Tidak ada disk"
  else
    echo "Storage    : $storage_info"
  fi
  # IP Address (butuh qemu-guest-agent terpasang)
  ip_info=$(qm agent $vmid network-get-interfaces 2>/dev/null | grep "ip-address" | awk -F'"' '{print $4}')
  if [ -z "$ip_info" ]; then
    echo "IP Address : Tidak tersedia (pastikan qemu-guest-agent terpasang)"
  else
    echo "IP Address : $ip_info"
  fi
  echo "========================================"
  echo ""
done
