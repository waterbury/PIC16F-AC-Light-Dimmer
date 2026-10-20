# Host stand-in for MicroPython's machine.Pin, with the pins' levels kept in LEVELS.
LEVELS = {}
PINS = {}


class Pin:
    IN = 0
    OUT = 1
    PULL_UP = 1
    PULL_DOWN = 2
    IRQ_FALLING = 4
    IRQ_RISING = 8

    def __init__(self, id, mode=IN, pull=None, *, value=None):
        self.id = id
        self.mode = mode
        self.handler = None
        if value is not None:
            LEVELS[id] = value
        LEVELS.setdefault(id, 0)
        PINS[id] = self

    def value(self, v=None):
        if v is None:
            return LEVELS[self.id]
        LEVELS[self.id] = v

    def irq(self, handler=None, trigger=None, hard=False):
        self.handler = handler
        self.trigger = trigger
