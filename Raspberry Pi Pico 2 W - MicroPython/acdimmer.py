# acdimmer.py - AC phase-control light dimmer for the Raspberry Pi Pico 2 W (RP2350)
#
# MicroPython port of PIC16F628A-AC-Light-Dimmer.asm
# (C) 2011 Theodore Wahrburg. Free for all non-commercial use. No warranty, USE AT YOUR OWN RISK.
# https://github.com/waterbury/PIC16F-AC-Light-Dimmer
#
# How it works
# ------------
# The PIC version counted 250 software steps of 32.8 us after each zero-cross
# (plus a fixed 521 us offset) and turned each channel on when its step came up.
# Here every channel gets its own PIO state machine running at 1 MHz, so the
# timing is done in hardware with 1 us resolution and no jitter from Python,
# Wi-Fi or garbage collection:
#
#   zero-cross edge --(delay for this channel)--> gate pulse --> wait for next edge
#
# Python only has to work out each channel's delay when its level changes.
# A zero-cross pin interrupt hands new delays to the state machines once per
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
_FIRE_OVERHEAD_US = const(4)  # PIO cycles between the edge and the gate going high
_PULSE_OVERHEAD_US = const(3)  # PIO cycles of the pulse not spent in the loop
_EDGE_GUARD_US = const(50)  # state machine must be waiting again this long before the next edge

# Plausible zero-cross intervals (one edge per half-cycle, 40-80 Hz mains)
_MIN_HALF_US = const(6250)
_MAX_HALF_US = const(12500)


# Gate a triac once per half-cycle.
#   x   = delay after the zero-cross edge, in us (0 = channel off)
#   isr = gate pulse length, in us (loaded once at start-up)
@rp2.asm_pio(set_init=rp2.PIO.OUT_LOW)
def _fire_on_rising():
    wrap_target()
    label("top")
    pull(noblock)  # take a new delay if one was queued, otherwise keep x
    mov(x, osr)
    wait(0, pin, 0)
    wait(1, pin, 0)  # zero-cross edge
    jmp(not_x, "top")  # level 0: stay off
    mov(y, x)
    label("delay")
    jmp(y_dec, "delay")
    set(pins, 1)
    mov(y, isr)
    label("pulse")
    jmp(y_dec, "pulse")
    set(pins, 0)
    wrap()


@rp2.asm_pio(set_init=rp2.PIO.OUT_LOW)
def _fire_on_falling():
    wrap_target()
    label("top")
    pull(noblock)
    mov(x, osr)
    wait(1, pin, 0)
    wait(0, pin, 0)  # zero-cross edge
    jmp(not_x, "top")
    mov(y, x)
    label("delay")
    jmp(y_dec, "delay")
    set(pins, 1)
    mov(y, isr)
    label("pulse")
    jmp(y_dec, "pulse")
    set(pins, 0)
    wrap()


def fire_delay_us(level, half_us, offset_us, pulse_us, end_margin_us):
    """Delay from the zero-cross edge to the gate pulse for a 0-255 level.

    Returns 0 for "off". Level 255 fires right at the true zero crossing
    (edge + offset), level 1 fires end_margin_us + pulse_us before the next one.
    """
    if level <= 0:
        return 0
    if level > 255:
        level = 255
    window = half_us - pulse_us - end_margin_us
    if window < 0:
        window = 0
    t = (255 - level) * window // 254  # time after the true zero crossing
    # The offset can push the firing point past the next edge (or before this
    # one); mains repeats every half-cycle, so firing that far after the
    # previous edge is the same moment.
    d = (offset_us + t) % half_us
    # The pulse has to finish before the next edge or the state machine would
    # miss it and skip a half-cycle, so fire a touch earlier instead.
    limit = half_us - pulse_us - _EDGE_GUARD_US
    if d > limit:
        d = limit if limit > 0 else 0
    return d + 1  # never 0, which means "off"


def _sm_value(delay_us):
    if delay_us == 0:
        return 0
    v = delay_us - _FIRE_OVERHEAD_US
    return v if v > 0 else 1


class Dimmer:
    """Phase-control dimmer for up to 12 triac channels sharing one zero-cross input.

    zc_pin         GPIO number of the zero-cross detector output
    out_pins       GPIO numbers of the triac drivers (active high), channel 0 first
    mains_hz       50, 60, or None to measure it at start-up
    zc_offset_us   time from the detector's edge to the true zero crossing; may be
                   negative if the detector edge comes late. The PIC board used 521.
    zc_edge        RISING or FALLING: the detector edge that marks a zero crossing
    zc_pull        None, Pin.PULL_UP or Pin.PULL_DOWN for the zero-cross input
    gate_pulse_us  how long each gate pulse lasts
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
        gate_pulse_us=200,
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
        if gate_pulse_us < _PULSE_OVERHEAD_US + 1:
            raise ValueError("gate_pulse_us too short")

        self._n = n
        self._offset = zc_offset_us
        self._pulse = gate_pulse_us
        self._margin = end_margin_us
        self._levels = bytearray(n)
        self._pending = [-1] * n  # values waiting for the next zero-cross
        self._half = 10_000 if mains_hz == 50 else 8_333
        self._last_edge = 0
        self._interval = 0
        self._edges = 0

        self._zc = Pin(zc_pin, Pin.IN, zc_pull)
        prog = _fire_on_rising if zc_edge == RISING else _fire_on_falling
        self._sms = []
        for i in range(n):
            sm = rp2.StateMachine(
                sm_ids[i], prog, freq=_SM_FREQ, in_base=self._zc, set_base=self._outs[i]
            )
            sm.put(gate_pulse_us - _PULSE_OVERHEAD_US)
            sm.exec("pull()")
            sm.exec("mov(isr, osr)")
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
        self._pending[channel] = _sm_value(
            fire_delay_us(level, self._half, self._offset, self._pulse, self._margin)
        )

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
