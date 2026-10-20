# Host stand-in for MicroPython's _rp2: a StateMachine that runs the handful of
# PIO instructions acdimmer uses, one call to step() per PIO clock.
import machine


class PIO:
    OUT_LOW = 0
    OUT_HIGH = 1
    IN_LOW = 0
    IN_HIGH = 1
    JOIN_NONE = 0
    JOIN_TX = 1
    JOIN_RX = 2


MACHINES = {}


class StateMachine:
    def __init__(self, id, prog, freq, *, in_base, set_base):
        assert id not in MACHINES, "state machine %d used twice" % id
        MACHINES[id] = self
        self.id = id
        self.code = list(prog[0])
        execctrl = prog[3]
        self.wrap_bottom = (execctrl >> 7) & 0x1F
        self.wrap_top = (execctrl >> 12) & 0x1F
        self.freq = freq
        self.in_pin = in_base.id
        self.set_pin = set_base.id
        self.fifo = []
        self.x = self.y = self.isr = 0
        self.osr = 0
        self.pc = 0
        self.running = False

    def active(self, v=None):
        if v is not None:
            self.running = bool(v)
        return self.running

    def put(self, v):
        assert 0 <= v < 1 << 32
        assert len(self.fifo) < 4, "tx fifo overflow"
        self.fifo.append(v)

    def tx_fifo(self):
        return len(self.fifo)

    def exec(self, src):
        import rp2
        self._run(rp2.asm_pio_encode(src, 0), from_exec=True)

    def step(self):
        if self.running:
            self._run(self.code[self.pc])

    def _src(self, s):
        return {1: self.x, 2: self.y, 3: 0, 6: self.isr, 7: self.osr}[s]

    def _run(self, w, from_exec=False):
        op = w >> 13
        nxt = self.pc + 1 if self.pc != self.wrap_top else self.wrap_bottom
        if op == 0:  # jmp
            cond, addr = (w >> 5) & 7, w & 0x1F
            take = {0: True, 1: self.x == 0, 4: self.y != 0}[cond]
            if cond == 4:
                self.y = (self.y - 1) & 0xFFFFFFFF
            if take:
                nxt = addr
        elif op == 1:  # wait pin
            assert (w >> 5) & 3 == 1
            pol, idx = (w >> 7) & 1, w & 0x1F
            if machine.LEVELS[self.in_pin + idx] != pol:
                return  # stall
        elif op == 4:  # pull
            assert w & 0x80
            block = (w >> 5) & 1
            if self.fifo:
                self.osr = self.fifo.pop(0)
            elif block:
                return  # stall
            else:
                self.osr = self.x
        elif op == 5:  # mov
            dest, src = (w >> 5) & 7, w & 7
            assert (w >> 3) & 3 == 0
            v = self._src(src)
            if dest == 1:
                self.x = v
            elif dest == 2:
                self.y = v
            elif dest == 6:
                self.isr = v
            else:
                raise NotImplementedError(hex(w))
        elif op == 7:  # set
            dest, data = (w >> 5) & 7, w & 0x1F
            if dest == 0:
                machine.LEVELS[self.set_pin] = data & 1
            elif dest == 1:
                self.x = data
            elif dest == 2:
                self.y = data
            else:
                raise NotImplementedError(hex(w))
        else:
            raise NotImplementedError(hex(w))
        if not from_exec:
            self.pc = nxt
