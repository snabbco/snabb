#!/bin/bash

. defs.sh

#sudo onload_tool reload
sudo ifconfig $SEND_DEV $SEND_IP
sudo ifconfig $RECV_DEV $RECV_IP
