#!/usr/bin/env python3
import sys
import statistics
import re

def get_num_from_line(l):
	return float(re.findall("([0-9.]+) MPPS", l)[0])

def wrap_stdev(s):
	if len(s) < 2: return 0
	return statistics.stdev(s)

def print_stats(s, desc):
	print("%s: min: %.3f, max: %.3f, avg: %.3f, stdev: %.4f" % (desc, min(s), max(s), statistics.mean(s), wrap_stdev(s)))

def process_chunk(lines):
	v = list(filter(lambda x: x != '' and x[0] == 'v', lines))
	v4i = get_num_from_line(v[0])
	v6i = get_num_from_line(v[1])
	v4f = get_num_from_line(v[-2])
	v6f = get_num_from_line(v[-1])
	return v4i, v6i, v4f, v6f

def main():
	chunks = sys.stdin.read().split("link report")
	v4i = []
	v6i = []
	v4f = []
	v6f = []

	for i in range(0, len(chunks) - 1):
		a, b, c, d = process_chunk(chunks[i].split("\n"))
		v4i.append(a)
		v6i.append(b)
		v4f.append(c)
		v6f.append(d)

	print_stats(v4i, "Initial v4 MPPS")
	print_stats(v6i, "Initial v6 MPPS")
	print_stats(v4f, "  Final v4 MPPS")
	print_stats(v6f, "  Final v6 MPPS")

main()
