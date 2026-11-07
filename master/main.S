#define __SFR_OFFSET 0x00
#include <avr/io.h>

.global main
.global INT0_vect
.global INT1_vect

.section .text

; === ROLE 2 MODULES — DO NOT CHANGE ORDER ===
#include "lcd_i2c.S"        // 1. Low-level TWI primitives
#include "lcd_driver.S"     // 2. LCD driver (requires TWI)
#include "lookup_table.S"   // 3. Flash table data
#include "bcd_ascii.S"      // 4. Number-to-ASCII converter
#include "mapping.S"        // 5. Mapping logic (requires lookup table)
#include "display.S"        // 6. Display update routines (requires modules above)
; === END ROLE 2 MODULES ===

main:
    ; Init Stack Pointer
    ldi r16, hi8(RAMEND)
    out SPH, r16
    ldi r16, lo8(RAMEND)
    out SPL, r16

    ; Clear Registers
    clr r1
    clr r22           ; R22 = New Data Flag
    clr r23           ; R23 = Target string index (0 = E2)
    clr r24           ; R24 = Low Byte Hz
    clr r25           ; R25 = High Byte Hz

    ; Set INT0 (PD2) and INT1 (PD3) as Input with Pull-up
    cbi DDRD, 2
    sbi PORTD, 2
    cbi DDRD, 3
    sbi PORTD, 3

    ; Configure External Interrupts INT0 & INT1
    ; INT0: Trigger on Falling Edge     (ISC01=1, ISC00=0)
    ; INT1: Trigger on Any Logic Change (ISC11=0, ISC10=1) -> For Buzzer HOLD
    ldi r16, (0<<ISC11) | (1<<ISC10) | (1<<ISC01) | (0<<ISC00)
    sts EICRA, r16
    ; Enable INT0 and INT1
    ldi r16, (1<<INT1) | (1<<INT0)
    out EIMSK, r16

    ; Initialize Modules
    rcall USART_INIT
    rcall BUZZER_INIT
    
    ; LCD initialization - called once on RESET
    RCALL LCD_INIT
    RCALL DISPLAY_STARTUP   ; Optional startup splash screen

    ; Enable Global Interrupts
    sei

MAIN_LOOP:
    ; Check if new data flag R22 == 0x01
    cpi r22, 0x01
    brne MAIN_LOOP
    
    ; Reset flag once new data is detected
    clr r22

    ; Load latest Hz from SRAM into R24/R25 right before rendering.
    ; ISR stores incoming data to rx_final_lo/hi to avoid clobbering.
    lds r24, rx_final_lo
    lds r25, rx_final_hi

    ; Update LCD with fresh frequency & tuning state
    RCALL UPDATE_DISPLAY

    rjmp MAIN_LOOP


; --- ISR for INT0 (Mode / Target String Index) ---
INT0_vect:
    push r16
    in r16, SREG
    push r16
    ; Preserve R17, ZH, ZL before calling BUZZER_UPDATE_FREQ
    push r17
    push zh
    push zl

    ; Increment R23 Mode (0-5)
    inc r23
    cpi r23, 6
    brsh reset_mode
    rjmp end_int0
reset_mode:
    clr r23
end_int0:

    ; Set R22=1 to refresh screen upon string switch
    ldi r22, 0x01

    ; Update buzzer frequency if active
    rcall BUZZER_UPDATE_FREQ

    ; Restore ZL, ZH, R17 in LIFO order
    pop zl
    pop zh
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti


; --- ISR for INT1 (Buzzer Toggle) ---
INT1_vect:
    push r16
    in r16, SREG
    push r16
    ; Preserve R17, ZH, ZL across BUZZER_TOGGLE
    push r17
    push zh
    push zl

    rcall BUZZER_TOGGLE

    ; Restore ZL, ZH, R17 in LIFO order
    pop zl
    pop zh
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti

#include "usart_rx.S"
#include "buzzer_core.S"
