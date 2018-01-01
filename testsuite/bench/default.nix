# Run a large parallel benchmark campaign and generate R/ggplot2 reports.

{ pkgs ? (import ../../pkgs.nix) {},
  Asrc,        Aname ? "A", Aargs ? "",
  Bsrc ? null, Bname ? "B", Bargs ? "",
  Csrc ? null, Cname ? "C", Cargs ? "",
  Dsrc ? null, Dname ? "D", Dargs ? "",
  Esrc ? null, Ename ? "E", Eargs ? "",
  hardware ? null,
  runs ? 30 }:

with pkgs;
with stdenv;

# Derivation to run benchmarks and produce a CSV result.
let benchmark = letter: name: src: args: run:
  let raptorjit = (import src {inherit pkgs; version = name;}).raptorjit; in
  mkDerivation {
    name = "benchmark-${name}-${toString run}";
    src = pkgs.lib.cleanSource ./.;
    # Force consistent hardware
    requiredSystemFeatures = if hardware != null then [hardware] else [];
    buildInputs = [ raptorjit linuxPackages.perf utillinux ];
    buildPhase = ''
      # Run multiple iterations of the benchmarks
      echo "Run $run"
      mkdir -p result/$run
      # Run each individual benchmark
      cat PARAM_x86_CI.txt |
        (while read benchmark params; do
           echo "running $benchmark"
           # Execute with performance monitoring & time supervision
           # Note: discard stdout due to overwhelming output
           timeout -sKILL 60 \
             perf stat -x, -o result/$run/$benchmark.perf \
             raptorjit ${args} -e "math.randomseed(${toString run})" $benchmark.lua $params \
                > /dev/null || \
                rm result/$run/$benchmark.perf
        done)
    '';
    installPhase = ''
      # Copy the raw perf output for reference
      cp -r result $out
      # Log the exact CPU
      lscpu > $out/cpu.txt
      # Create a CSV file
      # Create the rows based on the perf logs
      for result in result/*.perf; do
        version=${name}
        benchmark=$(basename -s.perf -a $result)
        instructions=$(awk -F, -e '$3 ~ "^instructions" { print $1; }' $result)
        cycles=$(      awk -F, -e '$3 ~ "^cycles"       { print $1; }' $result)
        echo ${letter},$version,$benchmark,${toString run},$instructions,$cycles >> $out/bench.csv
      done
    '';
  };

# Run a set of benchmarks and aggregate the results into a CSV file.
# Each benchmark run is a separate derivation. This allows nix to
# parallelize and distribute the benchmarking.
  benchmarkSet = letter: name: src: args:
    let benchmarks = map (benchmark letter name src args) (pkgs.lib.range 1 runs);
    in
      runCommand "benchmarks-${name}" { buildInputs = benchmarks; } ''
        source $stdenv/setup
        mkdir -p $out
        for dir in ${pkgs.lib.fold (acc: x: "${acc} ${x}") "" benchmarks}; do
          cat $dir/bench.csv >> $out/bench.csv
        done
      '';

  benchA =                      (benchmarkSet "A" Aname Asrc Aargs);
  benchB = if Bsrc != null then (benchmarkSet "B" Bname Bsrc Bargs) else "";
  benchC = if Csrc != null then (benchmarkSet "C" Cname Csrc Cargs) else "";
  benchD = if Dsrc != null then (benchmarkSet "D" Dname Dsrc Dargs) else "";
  benchE = if Esrc != null then (benchmarkSet "E" Ename Esrc Eargs) else "";
in

rec {
  benchmarkResults = mkDerivation {
    name = "benchmark-results";
    buildInputs = with pkgs.rPackages; [ pkgs.R ggplot2 dplyr ];
    builder = pkgs.writeText "builder.csv" ''
      source $stdenv/setup
      # Get the CSV file
      mkdir -p $out/nix-support
      echo "letter,version,benchmark,run,instructions,cycles" > bench.csv
                            cat ${benchA}/bench.csv >> bench.csv
      [ -n "${benchB}" ] && cat ${benchB}/bench.csv >> bench.csv
      [ -n "${benchC}" ] && cat ${benchC}/bench.csv >> bench.csv
      [ -n "${benchD}" ] && cat ${benchD}/bench.csv >> bench.csv
      [ -n "${benchE}" ] && cat ${benchE}/bench.csv >> bench.csv
      cp bench.csv $out
      echo "file CSV $out/bench.csv" >> $out/nix-support/hydra-build-products
      # Generate the report
      (cd ${./.}; Rscript ./generate.R $out/bench.csv $out)
      for png in $out/*.png; do
        echo "file PNG $png" >> $out/nix-support/hydra-build-products
      done
    '';
  };
}

