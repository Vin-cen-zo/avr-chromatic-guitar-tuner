#define __SFR_OFFSET 0x00
#include "avr/io.h"

; =============================================================================
; CONSTANTS
; =============================================================================
.equ LCD_I2C_ADDR,  0x4E        ; I2C 7-bit address 0x27 shifted left + Write bit (0x27 << 1)
.equ TWI_FREQ,      100000      ; Target I2C bus clock: 100 kHz (Standard-mode)
.equ CPU_FREQ,      16000000    ; MCU clock: 16 MHz

; TWBR Formula: TWBR = ((CPU_FREQ / TWI_FREQ) - 16) / (2 * Prescaler)
; = ((16,000,000 / 100,000) - 16) / 2 = 72
.equ TWBR_VAL,      72          ; Bitrate register value for 16 MHz -> 100 kHz

; =============================================================================
; TWI_INIT
; Description: Initializes hardware TWI / I2C peripheral on ATmega328P.
; =============================================================================
TWI_INIT:
    PUSH R16

    ; Enable internal pull-ups on SDA (PC4) and SCL (PC5)
    ; Prevents floating bus conditions that could stall TWI in simulation
    SBI PORTC, 4
    SBI PORTC, 5

    ; Set I2C clock frequency
    LDI R16, TWBR_VAL
    STS TWBR, R16

    ; Set Prescaler = 1 (TWPS1:0 = 00)
    LDI R16, 0x00
    STS TWSR, R16

    ; Enable TWI hardware module
    LDI R16, (1 << TWEN)
    STS TWCR, R16

    POP R16
    RET

; =============================================================================
; TWI_START
; Description: Transmits START condition onto I2C bus.
; =============================================================================
TWI_START:
    PUSH R16

    ; Send START condition: TWINT=1, TWSTA=1, TWEN=1
    LDI R16, (1 << TWINT) | (1 << TWSTA) | (1 << TWEN)
    STS TWCR, R16

    ; Poll until START condition finishes transmission
    RCALL TWI_WAIT

    POP R16
    RET

; =============================================================================
; TWI_STOP
; Description: Transmits STOP condition to release the I2C bus.
; =============================================================================
TWI_STOP:
    PUSH R16

    ; Send STOP condition: TWINT=1, TWSTO=1, TWEN=1
    LDI R16, (1 << TWINT) | (1 << TWSTO) | (1 << TWEN)
    STS TWCR, R16

    ; Brief settling delay for bus idle
    NOP
    NOP
    NOP
    NOP

    POP R16
    RET

; =============================================================================
; TWI_WRITE
; Description: Writes a single byte over I2C.
; Input      : R16 = Byte to transmit
; =============================================================================
TWI_WRITE:
    PUSH R17

    ; Load data into TWDR
    STS TWDR, R16

    ; Clear TWINT to initiate transmission
    LDI R17, (1 << TWINT) | (1 << TWEN)
    STS TWCR, R17

    ; Wait for byte transmission to complete
    RCALL TWI_WAIT

    POP R17
    RET

; =============================================================================
; TWI_WAIT [INTERNAL]
; Description: Polls TWINT flag until TWI hardware operation finishes.
; =============================================================================
TWI_WAIT:
    PUSH R16

_twi_wait_loop:
    LDS R16, TWCR
    SBRS R16, TWINT
    RJMP _twi_wait_loop

    POP R16
    RET

; =============================================================================
; TWI_WRITE_ADDR [HELPER]
; Description: Transmits LCD device address with Write bit (0).
; =============================================================================
TWI_WRITE_ADDR:
    PUSH R16

    LDI R16, LCD_I2C_ADDR
    RCALL TWI_WRITE

    POP R16
    RET
