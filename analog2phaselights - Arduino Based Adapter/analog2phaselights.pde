// Allows for the use of an MSGEQ7 to control an AC Dimmable Box
// based on the PIC16F-AC-Light-Dimmer Project
// V1.0
// MSGEQ7 Code (c) J Skoba


//values for MSGEQ7 Chip
int analogPin = 0; // read from multiplexer using analog input 0
int strobePin = 2; // strobe is attached to digital pin 2
int resetPin = 3; // reset is attached to digital pin 3
int spectrumValue[7]; // to hold a2d values

void setup() 
{
  Serial.begin(19200);

  pinMode(analogPin, INPUT);
  pinMode(strobePin, OUTPUT);
  pinMode(resetPin, OUTPUT);
  analogReference(DEFAULT);
  digitalWrite(resetPin, LOW);
  digitalWrite(strobePin, HIGH);
 // Serial.println("MSGEQ7 test by J Skoba");
 
}

void loop()
{


  
  int i = 0;
  
  digitalWrite(resetPin, HIGH);
  digitalWrite(resetPin, LOW);

//grabs readings from chip
  for (i = 0; i < 7; i++)
  {
    digitalWrite(strobePin, LOW);
    delayMicroseconds(30); // to allow the output to settle
    spectrumValue[i] = analogRead(analogPin);

    digitalWrite(strobePin, HIGH);
    
    //makes 10 bit value 8 bit
    spectrumValue[i] /= 4;
    spectrumValue[i] += 30;
    
    if(spectrumValue[i] > 255)
     spectrumValue[i] = 255;
   
  }
 
  

   
  outputToLights(spectrumValue[0], spectrumValue[1], spectrumValue[2], spectrumValue[3], spectrumValue[4], spectrumValue[5], spectrumValue[6], 0);
   
/* //Test stuff  
  if (i == 255){
   i = 0; 
  }
  channel_1 = i;

  outputToLights(channel_1, 0, 0, 0, 0, 0, 0, 0);
  
  delayMicroseconds(100000);  
  
  i++;
 */
 //}
}

//Takes in 8 light channels and outputs to serial. 8-bit Int 
//If a channel is invalid returns 0, else 1
int outputToLights(int channel_1, int channel_2, int channel_3, int channel_4, int channel_5, int channel_6, int channel_7, int channel_8)
{

int channelArray[10];

channelArray[0] = channel_1;
channelArray[1] = channel_2;
channelArray[2] = channel_3;
channelArray[3] = channel_4;
channelArray[4] = channel_5;
channelArray[5] = channel_6;
channelArray[6] = channel_7;
channelArray[7] = channel_8;
channelArray[8] = 0;
channelArray[9] = 0;
 
int checksum = 0;


Serial.print(01, BYTE);//Start Byte

for(int i=0; i<10 ; i++)
 {
  //If Channel Value is invalid, return 0
  if( channelArray[i] > 255 || channelArray[i] < 0 )
   return 0;
   
  //value '1' is reserved for start byte, if 1, change it.  
  if (channelArray[i] == 1)
   channelArray[i] = 0;

  //generates checksum by xor'ing channels 1-10
  checksum = checksum ^ channelArray[i];

  //Sends channel
  Serial.print(channelArray[i], BYTE);
 }
  
Serial.print(checksum, BYTE);  
  
   delayMicroseconds(8333); //delay execution to 120hz. Same as AC 
   
  return 1;//Return 1 as Function completed
}  




