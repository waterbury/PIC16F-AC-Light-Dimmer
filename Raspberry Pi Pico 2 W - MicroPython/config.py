# Board settings shared by boot.py and main.py.

# Zero-cross detector output (the PIC used RB0).
ZC_PIN = 2

# Triac driver inputs, channel 1 first (the PIC used RA0-RA2, RB3-RB7).
OUT_PINS = (6, 7, 8, 9, 10, 11, 12, 13)

# 50, 60, or None to measure the mains frequency at start-up.
MAINS_HZ = None

# Time from the zero-cross detector's edge to the real zero crossing.
# The PIC firmware used 521 us (Timer1 preload 0xF5D3 at 20 MHz) for the original board.
ZC_OFFSET_US = 521

# Serial input, same as the PIC: 19200 baud, 8N1, 12-byte packets.
UART_ID = 0
UART_TX_PIN = 0
UART_RX_PIN = 1
UART_BAUD = 19200
