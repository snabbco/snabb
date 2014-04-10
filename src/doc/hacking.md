Several environment variables can be set for snabbswitch code:

* SNABB_TEST_VHOST_USER_SOCKET filename of the vhost_user socket file.
  No default value

* SNABB_TEST_INTEL10G_PCI_ID PCI ID of an Intel 82599 network device.
  No default value

You can run tests defining some of the variables:

    cd src; sudo SNABB_TEST_PCI_ID="0000:01:00.0" \
      SNABB_VHOST_USER_SOCKET_FILE="vhost_user_test.sock" make test;

if a test can't find resource needed it will usually skip and return code 43
(TEST_SKIPPED_CODE).

FIXME: add some sane examples and explanatory notes to variables.
