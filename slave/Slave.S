#define __SFR_OFFSET 0x00
#include "avr/io.h"

.global main

main:
    ; --- Initialize USART (9600 bps, 8 Data bits, 1 Stop bit) ---
    ldi r16, 0x00
    sts UBRR0H, r16
    ldi r16, 0x67
    sts UBRR0L, r16
    ldi r16, (1<<TXEN0)
    sts UCSR0B, r16
    ldi r16, (1<<UCSZ01) | (1<<UCSZ00)
    sts UCSR0C, r16

    ; --- Initialize ADC (Single Conversion Mode, Pin PC0) ---
    ; 1. Ensure PC0 is input without pull-up
    ldi r16, 0x00
    sts DDRC, r16           ; Set PORTC as input
    sts PORTC, r16          ; Disable pull-up

    ; 2. Disable digital input buffer on ADC0
    ldi r16, (1<<ADC0D)
    sts DIDR0, r16

    ; 3. Set reference to AVCC, input channel ADC0
    ldi r16, (1<<REFS0)
    sts ADMUX, r16

    ; 4. Enable ADC with prescaler 128
    ldi r16, (1<<ADEN) | (1<<ADPS2) | (1<<ADPS1) | (1<<ADPS0) 
    sts ADCSRA, r16
    ldi r16, 0x00
    sts ADCSRB, r16

    ; 5. Perform dummy first conversion to stabilize ADC
    lds r16, ADCSRA
    ori r16, (1<<ADSC)
    sts ADCSRA, r16
dummy_wait:
    lds r16, ADCSRA
    sbrc r16, ADSC
    rjmp dummy_wait

    ; --- Initialize Timer 1 (Normal Mode, initially stopped) ---
    ldi r16, 0x00
    sts TCCR1A, r16
    sts TCCR1B, r16         ; Timer 1 halted

    ; --- Macro: Read ADC (Single Conversion Polling) ---
    .macro BACA_ADC
        lds r19, ADCSRA
        ori r19, (1<<ADSC)
        sts ADCSRA, r19
    wait_adc_\@:
        lds r19, ADCSRA
        sbrc r19, ADSC
        rjmp wait_adc_\@
        lds r16, ADCL
        lds r17, ADCH
    .endm

    ; --- Macro: Send 1 Byte via USART ---
    .macro KIRIM_BYTE reg
    wait_tx_\@:
        lds r19, UCSR0A
        sbrs r19, UDRE0
        rjmp wait_tx_\@
        sts UDR0, \reg
    .endm

main_loop:

    ; --- Reset Timeout Watchdog Counter ---
    clr r26
    clr r27

    ; Reset Timer 1 counter
    ldi r16, 0x00
    sts TCCR1B, r16         ; Stop timer
    sts TCNT1H, r16         ; Reset counter
    sts TCNT1L, r16

    ; --- Phase 1: Wait for signal to fall below 511 (0x01FF) ---
fase_1_turun:
    BACA_ADC
    adiw r26, 1             ; Increment timeout watchdog
    cpi r27, 0x08           ; Check timeout threshold
    brlo skip_to1
    rjmp send_zero          ; Force send 0 Hz if signal lost
skip_to1:
    cpi r16, 0xFF
    ldi r18, 0x01
    cpc r17, r18
    brsh fase_1_turun

    ; --- Phase 2: Wait for signal to rise above 513 (0x0201) -> START ---
fase_2_naik:
    BACA_ADC
    adiw r26, 1
    cpi r27, 0x08
    brlo skip_to2
    rjmp send_zero
skip_to2:
    cpi r16, 0x01
    ldi r18, 0x02
    cpc r17, r18
    brlo fase_2_naik

    ; Zero-crossing edge detected! Start Timer 1 (Prescaler 8 -> 2 MHz tick rate @ 16 MHz CPU)
    ldi r16, (1<<CS11)
    sts TCCR1B, r16

    ; --- Phase 3: Wait for signal to fall below 511 (0x01FF) again ---
fase_3_turun:
    BACA_ADC
    adiw r26, 1
    cpi r27, 0x08
    brlo skip_to3
    rjmp send_zero
skip_to3:
    cpi r16, 0xFF
    ldi r18, 0x01
    cpc r17, r18
    brsh fase_3_turun

    ; --- Phase 4: Wait for signal to rise above 513 (0x0201) again -> STOP ---
fase_4_naik:
    BACA_ADC
    adiw r26, 1
    cpi r27, 0x08
    brlo skip_to4
    rjmp send_zero
skip_to4:
    cpi r16, 0x01
    ldi r18, 0x02
    cpc r17, r18
    brlo fase_4_naik

    ; Full period elapsed: Stop Timer 1
    ldi r16, 0x00
    sts TCCR1B, r16

    ; Read measured period duration (clock ticks) from Timer 1
    lds r20, TCNT1L
    lds r21, TCNT1H

    ; --- Validation: skip calculation if ticks = 0 ---
    mov r16, r20
    or  r16, r21
    brne div_start
    rjmp main_loop

; --- Watchdog Timeout Handler ---
send_zero:
    clr r24                 ; Frequency = 0 Hz
    clr r25
    rjmp transmisi_mulai    ; Forward 0 Hz directly to Master

div_start:

    ; --- Calculate Frequency: Hz = 2,000,000 / ticks ---
    ; Dividend (32-bit): 2,000,000 = 0x001E8480 -> r15:r14:r13:r12
    ; Divisor (16-bit):  ticks -> r21:r20
    ; Quotient (16-bit): Hz -> r25:r24

    ldi r16, 0x80
    mov r12, r16
    ldi r16, 0x84
    mov r13, r16
    ldi r16, 0x1E
    mov r14, r16
    clr r15

    clr r22
    clr r23
    clr r24
    clr r25

    ldi r18, 32

div_loop:
    lsl r12
    rol r13
    rol r14
    rol r15
    rol r22
    rol r23

    sub r22, r20
    sbc r23, r21

    brcc div_no_restore

    add r22, r20
    adc r23, r21
    rjmp div_next

div_no_restore:
    ori r24, 0x01

div_next:
    dec r18
    breq div_done

    lsl r24
    rol r25
    rjmp div_loop

div_done:
    ; r25:r24 = Frequency in Hz (16-bit)

    ; --- 1. Prevent Sync Collision ---
    ; Sync Byte is 0xFF, so actual payload bytes must not equal 0xFF
    cpi r25, 0xFF
    brne cek_low_byte
    ldi r25, 0xFE           ; Clamp down to 0xFE

cek_low_byte:
    cpi r24, 0xFF
    brne transmisi_mulai
    ldi r24, 0xFE           ; Clamp down to 0xFE

transmisi_mulai:
    ; --- 2. USART Transmission (Protocol: Sync -> Low Byte -> High Byte) ---
    ldi r16, 0xFF
    KIRIM_BYTE r16          ; Sync Byte (packet header)
    KIRIM_BYTE r24          ; Low Byte (Little-Endian)
    KIRIM_BYTE r25          ; High Byte

    ; --- 3. Rate Limiting Delay (~150ms @ 16 MHz) ---
    ; Prevents flooding the serial bus and allows Master time to update I2C LCD
    ldi r18, 13
delay_outer:
    ldi r19, 250
delay_inner:
    ldi r20, 250
delay_core:
    dec r20
    brne delay_core
    dec r19
    brne delay_inner
    dec r18
    brne delay_outer

    rjmp main_loop
