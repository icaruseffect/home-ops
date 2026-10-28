#!/opt/pipx/venvs/vdirsyncer/bin/python
import sys
import vobject

data = sys.stdin.read()
cal = vobject.readOne(data)

if hasattr(cal, "vevent"):
    event = cal.vevent
    if hasattr(event, "summary"):
        event.summary.value = "Busy"
    if hasattr(event, "description"):
        event.description.value = ""

sys.stdout.write(cal.serialize())
