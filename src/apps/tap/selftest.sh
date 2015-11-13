#!/bin/bash
sudo ip netns add snabbtest || exit $TEST_SKIPPED
sudo ip netns exec snabbtest ip link add name snabbtest type bridge
sudo ip netns exec snabbtest ip link set up dev snabbtest

sudo ip netns exec snabbtest ip tuntap add tapsrc mode tap
sudo ip netns exec snabbtest ip link set up dev tapsrc
sudo ip netns exec snabbtest ip link set master snabbtest dev tapsrc
sudo ip netns exec snabbtest ip tuntap add tapdst mode tap
sudo ip netns exec snabbtest ip link set up dev tapdst
sudo ip netns exec snabbtest ip link set master snabbtest dev tapdst

sudo SNABB_TAPTEST=yes ip netns exec snabbtest  ./snabb snsh -t apps.tap.tap

sudo ip netns delete snabbtest
