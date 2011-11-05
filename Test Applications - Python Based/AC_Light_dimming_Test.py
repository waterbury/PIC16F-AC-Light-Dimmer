import serial
import time
import sys


# LightDimmer Python control, by Theodore Wahrburg. (c)2011 (Ver 0.2)
# Requires 'Pyserial' library
# For use with PIC16F-AC-Light-Dimmer. https://github.com/waterbury/PIC16F-AC-Light-Dimmer
# Takes in nine bytes as arguments.
# First Byte is for startByte and should be '1'
# The next eight bytes represent channel brightness values from 0-255. If startbyte is used as a channel value, packet shouldn't work.
# Script comes with absolutely no warranty, to the extent permitted by applicable law. Use at your own risk.
# 
#-------------------------------------------------------------------------


#-------------------------------------------------------------------------
# Sets up serial port. Change com port as required. Speed should 19200 for Dimmer version 1.4 and later. 9600 was used prior.

LightDimmer = serial.Serial('/dev/ttyS0')  
LightDimmer.baudrate=19200

#------------------------------------------------------------------------
# Arguments; format is ID (0-10), PORT (0-8), POSITION (0-20000)

startByte = int(sys.argv[1])
Channel_0 = int(sys.argv[2]) 
Channel_1 = int(sys.argv[3]) 
Channel_2 = int(sys.argv[4]) 
Channel_3 = int(sys.argv[5]) 
Channel_4 = int(sys.argv[6]) 
Channel_5 = int(sys.argv[7]) 
Channel_6 = int(sys.argv[8]) 
Channel_7 = int(sys.argv[9]) 


#------------------------------------------------------------------------
#
byte_checksum = 0
byte_checksum = Channel_0
byte_checksum = byte_checksum ^ Channel_1
byte_checksum = byte_checksum ^ Channel_2
byte_checksum = byte_checksum ^ Channel_3
byte_checksum = byte_checksum ^ Channel_4
byte_checksum = byte_checksum ^ Channel_5
byte_checksum = byte_checksum ^ Channel_6
byte_checksum = byte_checksum ^ Channel_7
byte_checksum = byte_checksum ^ 0
byte_checksum = byte_checksum ^ 0

#------------------------------------------------------------------------
# Writes to serial port

LightDimmer.write(chr(startByte)+chr(Channel_0)+chr(Channel_1)+chr(Channel_2)+chr(Channel_3)+chr(Channel_4)+chr(Channel_5)+chr(Channel_6)+chr(Channel_7)+chr(00)+chr(00)+chr(byte_checksum))

LightDimmer.close()

print "xor'ed byte was INT(" + str(byte_checksum) + ") or Binary (" + denary2binary(byte_checksum) + ")"

#print "Sent: " + hex(ID) + " " + hex(servo) + " 0x80 " + hex(upByte) + " " + hex(lowByte) + "  --  Value: " + str(position) + "  --  Degrees: " + degSymb + str(degrees)

