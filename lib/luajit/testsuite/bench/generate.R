#!/usr/bin/env nix-shell
#!nix-shell -i Rscript -p R rpkgs.dplyr rpkgs.ggplot2

# R command-line program for making visualizations from benchmark results.

suppressWarnings(source("bench.R"))

args <- commandArgs(trailingOnly=T)
if (length(args) != 2) {
    message("Usage: generate.R <csv> <outdir>"); quit(status=1)
}

filename <- args[[1]]
outdir   <- args[[2]]

data <- bench.read(filename)
if (!dir.exists(outdir)) { dir.create(outdir, recursive=T) }

ggsave(filename = file.path(outdir,"bench-jitter.png"),
       plot = bench.jitterplot(data),
       width=12, height=12)

ggsave(filename = file.path(outdir,"bench-ecdf.png"),
       plot = bench.ecdfplot(data),
       width=12, height=12)
