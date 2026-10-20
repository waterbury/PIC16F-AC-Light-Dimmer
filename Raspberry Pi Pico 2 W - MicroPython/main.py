# Example: behave like the PIC dimmer, taking 12-byte packets at 19200 baud
# so the Vixen plugin, the Python test apps and the Arduino adapter work as-is.
# Set DEMO = True to fade the channels up and down without a serial source.
import time
from machine import UART, Pin
from acdimmer import Dimmer, PacketDecoder
import config

DEMO = False

dimmer = Dimmer(
    config.ZC_PIN,
    config.OUT_PINS,
    mains_hz=config.MAINS_HZ,
    zc_offset_us=config.ZC_OFFSET_US,
)
print("acdimmer: %d channels at %d Hz" % (len(dimmer), dimmer.mains_hz))


def demo():
    # Fade each channel up and back down in turn, like the PIC's diagnostic routine.
    while True:
        for ch in range(len(dimmer)):
            for level in tuple(range(0, 256, 5)) + tuple(range(255, -1, -5)):
                dimmer[ch] = level
                time.sleep_ms(20)


def serial_bridge():
    uart = UART(
        config.UART_ID,
        config.UART_BAUD,
        tx=Pin(config.UART_TX_PIN),
        rx=Pin(config.UART_RX_PIN),
    )
    decoder = PacketDecoder()
    while True:
        data = uart.read()
        if not data:
            time.sleep_ms(1)
            continue
        for b in data:
            levels = decoder.feed(b)
            if levels:
                dimmer.set_levels(levels)


try:
    demo() if DEMO else serial_bridge()
finally:
    dimmer.deinit()
