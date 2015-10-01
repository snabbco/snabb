#!/bin/bash

# Empty pdf/ directory
if [ -d "pdf" ]; then
   rm -Rf pdf
fi
mkdir pdf

# Convert docs to PDF and place them at pdf/
echo "Generating pdf/README.benchmarking.pdf"
pandoc README.benchmarking.md     -o pdf/README.benchmarking.pdf
echo "Generating pdf/README.bindingtable.pdf"
pandoc README.bindingtable.md     -o pdf/README.bindingtable.pdf
echo "Generating pdf/README.build.pdf"
pandoc README.build.md            -o pdf/README.build.pdf
echo "Generating pdf/README.configuration.pdf"
pandoc README.configuration.md    -o pdf/README.configuration.pdf
echo "Generating pdf/README.first.pdf"
pandoc README.first.md            -o pdf/README.first.pdf
echo "Generating pdf/README.performance.pdf"
pandoc README.performance.md      -o pdf/README.performance.pdf
echo "Generating pdf/README.rfccompliance.pdf"
pandoc README.rfccompliance.md    -o pdf/README.rfccompliance.pdf
echo "Generating pdf/README.testing.pdf"
pandoc README.testing.md          -o pdf/README.testing.pdf
echo "Generating pdf/README.troubleshooting.pdf"
pandoc README.troubleshooting.md  -o pdf/README.troubleshooting.pdf
echo "Generating pdf/README.virtualization.pdf"
pandoc README.virtualization.md   -o pdf/README.virtualization.pdf
