"""Host tests for acdimmer.py: run with `python3 -m unittest discover tests`
from the "Raspberry Pi Pico 2 W - MicroPython" folder.

The PIO programs are assembled with MicroPython's own assembler and run on a
small simulator (tests/stubs/_rp2.py) at 1 us per step, against a simulated
zero-cross detector, so these check real gate timing, not just arithmetic.
"""

import os
import sys
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "stubs"))
sys.path.insert(0, os.path.dirname(HERE))

import _rp2  # noqa: E402
import machine  # noqa: E402
import acdimmer  # noqa: E402
from acdimmer import Dimmer, PacketDecoder, fire_delay_us  # noqa: E402

ZC = 2
OUTS = (6, 7, 8, 9, 10, 11, 12, 13)


class World:
    """Mains zero-cross detector, PIO clock and MicroPython time, 1 us per tick."""

    def __init__(self, hz, zc_width_us=1000, edge_rising=True):
        self.now = 0
        self.half = 1_000_000 / (2 * hz) if hz else None
        self.next_edge = 1500.0
        self.width = zc_width_us
        self.rising = edge_rising
        self.pulse_end = None
        self.edges = []
        self.gate_on = {p: [] for p in OUTS}
        self.violations = []
        machine.LEVELS.clear()
        machine.PINS.clear()
        _rp2.MACHINES.clear()
        machine.LEVELS[ZC] = 0 if edge_rising else 1
        time.ticks_us = lambda: self.now
        time.ticks_ms = lambda: self.now // 1000
        time.ticks_diff = lambda a, b: a - b
        time.sleep_ms = lambda ms: self.run(ms * 1000)

    def run(self, us):
        idle = 0 if self.rising else 1
        for _ in range(int(us)):
            self.now += 1
            if self.half and self.now >= self.next_edge:
                machine.LEVELS[ZC] = 1 - idle
                self.pulse_end = self.now + self.width
                self.next_edge += self.half
                self.edges.append(self.now)
                pin = machine.PINS[ZC]
                if pin.handler:
                    pin.handler(pin)
            elif self.pulse_end is not None and self.now >= self.pulse_end:
                machine.LEVELS[ZC] = idle
                self.pulse_end = None
            before = {p: machine.LEVELS.get(p, 0) for p in OUTS}
            for sm in _rp2.MACHINES.values():
                sm.step()
            for p in OUTS:
                if machine.LEVELS.get(p, 0) and not before[p]:
                    self.gate_on[p].append(self.now)

    def delays(self, pin):
        """Gate-on time after the most recent zero-cross edge, for each firing."""
        out = []
        for t in self.gate_on[pin]:
            prev = [e for e in self.edges if e <= t]
            out.append(t - prev[-1])
        return out


class FireDelayTest(unittest.TestCase):
    def test_off_full_and_order(self):
        args = (8333, 0, 200, 200)
        self.assertEqual(fire_delay_us(0, *args), 0)
        self.assertEqual(fire_delay_us(255, *args), 1)
        delays = [fire_delay_us(lv, *args) for lv in range(1, 256)]
        self.assertEqual(delays, sorted(delays, reverse=True))
        self.assertEqual(delays[0], 8333 - 200 - 200 + 1)

    def test_offset_wraps_past_next_edge(self):
        # Edge comes 521 us before the true zero crossing (the PIC board).
        d = fire_delay_us(1, 8333, 521, 200, 200)
        self.assertLess(d + 200 + 50, 8333)
        # Dim enough that edge + offset + t lands in the next half-cycle.
        t = (255 - 4) * (8333 - 400) // 254
        self.assertEqual(fire_delay_us(4, 8333, 521, 200, 200), (521 + t) % 8333 + 1)
        # Just short of that the pulse would run into the next edge: fire a little earlier.
        self.assertEqual(fire_delay_us(10, 8333, 521, 200, 200), 8333 - 200 - 50 + 1)

    def test_negative_offset(self):
        # Edge comes 300 us after the true zero crossing: fire 300 us before the next edge.
        self.assertEqual(fire_delay_us(255, 10000, -300, 200, 200), 9701)


class DimmerTimingTest(unittest.TestCase):
    def check(self, hz, mains_hz, offset, levels, rising=True):
        world = World(hz, edge_rising=rising)
        d = Dimmer(ZC, OUTS, mains_hz=mains_hz, zc_offset_us=offset,
                   zc_edge=acdimmer.RISING if rising else acdimmer.FALLING)
        half = 10_000 if hz == 50 else 8_333
        self.assertEqual(d.mains_hz, hz)
        d.set_levels(levels)
        world.run(half * 10)
        for pin, lv in zip(OUTS, levels):
            want = fire_delay_us(lv, half, offset, 200, 200)
            got = world.delays(pin)[-4:]
            if want == 0:
                self.assertEqual(world.gate_on[pin], [], "channel at 0 fired")
                continue
            self.assertEqual(len(got), 4, "level %d did not fire every half-cycle" % lv)
            # The state machine can't fire sooner than a few us after the edge.
            want = max(want, 5)
            for g in got:
                self.assertLessEqual(abs(g - want), 3, (lv, got, want))
        return world, d

    def test_60hz(self):
        self.check(60, 60, 0, (0, 1, 30, 64, 128, 200, 254, 255))

    def test_50hz(self):
        self.check(50, 50, 0, (0, 1, 30, 64, 128, 200, 254, 255))

    def test_auto_detects_50hz(self):
        self.check(50, None, 521, (0, 5, 10, 64, 128, 200, 254, 255))

    def test_auto_detects_60hz_with_pic_offset(self):
        self.check(60, None, 521, (0, 5, 10, 64, 128, 200, 254, 255))

    def test_falling_edge_detector(self):
        self.check(60, 60, 0, (0, 1, 30, 64, 128, 200, 254, 255), rising=False)

    def test_gate_pulse_length(self):
        world = World(60)
        d = Dimmer(ZC, OUTS[:1], mains_hz=60, gate_pulse_us=150)
        d[0] = 128
        world.run(8333)
        world.gate_on[OUTS[0]].clear()
        high = 0
        for _ in range(8333 * 4):
            world.run(1)
            high += machine.LEVELS[OUTS[0]]
        pulses = len(world.gate_on[OUTS[0]])
        self.assertEqual(pulses, 4)
        self.assertLessEqual(abs(high / pulses - 150), 2)

    def test_latest_value_wins(self):
        world = World(60)
        d = Dimmer(ZC, OUTS[:1], mains_hz=60)
        for lv in range(1, 200):
            d[0] = lv  # far faster than mains; must not overflow the FIFO
        d[0] = 128
        world.run(8333 * 4)
        want = fire_delay_us(128, 8333, 0, 200, 200)
        self.assertLessEqual(abs(world.delays(OUTS[0])[-1] - want), 3)


class BootStateTest(unittest.TestCase):
    def test_nothing_fires_before_a_level_is_set(self):
        world = World(60)
        Dimmer(ZC, OUTS, mains_hz=60)
        world.run(8333 * 6)
        self.assertEqual(sum(len(v) for v in world.gate_on.values()), 0)

    def test_outputs_low_even_if_state_machine_had_junk(self):
        world = World(60)
        machine.LEVELS.update({p: 1 for p in OUTS})  # pins left high by something
        d = Dimmer(ZC, OUTS, mains_hz=60)
        self.assertEqual([machine.LEVELS[p] for p in OUTS], [0] * 8)
        world.run(8333 * 3)
        self.assertEqual(sum(len(v) for v in world.gate_on.values()), 0)
        d.deinit()

    def test_deinit_leaves_outputs_low(self):
        world = World(60)
        d = Dimmer(ZC, OUTS, mains_hz=60)
        d.set_levels([255] * 8)
        world.run(8333 * 3 + 100)
        d.deinit()
        world.run(8333 * 3)
        self.assertEqual([machine.LEVELS[p] for p in OUTS], [0] * 8)

    def test_no_mains_falls_back_to_60(self):
        World(None)
        d = Dimmer(ZC, OUTS[:1])
        self.assertEqual(d.mains_hz, 60)
        self.assertIsNone(d.measured_hz)


class PacketDecoderTest(unittest.TestCase):
    def packet(self, levels):
        x = 0
        for b in levels:
            x ^= b
        return bytes([1]) + bytes(levels) + bytes([x])

    def feed_all(self, dec, data):
        out = []
        for b in data:
            r = dec.feed(b)
            if r is not None:
                out.append(r)
        return out

    def test_good_packet(self):
        lv = [0, 255, 128, 2, 3, 4, 5, 6, 7, 8]
        self.assertEqual(self.feed_all(PacketDecoder(), self.packet(lv)), [bytes(lv)])

    def test_bad_checksum_dropped(self):
        p = bytearray(self.packet([10] * 10))
        p[-1] ^= 0xFF
        self.assertEqual(self.feed_all(PacketDecoder(), p), [])

    def test_checksum_of_one_allowed(self):
        lv = [3, 2, 0, 0, 0, 0, 0, 0, 0, 0]  # 3 ^ 2 == 1
        self.assertEqual(self.feed_all(PacketDecoder(), self.packet(lv)), [bytes(lv)])

    def test_start_byte_resyncs(self):
        dec = PacketDecoder()
        lv = [9] * 10
        data = b"\x01\x05\x06" + self.packet(lv) + b"\x22\x33" + self.packet(lv)
        self.assertEqual(self.feed_all(dec, data), [bytes(lv), bytes(lv)])


if __name__ == "__main__":
    unittest.main()
