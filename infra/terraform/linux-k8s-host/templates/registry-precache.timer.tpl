[Unit]
Description=Periodic registry precache

[Timer]
OnCalendar=${schedule}
Persistent=true

[Install]
WantedBy=timers.target
