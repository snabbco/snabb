"""
Test uses "snabb lwaftr generate-binding-table" subcommand. Does not
need NICs as it doesn't use any network functionality. The command is
just to produce a binding table config result.
"""

from test_env import ENC, SNABB_CMD, BaseTestCase

NUM_SOFTWIRES = 10


class TestGenerateBindingTable(BaseTestCase):

    generation_args = (
        str(SNABB_CMD), 'lwaftr', 'generate-binding-table', '193.5.1.100',
        str(NUM_SOFTWIRES), 'fc00::100', 'fc00:1:2:3:4:5:0:7e', '1')

    def test_binding_table_generation(self):
        """
        This runs the generate-binding-table subcommand and verifies that
        it gets back the number of softwires it expects.

        Usage can be found in the README; however, it's:

        <ipv4> <num_ipv4s> <br_address> <b4> <psid_len> <shift>
        """
        # Get generate-binding-table command output.
        output = self.run_cmd(self.generation_args)

        # Split it into lines.
        config = str(output, ENC).split('\n')[:-1]

        # The output should be "binding-table {" followed by NUM_SOFTWIRES
        # softwires, then "}".
        self.assertIn('binding-table {', config[0],
            'Start line: %s' % config[0])

        for idx, softwire in enumerate(config[1:-1]):
            line_msg = 'Line #%d: %s' % (idx + 2, softwire)
            self.assertTrue(softwire.startswith('  softwire {'), line_msg)
            self.assertTrue(softwire.endswith('}'), line_msg)

        self.assertIn(config[-1], '}',
            'End line: %s' % config[0])

        # Check that the number of lines is the number of softwires
        # plus the start and end lines.
        self.assertEqual(len(config), NUM_SOFTWIRES + 2, len(config))
