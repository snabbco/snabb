with import <nixpkgs> {};

let dataset = stdenv.mkDerivation {
  name = "lwaftr-dataset";

  dataset = (fetchTarball {
    url = https://people.igalia.com/atakikawa/lwaftr_benchmarking_dataset.tar.gz;
    # not supported in old NixOS
    #sha256 = "48b4204e656d19aa9f2b4023104f2483e66df7523e28188181fb3d052445eaba";
  });

  snabb_pci0 = builtins.getEnv "SNABB_PCI0";
  snabb_pci1 = builtins.getEnv "SNABB_PCI1";
  snabb_pci2 = builtins.getEnv "SNABB_PCI2";
  snabb_pci3 = builtins.getEnv "SNABB_PCI3";
  snabb_pci4 = builtins.getEnv "SNABB_PCI4";
  snabb_pci5 = builtins.getEnv "SNABB_PCI5";
  snabb_pci6 = builtins.getEnv "SNABB_PCI6";
  snabb_pci7 = builtins.getEnv "SNABB_PCI7";

  # substitute placeholders in the configs with actual pci addresses
  builder = builtins.toFile "builder.sh" "
    source $stdenv/setup
    mkdir $out
    cp $dataset/*.pcap $out/
    for conf in $dataset/lwaftr*.conf
    do
        target=$out/`basename $conf`
        cp $conf $target
        sed -i -e \"s/<SNABB_PCI0>/$snabb_pci0/; \\
                    s/<SNABB_PCI1>/$snabb_pci1/; \\
                    s/<SNABB_PCI2>/$snabb_pci2/; \\
                    s/<SNABB_PCI3>/$snabb_pci3/; \\
                    s/<SNABB_PCI4>/$snabb_pci4/; \\
                    s/<SNABB_PCI5>/$snabb_pci5/; \\
                    s/<SNABB_PCI6>/$snabb_pci6/; \\
                    s/<SNABB_PCI7>/$snabb_pci7/\" \\
            $target
    done
    ";
};
in runCommand "dummy" { dataset = dataset; } ""