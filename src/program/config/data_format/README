Data Format Usage:
  snabb config data-format <schema>

This command produces an annotated yang data format from a schema file
which can be used to check a yang schema or help you write the data
configuration file.

The output is an option or a container of options followed by the type
of value that is to be expected. In the case where there is a option
with a section in curly braces that will represent a nested structure
such as a list or a container. Comments preciding certain fields will
indicate if for example the block is a list, or comments may proceed
options specifying if they are for example mandatory.

An exaaple of an option could be:

  port uint8; // mandatory between 0..11

This describes a configuration option "port" which takes an unsigned
integer with a value between 0 and 11. The option is required so must
have a value. An example for this field in the configuration could be:

  port 7;

Example usage:

  $ snabb config data-format lib/yang/snabb-softwire.yang
