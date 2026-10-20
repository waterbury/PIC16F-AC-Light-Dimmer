# Runs first on every power-up and soft reset: drive every triac output low
# straight away so no light can flash while the rest of the firmware loads.
# The external pull-downs (see README.md) cover the time before this runs.
from machine import Pin
from config import OUT_PINS

for _p in OUT_PINS:
    Pin(_p, Pin.OUT, value=0)
del _p
