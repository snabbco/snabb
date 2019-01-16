"""
Test uses "snabb lwaftr generate-configuration" subcommand. Does not
need NICs as it doesn't use any network functionality. The command is
just to produce a binding table config result.
"""

from test_env import ENC, SNABB_CMD, BaseTestCase

NUM_SOFTWIRES = 10


class TestGenerateBindingTable(BaseTestCase):

    generation_args = (
        str(SNABB_CMD), 'lwaftr', 'generate-configuration', '193.5.1.100',
        str(NUM_SOFTWIRES), 'fc00::100', 'fc00:1:2:3:4:5:0:7e', '1')

    def test_binding_table_generation(self):
        """
        This runs the generate-configuration subcommand and verifies that
        the output contains a valid binding-table.

        Usage can be found in the README; however, it's:

        <ipv4> <num_ipv4s> <br_address> <b4> <psid_len> <shift>
        """
        # Get generate-configuration command output.
        output = self.run_cmd(self.generation_args)

        # Split it into lines.
        config = str(output, ENC).split('\n')[:-1]

        # Check out that output is softwire-config plus a binding-table.
        self.assertIn('softwire-config {', config[0].strip())
        self.assertIn('binding-table {', config[1].strip())

        lineno = 2
        while lineno < len(config):
            line = config[lineno].strip()
            if not line.startswith('softwire {'):
                break
            self.assertTrue(line.startswith('softwire {'))
            self.assertTrue(line.endswith('}'))
            lineno = lineno + 1

        self.assertTrue(lineno < len(config))
        self.assertTrue(config[lineno].strip() == '}')
