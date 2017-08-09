#!/usr/bin/perl
use strict;
use warnings;

use Net::Patricia;

# ./snabb snsh -e 'require("lib.lpm.lpm4").LPM4:build_verify_fixtures("pfxfile", "ipfile")'
# perl pat.pl pfxfile ipfile > resultsfile
# ./snabb snsh -e 'require("lib.lpm.lpm4_trie").LPM4_trie:new():verify_against_fixtures("pfxfile", "resultsfile")'

my $pat = Net::Patricia->new();

my ($pfxes, $tests) = @ARGV;

open my $FH, "<$pfxes";
while(<$FH>){
	chomp;
	if(/(\S+)\s+(\S+)/){
		$pat->add_string($1, [$1, $2]);
	}
}
open $FH, "<$tests";
while(<$FH>){
	chomp;
	my $aref = $pat->match_string($_);
	print("$_ $aref->[0] $aref->[1]\n");
}
