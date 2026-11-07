#define __SFR_OFFSET 0x00
#include <avr/io.h>

.global BUZZER_INIT
.global BUZZER_TOGGLE
.global BUZZER_UPDATE_FREQ

; Static SRAM variable allocation
.equ buzzer_state, 0x0104   ; 0 = off, 1 = on

.section .text

; OCR1A Lookup Table (for 16 MHz clock, Prescaler 8):
; E2 (0) = 0x2F65 (82.41 Hz)
; A2 (1) = 0x2382 (110.00 Hz)
; D3 (2) = 0x1A9A (146.83 Hz)
; G3 (3) = 0x13ED (196.00 Hz)
; B3 (4) = 0x0FD1 (246.94 Hz)
; E4 (5) = 0x0BD9 (329.63 Hz)
buzzer_lookup:
    .word 0x2F65, 0x2382, 0x1A9A, 0x13ED, 0x0FD1, 0x0BD9

BUZZER_INIT:
    ; Configure PB1 (OC1A) as Output
    sbi DDRB, 1
    
    ; Initial timer config: CTC mode, stopped
    ; WGM13:0 = 0100 (CTC Mode, TOP = OCR1A)
    ldi r16, 0x00
    sts TCCR1A, r16
    ; Prescaler 8 -> CS12:0 = 010
    ldi r16, (1<<WGM12)
    sts TCCR1B, r16
    
    ; Initial state: off
    ldi r16, 0
    sts buzzer_state, r16
    cbi PORTB, 1
    
    ret

BUZZER_UPDATE_FREQ:
    ; R23 contains target string index (0 to 5)
    andi r23, 0x07          ; Safety mask
    cpi r23, 6
    brsh skip_freq_update   ; Ignore if index >= 6
    
    ; Load base address of buzzer_lookup
    ldi zl, lo8(buzzer_lookup)
    ldi zh, hi8(buzzer_lookup)
    
    ; Offset = R23 * 2 (16-bit word entries)
    mov r16, r23
    lsl r16
    add zl, r16
    adc zh, r1
    
    ; Read OCR1A value from Flash using LPM
    lpm r16, z+     ; Read low byte
    lpm r17, z      ; Read high byte
    
    ; Write to OCR1A (high byte first)
    sts OCR1AH, r17
    sts OCR1AL, r16

skip_freq_update:
    ret

BUZZER_TOGGLE:
    sbic PIND, 3          ; If PD3 is released/HIGH, skip jump to turn_on
    rjmp turn_off         ; Branch to turn_off when button is released
    ; If execution reaches here, PD3 is LOW (button held down)
    
turn_on:
    ; Prevent redundant enable if already active
    lds r16, buzzer_state
    cpi r16, 1
    breq _bt_end

    ldi r16, 1
    sts buzzer_state, r16
    
    ; Update frequency based on current R23 before turning on
    rcall BUZZER_UPDATE_FREQ
    
    ; Toggle on Compare Match -> COM1A1:0 = 01
    ldi r16, (1<<COM1A0)
    sts TCCR1A, r16
    
    ; Start timer with Prescaler 8 -> CS12:0 = 010
    ldi r16, (1<<WGM12) | (1<<CS11)
    sts TCCR1B, r16
    
_bt_end:
    ret

turn_off:
    ; Prevent redundant disable if already inactive
    lds r16, buzzer_state
    cpi r16, 0
    breq _bt_end

    ldi r16, 0
    sts buzzer_state, r16
    
    ; Stop Toggle on Compare Match
    ldi r16, 0x00
    sts TCCR1A, r16
    ; Stop timer
    ldi r16, 0x00
    sts TCCR1B, r16
    
    cbi PORTB, 1
    ret
