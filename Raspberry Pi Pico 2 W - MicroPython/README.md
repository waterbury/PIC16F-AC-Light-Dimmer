# AC Light Dimmer for the Raspberry Pi Pico 2 W (MicroPython)

A port of `PIC16F628A-AC-Light-Dimmer.asm` to the Raspberry Pi Pico 2 W (RP2350),
written as a small MicroPython library so the dimmer can be driven from your own code.

* `acdimmer.py` – the library: `Dimmer` (phase-control output) and `PacketDecoder` (the PIC's serial protocol)
* `config.py` – pins, mains frequency and zero-cross offset for your board
* `boot.py` – drives every triac output low the moment MicroPython starts
* `main.py` – example: works like the PIC, taking 12-byte packets at 19200 baud
* `tests/` – host tests that run the PIO programs on a simulator (`python3 -m unittest discover tests`)

> **Mains voltage can kill you.** Everything on the mains side must be isolated from
> the Pico by the zero-cross optocoupler and the triac driver optocouplers, and the
> whole thing must be in a closed, earthed or double-insulated box. Never touch or
> probe the board while it is plugged in, and never connect USB to a computer while
> the mains side is live unless the isolation is known good.

## Using the library

```python
from acdimmer import Dimmer, FALLING

dimmer = Dimmer(
    zc_pin=2,                      # zero-cross detector output
    out_pins=(6, 7, 8, 9),         # triac drivers, channel 0 first
    mains_hz=None,                 # 50, 60, or None to measure it at start-up
    zc_offset_us=521,              # detector edge to real zero crossing (the PIC used 521 us)
)

dimmer[0] = 255                    # full on
dimmer[1] = 128                    # about half
dimmer.set_percent(2, 25)
dimmer.set_levels([0, 64, 128, 255])
dimmer.off()
print(dimmer.mains_hz, dimmer.measured_hz)
dimmer.zc_offset_us = 600          # can be tuned while running
dimmer.deinit()                    # stop and leave every output low
```

Levels are 0 (off) to 255 (full), the same as the PIC's channel bytes. You can set them as
often as you like; each channel picks up its newest level at the next half-cycle.

Other constructor options:

| Option | Default | Meaning |
| --- | --- | --- |
| `zc_edge` | `RISING` | Which edge of the detector output marks a zero crossing. Use `FALLING` for a detector that idles high and pulses low (e.g. an optocoupler with a pull-up). |
| `zc_pull` | `None` | `Pin.PULL_UP` or `Pin.PULL_DOWN` on the zero-cross input. |
| `gate_pulse_us` | `200` | Length of each gate pulse. Make it longer if LED strings flicker at low levels. |
| `end_margin_us` | `200` | The dimmest level fires at least this long (plus the pulse) before the next zero crossing. |
| `sm_ids` | PIO0, then PIO2, then PIO1 | Which PIO state machines to use, one per channel (up to 12). |

### Zero-cross offset

`zc_offset_us` is the time from the detector's edge to the real zero crossing. Most
optocoupler detectors switch a little before the crossing, so the offset is positive;
if yours switches after it, use a negative number. If the dimmest levels flicker or
full brightness is not quite full, adjust it in steps of about 50 us.

### 50 Hz and 60 Hz

Pass `mains_hz=50` or `mains_hz=60`, or leave it as `None` and the dimmer measures the
zero-cross input for up to a second at start-up. If it sees no zero crossings (mains not
connected) it assumes 60 Hz and prints a warning. The detector must give one edge every
half-cycle (a full-wave detector, like the original board); when measuring, a
half-wave detector raises an error.

## How it differs from the PIC

The PIC counted 250 steps of 32.8 us in a hand-timed loop after each zero crossing.
Here each channel has its own PIO state machine running at 1 MHz: it waits for the
zero-cross edge, waits that channel's delay, then sends one gate pulse. Timing is done
in hardware to 1 us, so Wi-Fi, garbage collection or slow Python code cannot make the
lights flicker. If the Python program crashes, the lights stay at their last levels.

The PIC held each output high from the moment it fired until the next half-cycle; this
port sends a short pulse instead, which is all a triac needs and means an output never
stays on across a zero crossing.

## The power-up flash

On the PIC board the lights flashed when it was plugged in because:

1. the outputs floated until the firmware started,
2. `TRISA` was set to outputs before `PORTA` was cleared, so the outputs briefly drove whatever was in the latch, and
3. the `CHANNEL_x_WORK` registers were never cleared, so the first half-cycle fired every channel at a random level.

This port fixes all three:

1. **Pull-down resistors** on every output (below) hold the triac drivers off from power-up until MicroPython runs.
2. **`boot.py`** sets every output pin to output-low before anything else is imported. The pin's level is set before it is made an output.
3. **`Dimmer()`** drives the outputs low again, and every state machine starts with its level at 0 (off), so nothing fires until your code sets a level.

The pull-downs matter on the Pico 2 W: the RP2350's own pull-down is weak, and erratum
RP2350-E9 means an undriven pin with only the internal pull-down can sit at about 2 V,
enough to half-turn-on a driver. Use an external pull-down of **8.2 kΩ or less**
(4.7 kΩ is a good value) on every output.

## Wiring

The Pico 2 W runs at 3.3 V. Pins below are the defaults in `config.py`; any free GPIO
works except GP23, GP24, GP25 and GP29, which the Pico 2 W uses for its wireless chip.

| Pico 2 W | Connects to | PIC equivalent |
| --- | --- | --- |
| GP2 | Zero-cross detector output | RB0 |
| GP6 … GP13 | Triac driver, channels 1–8 | RA0–RA2, RB3–RB7 |
| GP1 (UART0 RX) | Serial input from the controller, 19200 8N1 | RB1 |
| GP0 (UART0 TX) | Serial output (unused) | RB2 |
| GND | Logic ground (zero-cross detector and driver LED side only) | VSS |

### Each output channel

```
                     3V3 or 5V
                         |
                        [R]  sized for the driver's LED trigger current
                         |
                    1 (anode)    MOC3021 / MOC3023 (random-phase type,
                    2 (cathode)  NOT a MOC304x zero-crossing type)
                         |
                         C
GPxx ---[1 kΩ]---+-----B    2N3904 (or one input of a ULN2803)
                 |       E
              [4.7 kΩ]   |
                 |       |
                GND     GND
```

The RP2350 pins default to 4 mA, which is not enough for a MOC3021 (15 mA) directly, so
drive the optocoupler LED through a transistor or a ULN2803 as shown. The 4.7 kΩ
resistor from the GPIO to ground is the power-up pull-down. The mains side of the
MOC302x and triac is the same as on the PIC board.

### Zero-cross detector

Any detector that gives a clean pulse at every zero crossing works. Keep its output at
3.3 V: pull it up to the Pico's 3V3 pin, not 5 V. A typical H11AA1 or bridge + 4N25
detector with a pull-up idles high and pulses low, so use `zc_edge=FALLING` with it. A
detector wired like the original board (pulse goes high at the crossing) uses the
default `RISING`.

## Installing

1. Flash the MicroPython firmware for the Pico 2 W (`RPI_PICO2_W`), from https://micropython.org/download/RPI_PICO2_W/.
2. Edit `config.py` for your pins and offset.
3. Copy the files over, for example with `mpremote`:

   ```
   mpremote cp config.py boot.py acdimmer.py main.py :
   mpremote reset
   ```

Set `DEMO = True` in `main.py` to fade each channel up and down without a serial
controller connected. Test with a lamp on one channel first.

## Running the tests

On a PC, from this folder:

```
python3 -m unittest discover tests
```

The tests assemble the PIO programs with MicroPython's assembler (`tests/stubs/rp2.py`)
and run them on a simulated state machine against a simulated 50 Hz or 60 Hz
zero-cross signal, checking when each gate pulse starts and how long it lasts.
