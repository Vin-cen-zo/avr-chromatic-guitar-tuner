#define __SFR_OFFSET 0x00
#include <avr/io.h>

.global USART_INIT
.global USART_RX_vect

; Static SRAM variable allocation at 0x0100+ to prevent overlap with registers R0-R31
.equ rx_state,      0x0100    ; State machine: 0=wait sync, 1=wait low, 2=wait high
.equ rx_temp_lo,    0x0101    ; Temporary low byte buffer
.equ rx_final_lo,   0x0102    ; Last valid received Low Byte (Hz)
.equ rx_final_hi,   0x0103    ; Last valid received High Byte (Hz)

.section .text

USART_INIT:
    ; 9600 bps @ 16 MHz clock
    ldi r16, 0x00
    sts UBRR0H, r16
    ldi r16, 0x67
    sts UBRR0L, r16
    
    ; Enable RX and RX Complete Interrupt
    ldi r16, (1<<RXEN0) | (1<<RXCIE0)
    sts UCSR0B, r16
    
    ; Frame format: 8 data bits, 1 stop bit, no parity (8-N-1)
    ldi r16, (1<<UCSZ01) | (1<<UCSZ00)
    sts UCSR0C, r16

    ; Initialize state variables
    ldi r16, 0
    sts rx_state, r16
    sts rx_final_lo, r16
    sts rx_final_hi, r16
    ret

USART_RX_vect:
    push r16
    in r16, SREG
    push r16
    push r17

    lds r16, UDR0       ; Read received byte from hardware buffer

    lds r17, rx_state
    cpi r17, 0
    breq state_0
    cpi r17, 1
    breq state_1
    cpi r17, 2
    breq state_2
    rjmp reset_state

state_0:
    cpi r16, 0xFF       ; Check for Sync Byte (0xFF packet header)
    brne end_isr        ; Ignore byte if not sync
    ldi r17, 1
    sts rx_state, r17
    rjmp end_isr

state_1:
    sts rx_temp_lo, r16 ; Store Low Byte in temporary buffer
    ldi r17, 2
    sts rx_state, r17
    rjmp end_isr

state_2:
    ; R16 contains High Byte
    ; Store directly into SRAM buffer to prevent race conditions with display routines
    sts rx_final_hi, r16
    lds r17, rx_temp_lo
    sts rx_final_lo, r17

    ; Set flag indicating new valid packet is available
    ldi r22, 0x01
    
reset_state:
    ldi r17, 0
    sts rx_state, r17

end_isr:
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti
