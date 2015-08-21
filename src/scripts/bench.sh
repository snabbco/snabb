#!/bin/bash

for bench in $(ls bench/); do
    echo $bench $(bench/$bench || echo "0")
done
