#!/usr/bin/env python3
"""Current time in the [config] zones, relative to local time; night is dimmed."""
import json
import os
from datetime import datetime
from zoneinfo import ZoneInfo

zones = json.loads(os.environ.get("APPLET_CONFIG", "{}")).get("zones", ["UTC"])
local = datetime.now().astimezone()
items = []
for zone in zones:
    now = datetime.now(ZoneInfo(zone))
    offset = (now.utcoffset() - local.utcoffset()).total_seconds() / 3600
    day = "" if now.date() == local.date() else (" tomorrow" if now.date() > local.date() else " yesterday")
    night = now.hour < 7 or now.hour >= 22
    items.append({
        "icon": "☾" if night else "☀",
        "text": f"{now:%H:%M}  {zone.split('/')[-1].replace('_', ' ')}",
        "detail": f"{offset:+g} h{day}",
        "class": "muted" if night else "",
        "copy": f"{now:%H:%M} {zone}",
    })
print(json.dumps({"text": f"{local:%H:%M}", "items": items}))
