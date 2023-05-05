#!/bin/bash

iptables -t nat -D POSTROUTING -s 192.168.97.0/30 -j MASQUERADE
ip addr del 192.168.97.1/30 dev cvd-mtap-01
ip link set dev cvd-mtap-01 down
ip link delete cvd-mtap-01
