"""
Test uses "snabb lwaftr generate-binding-table" subcommand. Does not
need NICs as it doesn't use any network functionality. The command is
just to produce a binding table config result.
"""

from subprocess import Popen, PIPE

from test_env import SNABB_CMD, BaseTestCase

class TestGenerateBindingTable(BaseTestCase):

    generation_args = (str(SNABB_CMD), "lwaftr", "generate-binding-table")


    def test_binding_table_generation(self):
        """
        This runs the generate-binding-table subcommand and verifies that
        it gets the number of softwires it expects back.

        Usage can be found in the README however, it's:

        <ipv4> <num_ipv4s> <br_address> <b4> <psid_len> <shift>
        """
        # Build the generate-binding-table command.
        cmd = list(self.generation_args)
        num = 10
        cmd.extend(
            ("193.5.1.100", str(num), "fc00::100", "fc00:1:2:3:4:5:0:7e", "1")
        )

        # Execute the command.
        generation_proc = Popen(cmd, stdout=PIPE, stderr=PIPE)

        # Wait until it's finished.
        generation_proc.wait()

        # Check the status code is okay.
        self.assertEqual(generation_proc.returncode, 0)

        # Finally get the stdout value which should be the config.
        config = [l.decode("utf-8") for l in generation_proc.stdout.readlines()]

        # The output should be "binding-table {" followed by 10 softwires then "}"
        self.assertEqual("binding-table {\n", config[0])

        for softwire in config[1:-1]:
            self.assertTrue(softwire.startswith("  softwire {"))
            self.assertTrue(softwire.endswith("}\n"))

        self.assertEqual(config[-1], "}\n")

        # Check the count is 12 (10 softwires + start and end block)
        self.assertEqual(len(config), num+2)

