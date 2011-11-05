;***************************************************************
;(C) 2011 Theodore Wahrburg
; email: ted.wahrburg (At) gmail (dot) com
;This Program comes with no warranty. USE AT YOUR OWN RISK. Free for all non-commercial use. Plese provide proper credit if code is used in future project.
;

;Designed for 16F628 @20Mhz
;***************************************************************
LIST P=PIC16F628A
#include	<P16F628A.inc>


;v0.1 - Set up DIAGNOSTIC_ROUTINE that has LED counter for counting value from 0-15 repeatedly. Values changed every 2 seconds
;v0.2 - Updated DIAGNOSTIC_ROUTINE so that LED counter counts from 0-15, then counts down back to 0, then back up. Also switches between 2s switch, and 1/4s
;v0.3 - Increased clock speed from internal 4MHz clock, to External 20MHz crystal, because I'm a beast
;v0.4 - MASSIVE CHANGES. Implmented Zero Cross Dtection, phase offser, and phase control. Micro chip is actually performing as it should
;v0.5 - Cleaned up code; minor differences
;v0.6 - Optimized TIMER_LOOP, and Changed Channel 1 and 2 from PORTB to PORTA to prepare RBB1 and RB2 for future UART implementation, fixed Channel 7
;		bug which would turn off channel shortly after turning on.
;v0.7 - Started with UART Code, shit didn't work
;v0.8 - Continued with UART Code, shit works!! RTFM! Implimented UART Test routine
;v0.9 - Fixed  code that triggered a few wrong output lines
;v1.0 - Started Changing Brightness code
;v1.1 - Fixed Legacy Test Code Bits, fixed some XOR Checksum Bugs
;v1.2 - Rewrote..... EVERYTHING, well almost, changed dimming routine to main loop. Timed main loop to 164 clocks. 255 levels of phase control.
;v1.3 - Fixed a few minor timing bugs, cleaned comments
;v1.4 - Increasing UART Baud Rate from 9600 to 19200


; Configuration Bits
;	__config	_CP_OFF & _WDT_OFF & _PWRTE_ON & _BODEN_OFF &_INTRC_OSC_NOCLKOUT & _MCLRE_ON & _LVP_OFF


__Config 3F0Ah       	
;_cp_off & _lpv_off & _pwrte_off & _wdt_off & _intRC_oscI/O
;code protection - off
;low-voltage programming - off
;power-up timer -  off
;watchdog timer - off
;use  High Speed External Crystal for 20MHz - so that all pins except RA6, RA7 in-out

  
;	ERRORLEVEL -302
;***************************************************************
;DEFINE FILES
   cblock 0x20

;Main Channel Registers

CHANNEL_0_BUFFER; Buffered byte from UART
CHANNEL_0_RECEIVE; Receive byte from UART
CHANNEL_0_WORK; Use byte for software interrupt timer

CHANNEL_1_BUFFER; Buffered byte from UART
CHANNEL_1_RECEIVE; Receive byte from UART
CHANNEL_1_WORK; Use byte for software interrupt timer

CHANNEL_2_BUFFER; Buffered byte from UART
CHANNEL_2_RECEIVE; Receive byte from UART
CHANNEL_2_WORK; Use byte for software interrupt timer

CHANNEL_3_BUFFER; Buffered byte from UART
CHANNEL_3_RECEIVE; Receive byte from UART
CHANNEL_3_WORK; Use byte for software interrupt timer

CHANNEL_4_BUFFER; Buffered byte from UART
CHANNEL_4_RECEIVE; Receive byte from UART
CHANNEL_4_WORK; Use byte for software interrupt timer

CHANNEL_5_BUFFER; Buffered byte from UART
CHANNEL_5_RECEIVE; Receive byte from UART
CHANNEL_5_WORK; Use byte for software interrupt timer

CHANNEL_6_BUFFER; Buffered byte from UART
CHANNEL_6_RECEIVE; Receive byte from UART
CHANNEL_6_WORK; Use byte for software interrupt timer

CHANNEL_7_BUFFER; Buffered byte from UART
CHANNEL_7_RECEIVE; Receive byte from UART
CHANNEL_7_WORK; Use byte for software interrupt timer

BYTE_BUFFER; Recieved RS-232 Byte
BYTE_COUNT
BYTE_RECEIVED_FLAG
BYTE_TRIGGERS; Holds which bytes have been received
BYTE_TRIGGERS_2
BYTE_CHECKSUM

CHANNEL_TRIGGERS; Holds what Channels have been triggered

INTERRUPT_OPTIONS


;Registers used for test, diagnostic routine
BINARY_COUNTER
DELAY_SELECTOR; bit 0 is set for fast delay, clear for slow   (bit 1 is set if need to subtract BINARY COUNTER, Clear if Add is needed)
DELAY_SELECTOR_COUNTER

;Registers used for Delay Loops
d1
d2
d3

;ISR Temp Registers for holding main routine registers
W_ISR_TEMP
PCLATH_ISR_TEMP
FSR_ISR_TEMP
STATUS_ISR_TEMP


TIMER_LOOP_COUNTDOWN

;HARDWARE_INTERRUPT_STATUS_TEMP
;HARDWARE_INTERRUPT_W_TEMP
;TIMER_INTERRUPT_W_TEMP
    endc
;***************************************************************


;*****************************************
;SETUP PORT
	org	0x00
	
	goto	INIT
	

	org	0x0004					; memory location h004
; ***************************************************************************
; Interupt Service Routine    MUST RUN FROM HERE ONLY !
;
; First run the Context Save Registers   - you need to create the _temp files

isr_CS;  ---------------------------- (9 CLOCKS in isr_CS) -------------------------------------
	movwf	W_ISR_TEMP			; copy W to temp 					+ 1 clock = 1
	swapf	STATUS,W			; swap status to be saved into W	+ 1 clock = 2
	clrf	STATUS				; bank 0							+ 1 clock = 3
	movwf	STATUS_ISR_TEMP		; save status in bank O				+ 1 clock = 4
	movf	PCLATH,W			; save pclath						+ 1 clock = 5
	movwf	PCLATH_ISR_TEMP		;									+ 1 clock = 6
	clrf	PCLATH				; clear to page 0 for ISR			+ 1 clock = 7
	movf	FSR,W				; save FSR							+ 1 clock = 8
	movwf	FSR_ISR_TEMP		;									+ 1 clock = 9
;****************************************************************************

; User Code   - MUST STAY WITHING ISR BOUNDARIES  - DO NOT USE GOTOs OUT OF THE ISR - USE NO CALLS




READ_WHICH_INTERRUPT; WAS TRIGGERED TO GET HERE
	btfsc	PIR1,5 ;Check if the RCIF flag is set; if so, goto RECIEVE_BYTE_INTERRUPT, else, check other interrupts		+ 1 clock (If Byte Receieved) = 10
	goto	RECEIVE_BYTE_INTERRUPT	;								+ 2 clock = 12

	btfsc	PIR1,0; If PIR1 Bit 0 Is high, this means that the TMR1 Timer Register has been triggered...
	goto	PHASE_OFFSET; Goto PHASE_OFFSET

	btfsc	INTCON,1; If INTCON Bit 1 Is high, this means that the RB1 Register has been triggered...
	goto	ZERO_CROSSING_INTERRUPT_CODE; GOTO ZERO_CROSSING_INTERRUPT_CODE as Zero crossing circuit has triggered this

	goto	WRAP_UP_TIMER; Leave if here in error?...




ZERO_CROSSING_INTERRUPT_CODE;  ---------------------------- (11 CLOCKS in ZERO_CROSSING_INTERRUPT_CODE) -------------------------------------
	bcf		INTCON,4; Disables Hardware interrupt until PHASE_OFFSET Offsets 	+ 1 clock (=1)
	bcf		INTCON,1; Clears Hardware Interrupt bit								+ 1 clock (=2)

	bsf		PORTA,3; Goes high to indicate Zero-Crossing Phase (RISING EDGE)	+ 1 clock (=3)

	bsf		INTERRUPT_OPTIONS,0; Indicates that hardware Zero crossing interrupt has occurred	+ 1 clock (=4)


; ZERO-CROSSING OFFSET    Set Timer 1 here...
	movlw	0xF5
	movwf	TMR1H
	movlw	0xD3
	movwf	TMR1L ; Sets up F5D3 as Timer 1, which is 2604 cycles. (Phase Offset)	+ 4 Clocks (=8)
	
	bsf		T1CON,0; Enables Timer 1, should be triggered for Phase Differental		+ 1 clock (=9)


	goto	isr_END;																+ 2 clocks (=11)
;****************************************************************************





PHASE_OFFSET
;Check CHANNEL_BYTEs for full 0xFx Brightness on first nibble
;If Full brightness is desired, Turn On Channel Ouput, else, Turn Off

	movlw	0xFA
	movwf	TIMER_LOOP_COUNTDOWN; Sets up to start TIMER_LOOP, and sets up countdown from 255

	bcf		T1CON,0; Disables Timer 1
	bcf		PIR1,0; Clears Timer 1 Interrupt

	clrf	TMR1H
	clrf	TMR1L ; clears Timer 1

	bcf		PORTA,3; Goes low to indicate Phase Offset (FALLING EDGE)
	bsf		INTCON,4; Re-enables Hardware Interrupt

	goto	isr_END







RECEIVE_BYTE_INTERRUPT;  ---------------------------- (9 CLOCKS in RECEIVE_BYTE_INTERRUPT) -------------------------------------
	btfss	PIR1,5 ;Check if the RCIF flag is set					+ 2 clock (if RCIF flag is set) = 14
	goto	isr_END ;If not, leave ISR

	movf	RCREG,0 ;Move the received byte to W					+ 1 clock = 15
	movwf	BYTE_BUFFER;Move W t0 BYTE_BUFFER						+ 1 clock = 16
	bcf		PIR1,5;Clear RCIF flag									+ 1 clock = 17
	bsf		BYTE_RECEIVED_FLAG,0	;								+ 1 clock = 18
	clrf	RCREG;Clears Receive Register							+ 1 clock = 19

	goto	isr_END	;												+ 2 clock = 21
;****************************************************************************










;isr_UC
;	bcf	STATUS,RP0			;  set bank0 - 			- EXAMPLE CODE
;	btfsc	PIR1,TMR1IF			; timer1 overflow int
;	goto	tm1over		        ; timer1 has overflowed
;	goto 	isr_END				; not tmr1 overflow - error - go back

;tm1over 
;	bcf	PIR1,TMR1IF			; reset timer1
;	movlw	0x80				; preload with 80
;	movwf	TMR1H

;	ETC
;	ETC
	

; CONTEXT RESTORE REGISTERS
isr_END;  ---------------------------- (10 CLOCKS in isr_END) -------------------------------------
	movf	FSR_ISR_TEMP,W	;										+ 1 clock = 22
	movwf	FSR				;										+ 1 clock = 23
	movf	PCLATH_ISR_TEMP,W	;									+ 1 clock = 24
	movwf	PCLATH				;									+ 1 clock = 25
	swapf	STATUS_ISR_TEMP,W	; swap status temp to w to set org bank		+ 1 clock = 26
	movwf	STATUS				; mov W to status							+ 1 clock = 27
	swapf	W_ISR_TEMP,F		; restore W									+ 1 clock = 28
	swapf	W_ISR_TEMP,W		;											+ 1 clock = 29
	retfie						; return from isr							+ 2 clock = (31 Clocks used for receiving byte) <----

; End of ISR  
;****************************************************************************





INIT
;	NOP
	nop
	nop
	nop

org	0x00FF
	movlw	0x07
	movwf	CMCON;Turns off comparator functions?

	movlw	b'00000100'       ; RB2(TX)=1 others are 0
	movwf	PORTB 


    bsf    STATUS,RP0; select register Page 1

	clrf	VRCON	;disable Voltage Reference

	movlw   0x00; Sets all RA as outputs
	movwf   TRISA; Progam Register

	movlw	0x03
	movwf	TRISB	;Port B bit 0 is Hardware Interrupt Input, bit 1 & 2 is UART, rest is output

	movlw	b'11000000'
	movwf	OPTION_REG; Sets up OPTION_REG
			; 7- PORTB Pullups are disabled,
			; 6- Hardware Interrupts are on rising edge of RB0
			; 5 - use internal instruction cycle clock for Prescaler
			; 4 - Transition from low to high for TMR0??
			; 3 - Assign Prescaler to Timer0
			; 2-0  - Set Prescaler for 1:32 Ratio

;bit 7 RBPU: PORTB Pull-up Enable bit
; 1 = PORTB pull-ups are disabled
; 0 = PORTB pull-ups are enabled by individual port latch values
;bit 6 INTEDG: Interrupt Edge Select bit
; 1 = Interrupt on rising edge of RB0/INT pin
; 0 = Interrupt on falling edge of RB0/INT pin
;bit 5 T0CS: TMR0 Clock Source Select bit
; 1 = Transition on RA4/T0CKI/CMP2 pin
; 0 = Internal instruction cycle clock (CLKOUT)
;bit 4 T0SE: TMR0 Source Edge Select bit
; 1 = Increment on high-to-low transition on RA4/T0CKI/CMP2 pin
; 0 = Increment on low-to-high transition on RA4/T0CKI/CMP2 pin
;bit 3 PSA: Prescaler Assignment bit
; 1 = Prescaler is assigned to the WDT
; 0 = Prescaler is assigned to the Timer0 module
;bit 2-0 PS<2:0>: Prescaler Rate Select bits


	bcf		STATUS,RP0	;Select Bank 0

	;movlw	b'10010000'       ; enable Async Reception
	;movwf	RCSTA 

	bsf	RCSTA,SPEN	;enable receive
	bsf	RCSTA,CREN	;enable continous receive

;*****************************************



;*****************************************
;REGISTER INITS
	clrf	PORTA
	;clrf	PORTB
	clrf	BINARY_COUNTER
	clrf	DELAY_SELECTOR_COUNTER
	clrf	CHANNEL_TRIGGERS
	clrf	TIMER_LOOP_COUNTDOWN

	clrf	INTERRUPT_OPTIONS

	clrf	CHANNEL_0_RECEIVE;
	clrf	CHANNEL_1_RECEIVE;
	clrf	CHANNEL_2_RECEIVE;
	clrf	CHANNEL_3_RECEIVE;
	clrf	CHANNEL_4_RECEIVE;
	clrf	CHANNEL_5_RECEIVE;
	clrf	CHANNEL_6_RECEIVE;
	clrf	CHANNEL_7_RECEIVE;
	clrf	BYTE_BUFFER
	clrf	BYTE_CHECKSUM
	clrf	BYTE_TRIGGERS
	clrf	BYTE_TRIGGERS_2
	bcf		PIR1,0
	clrf	DELAY_SELECTOR
	clrf	BYTE_RECEIVED_FLAG
	bsf		DELAY_SELECTOR,0; Sets Delay for Fast to start

;*****************************************


;TIMER 1 INIT
	clrf	TMR1H
	clrf	TMR1L; Clears Timer 1 Registers

	movlw	b'00000100'
	movwf	T1CON;Sets up Timer 1, at INIT, is is disabled




	bsf		STATUS,RP0; select register Page 1
	
	bsf		PIE1,0; Enables TIMER 1 Interrupt

	;---Configure SPBRG for desired baud rate
	MOVLW D'64'; We will use 19200
	MOVWF SPBRG ;baud at 20MHz


	;---Configure TXSTA
	MOVLW B'00100100' ;Configure TXSTA as :
	MOVWF TXSTA ;
	;8 bit transmission - 6.bit
	;Transmit enabled - 5.bit
	;Asynchronous mode - 4.bit
	;Enable high speed baud rate - 2.bit

	bcf		STATUS,RP0; select register Page 0

;-------


	MOVLW B'10010000' ;Enable serial port
	MOVWF RCSTA ;Receive status reg


;HARDWARE INTERUPT ENABLE
	movlw	b'11010000'
	movwf	INTCON; Sets up Initial Hardware Interrupt

		;we need to initialize some things, so do it here.
        movf    RCREG,W                                 ;clear uart receiver
        movf    RCREG,W                                 ;including fifo
        movf    RCREG,W                                 ;which is three deep.

	bsf		STATUS,RP0	;Select Bank 1
	bsf		PIE1,5; Enables USART RECIEVE Interrupt
	bcf		STATUS,RP0	;Select Bank 0

;bit 7 GIE: Global Interrupt Enable bit
; 1 = Enables all un-masked interrupts
; 0 = Disables all interrupts
;bit 6 PEIE: Peripheral Interrupt Enable bit
; 1 = Enables all un-masked peripheral interrupts
; 0 = Disables all peripheral interrupts
;bit 5 T0IE: TMR0 Overflow Interrupt Enable bit
; 1 = Enables the TMR0 interrupt
; 0 = Disables the TMR0 interrupt
;bit 4 INTE: RB0/INT External Interrupt Enable bit
; 1 = Enables the RB0/INT external interrupt
; 0 = Disables the RB0/INT external interrupt
;bit 3 RBIE: RB Port Change Interrupt Enable bit
; 1 = Enables the RB port change interrupt
; 0 = Disables the RB port change interrupt
;bit 2 T0IF: TMR0 Overflow Interrupt Flag bit
; 1 = TMR0 register has overflowed (must be cleared in software)
; 0 = TMR0 register did not overflow
;bit 1 INTF: RB0/INT External Interrupt Flag bit
; 1 = The RB0/INT external interrupt occurred (must be cleared in software)
; 0 = The RB0/INT external interrupt did not occur
;bit 0 RBIF: RB Port Change Interrupt Flag bit
; 1 = When at least one of the RB<7:4> pins changes state
; 0 = None of the RB<7:4> pins have changed state

;-------






;==========================================================
;MAIN Loop
START
	call	TIMER_LOOP_ROUTINE; 80 Clocks (Typical) OR 96 Clocks upon last loop (Including Call)
;	call	ZERO_CROSSING_DELAY_ROUTINE; 36 Clocks (Including Call,)  80 + 36 = 116 Clocks Total
	call	UART_ROUTINE; Routine for RS-232,	 82 Clocks (Including Call)

	;call	DIAGNOSTIC_ROUTINE ;Manual Increment of Brightness

	goto	START;				+ 2 clocks (=164)
;***************************************************************
;***************************************************************




;==========================================================
TIMER_LOOP_ROUTINE

	movf	TIMER_LOOP_COUNTDOWN,0; Moves TIMER_LOOP_COUNTDOWN to W								+ 1 clock (=1)	
	xorlw	b'00000000' ; XOR byte and w, w will be zero if TIMER_LOOP_COUNTDOWN is 0x00		+ 1 clock (=2)
	btfss	STATUS, Z ; Skip if zero flag is set, AKA execute next line if Routine should be used	+ 1 clock, if executing next line (=3)
	goto	CHANNEL_0_TRIGGER;																	+ 2 clock (=5)

	return ;else Return

;--- 5 Clocks Total


;CHANNEL_0 -------------------------------------
CHANNEL_0_TRIGGER; ------------------*** 8 Clocks  ***------------------------------
	btfsc	CHANNEL_TRIGGERS,0; If BIT is SET, skip to next channel, else proceed  + 1 Clock if Channel has been triggered (=1), + 2 if not (=2)
	goto	CHANNEL_0_DELAY; + 2 Clocks =  3 Clocks

	incfsz	CHANNEL_0_WORK,1; Adds 1 to CHANNEL_0_WORK, if register overflows to Zero, skip next line, and Turn channel on + 2 clocks if Channel should be turned on, (=4) else 1 clock (=3)
	goto	CHANNEL_0_TURN_OFF; will go to turn channel off if register was not 0xFF before overflow + 2 clocks (=5)

CHANNEL_0_TURN_ON
	bsf		PORTA,0; Turn On Channel 0 Output pin + 1 clock (=5)
	bsf		CHANNEL_TRIGGERS,0; Notifies that Channel 0 Has been activated this loop, check no further + 1 clock (=6)
	goto	CHANNEL_1_TRIGGER; Proceed to check other channels..   + 2 clock (=8)

CHANNEL_0_TURN_OFF
	bcf		PORTA,0; Turn Off Channel 0 Output pin (=6)
	goto	CHANNEL_1_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)

CHANNEL_0_DELAY
	nop		;														+ 1 clock (=4)
	nop		;														+ 1 clock (=5)
	nop		;														+ 1 clock (=6)
	goto	CHANNEL_1_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)


;CHANNEL_1 -------------------------------------
CHANNEL_1_TRIGGER; ------------------*** 8 Clocks  ***------------------------------
	btfsc	CHANNEL_TRIGGERS,1; If BIT is SET, skip to next channel, else proceed  + 1 Clock if Channel has been triggered (=1), + 2 if not (=2)
	goto	CHANNEL_1_DELAY; + 2 Clocks =  3 Clocks

	incfsz	CHANNEL_1_WORK,1; Adds 1 to CHANNEL_1_WORK, if register overflows to Zero, skip next line, and Turn channel on + 2 clocks if Channel should be turned on, (=4) else 1 clock (=3)
	goto	CHANNEL_1_TURN_OFF; will go to turn channel off if register was not 0xFF before overflow + 2 clocks (=5)

CHANNEL_1_TURN_ON
	bsf		PORTA,1; Turn On Channel 1 Output pin + 1 clock (=5)
	bsf		CHANNEL_TRIGGERS,1; Notifies that Channel 1 Has been activated this loop, check no further + 1 clock (=6)
	goto	CHANNEL_2_TRIGGER; Proceed to check other channels..   + 2 clock (=8)

CHANNEL_1_TURN_OFF
	bcf		PORTA,1; Turn Off Channel 1 Output pin (=6)
	goto	CHANNEL_2_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)

CHANNEL_1_DELAY
	nop		;														+ 1 clock (=4)
	nop		;														+ 1 clock (=5)
	nop		;														+ 1 clock (=6)
	goto	CHANNEL_2_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)


;CHANNEL_2 -------------------------------------
CHANNEL_2_TRIGGER; ------------------*** 8 Clocks  ***------------------------------
	btfsc	CHANNEL_TRIGGERS,2; If BIT is SET, skip to next channel, else proceed  + 1 Clock if Channel has been triggered (=1), + 2 if not (=2)
	goto	CHANNEL_2_DELAY; + 2 Clocks =  3 Clocks

	incfsz	CHANNEL_2_WORK,1; Adds 1 to CHANNEL_2_WORK, if register overflows to Zero, skip next line, and Turn channel on + 2 clocks if Channel should be turned on, (=4) else 1 clock (=3)
	goto	CHANNEL_2_TURN_OFF; will go to turn channel off if register was not 0xFF before overflow + 2 clocks (=5)

CHANNEL_2_TURN_ON
	bsf		PORTA,2; Turn On Channel 2 Output pin + 1 clock (=5)
	bsf		CHANNEL_TRIGGERS,2; Notifies that Channel 2 Has been activated this loop, check no further + 1 clock (=6)
	goto	CHANNEL_3_TRIGGER; Proceed to check other channels..   + 2 clock (=8)

CHANNEL_2_TURN_OFF
	bcf		PORTA,2; Turn Off Channel 2 Output pin (=6)
	goto	CHANNEL_3_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)

CHANNEL_2_DELAY
	nop		;														+ 1 clock (=4)
	nop		;														+ 1 clock (=5)
	nop		;														+ 1 clock (=6)
	goto	CHANNEL_3_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)


;CHANNEL_3 -------------------------------------
CHANNEL_3_TRIGGER; ------------------*** 8 Clocks  ***------------------------------
	btfsc	CHANNEL_TRIGGERS,3; If BIT is SET, skip to next channel, else proceed  + 1 Clock if Channel has been triggered (=1), + 2 if not (=2)
	goto	CHANNEL_3_DELAY; + 2 Clocks =  3 Clocks

	incfsz	CHANNEL_3_WORK,1; Adds 1 to CHANNEL_3_WORK, if register overflows to Zero, skip next line, and Turn channel on + 2 clocks if Channel should be turned on, (=4) else 1 clock (=3)
	goto	CHANNEL_3_TURN_OFF; will go to turn channel off if register was not 0xFF before overflow + 2 clocks (=5)

CHANNEL_3_TURN_ON
	bsf		PORTB,3; Turn On Channel 3 Output pin + 1 clock (=5)
	bsf		CHANNEL_TRIGGERS,3; Notifies that Channel 3 Has been activated this loop, check no further + 1 clock (=6)
	goto	CHANNEL_4_TRIGGER; Proceed to check other channels..   + 2 clock (=8)

CHANNEL_3_TURN_OFF
	bcf		PORTB,3; Turn Off Channel 3 Output pin (=6)
	goto	CHANNEL_4_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)

CHANNEL_3_DELAY
	nop		;														+ 1 clock (=4)
	nop		;														+ 1 clock (=5)
	nop		;														+ 1 clock (=6)
	goto	CHANNEL_4_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)


;CHANNEL_4 -------------------------------------
CHANNEL_4_TRIGGER; ------------------*** 8 Clocks  ***------------------------------
	btfsc	CHANNEL_TRIGGERS,4; If BIT is SET, skip to next channel, else proceed  + 1 Clock if Channel has been triggered (=1), + 2 if not (=2)
	goto	CHANNEL_4_DELAY; + 2 Clocks =  3 Clocks

	incfsz	CHANNEL_4_WORK,1; Adds 1 to CHANNEL_4_WORK, if register overflows to Zero, skip next line, and Turn channel on + 2 clocks if Channel should be turned on, (=4) else 1 clock (=3)
	goto	CHANNEL_4_TURN_OFF; will go to turn channel off if register was not 0xFF before overflow + 2 clocks (=5)

CHANNEL_4_TURN_ON
	bsf		PORTB,4; Turn On Channel 4 Output pin + 1 clock (=5)
	bsf		CHANNEL_TRIGGERS,4; Notifies that Channel 4 Has been activated this loop, check no further + 1 clock (=6)
	goto	CHANNEL_5_TRIGGER; Proceed to check other channels..   + 2 clock (=8)

CHANNEL_4_TURN_OFF
	bcf		PORTB,4; Turn Off Channel 4 Output pin (=6)
	goto	CHANNEL_5_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)

CHANNEL_4_DELAY
	nop		;														+ 1 clock (=4)
	nop		;														+ 1 clock (=5)
	nop		;														+ 1 clock (=6)
	goto	CHANNEL_5_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)


;CHANNEL_5 -------------------------------------
CHANNEL_5_TRIGGER; ------------------*** 8 Clocks  ***------------------------------
	btfsc	CHANNEL_TRIGGERS,5; If BIT is SET, skip to next channel, else proceed  + 1 Clock if Channel has been triggered (=1), + 2 if not (=2)
	goto	CHANNEL_5_DELAY; + 2 Clocks =  3 Clocks

	incfsz	CHANNEL_5_WORK,1; Adds 1 to CHANNEL_5_WORK, if register overflows to Zero, skip next line, and Turn channel on + 2 clocks if Channel should be turned on, (=4) else 1 clock (=3)
	goto	CHANNEL_5_TURN_OFF; will go to turn channel off if register was not 0xFF before overflow + 2 clocks (=5)

CHANNEL_5_TURN_ON
	bsf		PORTB,5; Turn On Channel 5 Output pin + 1 clock (=5)
	bsf		CHANNEL_TRIGGERS,5; Notifies that Channel 5 Has been activated this loop, check no further + 1 clock (=6)
	goto	CHANNEL_6_TRIGGER; Proceed to check other channels..   + 2 clock (=8)

CHANNEL_5_TURN_OFF
	bcf		PORTB,5; Turn Off Channel 5 Output pin (=6)
	goto	CHANNEL_6_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)

CHANNEL_5_DELAY
	nop		;														+ 1 clock (=4)
	nop		;														+ 1 clock (=5)
	nop		;														+ 1 clock (=6)
	goto	CHANNEL_6_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)


;CHANNEL_6 -------------------------------------
CHANNEL_6_TRIGGER; ------------------*** 8 Clocks  ***------------------------------
	btfsc	CHANNEL_TRIGGERS,6; If BIT is SET, skip to next channel, else proceed  + 1 Clock if Channel has been triggered (=1), + 2 if not (=2)
	goto	CHANNEL_6_DELAY; + 2 Clocks =  3 Clocks

	incfsz	CHANNEL_6_WORK,1; Adds 1 to CHANNEL_6_WORK, if register overflows to Zero, skip next line, and Turn channel on + 2 clocks if Channel should be turned on, (=4) else 1 clock (=3)
	goto	CHANNEL_6_TURN_OFF; will go to turn channel off if register was not 0xFF before overflow + 2 clocks (=5)

CHANNEL_6_TURN_ON
	bsf		PORTB,6; Turn On Channel 6 Output pin + 1 clock (=5)
	bsf		CHANNEL_TRIGGERS,6; Notifies that Channel 6 Has been activated this loop, check no further + 1 clock (=6)
	goto	CHANNEL_7_TRIGGER; Proceed to check other channels..   + 2 clock (=8)

CHANNEL_6_TURN_OFF
	bcf		PORTB,6; Turn Off Channel 6 Output pin (=6)
	goto	CHANNEL_7_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)

CHANNEL_6_DELAY
	nop		;														+ 1 clock (=4)
	nop		;														+ 1 clock (=5)
	nop		;														+ 1 clock (=6)
	goto	CHANNEL_7_TRIGGER; Proceed to check other channels..	+ 2 clocks (=8)


;CHANNEL_7 -------------------------------------
CHANNEL_7_TRIGGER; ------------------*** 8 Clocks  ***------------------------------
	btfsc	CHANNEL_TRIGGERS,7; If BIT is SET, skip to next channel, else proceed  + 1 Clock if Channel has been triggered (=1), + 2 if not (=2)
	goto	CHANNEL_7_DELAY; + 2 Clocks =  3 Clocks

	incfsz	CHANNEL_7_WORK,1; Adds 1 to CHANNEL_7_WORK, if register overflows to Zero, skip next line, and Turn channel on + 2 clocks if Channel should be turned on, (=4) else 1 clock (=3)
	goto	CHANNEL_7_TURN_OFF; will go to turn channel off if register was not 0xFF before overflow + 2 clocks (=5)

CHANNEL_7_TURN_ON
	bsf		PORTB,7; Turn On Channel 7 Output pin + 1 clock (=5)
	bsf		CHANNEL_TRIGGERS,7; Notifies that Channel 7 Has been activated this loop, check no further + 1 clock (=6)
	goto	WRAP_UP_TIMER; Proceed to Finish Loop..					+ 2 clock (=8)

CHANNEL_7_TURN_OFF
	bcf		PORTB,7; Turn Off Channel 7 Output pin (=6)
	goto	WRAP_UP_TIMER; Proceed to Finish Loop..					+ 2 clocks (=8)

CHANNEL_7_DELAY
	nop		;														+ 1 clock (=4)
	nop		;														+ 1 clock (=5)
	nop		;														+ 1 clock (=6)
	goto	WRAP_UP_TIMER; Proceed to Finish Loop..					+ 2 clocks (=8)

;--- 5 + (8 * 8) = 69 Clocks Total


FINISH_TIMER_LOOP

WRAP_UP_TIMER; ------------------*** 25 Clocks Wrapping up, OR 9 Clocks Continuing ***------------------------------
	movf	TIMER_LOOP_COUNTDOWN,0; Moves TIMER_LOOP_COUNTDOWN to W				+ 1 clock (=1) 
	xorlw	b'00000001' ; XOR byte and w, w will be zero if TIMER_LOOP_COUNTDOWN is 0x01	+ 1 clock (=2)
	btfss	STATUS, Z ; Skip if zero flag is set, AKA execute next line if Timer should stop	+ 2 clocks IF TIMER WILL END (=4) + 1 clock IF TIMER WILL NOT (=3)
	goto	CONTINUE_TIMER;					+ 2 clock (=5)


	; + 16 Clocks -------------
	movf	CHANNEL_0_RECEIVE,0; Moves Nibbles, moves RECEIVED CHANNEL to W
	movwf	CHANNEL_0_WORK; Moves RECEIVED CHANNEL to Temporay Work Register. Register will be incremented to overflow

	movf	CHANNEL_1_RECEIVE,0; Moves Nibbles, moves RECEIVED CHANNEL to W
	movwf	CHANNEL_1_WORK; Moves RECEIVED CHANNEL to Temporay Work Register. Register will be incremented to overflow

	movf	CHANNEL_2_RECEIVE,0; Moves Nibbles, moves RECEIVED CHANNEL to W
	movwf	CHANNEL_2_WORK; Moves RECEIVED CHANNEL to Temporay Work Register. Register will be incremented to overflow

	movf	CHANNEL_3_RECEIVE,0; Moves Nibbles, moves RECEIVED CHANNEL to W
	movwf	CHANNEL_3_WORK; Moves RECEIVED CHANNEL to Temporay Work Register. Register will be incremented to overflow

	movf	CHANNEL_4_RECEIVE,0; Moves Nibbles, moves RECEIVED CHANNEL to W
	movwf	CHANNEL_4_WORK; Moves RECEIVED CHANNEL to Temporay Work Register. Register will be incremented to overflow

	movf	CHANNEL_5_RECEIVE,0; Moves Nibbles, moves RECEIVED CHANNEL to W
	movwf	CHANNEL_5_WORK; Moves RECEIVED CHANNEL to Temporay Work Register. Register will be incremented to overflow

	movf	CHANNEL_6_RECEIVE,0; Moves Nibbles, moves RECEIVED CHANNEL to W
	movwf	CHANNEL_6_WORK; Moves RECEIVED CHANNEL to Temporay Work Register. Register will be incremented to overflow

	movf	CHANNEL_7_RECEIVE,0; Moves Nibbles, moves RECEIVED CHANNEL to W
	movwf	CHANNEL_7_WORK; Moves RECEIVED CHANNEL to Temporay Work Register. Register will be incremented to overflow
	; -------------------(=21)

	
	clrf	TIMER_LOOP_COUNTDOWN;		+ 1 clock (=22) 
	clrf	CHANNEL_TRIGGERS;			+ 1 clock (=23)

	return;								+ 2 clocks (=25)
;--- 69 + 25 = 94 Clocks Total when ending


CONTINUE_TIMER
	;Set Timer 1 here...

	movlw	b'00000001';				+ 1 clock (=6)
	subwf	TIMER_LOOP_COUNTDOWN,1; Subtracts 1 from TIMER_LOOP_COUNTDOWN	+ 1 clock (=7)


	return;								+  2 clocks (=9)

;--- 69 + 9 = 78 Clocks Total when continuing






;==========================================================
UART_ROUTINE; ------------------*** 80 Packets in entire routine  ***------------------------------

CHECK_BYTE
	btfsc	BYTE_RECEIVED_FLAG,0 ;continues if byte has come in	+ 1 clock (=1), if byte has NOT, 	+ 2 clock (=2)
	goto	INCOMING_BYTE_RECEIVED;								+ 2 clocks (=3)

;31 clocks for Receieve interrupt filler
	call	Delay_TenClocks_20MHz;								+ 10 clocks (=12)
	call	Delay_TenClocks_20MHz;								+ 10 clocks (=22)
	call	Delay_FourClocks_20MHz;								+  4 clocks (=26)
	call	Delay_FourClocks_20MHz;								+  4 clocks (=30)
	nop;														+  1 clock  (=31)

;49 clocks that would have been used by routine (=80)
	call	Delay_TenClocks_20MHz;								+ 10 clocks (=41)
	call	Delay_TenClocks_20MHz;								+ 10 clocks (=51)
	call	Delay_TenClocks_20MHz;								+ 10 clocks (=61)
	call	Delay_TenClocks_20MHz;								+ 10 clocks (=71)
	call	Delay_FourClocks_20MHz;								+  4 clocks (=75)
	nop;														+ 1 clocks  (=76)	
	nop;														+ 1 clocks  (=78)

	return;														+ 4 clocks  (=80)


INCOMING_BYTE_RECEIVED

;If byte came in, clear flag
	bcf		BYTE_RECEIVED_FLAG,0;								+ 1 clocks (=4)


; Test UART with single byte
;	call	UART_BYTE_TEST
;	goto	CHECK_BYTE
; ------------------------------------------

	movf	BYTE_COUNT,0; Moves BYTE_COUNT to W					+ 1 clock (=5)
	xorlw	b'00001011' ; XOR byte and w, w will be zero if BYTE_COUNT is d'11', time to compare checksum		+ 1 clock (=6)
	btfsc	STATUS, Z ; Skip if zero flag is NOT set, AKA execute next line to compare checksum					+ 2 clocks if byte is not checksum (=8),	+ 1 clock if byte IS checksum (=7)
	goto	CHECKSUM_CHECK;										+ 2 clocks (=9)


	movf	BYTE_BUFFER,0; Moves BYTE_BUFFER to W	+ 1 clock (=9)
	xorlw	b'00000001' ; XOR byte and w, w will be zero if BYTE_BUFFER is 0x01, HENCE START BYTE!!!!	+ 1 clock (=10)
	btfss	STATUS, Z ; Skip if zero flag is NOT set, AKA execute next line if byte is NOT recognised as a start byte	+ 1 clock if not start byte (=11),	+ 2 clock if IT IS start byte (=12)
	goto	PROCESS_PACKET;										+ 2 clocks (=13)

	movlw	b'00000001';										+ 1 clocks (=13)
	movwf	BYTE_COUNT;makes BYTE_COUNT 1						+ 1 clocks (=14)
	clrf	BYTE_TRIGGERS;										+ 1 clocks (=15)
	clrf	BYTE_TRIGGERS_2;									+ 1 clocks (=16)

; offsetting for time that would have been used

	call	Delay_TenClocks_20MHz;								+ 10 clocks (=26)
	call	Delay_TenClocks_20MHz;								+ 10 clocks (=36)
	call	Delay_TenClocks_20MHz;								+ 10 clocks (=46)
	nop;														+ 1 clocks  (=47)	

	return; starts over 										+ 2 clocks  (=49) 



;---------------------------------------------------
PROCESS_PACKET

;	movlw	0xFF
;	movwf	CHANNEL_7_RECEIVE

	movf	BYTE_COUNT,0; Moves BYTE_COUNT to W					+ 1 clock (=10)
	xorlw	b'00000000' ; XOR byte and w, w will be zero if BYTE_COUNT is 0x00, HENCE NO START BYTE PRIOR!!!!		+ 1 clock (=11)
	btfss	STATUS, Z ; Skip if zero flag is NOT set, AKA execute next line if there IS a start byte				+ 1 clock if packet should be processed (=12),	+ 2 clocks if packet should be processed (=13)
	goto	PROCESS_PACKET_CONTINUE;							+ 2 clocks (=14)

	clrf	BYTE_TRIGGERS;										+ 1 clocks (=14)
	clrf	BYTE_TRIGGERS_2;									+ 1 clocks (=15)

; Offsetting for time that would have been taken by PROCESS_PACKET_CONTINUE
	call	Delay_TenClocks_20MHz;								+ 10 clocks (=25)
	call	Delay_TenClocks_20MHz;								+ 10 clocks (=35)
	call	Delay_TenClocks_20MHz;								+ 10 clocks (=45)
	nop;														+ 1 clocks  (=46)	
	nop;														+ 1 clocks  (=47)	

	return; else keep looking for a start byte, and exit routine	+ 2 clocks  (=49)





; 14 Packets + 35 Packets (=49)
PROCESS_PACKET_CONTINUE; ------------------*** 35 Clocks in PROCESS_PACKET_CONTINUE  ***------------------------------
RECEIVE_CHANNEL_0
	btfsc	BYTE_TRIGGERS,0; If BIT is SET, skip to apply next byte, else proceed to buffer byte 	+ 1 clock IF BYTE 0 has been triggered (=1),	+ 2 clocks IF BYTE 8 has NOT been triggered (=2)
	goto	RECEIVE_CHANNEL_1; 								+ 2 clocks IF BYTE 0 has been triggered (=3)

	movf	BYTE_BUFFER,0; Moves Buffered byte to W							+ 1 clock (=3)
	movwf	CHANNEL_0_BUFFER; Moves buffered byte to assosiated register	+ 1 clock (=4)
	movwf	BYTE_CHECKSUM;Sets up Initial BYTE_CHECKSUM						+ 1 clock (=5)

	bsf		BYTE_TRIGGERS,0; Notify that this channel's byte has been received			+ 1 clock (=6)
	call	Delay_TenClocks_20MHz;											+ 10 clocks (=16)
	call	Delay_TenClocks_20MHz;											+ 10 clocks (=26)
	call	Delay_FourClocks_20MHz;											+  4 clocks (=30)

	goto	WRAP_UP_RECEIVE;								+ 2 clocks (=32)


RECEIVE_CHANNEL_1
	btfsc	BYTE_TRIGGERS,1; If BIT is SET, skip to apply next byte, else proceed to buffer byte 	+ 1 clock IF BYTE 1 has been triggered (=4),	+ 2 clocks IF BYTE 8 has NOT been triggered (=5)
	goto	RECEIVE_CHANNEL_2; 								+ 2 clocks IF BYTE 1 has been triggered (=6)

	movf	BYTE_BUFFER,0; Moves Buffered byte to W							+ 1 clock (=6)
	movwf	CHANNEL_1_BUFFER; Moves buffered byte to assosiated register	+ 1 clock (=7)
	xorwf	BYTE_CHECKSUM,1;Xor byte with BYTE_CHECKSUM						+ 1 clock (=8)

	bsf		BYTE_TRIGGERS,1; Notify that this channel's byte has been received			+ 1 clock (=9)
	call	Delay_TenClocks_20MHz;											+ 10 clocks (=19)
	call	Delay_TenClocks_20MHz;											+ 10 clocks (=29)
	nop		;																+  1 clock  (=30)

	goto	WRAP_UP_RECEIVE;								+ 2 clocks (=32)

RECEIVE_CHANNEL_2
	btfsc	BYTE_TRIGGERS,2; If BIT is SET, skip to apply next byte, else proceed to buffer byte 	+ 1 clock IF BYTE 2 has been triggered (=7),	+ 2 clocks IF BYTE 8 has NOT been triggered (=8)
	goto	RECEIVE_CHANNEL_3; 								+ 2 clocks IF BYTE 2 has been triggered (=9)

	movf	BYTE_BUFFER,0; Moves Buffered byte to W							+ 1 clock (=9)
	movwf	CHANNEL_2_BUFFER; Moves buffered byte to assosiated register	+ 1 clock (=10)
	xorwf	BYTE_CHECKSUM,1;Xor byte with BYTE_CHECKSUM						+ 1 clock (=11)

	bsf		BYTE_TRIGGERS,2; Notify that this channel's byte has been received			+ 1 clock (=12)
	call	Delay_TenClocks_20MHz;											+ 10 clocks (=22)
	call	Delay_FourClocks_20MHz;											+  4 clocks (=26)
	call	Delay_FourClocks_20MHz;											+  4 clocks (=30)

	goto	WRAP_UP_RECEIVE;								+ 2 clocks (=32)

RECEIVE_CHANNEL_3
	btfsc	BYTE_TRIGGERS,3; If BIT is SET, skip to apply next byte, else proceed to buffer byte 	+ 1 clock IF BYTE 3 has been triggered (=10),	+ 2 clocks IF BYTE 8 has NOT been triggered (=11)
	goto	RECEIVE_CHANNEL_4; 								+ 2 clocks IF BYTE 3 has been triggered (=12)

	movf	BYTE_BUFFER,0; Moves Buffered byte to W							+ 1 clock (=12)
	movwf	CHANNEL_3_BUFFER; Moves buffered byte to assosiated register	+ 1 clock (=13)
	xorwf	BYTE_CHECKSUM,1;Xor byte with BYTE_CHECKSUM						+ 1 clock (=14)


	bsf		BYTE_TRIGGERS,3; Notify that this channel's byte has been received			+ 1 clock (=15)
	call	Delay_TenClocks_20MHz;											+ 10 clocks (=25)
	call	Delay_FourClocks_20MHz;											+  4 clocks (=29)
	nop		;																+  1 clock (=30)

	goto	WRAP_UP_RECEIVE;								+ 2 clocks (=32)

RECEIVE_CHANNEL_4
	btfsc	BYTE_TRIGGERS,4; If BIT is SET, skip to apply next byte, else proceed to buffer byte 	+ 1 clock IF BYTE 4 has been triggered (=13),	+ 2 clocks IF BYTE 8 has NOT been triggered (=14)
	goto	RECEIVE_CHANNEL_5; 								+ 2 clocks IF BYTE 4 has been triggered (=15)

	movf	BYTE_BUFFER,0; Moves Buffered byte to W							+ 1 clock (=15)
	movwf	CHANNEL_4_BUFFER; Moves buffered byte to assosiated register	+ 1 clock (=16)
	xorwf	BYTE_CHECKSUM,1;Xor byte with BYTE_CHECKSUM						+ 1 clock (=17)

	bsf		BYTE_TRIGGERS,4; Notify that this channel's byte has been received			+ 1 clock (=18)
	call	Delay_TenClocks_20MHz;											+ 10 clocks (=28)
	nop		;																+ 1 clock (=29)
	nop		;																+ 1 clock (=30)

	goto	WRAP_UP_RECEIVE;								+ 2 clocks (=32)

RECEIVE_CHANNEL_5
	btfsc	BYTE_TRIGGERS,5; If BIT is SET, skip to apply next byte, else proceed to buffer byte 	+ 1 clock IF BYTE 1 has been triggered (=16),	+ 2 clocks IF BYTE 8 has NOT been triggered (=17)
	goto	RECEIVE_CHANNEL_6; 								+ 2 clocks IF BYTE 5 has been triggered (=18)

	movf	BYTE_BUFFER,0; Moves Buffered byte to W							+ 1 clock (=18)
	movwf	CHANNEL_5_BUFFER; Moves buffered byte to assosiated register	+ 1 clock (=29)
	xorwf	BYTE_CHECKSUM,1;Xor byte with BYTE_CHECKSUM						+ 1 clock (=20)

	bsf		BYTE_TRIGGERS,5; Notify that this channel's byte has been received			+ 1 clock (=21)
	call	Delay_FourClocks_20MHz;											+ 4 clocks (=25)
	call	Delay_FourClocks_20MHz;											+ 4 clocks (=29)
	nop		;																+ 1 clock  (=30)

	goto	WRAP_UP_RECEIVE;								+ 2 clocks (=32)

RECEIVE_CHANNEL_6
	btfsc	BYTE_TRIGGERS,6; If BIT is SET, skip to apply next byte, else proceed to buffer byte 	+ 1 clock IF BYTE 6 has been triggered (=19),	+ 2 clocks IF BYTE 8 has NOT been triggered (=20)
	goto	RECEIVE_CHANNEL_7; 								+ 2 clocks IF BYTE 6 has been triggered (=21)

	movf	BYTE_BUFFER,0; Moves Buffered byte to W							+ 1 clock (=21)
	movwf	CHANNEL_6_BUFFER; Moves buffered byte to assosiated register	+ 1 clock (=22)
	xorwf	BYTE_CHECKSUM,1;Xor byte with BYTE_CHECKSUM						+ 1 clock (=23)

	bsf		BYTE_TRIGGERS,6; Notify that this channel's byte has been received			+ 1 clock (=24)
	call	Delay_FourClocks_20MHz;											+ 4 clocks (=28)
	nop		;																+ 1 clock (=29)
	nop		;																+ 1 clock (=30)

	goto	WRAP_UP_RECEIVE;								+ 2 clocks (=32)

RECEIVE_CHANNEL_7
	btfsc	BYTE_TRIGGERS,7; If BIT is SET, skip to apply next byte, else proceed to buffer byte 	+ 1 clock IF BYTE 7 has been triggered (=22),	+ 2 clocks IF BYTE 8 has NOT been triggered (=23)
	goto	RECEIVE_CHANNEL_8; 								+ 2 clocks IF BYTE 7 has been triggered (=24)

	movf	BYTE_BUFFER,0; Moves Buffered byte to W							+ 1 clock (=24)
	movwf	CHANNEL_7_BUFFER; Moves buffered byte to assosiated register	+ 1 clock (=25)
	xorwf	BYTE_CHECKSUM,1;Xor byte with BYTE_CHECKSUM						+ 1 clock (=26)

	bsf		BYTE_TRIGGERS,7; Notify that this channel's byte has been received			+ 1 clock (=27)
	nop		;																+ 1 clock (=28)
	nop		;																+ 1 clock (=29)
	nop		;																+ 1 clock (=30)

	goto	WRAP_UP_RECEIVE;												+ 2 clocks (=32)

RECEIVE_CHANNEL_8
	btfsc	BYTE_TRIGGERS_2,0; If BIT is SET, skip to apply next byte, else proceed to buffer byte 	+ 1 clock IF BYTE 8 has been triggered (=25),	+ 2 clocks IF BYTE 8 has NOT been triggered (=26) 
	goto	RECEIVE_CHANNEL_9; 								+ 2 clocks IF BYTE 8 has been triggered (=27)

	movf	BYTE_BUFFER,0; Moves Buffered byte to W,						+ 1 clock (=27) 
	xorwf	BYTE_CHECKSUM,1;Xor byte with BYTE_CHECKSUM,					+ 1 clock (=28) 

	bsf		BYTE_TRIGGERS_2,0; Notify that this channel's byte has been received,		+ 1 clock (=29) 
	nop		;																+ 1 clock (=30) 
	goto	WRAP_UP_RECEIVE;												+ 2 clocks (=32) 


RECEIVE_CHANNEL_9
	btfsc	BYTE_TRIGGERS_2,1; If BIT is SET, skip to apply next byte, else proceed to buffer byte 	+ 1 clock IF BYTE 1 has been triggered (=28),	+ 2 clocks IF BYTE 8 has NOT been triggered (=29)
	goto	WRAP_UP_DELAY; 								+ 2 clocks IF BYTE 9 has been triggered (=30)

	movf	BYTE_BUFFER,0; Moves Buffered byte to W							+ 1 clock (=30)
	xorwf	BYTE_CHECKSUM,1;Xor byte with BYTE_CHECKSUM						+ 1 clock (=31)

	bsf		BYTE_TRIGGERS_2,1; Notify that this channel's byte has been received		+ 1 clock (=32)


WRAP_UP_RECEIVE
	incf	BYTE_COUNT,1;Increment BYTE_COUNT								+ 1 clock (=33)
	return;																	+ 2 clock (=35)


WRAP_UP_DELAY; Delays execution to make 35 clocks
	goto	WRAP_UP_RECEIVE; 												+ 2 clocks(=32)




CHECKSUM_CHECK;  ---------------------------- ('28 CLOCKS TOTAL in CHECKSUM_CHECK + PACKET_OK' + OFFSET DELAY =49 ) -------------------------------------

;	goto	PACKET_OK; Skip Checksum check

; Offset delay
; 9 Packets are used to get here + 28 clocks TOTAL if not for following delay (=37), need to account for 49 packets as would have been used in PROCESS_PACKET
	call	Delay_TenClocks_20MHz;											+ 10 clocks (=47)
	nop		;																+ 1 clock   (=48)
	nop		;																+ 1 clock   (=49)


	movf	BYTE_BUFFER,0; Moves BYTE_BUFFER to W			+ 1 clock (=1)
	xorwf	BYTE_CHECKSUM,0 ; XOR BYTE_BUFFER and BYTE_CHECKSUM, w will be zero if packet's checksum is OK		+ 1 clock (=2)
	btfsc	STATUS, Z ; Skip if packet's checksum is not right, AKA execute next line if packet is OK			+ 1 clock if Packet OK (=3), + 2 clock if packet fails (=4)
	goto	PACKET_OK;										+ 2 clocks (=5)

	clrf	BYTE_CHECKSUM;									+ 1 clocks (=5)
	clrf	BYTE_BUFFER;									+ 1 clocks (=6)
	clrf	BYTE_TRIGGERS;									+ 1 clocks (=7)
	clrf	BYTE_TRIGGERS_2;								+ 1 clocks (=8)
	clrf	BYTE_COUNT;										+ 1 clocks (=9)

	call	Delay_TenClocks_20MHz;							+ 10 clocks (=19)
	call	Delay_FourClocks_20MHz;							+  4 clocks (=23)
	nop;													+ 1 clocks (=24)
	nop;													+ 1 clocks (=25)
	nop;													+ 1 clocks (=26)

	return;													+ 2 clocks (=28)

PACKET_OK;  ---------------------------- (23 CLOCKS in PACKET_OK) -------------------------------------

; + 16 Clocks -------------
	movf	CHANNEL_0_BUFFER,0; moves bytes, moves BUFFERD CHANNEL to W
	movwf	CHANNEL_0_RECEIVE; Moves BUFFERD CHANNEL to Temporay Work Register.

	movf	CHANNEL_1_BUFFER,0; moves bytes, moves BUFFERD CHANNEL to W
	movwf	CHANNEL_1_RECEIVE; Moves BUFFERD CHANNEL to Temporay Work Register.

	movf	CHANNEL_2_BUFFER,0; moves bytes, moves BUFFERD CHANNEL to W
	movwf	CHANNEL_2_RECEIVE; Moves BUFFERD CHANNEL to Temporay Work Register.

	movf	CHANNEL_3_BUFFER,0; moves bytes, moves BUFFERD CHANNEL to W
	movwf	CHANNEL_3_RECEIVE; Moves BUFFERD CHANNEL to Temporay Work Register.

	movf	CHANNEL_4_BUFFER,0; moves bytes, moves BUFFERD CHANNEL to W
	movwf	CHANNEL_4_RECEIVE; Moves BUFFERD CHANNEL to Temporay Work Register.

	movf	CHANNEL_5_BUFFER,0; moves bytes, moves BUFFERD CHANNEL to W
	movwf	CHANNEL_5_RECEIVE; Moves BUFFERD CHANNEL to Temporay Work Register.

	movf	CHANNEL_6_BUFFER,0; moves bytes, moves BUFFERD CHANNEL to W
	movwf	CHANNEL_6_RECEIVE; Moves BUFFERD CHANNEL to Temporay Work Register.

	movf	CHANNEL_7_BUFFER,0; moves bytes, moves BUFFERD CHANNEL to W
	movwf	CHANNEL_7_RECEIVE; Moves BUFFERD CHANNEL to Temporay Work Register.
;--------------------------
	
	clrf	BYTE_CHECKSUM
	clrf	BYTE_BUFFER
	clrf	BYTE_TRIGGERS
	clrf	BYTE_TRIGGERS_2
	clrf	BYTE_COUNT;			; + 5 Clocks  (=21)

	return						; + 2 Clocks  (=23), 5 clocks from CHECKSUM_CHECK + 23 clocks from PACKET_OK (=28)














ZERO_CROSSING_DELAY_ROUTINE;  ---------------------------- (34 CLOCKS in ZERO_CROSSING_DELAY_ROUTINE) ---------------------
;29 clocks in Zero-Crossing HARDWARE Interrupt

	btfss	INTERRUPT_OPTIONS,0;	+ 2 clocks if Hardware Interrupt had occurred (=31 With Interrupt clocks), 1 clock if not (=1)
	goto	ZERO_CROSSING_DELAY;	+ 2 clocks (=3)

	bcf		INTERRUPT_OPTIONS,0; Clear Flag indicating Hardware Interrupt	+ 1 clock (=32)

	return;							+ 2 clocks (=34)

ZERO_CROSSING_DELAY
	call	Delay_TenClocks_20MHz;	+ 10 clocks (=13)
	call	Delay_TenClocks_20MHz;	+ 10 clocks (=23)
	call	Delay_FourClocks_20MHz;	+  4 clocks (=27)
	call	Delay_FourClocks_20MHz;	+  4 clocks (=31)
	nop;							+  1 clock  (=32)

	return;							+  2 clocks (=34)
































UART_BYTE_TEST


	clrf CHANNEL_0_RECEIVE; Start with a clear Channel before applying outputs
	clrf CHANNEL_1_RECEIVE; Start with a clear Channel before applying outputs
	clrf CHANNEL_2_RECEIVE; Start with a clear Channel before applying outputs
	clrf CHANNEL_3_RECEIVE; Start with a clear Channel before applying outputs
	clrf CHANNEL_4_RECEIVE; Start with a clear Channel before applying outputs
	clrf CHANNEL_5_RECEIVE; Start with a clear Channel before applying outputs
	clrf CHANNEL_6_RECEIVE; Start with a clear Channel before applying outputs
	clrf CHANNEL_7_RECEIVE; Start with a clear Channel before applying outputs


	movlw	0xFF; Move full brightness byte into W Register



	btfsc	BYTE_BUFFER,0 ; If bit 0 of BYTE_BUFFER is set
	movwf	CHANNEL_0_RECEIVE; Set Channel_4 to Full Brightness

	btfsc	BYTE_BUFFER,1 ; If bit 1 of BYTE_BUFFER is set
	movwf	CHANNEL_1_RECEIVE; Set Channel_5 to Full Brightness 

	btfsc	BYTE_BUFFER,2 ; If bit 2 of BYTE_BUFFER is set
	movwf	CHANNEL_2_RECEIVE; Set Channel_6 to Full Brightness 

	btfsc	BYTE_BUFFER,3 ; If bit 3 of BYTE_BUFFER is set
	movwf	CHANNEL_3_RECEIVE; Set Channel_7 to Full Brightness


	btfsc	BYTE_BUFFER,4 ; If bit 0 of BYTE_BUFFER is set
	movwf	CHANNEL_4_RECEIVE; Set Channel_4 to Full Brightness

	btfsc	BYTE_BUFFER,5 ; If bit 0 of BYTE_BUFFER is set
	movwf	CHANNEL_5_RECEIVE; Set Channel_5 to Full Brightness 

	btfsc	BYTE_BUFFER,6 ; If bit 0 of BYTE_BUFFER is set
	movwf	CHANNEL_6_RECEIVE; Set Channel_6 to Full Brightness 

	btfsc	BYTE_BUFFER,7 ; If bit 0 of BYTE_BUFFER is set
	movwf	CHANNEL_7_RECEIVE; Set Channel_7 to Full Brightness

	return


















;==========================================================
DIAGNOSTIC_ROUTINE
	btfsc	DELAY_SELECTOR,0; If DELAY_SELECTOR bit 0 is set, change brightness FAST, ELSE, SLOW
	goto	FAST_CHANGE; Will Execute if bit 0 is SET

	goto	SLOW_CHANGE; Will Execute if bit 0 is CLEAR


FAST_CHANGE
	call	Delay_EighthSec_20MHz; Delay Code Execution for 1/8 s, then act on BINARY_COUNTER
	goto	EXECUTE_DIAGNOSTIC_CODE

SLOW_CHANGE
	call	Delay_2s_20MHz; Delay Code Execution for 5s, then act on BINARY_COUNTER
	goto	EXECUTE_DIAGNOSTIC_CODE


EXECUTE_DIAGNOSTIC_CODE
	clrf CHANNEL_4_RECEIVE; Start with a clear Channel before applying outputs
	clrf CHANNEL_5_RECEIVE; Start with a clear Channel before applying outputs
	clrf CHANNEL_6_RECEIVE; Start with a clear Channel before applying outputs
	clrf CHANNEL_7_RECEIVE; Start with a clear Channel before applying outputs

;Set Channels 7-4 as a binary counter ---------------------------------------------------
	movlw	0xFF; Move full brightness byte into W Register

	btfsc	BINARY_COUNTER,0 ; If bit 0 of BINARY_COUNTER is set
	movwf	CHANNEL_4_RECEIVE; Set Channel_4 to Full Brightness

	btfsc	BINARY_COUNTER,1 ; If bit 0 of BINARY_COUNTER is set
	movwf	CHANNEL_5_RECEIVE; Set Channel_5 to Full Brightness 

	btfsc	BINARY_COUNTER,2 ; If bit 0 of BINARY_COUNTER is set
	movwf	CHANNEL_6_RECEIVE; Set Channel_6 to Full Brightness 

	btfsc	BINARY_COUNTER,3 ; If bit 0 of BINARY_COUNTER is set
	movwf	CHANNEL_7_RECEIVE; Set Channel_7 to Full Brightness
;----------------------------------------------------------------------------------------


;Manual Output To PORTB------------------------------------------------------------------
;	swapf	BINARY_COUNTER,0; swaps Binary Counter, and puts result into W
;	movwf	PORTB; Moves Binary Counter to PORTB
;----------------------------------------------------------------------------------------

	swapf	BINARY_COUNTER,0;swaps nibbles, moves counter to W
	movwf	CHANNEL_0_RECEIVE; Sends bye to CHANNEL_0


	btfsc	DELAY_SELECTOR,1; If DELAY_SELECTOR bit 1 is set, goto SUBTRACT_BINARY_COUNTER, ELSE, ADD_BINARY_COUNTER
	goto	SUBTRACT_BINARY_COUNTER

	goto	ADD_BINARY_COUNTER



ADD_BINARY_COUNTER
	movf	BINARY_COUNTER,0; Moves BINARY_COUNTER to W
	xorlw	b'00001111' ; XOR byte and w, w will be zero if BINARY_COUNTER is 0x0F
	btfsc	STATUS, Z ; Skip if zero flag is NOT set, AKA execute next line if BINARY_COUNTER needs to flipped
	goto	FLIP_ADD_SUBTRACT_COUNTER


	movlw	b'00000001'; moves 1 to W register
	addwf	BINARY_COUNTER,1; adds W Register to BINARY_COUNTER, to Increment
	

	goto	CHECK_DELAY_SPEED



SUBTRACT_BINARY_COUNTER
	movf	BINARY_COUNTER,0; Moves BINARY_COUNTER to W
	xorlw	b'00000000' ; XOR byte and w, w will be zero if BINARY_COUNTER is 0x00
	btfsc	STATUS, Z ; Skip if zero flag is NOT set, AKA execute next line if BINARY_COUNTER needs to flipped
	goto	FLIP_ADD_SUBTRACT_COUNTER

	movlw	b'00000001'; moves 1 to W register
	subwf	BINARY_COUNTER,1; subtracts W Register to BINARY_COUNTER, to Decrement

	goto	CHECK_DELAY_SPEED

CHECK_DELAY_SPEED
	btfsc	DELAY_SELECTOR,0; If DELAY_SELECTOR bit 0 is set, goto FAST_COUNTER, ELSE, SLOW_COUNTER
	goto	FAST_COUNTER

	goto	SLOW_COUNTER



FAST_COUNTER
	movf	DELAY_SELECTOR_COUNTER,0; Moves DELAY_SELECTOR_COUNTER to W
	xorlw	b'11111111' ; XOR byte and w, w will be zero if Above 0f
	btfsc	STATUS, Z ; Skip if zero flag is NOT set, AKA execute next line if BINARY_COUNTER needs to reset
	goto	FLIP_DELAY_TEST_SPEED


	movlw	0x01; Move 1 to W Register
	addwf	DELAY_SELECTOR_COUNTER,1;Adds the 1 to DELAY_SELECTOR_COUNTER


	goto	EXIT_TEST


SLOW_COUNTER
	movf	DELAY_SELECTOR_COUNTER,0; Moves DELAY_SELECTOR_COUNTER to W
	xorlw	b'10000000' ; XOR byte and w, w will be zero if Above 0f
	btfsc	STATUS, Z ; Skip if zero flag is NOT set, AKA execute next line if BINARY_COUNTER needs to reset
	goto	FLIP_DELAY_TEST_SPEED

	movlw	0x01; Move 1 to W Register
	addwf	DELAY_SELECTOR_COUNTER,1;Adds the 1 to DELAY_SELECTOR_COUNTER


	goto	EXIT_TEST


EXIT_TEST

	return




FLIP_DELAY_TEST_SPEED; Flips Bit to switch Delay speed, and resets counter
	clrf	DELAY_SELECTOR_COUNTER

	movlw	b'00000001'
	xorwf	DELAY_SELECTOR,1

	goto	EXIT_TEST

FLIP_ADD_SUBTRACT_COUNTER; Flips Bit to switch whether to add or subtract to counter,
	movlw	b'00000010'
	xorwf	DELAY_SELECTOR,1

	btfsc	DELAY_SELECTOR,1; If DELAY_SELECTOR bit 1 is set, subtraction is needed goto SUBTRACT_BINARY_COUNTER, ELSE, ADD_BINARY_COUNTER
	goto	SUBTRACT_BINARY_COUNTER

	goto	ADD_BINARY_COUNTER






;------------DELAY ROUTINES-------------------------------------------------------------------------------------------------------------
;#######################################################################################################################################


Delay_FourClocks_20MHz
; Delay = 4 instruction cycles
; Clock frequency = 20 MHz

; Actual delay = 8e-007 seconds = 4 cycles
; Error = 0 %

			;4 cycles (including call)
	return




Delay_TenClocks_20MHz
; Delay = 10 instruction cycles
; Clock frequency = 20 MHz

; Actual delay = 2e-006 seconds = 10 cycles
; Error = 0 %

			;6 cycles
	goto	$+1
	goto	$+1
	goto	$+1

			;4 cycles (including call)
	return







Delay_QuarterSec_20MHz
; Delay = 0.25 seconds
; Clock frequency = 20 MHz

; Actual delay = 0.25 seconds = 1250000 cycles
; Error = 0 %

			;1249995 cycles
	movlw	0x8A
	movwf	d1
	movlw	0xBA
	movwf	d2
	movlw	0x03
	movwf	d3
Delay_QuarterSec_20MHz_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	$+2
	decfsz	d3, f
	goto	Delay_QuarterSec_20MHz_0

			;1 cycle
	nop

			;4 cycles (including call)
	return




Delay_EighthSec_20MHz
; Delay = 0.125 seconds
; Clock frequency = 20 MHz

; Actual delay = 0.125 seconds = 625000 cycles
; Error = 0 %

			;624993 cycles
	movlw	0xC4
	movwf	d1
	movlw	0x5D
	movwf	d2
	movlw	0x02
	movwf	d3
Delay_EighthSec_20MHz_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	$+2
	decfsz	d3, f
	goto	Delay_EighthSec_20MHz_0

			;3 cycles
	goto	$+1
	nop

			;4 cycles (including call)
	return



Delay_1s_20MHz
; Delay = 1 seconds
; Clock frequency = 20 MHz

; Actual delay = 1 seconds = 5000000 cycles
; Error = 0 %

			;4999993 cycles
	movlw	0x2C
	movwf	d1
	movlw	0xE7
	movwf	d2
	movlw	0x0B
	movwf	d3
Delay_1s_20MHz_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	$+2
	decfsz	d3, f
	goto	Delay_1s_20MHz_0

			;3 cycles
	goto	$+1
	nop

			;4 cycles (including call)
	return







Delay_2s_20MHz
; Delay = 2 seconds
; Clock frequency = 20 MHz

; Actual delay = 2 seconds = 10000000 cycles
; Error = 0 %

			;9999995 cycles
	movlw	0x5A
	movwf	d1
	movlw	0xCD
	movwf	d2
	movlw	0x16
	movwf	d3
Delay_2s_20MHz_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	$+2
	decfsz	d3, f
	goto	Delay_2s_20MHz_0

			;1 cycle
	nop

			;4 cycles (including call)
	return



end