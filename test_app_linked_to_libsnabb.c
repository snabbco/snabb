#include <stdio.h>
#include <stdlib.h>

// This code defined in SnabbSwitch
int start_snabb_switch(int snabb_argc, char **snabb_argv);

int main() {
    char* cli_arguments[] = {
        "snabb", // emulate call of standard application
        "firehose",
        "--input",
        "0000:02:00.0",
        "--input",
        "0000:02:00.1",
        "/root/capturecallback.so",
    };

    int cli_numbar_of_arguments = sizeof(cli_arguments) / sizeof(char*);

    start_snabb_switch(cli_numbar_of_arguments, cli_arguments);
}
