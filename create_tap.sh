#!/bin/bash

echo 1 > /proc/sys/net/ipv4/ip_forward

ip tuntap add dev cvd-mtap-01 mode tap group kvm vnet_hdr
ip link set dev cvd-mtap-01 up
ip addr add 192.168.97.1/30 broadcast + dev cvd-mtap-01
iptables -t nat -A POSTROUTING -s 192.168.97.0/30 -j MASQUERADE
