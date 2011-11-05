import socket
import time
import serial


# LightDimmer Python control, by Theodore Wahrburg. (c)2011 (Ver 7)
# Requires 'Pyserial' library
# For use with PIC16F-AC-Light-Dimmer. https://github.com/waterbury/PIC16F-AC-Light-Dimmer
# Listens on UDP Port 9802, 
# and will directly take Light Dimming channels from Discolitez Pro's "Network Pipe" module.

# denary2binary provided by "vegaseat    6/1/2005"
# It converts a decimal (denary, base 10) integer to a binary string (base 2)


def denary2binary(n):
    '''convert denary integer n to binary string bStr'''
    bStr = ''
    if n < 0:  raise ValueError, "must be a positive integer"
    if n == 0: return '0'
    while n > 0:
        bStr = str(n % 2) + bStr
        n = n >> 1
    return bStr

def ChannelConvert (number):
 if number > 250 or number == 0:
  number = number
 else:
  number = number / 2.55
  number = number * 2
  number += 30

 if number > 255:
  number = 255

 return int(number)

#-------------------------------------------------------------------------
# Sets up serial port

LightDimmer = serial.Serial('/dev/tts/1')
LightDimmer.baudrate=19200





#Change IP to IP of device running script
UDP_IP="192.168.1.222"
UDP_PORT=9802

sock = socket.socket( socket.AF_INET, # Internet
                      socket.SOCK_DGRAM ) # UDP
sock.bind( (UDP_IP,UDP_PORT) )

startByte = 1
Channel_1 = 0
Channel_2 = 0
Channel_3 = 0
Channel_4 = 0
Channel_5 = 0
Channel_6 = 0
Channel_7 = 0
Channel_8 = 0
i=0

while True:

#    time.sleep(0.0181818)    

#    data, addr = sock.recvfrom( 256 )
    data, addr = sock.recvfrom( 18 ) # buffer size is 20 bytes
    if (len((data)) == 18):
     Byte_17 = ord(data[16])
     Byte_18 = ord(data[17])

     if(Byte_17 == 13 and Byte_18 == 10):
      i = 0

      value = data[0:2]
      if ( (value != "GG") and (value != "gg") ):
       Channel_1 = int(value,16)

      if ((data[2:4] != "GG") and (data[2:4] != "gg") ):
       Channel_2 = int(data[2:4],16)
 
      if ((data[4:6] != "GG") and (data[4:6] != "gg")):
       Channel_3 = int(data[4:6],16)

      if ((data[6:8] != "GG") and (data[6:8] != "gg")):
       Channel_4 = int(data[6:8],16)

      if ((data[8:10] != "GG") and (data[8:10] != "gg")):
       Channel_5 = int(data[8:10],16)

      if ((data[10:12] != "GG") and (data[10:12] != "gg")):
       Channel_6 = int(data[10:12],16)
 
      if ((data[12:14] != "GG") and (data[12:14] != "gg")):
       Channel_7 = int(data[12:14],16)

      if ((data[14:16] != "GG") and (data[14:16] != "gg")):
       Channel_8 = int(data[14:16],16)


      print "UDP In: " + str(Channel_1).zfill(3) + " " + str(Channel_2).zfill(3) + " " + str(Channel_3).zfill(3) + " " + str(Channel_4).zfill(3) + " " + str(Channel_5).zfill(3) + " " + str(Channel_6).zfill(3) + " " + str(Channel_7).zfill(3) + " " + str(Channel_8).zfill(3),



      Channel_1 = ChannelConvert(Channel_1)
      Channel_2 = ChannelConvert(Channel_2)
      Channel_3 = ChannelConvert(Channel_3)
      Channel_4 = ChannelConvert(Channel_4)
      Channel_5 = ChannelConvert(Channel_5)
      Channel_6 = ChannelConvert(Channel_6)
      Channel_7 = ChannelConvert(Channel_7)
      Channel_8 = ChannelConvert(Channel_8)

      if Channel_1 == 1:
       Channel_1 = 0
      if Channel_2 == 1:
       Channel_2 = 0
      if Channel_3 == 1:
       Channel_3 = 0
      if Channel_4 == 1:
       Channel_4 = 0
      if Channel_5 == 1:
       Channel_5 = 0
      if Channel_6 == 1:
       Channel_6 = 0
      if Channel_7 == 1:
       Channel_7 = 0
      if Channel_8 == 1:
       Channel_8 = 0

      print "         |      Serial Out: ",
      print str(Channel_1).zfill(3) + " " + str(Channel_2).zfill(3) + " " + str(Channel_3).zfill(3) + " " + str(Channel_4).zfill(3) + " " + str(Channel_5).zfill(3) + " " + str(Channel_6).zfill(3) + " " + str(Channel_7).zfill(3) + " " + str(Channel_8).zfill(3)
      
      byte_checksum = 0
      byte_checksum = Channel_1
      byte_checksum = byte_checksum ^ Channel_2
      byte_checksum = byte_checksum ^ Channel_3
      byte_checksum = byte_checksum ^ Channel_4
      byte_checksum = byte_checksum ^ Channel_5
      byte_checksum = byte_checksum ^ Channel_6
      byte_checksum = byte_checksum ^ Channel_7
      byte_checksum = byte_checksum ^ Channel_8
      byte_checksum = byte_checksum ^ 0
      byte_checksum = byte_checksum ^ 0

      LightDimmer.write(chr(startByte)+chr(Channel_1)+chr(Channel_2)+chr(Channel_3)+chr(Channel_4)+chr(Channel_5)+chr(Channel_6)+chr(Channel_7)+chr(Channel_8)+chr(00)+chr(00)+chr(byte_checksum))
      #print time.tm_sec
      #data, addr = sock.recvfrom( 1024 )

     else:
      print "Invalid Packet Ending -- Byte 17: " + denary2binary((Byte_17)).zfill(8) + " -- Byte 18: " + denary2binary((Byte_18)).zfill(8) + " -- Cnt: " + str(i)
      i += 1

    else:
     print "6" 

LightDimmer.close()
