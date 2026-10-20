# acdimmer.py - AC phase-control light dimmer for the Raspberry Pi Pico 2 W (RP2350)
#
# MicroPython port of PIC16F628A-AC-Light-Dimmer.asm
# (C) 2011 Theodore Wahrburg. Free for all non-commercial use. No warranty, USE AT YOUR OWN RISK.
# https://github.com/waterbury/PIC16F-AC-Light-Dimmer
#
# How it works
# ------------
# The PIC version counted 250 software steps of 32.8 us after each zero-cross
# (plus a fixed 521 us offset), turned each channel on when its step came up
# and held it on until the next zero crossing. This port does the same, but
# every channel gets its own PIO state machine running at 1 MHz, so the timing
# is done in hardware with 1 us resolution and no jitter from Python, Wi-Fi or
# garbage collection. Each half-cycle the state machine waits for the
# zero-cross edge and then makes two timed changes to its output:
#
#   fires mid half-cycle:   edge --> release at zero crossing --> fire (held over the edge)
#   fires late (wrapped):   edge --> fire --> release at zero crossing
#
# Level 255 holds the output on continuously and level 0 holds it off.
# Python only has to work out each channel's timings when its level changes.
# A zero-cross pin interrupt hands new timings to the state machines once per
# half-cycle (so the newest value always wins) and measures the mains period.
#
# Boot flash
# ----------
# The PIC flashed the lights at power-up for three reasons: the triac outputs
# floated before the firmware ran, TRISA made PORTA outputs before PORTA was
# cleared, and the per-channel work registers were never initialised, so the
# first half-cycle fired every channel at a random level. Here:
#   * boot.py drives every output low before anything else runs;
#   * Dimmer() drives every output low again before touching the PIO;
#   * every state machine starts with its level forced to 0 (off);
#   * a hardware pull-down on each output covers the time before MicroPython
#     starts (see README.md - the RP2350's internal pull-down is not enough).

import time
import rp2
from machine import Pin
from micropython import const

RISING = const(1)
FALLING = const(0)

_SM_FREQ = const(1_000_000)  # 1 PIO instruction = 1 us
_STEP_OVERHEAD_US = const(3)  # PIO cycles per output change not spent in the delay loop
_EDGE_GUARD_US = const(50)  # state machine must be waiting again this long before the next edge
_DELAY_BITS = const(14)

# Plausible zero-cross intervals (one edge per half-cycle, 40-80 Hz mains)
_MIN_HALF_US = const(6250)
_MAX_HALF_US = const(12500)


# Each half-cycle, after the zero-cross edge: wait a, drive the output to v1,
# wait b, drive it to v2. x holds the schedule, LSB first: a:14 v1:1 b:14 v2:1
# (30 bits, so it stays a small int in the interrupt handler).
@rp2.asm_pio(out_init=rp2.PIO.OUT_LOW, out_shiftdir=rp2.PIO.SHIFT_RIGHT)
def _gate_on_rising():
    wrap_target()
    pull(noblock)  # take a new schedule if one was queued, otherwise reuse x
    mov(x, osr)
    wait(0, pin, 0)
    wait(1, pin, 0)  # zero-cross edge
    out(y, 14)
    label("wait_a")
    jmp(y_dec, "wait_a")
    out(pins, 1)
    out(y, 14)
    label("wait_b")
    jmp(y_dec, "wait_b")
    out(pins, 1)
    wrap()


@rp2.asm_pio(out_init=rp2.PIO.OUT_LOW, out_shiftdir=rp2.PIO.SHIFT_RIGHT)
def _gate_on_falling():
    wrap_target()
    pull(noblock)
    mov(x, osr)
    wait(1, pin, 0)
    wait(0, pin, 0)  # zero-cross edge
    out(y, 14)
    label("wait_a")
    jmp(y_dec, "wait_a")
    out(pins, 1)
    out(y, 14)
    label("wait_b")
    jmp(y_dec, "wait_b")
    out(pins, 1)
    wrap()


def gate_times(level, half_us, offset_us, end_margin_us):
    """(on_us, off_us) after the zero-cross edge for a level of 1-254.

    The output goes high when the channel fires and stays high until the next
    true zero crossing (edge + offset), as the PIC did. Level 254 fires just
    after the zero crossing, level 1 end_margin_us before the next one.
    """
    window = half_us - end_margin_us
    if window < 0:
        window = 0
    t = (255 - level) * window // 254  # time after the true zero crossing
    # The offset can push either point past the next edge (or before this
    # one); mains repeats every half-cycle, so that far after the previous
    # edge is the same moment.
    on = (offset_us + t) % half_us
    off = offset_us % half_us
    # Both changes must be made before the next edge or the state machine
    # would miss it and skip a half-cycle.
    limit = half_us - _EDGE_GUARD_US
    return (on if on < limit else limit), (off if off < limit else limit)


def schedule_word(level, half_us, offset_us, end_margin_us):
    """The 30-bit schedule a channel's state machine runs every half-cycle."""
    if level <= 0:
        return 0  # low, low
    if level >= 255:
        return 1 << _DELAY_BITS | 1 << (2 * _DELAY_BITS + 1)  # high, high
    on, off = gate_times(level, half_us, offset_us, end_margin_us)
    if on < off:
        first, v1, second, v2 = on, 1, off, 0
    else:
        first, v1, second, v2 = off, 0, on, 1
    a = first - _STEP_OVERHEAD_US
    b = second - first - _STEP_OVERHEAD_US
    a = a if a > 0 else 0
    b = b if b > 0 else 0
    return a | v1 << _DELAY_BITS | b << (_DELAY_BITS + 1) | v2 << (2 * _DELAY_BITS + 1)


class Dimmer:
    """Phase-control dimmer for up to 12 triac channels sharing one zero-cross input.

    zc_pin         GPIO number of the zero-cross detector output
    out_pins       GPIO numbers of the triac drivers (active high), channel 0 first
    mains_hz       50, 60, or None to measure it at start-up
    zc_offset_us   time from the detector's edge to the true zero crossing; may be
                   negative if the detector edge comes late. The PIC board used 521.
    zc_edge        RISING or FALLING: the detector edge that marks a zero crossing
    zc_pull        None, Pin.PULL_UP or Pin.PULL_DOWN for the zero-cross input
    end_margin_us  keep the dimmest setting this far clear of the next zero crossing
    sm_ids         PIO state machines to use, one per channel (see README for Wi-Fi)
    """

    def __init__(
        self,
        zc_pin,
        out_pins,
        *,
        mains_hz=None,
        zc_offset_us=0,
        zc_edge=RISING,
        zc_pull=None,
        end_margin_us=200,
        sm_ids=None,
    ):
        # Outputs off before anything else can go wrong.
        self._outs = [Pin(p, Pin.OUT, value=0) for p in out_pins]
        self._out_ids = tuple(out_pins)
        n = len(self._outs)
        if sm_ids is None:
            sm_ids = (0, 1, 2, 3, 8, 9, 10, 11, 4, 5, 6, 7)
        if n > len(sm_ids):
            raise ValueError("too many channels for the available state machines")
        if mains_hz not in (None, 50, 60):
            raise ValueError("mains_hz must be 50, 60 or None (auto)")

        self._n = n
        self._offset = zc_offset_us
        self._margin = end_margin_us
        self._levels = bytearray(n)
        self._pending = [-1] * n  # values waiting for the next zero-cross
        self._half = 10_000 if mains_hz == 50 else 8_333
        self._last_edge = 0
        self._interval = 0
        self._edges = 0

        self._zc = Pin(zc_pin, Pin.IN, zc_pull)
        prog = _gate_on_rising if zc_edge == RISING else _gate_on_falling
        self._sms = []
        for i in range(n):
            sm = rp2.StateMachine(
                sm_ids[i], prog, freq=_SM_FREQ, in_base=self._zc, out_base=self._outs[i]
            )
            sm.exec("set(x, 0)")  # start off, whatever was left in x
            self._sms.append(sm)
        for sm in self._sms:
            sm.active(1)

        self._zc_handler = self._on_zero_cross  # allocate the bound method once
        trigger = Pin.IRQ_RISING if zc_edge == RISING else Pin.IRQ_FALLING
        self._zc.irq(self._zc_handler, trigger, hard=True)

        if mains_hz is None:
            self._half = self._detect_half_period()

    # -- levels ---------------------------------------------------------------

    def __len__(self):
        return self._n

    def __getitem__(self, channel):
        return self._levels[channel]

    def __setitem__(self, channel, level):
        self.set(channel, level)

    def set(self, channel, level):
        """Set one channel, 0 (off) to 255 (full)."""
        level = 0 if level < 0 else 255 if level > 255 else int(level)
        self._levels[channel] = level
        self._pending[channel] = schedule_word(level, self._half, self._offset, self._margin)

    def set_percent(self, channel, percent):
        self.set(channel, round(percent * 255 / 100))

    def set_levels(self, levels):
        """Set channels 0, 1, 2... from a sequence; extra values are ignored."""
        for i in range(min(self._n, len(levels))):
            self.set(i, levels[i])

    def levels(self):
        return bytes(self._levels)

    def off(self):
        for i in range(self._n):
            self.set(i, 0)

    # -- settings -------------------------------------------------------------

    @property
    def zc_offset_us(self):
        return self._offset

    @zc_offset_us.setter
    def zc_offset_us(self, value):
        self._offset = value
        self._refresh()

    @property
    def mains_hz(self):
        """Mains frequency the delays are calculated for."""
        return round(500_000 / self._half)

    @property
    def measured_hz(self):
        """Mains frequency measured from the zero-cross input, or None."""
        i = self._interval
        return 500_000 / i if i else None

    def _refresh(self):
        for i in range(self._n):
            self.set(i, self._levels[i])

    # -- zero-cross -----------------------------------------------------------

    def _on_zero_cross(self, pin):
        # Hard IRQ: no allocation in here.
        now = time.ticks_us()
        dt = time.ticks_diff(now, self._last_edge)
        self._last_edge = now
        if _MIN_HALF_US < dt < 2 * _MAX_HALF_US:
            if self._interval == 0:
                self._interval = dt
            else:
                self._interval += (dt - self._interval) // 8
        self._edges += 1
        pending = self._pending
        sms = self._sms
        for i in range(self._n):
            v = pending[i]
            if v >= 0 and sms[i].tx_fifo() == 0:
                sms[i].put(v)
                pending[i] = -1

    def _detect_half_period(self, timeout_ms=1000):
        start = time.ticks_ms()
        while self._edges < 12 and time.ticks_diff(time.ticks_ms(), start) < timeout_ms:
            time.sleep_ms(10)
        i = self._interval
        if not i:
            print("acdimmer: no zero-cross seen, assuming 60 Hz")
            return 8_333
        if i > _MAX_HALF_US:
            raise RuntimeError(
                "zero-cross detector gives one edge per mains cycle; "
                "it needs one per half-cycle (full-wave)"
            )
        return 10_000 if i > 9_167 else 8_333

    # -- shutdown -------------------------------------------------------------

    def deinit(self):
        """Stop dimming and leave every output driven low."""
        self._zc.irq(None)
        for sm in self._sms:
            sm.active(0)
        for p in self._out_ids:
            Pin(p, Pin.OUT, value=0)


class PacketDecoder:
    """Decodes the PIC dimmer's 12-byte serial packet, so existing senders
    (the Vixen plugin, the Python test apps, the Arduino adapter) still work.

    Packet: 0x01 start byte, 10 channel bytes (0-255, never 1), then the XOR of
    the 10 channel bytes. A 0x01 anywhere but the checksum restarts the packet.
    feed() returns the 10 channel levels when a packet checks out, else None.
    """

    START = 1

    def __init__(self):
        self._buf = bytearray(10)
        self._count = -1  # -1 = waiting for a start byte
        self._xor = 0

    def feed(self, byte):
        c = self._count
        if c == 10:
            self._count = -1
            if byte == self._xor:
                return bytes(self._buf)
            return None
        if byte == PacketDecoder.START:
            self._count = 0
            self._xor = 0
            return None
        if c < 0:
            return None
        self._buf[c] = byte
        self._xor ^= byte
        self._count = c + 1
        return None
