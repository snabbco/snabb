#!/usr/bin/env bash
ip netns add snabbtest || exit $TEST_SKIPPED
ip netns exec snabbtest ip link add name snabbtest type bridge
ip netns exec snabbtest ip link set up dev snabbtest

ip netns exec snabbtest ip tuntap add tapsrc mode tap
ip netns exec snabbtest ip link set up dev tapsrc
ip netns exec snabbtest ip link set master snabbtest dev tapsrc
ip netns exec snabbtest ip tuntap add tapdst mode tap
ip netns exec snabbtest ip link set up dev tapdst
ip netns exec snabbtest ip link set master snabbtest dev tapdst

SNABB_TAPTEST=yes ip netns exec snabbtest  ./snabb snsh -t apps.tap.tap

ip netns delete snabbtest
