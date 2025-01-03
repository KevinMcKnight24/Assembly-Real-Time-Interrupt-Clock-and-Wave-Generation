;*******************************************************
;* CMPEN 472, Homework 11: Signal Wave Generation with analog input and Digital Clock Program with HCS12
;* CodeWarrior Simulator/Debug edition, not for CSM-12C128 board
;*
;* Nov, 20, 2024 Kevin McKnight
;*
;* This program is a real time interupt clock and a wave form generator using timers
;* the program is able to generate 5 unique waves, Sawtooth wave, Sawtooth wave at 100hz
;* Square wave, Square wave at 100hz, and a Triangle wave. For the wave generator there
;* is an interrupt every .125uS where a single point of the wave is generated. For each
;* wave there are 2048 points. Also added for HW11 is the ADC function which will get the 
;* analog data from an input function that is given to us and print the output like the other
;* waves that we generated in HW10
;* After that the timer is halted until the next wave is 
;* generated. The clock functions are the same as in homework 8, you are able to 
;* display minutes, seconds and hours on a segment display and can change the time
;* you can also quit out of both these modes and the program will change to a type writer
;* program that simply displays what the user enters, both interrupts are disabled in this
;* mode.
;*
;* Please note the new feature of this program:
;* TIOS, TIE, TCNTH, TSCR1, TSCR2, TFLG1, TC6H, in general timers and how to use
;* two simulationus interrupts in our program.
;* Real Time Interrupt.
;* We assumed 24MHz bus clock and 4MHz external resonator clock frequency.  
;* 
;*******************************************************
;*******************************************************

; export symbols - program starting point
            XDEF        Entry        ; export 'Entry' symbol
            ABSENTRY    Entry        ; for assembly entry point

; include derivative specific macros
PORTA       EQU         $0000
PORTB       EQU         $0001
DDRA        EQU         $0002
DDRB        EQU         $0003

SCIBDH      EQU         $00C8        ; Serial port (SCI) Baud Register H
SCIBDL      EQU         $00C9        ; Serial port (SCI) Baud Register L
SCICR2      EQU         $00CB        ; Serial port (SCI) Control Register 2
SCISR1      EQU         $00CC        ; Serial port (SCI) Status Register 1
SCIDRL      EQU         $00CF        ; Serial port (SCI) Data Register

CRGFLG      EQU         $0037        ; Clock and Reset Generator Flags
CRGINT      EQU         $0038        ; Clock and Reset Generator Interrupts
RTICTL      EQU         $003B        ; Real Time Interrupt Control

TIOS        EQU         $0040        ; Timer Input Capture (IC) or Output Compare (OC) select
TIE         EQU         $004C        ; Timer interrupt enable register
TCNTH       EQU         $0044        ; Timer free runing main counter
TSCR1       EQU         $0046        ; Timer system control 1
TSCR2       EQU         $004D        ; Timer system control 2
TFLG1       EQU         $004E        ; Timer interrupt flag 1
TC1H        EQU         $0052        ; Timer channel 2 register

ATDCTL2     EQU         $0082        ; Analog-to-Digital Converter (ADC) registers
ATDCTL3     EQU         $0083
ATDCTL4     EQU         $0084
ATDCTL5     EQU         $0085
ATDSTAT0    EQU         $0086
ATDDR0H     EQU         $0090
ATDDR0L     EQU         $0091
ATDDR7H     EQU         $009e
ATDDR7L     EQU         $009f



CR          equ         $0d          ; carriage return, ASCII 'Return' key
LF          equ         $0a          ; line feed, ASCII 'next line' character

DATAmax     equ         2048         ; Data count maximum, 2048 constant

;*******************************************************
; variable/data section for clock
            ORG    $3000             ; RAMStart defined as $3000
                                     ; in MC9S12C128 chip

timeh       DS.B   1                 ; Hour counter
timem       DS.B   1                 ; Minute counter
times       DS.B   1                 ; Second counter

CCount      DS.B   1                 ; keeps track of how large user input is

segDispDig  DS.B   1                 ; number that should be displayed on segment display
timesDec    DS.B   1                 ; used to store second counter converted to decimal
timemDec    DS.B   1                 ; used to store minute counter converted to decimal
timehDec    DS.B   1                 ; used to store hour counter converted to decimal

segDisp     DS.B   1                 ; will keep track of what needs to be displayed on segment display (ie: hours, minutes, seconds)
temp1dig    DS.B   1                 ; used for hex conversion for first digit
temp2dig    DS.B   2                 ; used for hex conversion for second digit 
tempSwitch  DS.B   2                 ; used for hex conversion to swap values
  
temp        DS.B   2
hexNum      DS.B   2                 ; used to temp store converted hex numbers

intCnt      DS.W   1                 ; interrupt counter for 2.5 mSec. of time
tempNumDec  DS.B   2                 ; used to temp store converted decimal numbers


; variable/data for waveform generation

ctr125u     DS.W   1                 ; 16bit interrupt counter for 125 uSec. of time
BUF         DS.B   6                 ; character buffer for a 16bit number in decimal ASCII
CTR         DS.B   1                 ; character buffer fill count
wavetype    DS.B   1                 ; says what the wave type is so we know what to print for the wave
wavecounter DS.B   2                 ; keeps track of the wave we are printing
waveflag    DS.B   1                 ; used for triangle wave and square to determine if we need to go up or down
addamount   DS.B   2                 ; the amount we should add every 125 uSec to change the frequency
decCorrect  DS.B   1                 ; used to determine if we are generating 100hz or normal freq
sqrCorrect  DS.B   1
plusCnt     DS.B   1                 ; used for 100hz since you need to add 3.2, since we can only add whole numbers every 5 we need to correct

msg1        DC.B   'Clock> ', $00
msg2        DC.B   '    CMD> ', $00

;*******************************************************
; interrupt vector section
            ORG    $FFFE             ; RTI interrupt vector setup for the simulator
            DC.W   
            
            ORG     $FFEC            ; Timer channel 1 interrupt vector setup, on simulator
            DC.W    oc1isr

;*******************************************************
; code section

            ORG    $3100
Entry
            LDS    #Entry         ; initialize the stack pointer

            LDAA   #%11111111   ; Set PORTA and PORTB bit 0,1,2,3,4,5,6,7
            STAA   DDRA         ; all bits of PORTA as output
            STAA   PORTA        ; set all bits of PORTA, initialize
            STAA   DDRB         ; all bits of PORTB as output
            LDAA   #%00000000
            STAA   PORTB        ; set all bits of PORTB, initialize

            ldaa   #$0C         ; Enable SCI port Tx and Rx units
            staa   SCICR2       ; disable SCI interrupts

            ldd    #$0001       ; Set SCI Baud Register = $0001 => 1.5M baud at 24MHz (for simulation)
            std    SCIBDH       ; SCI port baud rate change
            
            
            LDAA  #%11000000       ; Turn ON ADC, clear flags, Disable ATD interrupt
            STAA  ATDCTL2
            LDAA  #%00001000       ; Single conversion per sequence, no FIFO
            STAA  ATDCTL3
            LDAA  #%10000111       ; 8bit, ADCLK=24MHz/16=1.5MHz, sampling time=2*(1/ADCLK)
            STAA  ATDCTL4          ; for SIMULATION


            bset   RTICTL,%00011001 ;set RTI: dev=10*(2**10)=2.555msec for C128 board
                                    ;      4MHz quartz oscillator clock
            bset   CRGINT,%10000000 ; enable RTI interrupt
            bset   CRGFLG,%10000000 ; clear RTI IF (Interrupt Flag)

            ldx    #msgStart
            jsr    printmsg
            jsr    nextline
            ldx    #msgStart2
            jsr    printmsg
            jsr    nextline
            ldx    #msgStart3
            jsr    printmsg
            jsr    nextline
            ldx    #msgStart4
            jsr    printmsg
            jsr    nextline
            ldx    #msgStart5
            jsr    printmsg
            jsr    nextline
            ldx    #msgStart6
            jsr    printmsg
            jsr    nextline
          
            ldx    #0
            stx    intCnt            ; initialize interrupt counter with 0.
            cli                     ; enable interrupt, global
restartLoop
            
            clr    CCount           ; reset all our variables to make sure no interference from previous inputs
            clr    wavetype
            clr    decCorrect
            
            ldaa   #01
            staa   plusCnt
            staa   waveflag
            staa   sqrCorrect
            ldx    #$0000
            stx    addamount
            stx    temp
            stx    hexNum
            stx    tempNumDec
            stx    tempSwitch
            ldx    #Buff
            
loop        
            jsr    incClock         ; if 0.5 second is up, toggle the LED 

            jsr    getchar          ; type writer - check the key board
            tsta                    ;  if nothing typed, keep checking
            beq    loop
            
            staa   1,X+
            inc    CCount
            
            cmpa   #CR
            beq    enterPress       ; if enter is pressed go to check command
            jsr    putchar          ; otherwise display char on the terminal window
            bne    loop
enterPress 
            
            ldx    #Buff            ; load Buff into x reg
            
            pshx                    ; save x reg
            jsr    checkCommand     ; go to check what command user entered
            pulx                    ; restore x
            bra    loop             ; go back to main loop


;subroutine section below

;***********RTI interrupt service routine***************
rtiisr      bset   CRGFLG,%10000000 ; clear RTI Interrupt Flag - for the next one
            pshx
            ldx    intCnt            ; every time the RTI occur, increase
            inx                     ;    the 16bit interrupt count
            stx    intCnt
            pulx
rtidone     RTI

;***********end of RTI interrupt service routine********

;***********Timer OC1 interrupt service routine***************
oc1isr
            ldd   #3000              ; 125usec with (24MHz/1 clock)
            addd  TC1H               ;    for next interrupt
            std   TC1H               ; 
            bset  TFLG1,%00000010    ; clear timer CH1 interrupt flag, not needed if fast clear enabled
            ldd   ctr125u
            ldx   ctr125u
            inx                      ; update OC1 (125usec) interrupt counter
            stx   ctr125u            ; increse ctr125u and store it back
            
            
            ldx   wavecounter        ; load our wave counter into x            
            ldy   wavecounter        ; load our wave counter into y so we can increment it 
            ldab  addamount          ; load b with amount we need to add
            aby                      ; add that amount to wavecounter
            sty   wavecounter        ; store that new value
            
            tfr   x,d                ; transfer x to d, x is our 

            tstb                     ; test to see if we have hit the wave peak to either start going down for
                                     ; triangle wave or switch from 0 to 255 for square wave
            bne   noflag             ; if we are not a wave peak then don't switch flag
            
            ldaa  #%00000001         ; xor flag to flip it
            eora  waveflag
            staa  waveflag           ; store the flipped bit
            
            ldaa  #%00000001
            eora  sqrCorrect         ; flip sqrCorrect to change if we are printing 0 or 1
            staa  sqrCorrect

noflag            
            tfr   x,d
            
            cmpb  #$80               ; check again to see if we should print 0 or 1 for square
            bne   noflag2
            ldaa  #%00000001
            eora  sqrCorrect
            staa  sqrCorrect
            
noflag2            

            pshd                     ; store d
            
            ldaa    decCorrect       ; load in decCorrect to see what freq we are generating
            cmpa    #$01
            bne     not100hz         ; if its not 100hz then skip
            ldd     ctr125u          ; load in ctr125 to see how many points we have generated
            
            ldaa    #$03             ; load in 3 which is how much we should pre correction for 100hz
            staa    addamount
            inc     plusCnt
            ldaa    plusCnt          ; load in plusCnt to see if we have added 3 five times 
            cmpa    #$05
            bne     not100hz         ; if we haven't then we can keep add amount at 3

            clr     plusCnt          ; if we have then reset plusCnt
            inc     addamount        ; then we should add 4
            
not100hz
            puld                     ; restore d
            ldaa  wavetype           ; check to see what wave form we are currently generating
            cmpa  #$00
            beq   genSaw
            cmpa  #$01
            beq   genTri
            cmpa  #$02
            beq   genSqr
            cmpa  #$03
            beq   getAnalog
                     
genSaw
            bra   finishgencycle     ; if we are generating a saw wave then no further action is needed and we can finish this interupt cycle

genSqr
            ldaa  sqrCorrect         ; if we are generating square wave we need to check if we should print 0 or 255
            cmpa  #$01               
            beq   print1             ; if we need to print 255 then skip to that
            
            ldab  #$00               ; otherwise print zero and finish interupt cycle
            bra   finishgencycle
print1
            ldab  #255               ; print 255 and finish interupt cycle
            bra   finishgencycle    

genTri      
            ldaa  waveflag           ; if we are generating a triangle wave then we need to check if we are going up or down
            cmpa  #$01
            bne   countDown          ; go to count down if we need to count down
            bra   finishgencycle     ; otherwise we don't need to do anything and we can finish cycle
countDown
            ldaa  #255               ; however if we are counting down then we should subtract the number we have from 255 to effectively flip it (ie 4 turns to 251)
            sba
            tab
            bra   finishgencycle     ; then we can finish interupt cycle 
         
            
getAnalog            
            PSHA                   ; Start ATD conversion
            LDAA  #%10000111       ; right justified, unsigned, single conversion,
            STAA  ATDCTL5          ; single channel, CHANNEL 7, start the conversion

adcwait     ldaa  ATDSTAT0         ; Wait until ATD conversion finish
            anda  #%10000000       ; check SCF bit, wait for ATD conversion to finish
            beq   adcwait

            ldab  ATDDR0L          ; for SIMULATOR, pick up the lower 8bit result
            clra
            jsr   pnum10           ; print the result in decimal

            PULA
            RTI
            
finishgencycle
                        
            clra                     ; print ctr125u, only the last byte 
            jsr   pnum10             ; to make the file RxData3.txt with exactly 2048 data 
oc1done     RTI
;***********end of Timer OC1 interrupt service routine********

;***********timer module channel 1 interrupt******************


;***************checkInput**********************
;* Program: This will check the users input to see what we need to do
;* Input: user input Buff   
;* Output: no output unless error but will send us to proper subroutine  
;* Registers modified: B, Y, A
;**********************************************
checkCommand
            ;ldab   $0B
            ;cmpb   CCount
            
            ldy    #Buff
            ldaa   0,Y
            
            cmpa   #$68             ; check to see if h
            lbeq   displayHour
            
            cmpa   #$6D             ; check to see if m
            lbeq   displayMin
            
            cmpa   #$71             ; check to see if q
            lbeq   quitOp
            
            cmpa   #$73             ; check to see if s
            lbeq   displaySec
            
            cmpa   #$74             ; check to see if t
            lbeq   userTime
            
            cmpa   #$61             ; check to see if a
            lbeq   analog
            
            cmpa   #$67
            beq    generateWave 
            
            lbra   errorMsg        ; if none of those inputs go to error message
            
;***************generateWave**********************
;* Program: This part of the program will determine 
;* what wave we are currently generating and select
;* the parameters to generate the correct wave 
;*
;* Input: User entered wave, ctr125u, wavecounter
;* wavetype 
;* Output: no output from this directly but will
;* call subroutines to print wave
;* Registers modified: x, y, a, b, d 
;**********************************************
generateWave
            ldx     #0              ; reset ctr125
            stx     ctr125u
            stx     wavecounter     ; reset wavecounter
      
            ldy     #Buff           ; load buff to check user input
            iny
            ldaa    1,Y+
           
            cmpa    #$77            ; check to see if w
            beq     sawtooth 
           
            cmpa    #$74            ; check to see if t
            beq     triangle
           
            cmpa    #$71            ; check to see if q
            beq     square
           
            lbra     errorMsg
           
           
sawtooth
            ldaa    1,Y+            ; check to see if the next inputs are 2 or enter
            cmpa    #$32
            beq     correctinput
            cmpa    #$0D
            beq     correctinput
            
            jsr     errorMsg        ; if they are not then there is an input error

correctinput
            ldaa    #$00            ; load 0 to represent we are generating sawtooth
            staa    wavetype
            ldaa    #$01            ; set add amount to 1 since we are generating default sawtooth
            staa    addamount
            
            ldaa    1,-Y            ; check to see if we need to generate the 100hz version
            cmpa    #$32
            beq     sawtooth2       ; if we do go to that one
            ldx     #msgSaw
            bra     printwave       ; otherwise go to print wave
           
sawtooth2
            ldaa    1,+Y            ; check to see if there is a enter after the 2
            cmpa    #$0D
            beq     noerror
            jsr     errorMsg     
noerror            
            ldx     #msgSaw2        ; load saw2 message
            ldaa    #$01
            staa    decCorrect      ; set decCorrect to show that we are generating a 100hz wave
            ldaa    #$03            ; load add amount as 3
            staa    addamount
            bra     printwave       ; go to print wave
            
           
triangle
            ldaa    1,Y+            ; check to see if the next inputs are 2 or enter
            cmpa    #$0D
            beq     correctinput2
            
            jsr     errorMsg        ; if they are not then there is an input error
correctinput2            
            ldaa    #$01            ; load 1 to show we are generating a triangle wave
            staa    wavetype        ; rest is the same as before
            ldaa    #$01
            staa    addamount
            ldx     #msgTri
            bra     printwave

square     
            ldaa    1,Y+            ; check to see if the next inputs are 2 or enter
            cmpa    #$32
            beq     correctinput3
            cmpa    #$0D
            beq     correctinput3
            
            jsr     errorMsg        ; if they are not then there is an input error

correctinput3
            ldaa    #$02            ; load 2 to show we are generating a square wave
            staa    wavetype        ; rest is the same as the other waves 
            ldaa    #$01
            staa    addamount                 
            ldaa    1,-Y
            cmpa    #$32
            beq     square2
           
            ldx     #msgSqr
            bra     printwave

square2
            ldaa    1,+Y
            cmpa    #$0D
            beq     noerror2
            jsr     errorMsg     
noerror2            
            ldx     #msgSqr2
            ldaa    #$01
            staa    decCorrect
            ldaa    #$03
            staa    addamount
            bra     printwave


printwave
            jsr     printmsg         ; print the message we loaded
            jsr     nextline
            jsr     delay1ms         ; delay to clear
            ldx     #0
            stx     wavecounter
            jsr     StartTimer1oc    ; go to start interupt timer
            
printwaveloop           
          
            ldd     ctr125u          
            cpd     #DATAmax         ; 2048 bytes will be sent, the receiver at Windows PC 
            bhs     loopTxON         ; will only take 2048 bytes.
            bra     printwaveloop
           

loopTxON
            LDAA    #%00000000
            STAA    TIE               ; disable OC1 interrupt

            jsr     nextline
            jsr     nextline

            ldx     #msgDone            ; print '> Done!  Close Output file.'
            jsr     printmsg
            jsr     nextline

            lbra    restartLoop 



;***************analog************************
analog
            ldx     #0              ; reset ctr125
            stx     ctr125u
            stx     wavecounter     ; reset wavecounter
      
            ldy     #Buff           ; load buff to check user input
            iny
            ldaa    1,Y+
            
            cmpa    #$64
            lbne    errorMsg
            
            ldaa    1,Y+
            cmpa    #$63
            lbne    errorMsg
            
            ldaa    1,Y+
            cmpa    #$0D
            lbne    errorMsg
            
            ldaa    #$03            ; load 0 to represent we are generating sawtooth
            staa    wavetype
            ldx     #msgAnalog
            
            
            
getsignal
            jsr     printmsg         ; print the message we loaded
            jsr     nextline
            jsr     delay1ms         ; delay to clear
            ldx     #0
            stx     wavecounter
            jsr     StartTimer1oc    ; go to start interupt timer
getsignalloop           
          
            ldd     ctr125u          
            cpd     #DATAmax         ; 2048 bytes will be sent, the receiver at Windows PC 
            bhs     loopTxON         ; will only take 2048 bytes.
            bra     printwaveloop
            
;***************userTime**********************
;* Program: Will be called if user enters t, will check
;* to make sure input is valid and store that time
;* to the proper counters to be displayed 
;*
;* Input: User input Buff   
;* Output: Will output the user entered time if no error 
;* Registers modified: Y, A, D, B, X
;**********************************************
userTime
            iny                     ; iny to get the next char of user input
            ldaa   0,Y
            cmpa   #$20             ; char should be a SPACE so check to see if it is
            lbne   errorMsg
            jsr    goNextTimeDiv    ; if char is a space then go the hour div and get those number (ie 12:34:54 get 12)
            cmpa   #$23             ; make sure hour is not greater than 23 which is the max before resetting to 0
            lbgt   errorMsg
            
            pshy                    ; save y
            jsr    convertHex       ; convert input to hex so we can use it in code (NOTE: there is definitely a way to do this without converting to hex - 
                                    ; - but I wanted more experience with doing that since I feel like it will be important in the future)
            puly                    ; restore y
            
            iny                     ; go to next char to make sure it is a :, I did it in this order to make sure that it didn't change anything if there was an error
            ldaa   0,Y              
            cmpa   #$3A
            lbne   errorMsg
            
            ldd    hexNum           ; save the converted hex number to timeh which is our counter for hours
            stab   timeh           
            
            ldx    #$0000           ; load x with 0000 so we can reset the hexNum otherwise the next number would be added on top
            stx    hexNum
            jsr    goNextTimeDiv    ; go retrieve the minute time div
            cmpa   #$59             ; make sure it is not above 59 the max for minutes
            lbgt   errorMsg
            
            pshy                    ; save y
            jsr    convertHex       ; convert the minutes to hex
            puly                    ; restore y
            iny                     ; make sure that next char is a :
            ldaa   0,Y
            cmpa   #$3A
            lbne   errorMsg

            
            ldd    hexNum           ; save hex number into timem our minute counter
            stab   timem
            ldx    #$0000
            stx    hexNum           ; reset the hexNum to use again
            jsr    goNextTimeDiv    ; go get the seconds time div
            cmpa   #$59             ; make sure it is not above 59
            lbgt   errorMsg
                                    
            pshy                    ; save y
            jsr    convertHex       ; convert seconds to hex
            puly                    ; restore y
            iny                     ; make sure next char is ENTER
            ldaa   0,Y
            cmpa   #$0D
            lbne   errorMsg


            ldd    hexNum           ; reset hex num
            stab   times
            ldx    #$0000
            stx    hexNum
            
            jsr    nextline
            ldx    #msgTime
            jsr    printmsg
            jsr    nextline
            
            rts                     ; return back to mainLoop (Note, printing is done in other sub routines)
                    
;***************displaySec**********************
;* Program: Will change flag to show that we should
;* display seconds on the segment display and will
;* also update the segment display
;* 
;* Input: No input   
;* Output: Will change the segment display and tell
;* rest of code to update with seconds  
;* Registers modified: Y, A
;**********************************************
displaySec
            
            pshy
            iny
            ldaa   0,Y              ; make sure next char is a ENTER
            cmpa   #$0D
            lbne   errorMsg
            puly
            
            jsr    nextline
            ldx    #msgSec
            jsr    printmsg
            jsr    nextline
            
            ldaa   #$01             ; load segDisp with 1, this will show that our segment display should be showing seconds 
            staa   segDisp
            ldaa   timesDec         ; load the seg display with current number
            staa   PORTB
            rts
            
;***************displayMin**********************
;* Program: Will change flag to show that we should
;* display minutes on the segment display and will
;* also update the segment display
;* 
;* Input: No input   
;* Output: Will change the segment display and tell
;* rest of code to update with seconds  
;* Registers modified: Y, A
;**********************************************
displayMin
           
            pshy
            iny
            ldaa   0,Y              ; make sure next char is a ENTER
            cmpa   #$0D
            lbne   errorMsg
            puly

            jsr    nextline
            ldx    #msgMin
            jsr    printmsg
            jsr    nextline

            ldaa   #$02             ; load segDisp with 2, this will show that our segment display should be showing minutes
            staa   segDisp
            ldaa   timemDec         ; load the seg display with current number
            staa   PORTB
            
            
            
            rts

;***************displayHour**********************
;* Program: Will change flag to show that we should
;* display hours on the segment display and will
;* also update the segment display
;* 
;* Input: No input   
;* Output: Will change the segment display and tell
;* rest of code to update with seconds  
;* Registers modified: Y, A
;**********************************************
displayHour
            
           
            pshy
            iny
            ldaa   0,Y              ; make sure next char is a ENTER
            cmpa   #$0D
            lbne    errorMsg
            puly
  
            jsr    nextline
            ldx    #msgHour
            jsr    printmsg
            jsr    nextline
  
            ldaa   #$03             ; load segDisp with 3, this will show that our segment display should be showing minutes
            staa   segDisp
            ldaa   timehDec         ; load the seg display with current number
            staa   PORTB
            rts


;***************quitOp**********************
;* Program: 
;* Input:   
;* Output:  
;* Registers modified:
;**********************************************            
quitOp
            bclr   CRGINT,%10000000 ; disable RTI interrupt
            bset   CRGFLG,%00000000 ; set RTI IF  
            orcc   #%00010000       ; for good measure we can set i bit in ccr to 1 to turn off interupts (altough this is not needed)
            jsr    nextline
            ldx   #msgQuit          ; load in quit message
            jsr   printmsg
            jsr   nextline
            ldx   #msgQuit2
            jsr   printmsg
            jsr   nextline

typeWriter
            jsr    getchar          ; type writer - check the key board
            tsta                    ;  if nothing typed, keep checking
            beq    typeWriter
            
            staa   1,X+
            inc    CCount
                                    ;  otherwise - what is typed on key board
            jsr    putchar          ; is displayed on the terminal window
            cmpa   #CR
            bne    typeWriter       ; if Enter/Return key is pressed, move the
            ldaa   #LF              ; cursor to next line    
            jsr    putchar
            bra    typeWriter
    
            
                
                  

;***************goNextTimeDiv**********************
;* Program: Used to get the next time division (Hour -> Min -> Sec) 
;* Input: User input Buff   
;* Output: Two digit time div (Hour, Min, Sec)  
;* Registers modified: Y, A 
;**********************************************
goNextTimeDiv
            iny                    ; iny to get the first char of time div
            ldaa   0,Y             ; load a with said char
            jsr    testValid       ; make sure the char is a number 0-9
            suba   #$30            ; remove ascii bias
            ldab   #$10            ; mul by #$10 to shift number to left (ie: 4 -> 40)
            mul
            iny                    ; iny to get the next char
            ldaa   0,Y             ; load char in a
            jsr    testValid       ; make sure it is a number 0-9
            suba   #$30            ; remove ascii bias
            aba                    ; add it to the previous result which is stored in b (ie: 3 + 40 -> 43)
            staa   tempNumDec      ; store that value to a tempNumDec (Dec meaning decimal)
                   
            rts           
            
;***************convertHex**********************
;* Program: Will convert a two digit decimal number to a 
;* hex number
;* 
;* Input: User entered decimal number which in this case is
;* either hours, minutes, or seconds  
;* Output: The inputed number converted to hexadecimal  
;* Registers modified: B, A, Y, D, X
;**********************************************

convertHex

twoDig
            ldab  tempNumDec         ;load tempDecNum into d which should only be two digits
            ldaa  #$00
            ldy   #$10               ;load y with $10, this is so we can issolate just the first digit
            emul                     ;multiply to isolate digit into A reg (ie if number is 47 it will turn to 470 so 4 is in A and 70 is in B)
            std   tempNumDec         ;store d into num
            ldab  #$0A               ;load b with $0A (ie if number was 47, 4 will be in a and $0A will be in b)
            mul                      ;mul those numbers together to get what the hex number is
            addd  hexNum             ;add that hex number to the previous one
            std   hexNum             ;store new hex number back to the var
            
            ldd   tempNumDec         ;load d with number 1, this is once again to isolate the final digit
            ldab  #$00               ;load b with 0
            std   temp               ;store d to a temp
            ldd   tempNumDec         ;put the number back into d
            subd  temp               ;sub the temp (ie if number was 47, it will be 470 - 400 to get 70)
            
            ldx   #$10               ;this is to get rid of the extra zero we have from manipulating it
            idiv                     ;divide number by 10 (ie if number was 47 we have 470-400 = 70 which will then be 70/10 = 7)
            stx   tempNumDec         ;store the number back into num1
            
oneDig      
            ldd   tempNumDec         ;load num into d
            addd  hexNum             ;add final number into hexNum
            std   hexNum             ;store that final hexNum
                 
            rts
            
 
;***********printHx***************************
; prinHx: print the content of accumulator A in Hex on SCI port
printHx     psha
            lsra
            lsra
            lsra
            lsra
            cmpa   #$09
            bhi    alpha1
            adda   #$30
            jsr    putchar
            bra    low4bits
alpha1      adda   #$37
            jsr    putchar            
low4bits    pula
            anda   #$0f
            cmpa   #$09
            bhi    alpha2
            adda   #$30
            jsr    putchar
            rts
alpha2      adda   #$37
            jsr    putchar
            rts
;***********end of printhx***************************
            

;***************incClock**********************
;* Program: Will be used to increment the clock
;* when a second has passed. If seconds reach 60
;* then they will be reset and minute will be increased
;* and so on and so forth. 
;* Input: Our time counters  
;* Output: time counters increased to proper amount  
;* Registers modified: X, A
;**********************************************
incClock    psha
            pshx


            ldx    intCnt          ; check for 1 sec
            cpx    #10460          ; 1 sec at least on my computer 
           
            blo    dontChange      ; NOT yet

            ldx    #$00            ; 1 sec is up,
            stx    intCnt          ; clear counter to restart

            inc    times           ; inc the second counter
    
            ldaa   times           ; load in second counter
            cmpa   #60             ; compare it against 60 to see if a minute has passed
            bne    doneClock       ; if it hasn't then go to change clock to change the second
            
            ldx    #$00            ; reset times to 0
            stx    times
            inc    timem           ; inc timem by 1 minute
            
            ldaa   timem           ; check to see if one hour has passed
            cmpa   #60             
            bne    doneClock
            
            ldx    #$00            ; reset timem to 0
            stx    timem
            inc    timeh           ; inc timeh to show hour has passed
            
            ldaa   timeh           ; check to see if time has hit 24 so we can reset to 0
            cmpa   #24
            bne    doneClock
            
            ldx    #$00
            stx    timeh           ; all our counters should accuratlely reflect time now

doneClock   
            jsr    changeClock
            
dontChange
            
            pulx
            pula
            rts


;***************changeClock**********************
;* Program: Used to update and format the clock and call 
;* convert loop which displays clock numbers
;* Input: Time counters  
;* Output: printed out clock with the correct numbers  
;* Registers modified: X, A, B
;**********************************************
changeClock
            pshx                     ; save x
            psha                     ; save a
            
            jsr   nextline           ; go to next line so we can print new clock
            ldx   #msg1              ; print Clock>
            jsr   printmsg
            
            ldd   #$0000             ; set d with 0 so a and b dont mess with each other
            ldab  timeh              ; load b with our hour counter
            jsr   convertLoop        ; convert hours which are in hex back into decimal (number also printed in this subroutine) 
            
            
            ldaa  segDispDig         ; save decimal number so we can display it on seg display if we need
            staa  timehDec
            
            
            ldaa  #$3A               ; load a with : and print it after the hours are printed
            jsr   putchar
            
            ldd   #$0000             ; reset d
            ldab  timem              ; load in minute counter
            jsr   convertLoop        ; convert minute to decimal and print
            
            
            ldaa  segDispDig         ; save converted decimal number to min decimal
            staa  timemDec


            ldaa  #$3A               ; load a with :
            jsr   putchar            ; print it after minutes
            
            ldd   #$0000             ; reset d
            ldab  times              ; load d with second counter
            jsr   convertLoop        ; convert seconds into decimal
            
            ldaa  segDispDig         ; save converted number to use for later 
            staa  timesDec
            
            pulx                     ; restore x and a
            pula                     

            ldx    #msg2             ; print CMD>
            jsr    printmsg
            
            jsr    segChange         ; go to segChange which will change the segment display

            rts                      ; return to mainLoop


;***********segChange**************************
;* Program: Will update the segment display
;* with the correct number every second 
;* Input: Time counter converted to decimal  
;* Output: Will update the seg display  
;* Registers modified: A, B
;**********************************************

segChange
            ldaa   segDisp           ; load segDisp which is set by s, m or h and will tell us which number to print to seg display
            cmpa   #$03              ; if number is a three we want to display the hours
            bne    skip3
            ldab   timehDec          ; load b with our hours converted to decimal and then store to PORTB
            bra    printOnSeg
            
skip3            
            cmpa   #$02              ; if number is a two we want to display minutes
            bne    skip2
            ldab   timemDec          ; load b with our minutes converted to decimal and then store to PORTB
            bra    printOnSeg

skip2            
            ldab   timesDec          ; we will defaultly display the seconds if nothing else is selected, we can turn this off by checking to see if its a 
                                     ; 1 but I thought there was no point
           
printOnSeg            
            stab   PORTB             ; store whatever we needed to to PORTB to display on the segment display
            rts                      ; return to changeClock

;***********convertLoop***************************
;* Program: Will convert clock digits to decimal 
;* Input: time counter of either hour, min, or sec   
;* Output: that number converted to decimal  
;* Registers modified: X, B, D, A
;**********************************************
convertLoop 
            pshx                     ; save x and a
            psha  
              
            ldx   #$000A             ; load x with A
            idiv                     ; divide hex number by A
            stab  temp1dig           ; save the remainder which is our first decimal number
            stx   tempSwitch         ; store the actual answer which we need to divide again but we need to move it back to d
            ldd   #$0000             ; clear d
            ldd   tempSwitch         ; load d back with our answer to divide again
            ldx   #$000A             ; divide by A
            
            idiv
            stab  temp2dig           ; store second number
            ldaa  temp2dig           ; load a with that number
            ldab  #$30               ; add a ascii bias to display to screen
            aba
            jsr   putchar            ; print number which is second dig (ie if display 35 this is 3)
            
            ldaa  temp1dig           ; load first dig to a
            ldab  #$30               ; add ascii bias
            aba
            jsr   putchar            ; print number which is first dig (ie if display 35 this is 5)
            
            ldaa  #$10               ; we want to save this number to use for later so multiply dig 2 by 10 (ie if number is 35 this is 3 -> 30)
            ldab  temp2dig
            mul
            ldaa  temp1dig           ; load in first dig to add (ie if number is 35 this will be 5 + 30 -> 35)
            aba
            staa  segDispDig         ; save that number which we are going to use to change the segment display
            
            
            pulx                     ; restore x and a
            pula
            
            rts                      ; return to changeClock

;***********testValid*************************
;* Program: Will test to see if a char is a number
;* 0-9 
;* Input: A user entered char   
;* Output: no output unless erorr 
;* Registers modified: A
;*********************************************
testValid
            cmpa  #$30
            beq   valid
            cmpa  #$31
            beq   valid
            cmpa  #$32
            beq   valid
            cmpa  #$33
            beq   valid
            cmpa  #$34
            beq   valid
            cmpa  #$35
            beq   valid
            cmpa  #$36
            beq   valid
            cmpa  #$37
            beq   valid
            cmpa  #$38
            beq   valid
            cmpa  #$39
            beq   valid
            
                 
            bra   errorMsg
 
valid
           
            rts

;***************StartTimer1oc************************
;* Program: Start the timer interrupt, timer channel 6 output compare
;* Input:   Constants - channel 6 output compare, 125usec at 24MHz
;* Output:  None, only the timer interrupt
;* Registers modified: D used and CCR modified
;* Algorithm:
;             initialize TIOS, TIE, TSCR1, TSCR2, TC2H, and TFLG1
;**********************************************
StartTimer1oc
            PSHD
            LDAA   #%00000010
            STAA   TIOS              ; set CH1 Output Compare
            STAA   TIE               ; set CH1 interrupt Enable
            LDAA   #%10000010        ; enable timer, Fast Flag Clear not set
            STAA   TSCR1
            LDAA   #%00000000        ; TOI Off, TCRE Off, TCLK = BCLK/1
            STAA   TSCR2             ;   not needed if started from reset

            LDD    #3000            ; 125usec with (24MHz/1 clock)
            ADDD   TCNTH            ;    for first interrupt
            STD    TC1H             ; 

            BSET   TFLG1,%00000010   ; initial Timer CH1 interrupt flag Clear, not needed if fast clear set
            LDAA   #%00000010
            STAA   TIE               ; set CH1 interrupt Enable
            PULD
            RTS
;***************end of StartTimer1oc*****************

;***********pnum10***************************
;* Program: print a word (16bit) in decimal to SCI port
;* Input:   Register D contains a 16 bit number to print in decimal number
;* Output:  decimal number printed on the terminal connected to SCI port
;* 
;* Registers modified: CCR
;* Algorithm:
;     Keep divide number by 10 and keep the remainders
;     Then send it out to SCI port
;  Need memory location for counter CTR and buffer BUF(6 byte max)
;**********************************************
pnum10          pshd                   ;Save registers
                pshx
                pshy
                clr     CTR            ; clear character count of an 8 bit number

                ldy     #BUF
pnum10p1        ldx     #10
                idiv
                beq     pnum10p2
                stab    1,y+
                inc     CTR
                tfr     x,d
                bra     pnum10p1

pnum10p2        stab    1,y+
                inc     CTR                        
;--------------------------------------

pnum10p3        ldaa    #$30                
                adda    1,-y
                jsr     putchar
                dec     CTR
                bne     pnum10p3
                jsr     nextline
                puly
                pulx
                puld
                rts
;***********end of pnum10********************


;***********errorMsg***************************
;* Program: Will display error message
;* Input: None   
;* Output: displayed error message  
;* Registers modified: X
;**********************************************
errorMsg

            ldx   #msgInv            ; Load in Invalid message
            jsr   printmsg
            jsr   nextline
            lbra  restartLoop


;***********printmsg***************************
;* Program: Output character string to SCI port, print message
;* Input:   Register X points to ASCII characters in memory
;* Output:  message printed on the terminal connected to SCI port
;* 
;* Registers modified: CCR
;* Algorithm:
;     Pick up 1 byte from memory where X register is pointing
;     Send it out to SCI port
;     Update X register to point to the next byte
;     Repeat until the byte data $00 is encountered
;       (String is terminated with NULL=$00)
;**********************************************
NULL            equ     $00
printmsg        psha                   ;Save registers
                pshx
printmsgloop    ldaa    1,X+           ;pick up an ASCII character from string
                                       ;   pointed by X register
                                       ;then update the X register to point to
                                       ;   the next byte
                cmpa    #NULL
                beq     printmsgdone   ;end of strint yet?
                bsr     putchar        ;if not, print character and do next
                bra     printmsgloop
printmsgdone    pulx 
                pula
                rts
;***********end of printmsg********************

;***************putchar************************
;* Program: Send one character to SCI port, terminal
;* Input:   Accumulator A contains an ASCII character, 8bit
;* Output:  Send one character to SCI port, terminal
;* Registers modified: CCR
;* Algorithm:
;    Wait for transmit buffer become empty
;      Transmit buffer empty is indicated by TDRE bit
;      TDRE = 1 : empty - Transmit Data Register Empty, ready to transmit
;      TDRE = 0 : not empty, transmission in progress
;**********************************************
putchar     brclr SCISR1,#%10000000,putchar   ; wait for transmit buffer empty
            staa  SCIDRL                      ; send a character
            rts
;***************end of putchar*****************

;****************getchar***********************
;* Program: Input one character from SCI port (terminal/keyboard)
;*             if a character is received, other wise return NULL
;* Input:   none    
;* Output:  Accumulator A containing the received ASCII character
;*          if a character is received.
;*          Otherwise Accumulator A will contain a NULL character, $00.
;* Registers modified: CCR
;* Algorithm:
;    Check for receive buffer become full
;      Receive buffer full is indicated by RDRF bit
;      RDRF = 1 : full - Receive Data Register Full, 1 byte received
;      RDRF = 0 : not full, 0 byte received
;**********************************************

getchar     brclr SCISR1,#%00100000,getchar7
            ldaa  SCIDRL
            rts
getchar7    clra
            rts
;****************end of getchar**************** 

;****************nextline**********************
nextline    psha
            ldaa  #CR              ; move the cursor to beginning of the line
            jsr   putchar          ;   Cariage Return/Enter key
            ldaa  #LF              ; move the cursor to next line, Line Feed
            jsr   putchar
            pula
            rts
;****************end of nextline***************

;****************delay1ms**********************
delay1ms:   pshx
            ldx   #$1000           ; count down X, $8FFF may be more than 10ms 
d1msloop    nop                    ;   X <= X - 1
            dex                    ; simple loop
            bne   d1msloop
            pulx
            rts
;****************end of delay1ms***************

msgStart       DC.B    'Welcome to Wave Generation! See wave instructions below',$00
msgStart2      DC.B    'gw = generate sawtooth wave, gw2 = generate sawtooth wave at 100hz',$00
msgStart3      DC.B    'gt = generate triangle wave',$00
msgStart4      DC.B    'gq = generate square wave, gq2 = generate square wave at 100hz',$00
msgStart5      DC.B    't xx:xx:xx to change time, s = display seconds, m = minutes',$00
msgStart6      DC.B    'h = hours on segment display and q = quit' ,$00
                      
msgSec         DC.B    'Displaying seconds',$00
msgMin         DC.B    'Displaying minutes',$00
msgHour        DC.B    'Displaying hours',$00
msgTime        DC.B    'Updated Time!',$00

msgInv         DC.B    '          Error> Invalid input', $00
msgQuit        DC.B    'Clock and Wave generation stopped and Typewriter started.',$00
msgQuit2       DC.B    'Please type anything below!', $00
msgSaw         DC.B    '    Sawtooth wave generation ...',$00
msgSaw2        DC.B    '    Sawtooth wave generation at 100Hz ...',$00
msgSqr         DC.B    '    Square wave generation ...',$00
msgSqr2        DC.B    '    Square wave generation at 100Hz ...',$00
msgTri         DC.B    '    Triangle wave generation ...',$00
msgDone        DC.B    '    Generation complete!',$00
msgAnalog      DC.B    '    Acquiring Analog Signal',$00
Buff           DS.B   13

            END               ; this is end of assembly source file
                              ; lines below are ignored - not assembled/compiled
