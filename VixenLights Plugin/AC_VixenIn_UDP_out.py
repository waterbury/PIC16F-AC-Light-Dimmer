import socket
import time
import serial
import threading
import array

#-------------------------------------------------------------------------
# Sets up serial port

LightDimmer = serial.Serial(port='/dev/ttyS0', timeout=0)
LightDimmer.baudrate=57600
#LightDimmer.timeout = 0
#LightDimmer.






color = 31
colorstr = ""
startByte = 1
channels = array.array('i',(0 for i in range(0,32)))
packets = 1.0
packets_successful = 1.0
count = 0
byte_checksum = 0
data_packet = ""
i=0
valueTest = ""
hexstr = ""
escapeFlag = 0
prevCount = 0
high_byte = 0
low_byte = 0

from socket import socket, AF_INET, SOCK_DGRAM
data = 'UDP Data Content'
port = 9802
hostname = '192.168.10.222'
udp = socket(AF_INET,SOCK_DGRAM)


while True:
#     time.sleep(0.0181818)

      for char in valueTest:

       
       if ord(char) == 126:
        count = 1
        print ""
        print "Packet: ",

       if ord(char) == 128 and count == 1:
        count = 2
        prevCount = 2


        



        
       elif count >= 2:
        if ord(char) == 127:
         escapeFlag = 1;
		 
        elif escapeFlag ==1:
         escapeFlag = 0
		 
         if  ord(char) == 47:
          channels[count-2] = 125 # 0x7D
          count += 1
		  
         elif  ord(char) == 48:
          channels[count-2] = 126 # 0x7E
          count += 1
		  
         elif  ord(char) == 49:
          channels[count-2] = 128 # 0x7F
          count += 1
		  
         else:  
          count = 0
		  
		  
        else:
         channels[count-2] = ord(char)
         count += 1		


       if count == 10:
        #count = 0
        data_packet = ""

        for i in range(0, 8):
         hexstr = hex(channels[i])[2:]
         if len(hexstr) == 1:
          hexstr = '0' + hexstr
         data_packet = data_packet + hexstr

        data_packet = data_packet + chr(13) + chr(10)
        udp.sendto(data_packet, ("192.168.10.222", 9802))


       if count > prevCount:
        prevcount = count	 
       if ord(char) > 200:
        color = 31
       elif ord(char) > 150:
        color = 35
       elif ord(char) > 100:
        color = 33
       elif ord(char) > 50:
        color = 34
       else: 
        color = 32
		
       colorstr = "\033[1;"
				
       colorstr += str(color)
				
       colorstr += "m" + str(ord(char)).zfill(3) +"\033[1;m"
       print colorstr,



      #print "" 
      valueTest = ( LightDimmer.read(10) )

      #LightDimmer.flushInput()
      

LightDimmer.close()
