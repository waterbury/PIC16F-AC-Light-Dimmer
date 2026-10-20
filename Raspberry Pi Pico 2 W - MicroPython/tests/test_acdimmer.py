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
from acdimmer import Dimmer, PacketDecoder, gate_times  # noqa: E402

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
        self.gate_off = {p: [] for p in OUTS}
        self.high_us = {p: 0 for p in OUTS}
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
                level = machine.LEVELS.get(p, 0)
                self.high_us[p] += level
                if level and not before[p]:
                    self.gate_on[p].append(self.now)
                elif before[p] and not level:
                    self.gate_off[p].append(self.now)

    def since_edge(self, times):
        """Each time, measured from the most recent zero-cross edge."""
        out = []
        for t in times:
            prev = [e for e in self.edges if e <= t]
            out.append(t - prev[-1])
        return out


class GateTimesTest(unittest.TestCase):
    def test_no_offset(self):
        # Fires later as the level drops, always released at the zero crossing.
        times = [gate_times(lv, 8333, 0, 200) for lv in range(1, 255)]
        ons = [on for on, off in times]
        self.assertEqual(ons, sorted(ons, reverse=True))
        self.assertEqual(ons[0], 8333 - 200)
        self.assertLess(ons[-1], 40)
        self.assertEqual({off for on, off in times}, {0})

    def test_pic_offset_wraps_past_next_edge(self):
        # Edge comes 521 us before the true zero crossing (the PIC board).
        t = (255 - 4) * (8333 - 200) // 254
        self.assertEqual(gate_times(4, 8333, 521, 200), ((521 + t) % 8333, 521))
        self.assertEqual(gate_times(128, 8333, 521, 200)[1], 521)
        # Just short of wrapping, the change would land on the next edge: make it a little earlier.
        self.assertEqual(gate_times(12, 8333, 521, 200)[0], 8333 - 50)

    def test_negative_offset(self):
        # Edge comes 300 us after the true zero crossing.
        self.assertEqual(gate_times(254, 10000, -300, 200), (9700 + 38, 9700))


class DimmerTimingTest(unittest.TestCase):
    def check(self, hz, mains_hz, offset, levels, rising=True):
        world = World(hz, edge_rising=rising)
        d = Dimmer(ZC, OUTS, mains_hz=mains_hz, zc_offset_us=offset,
                   zc_edge=acdimmer.RISING if rising else acdimmer.FALLING)
        half = 10_000 if hz == 50 else 8_333
        self.assertEqual(d.mains_hz, hz)
        d.set_levels(levels)
        world.run(half * 6)
        for p in OUTS:
            world.gate_on[p].clear()
            world.gate_off[p].clear()
            world.high_us[p] = 0
        world.run(half * 4)
        for pin, lv in zip(OUTS, levels):
            if lv == 0:
                self.assertEqual(world.high_us[pin], 0, "channel at 0 turned on")
                continue
            if lv == 255:
                self.assertEqual(world.high_us[pin], half * 4, "255 not held on")
                continue
            on, off = gate_times(lv, half, offset, 200)
            ons = world.since_edge(world.gate_on[pin])
            offs = world.since_edge(world.gate_off[pin])
            self.assertEqual(len(ons), 4, "level %d did not fire every half-cycle" % lv)
            self.assertEqual(len(offs), 4, "level %d was not released every half-cycle" % lv)
            for g in ons:
                self.assertLessEqual(abs(g - max(on, 3)), 3, (lv, ons, on))
            for g in offs:
                self.assertLessEqual(abs(g - max(off, 3)), 3, (lv, offs, off))
            # Held from firing until the zero crossing.
            held = (off - on) % half
            self.assertLessEqual(abs(world.high_us[pin] / 4 - held), 4, (lv, world.high_us[pin], held))
        return world, d

    def test_60hz(self):
        self.check(60, 60, 0, (0, 1, 30, 64, 128, 200, 254, 255))

    def test_50hz(self):
        self.check(50, 50, 0, (0, 1, 30, 64, 128, 200, 254, 255))

    def test_auto_detects_50hz(self):
        self.check(50, None, 521, (0, 4, 12, 64, 128, 200, 254, 255))

    def test_auto_detects_60hz_with_pic_offset(self):
        self.check(60, None, 521, (0, 4, 12, 64, 128, 200, 254, 255))

    def test_negative_offset(self):
        self.check(60, 60, -300, (0, 1, 30, 64, 128, 200, 254, 255))

    def test_falling_edge_detector(self):
        self.check(60, 60, 521, (0, 1, 30, 64, 128, 200, 254, 255), rising=False)

    def test_latest_value_wins(self):
        world = World(60)
        d = Dimmer(ZC, OUTS[:1], mains_hz=60)
        for lv in range(1, 200):
            d[0] = lv  # far faster than mains; must not overflow the FIFO
        d[0] = 128
        world.run(8333 * 4)
        on, off = gate_times(128, 8333, 0, 200)
        self.assertLessEqual(abs(world.since_edge(world.gate_on[OUTS[0]])[-1] - on), 3)

    def test_level_changes_cleanly(self):
        # Switching between levels either side of the wrap never leaves a channel stuck on.
        world = World(60)
        d = Dimmer(ZC, OUTS[:1], mains_hz=60, zc_offset_us=521)
        for lv in (4, 200, 4, 0, 255, 0):
            d[0] = lv
            world.run(8333 * 3)
        self.assertEqual(machine.LEVELS[OUTS[0]], 0)


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
