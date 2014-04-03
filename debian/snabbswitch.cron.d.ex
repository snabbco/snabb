#
# Regular cron jobs for the snabbswitch package
#
0 4	* * *	root	[ -x /usr/bin/snabbswitch_maintenance ] && /usr/bin/snabbswitch_maintenance
