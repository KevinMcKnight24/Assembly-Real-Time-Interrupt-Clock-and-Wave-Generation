This program is a real time interupt clock and a wave form generator using timers
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
