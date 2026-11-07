; =============================================================================
; FILE: lcd_driver.S
; DESCRIPTION: 16x2 HD44780-compatible LCD driver over I2C via PCF8574.
;              Operates in 4-bit bus mode.
;
; DEPENDENCY: lcd_i2c.S must be #included BEFORE this file.
;
; PCF8574 PINOUT (LiquidCrystal_I2C standard mapping):
;   P0 = RS   (Register Select: 0=Command, 1=Data)
;   P1 = RW   (Read/Write: tied to 0=Write)
;   P2 = EN   (Enable strobe pulse)
;   P3 = BL   (Backlight control: 1=ON)
;   P4 = D4
;   P5 = D5
;   P6 = D6
;   P7 = D7
;
; CALLING CONVENTIONS:
;   LCD_CMD          -> R16 = command byte
;   LCD_CHAR         -> R16 = ASCII character byte
;   LCD_GOTOXY       -> R16 = row (0/1), R17 = column (0-15)
;   LCD_STRING       -> ZH:ZL = pointer to null-terminated string in Flash
;   LCD_CLEAR_SCREEN -> Clears display and resets cursor
;   LCD_INIT         -> Initializes TWI and LCD into 4-bit mode
; =============================================================================

#define __SFR_OFFSET 0x00
#include "avr/io.h"

; =============================================================================
; PCF8574 BIT MASKS
; =============================================================================
.equ LCD_BL,  0x08      ; P3 — Backlight ON
.equ LCD_EN,  0x04      ; P2 — Enable
.equ LCD_RW,  0x02      ; P1 — RW (always 0)
.equ LCD_RS,  0x01      ; P0 — RS

; HD44780 Commands
.equ LCD_CLEAR,       0x01   ; Clear display
.equ LCD_HOME,        0x02   ; Return home
.equ LCD_ENTRY_MODE,  0x06   ; Entry mode: increment, no shift
.equ LCD_DISPLAY_ON,  0x0C   ; Display ON, cursor OFF, blink OFF
.equ LCD_4BIT_2LINE,  0x28   ; 4-bit mode, 2 lines, 5x8 font
.equ LCD_ROW0,        0x80   ; DDRAM address line 0, column 0
.equ LCD_ROW1,        0xC0   ; DDRAM address line 1, column 0

; =============================================================================
; LCD_SEND_NIBBLE [INTERNAL]
; Description: Transmits the upper nibble of R16 to the LCD via PCF8574
;              Generates EN strobe: HIGH -> LOW
; Input      : R16 = Byte whose upper nibble will be sent
;              R18 = RS bit value (0x00 = command, LCD_RS = data)
; =============================================================================
LCD_SEND_NIBBLE:
    PUSH R17

    MOV  R17, R16
    ANDI R17, 0xF0          ; Mask upper nibble

    ; Combine with Backlight and Register Select bits
    OR   R17, R18
    ORI  R17, LCD_BL        ; Backlight active

    ; Transmit with EN = HIGH
    MOV  R16, R17
    ORI  R16, LCD_EN
    RCALL TWI_START
    RCALL TWI_WRITE_ADDR
    RCALL TWI_WRITE
    RCALL TWI_STOP

    ; Transmit with EN = LOW (falling edge latches data into LCD)
    MOV  R16, R17
    ANDI R16, ~LCD_EN
    RCALL TWI_START
    RCALL TWI_WRITE_ADDR
    RCALL TWI_WRITE
    RCALL TWI_STOP

    POP R17
    RET

; =============================================================================
; LCD_SEND_BYTE [INTERNAL]
; Description: Transmits a full 8-bit byte as two 4-bit nibbles.
; Input      : R16 = Byte to send
;              R18 = Mode (0x00 = command, LCD_RS = data)
; =============================================================================
LCD_SEND_BYTE:
    PUSH R17
    PUSH R19

    MOV  R19, R16           ; Save original byte

    ; Send upper nibble (bits 7-4)
    RCALL LCD_SEND_NIBBLE

    ; Swap lower nibble to upper position and send
    MOV  R16, R19
    SWAP R16
    RCALL LCD_SEND_NIBBLE

    ; Short delay for command settling (~40us)
    RCALL LCD_DELAY_SHORT

    POP R19
    POP R17
    RET

; =============================================================================
; LCD_CMD
; Description: Sends a control command byte to LCD (RS = 0).
; Input      : R16 = Command byte
; =============================================================================
LCD_CMD:
    PUSH R18
    LDI  R18, 0x00          ; RS = 0 (Command)
    RCALL LCD_SEND_BYTE
    POP  R18
    RET

; =============================================================================
; LCD_CHAR
; Description: Sends an ASCII character byte to LCD (RS = 1).
; Input      : R16 = ASCII character (e.g. 0x41 = 'A')
; =============================================================================
LCD_CHAR:
    PUSH R18
    LDI  R18, LCD_RS        ; RS = 1 (Data)
    RCALL LCD_SEND_BYTE
    POP  R18
    RET

; =============================================================================
; LCD_STRING
; Description: Prints a null-terminated string from Flash to LCD.
; Input      : ZH:ZL = Pointer to string in Flash
; =============================================================================
LCD_STRING:
    PUSH R16
    PUSH R18

_lcd_string_loop:
    LPM  R16, Z+            ; Load byte from Flash and increment Z
    CPI  R16, 0x00          ; Check for null terminator
    BREQ _lcd_string_done
    RCALL LCD_CHAR
    RJMP _lcd_string_loop

_lcd_string_done:
    POP  R18
    POP  R16
    RET

; =============================================================================
; LCD_GOTOXY
; Description: Moves cursor to specified row and column.
; Input      : R16 = Row (0 = top line, 1 = bottom line)
;              R17 = Column (0-15)
; =============================================================================
LCD_GOTOXY:
    PUSH R16
    PUSH R17
    PUSH R18
    PUSH R19

    CPI  R16, 0
    BREQ _gotoxy_row0
    LDI  R19, LCD_ROW1      ; Line 1 base 0xC0
    RJMP _gotoxy_set
_gotoxy_row0:
    LDI  R19, LCD_ROW0      ; Line 0 base 0x80
_gotoxy_set:
    ADD  R19, R17           ; Add column offset
    MOV  R16, R19
    RCALL LCD_CMD

    POP  R19
    POP  R18
    POP  R17
    POP  R16
    RET

; =============================================================================
; LCD_CLEAR_SCREEN
; Description: Clears LCD DDRAM and resets cursor to home position.
; =============================================================================
LCD_CLEAR_SCREEN:
    PUSH R16
    LDI  R16, LCD_CLEAR
    RCALL LCD_CMD
    RCALL LCD_DELAY_LONG    ; Clear execution takes ~1.52ms
    POP  R16
    RET

; =============================================================================
; LCD_INIT
; Description: Initializes HD44780 controller into 4-bit mode via PCF8574.
;              Must be called ONCE at power-on / system reset.
; =============================================================================
LCD_INIT:
    PUSH R16
    PUSH R17
    PUSH R18

    ; Initialize I2C/TWI hardware
    RCALL TWI_INIT

    ; Wait for power rails to stabilize (>40ms)
    RCALL LCD_DELAY_LONG
    RCALL LCD_DELAY_LONG
    RCALL LCD_DELAY_LONG

    ; Standard HD44780 4-bit startup sequence
    ; Step 1: Send 0x30 nibble
    LDI  R16, 0x30
    LDI  R18, 0x00
    RCALL LCD_SEND_NIBBLE
    RCALL LCD_DELAY_LONG    ; Wait >4.1ms

    ; Step 2: Send 0x30 nibble again
    LDI  R16, 0x30
    RCALL LCD_SEND_NIBBLE
    RCALL LCD_DELAY_SHORT   ; Wait >100us

    ; Step 3: Send 0x30 nibble third time
    LDI  R16, 0x30
    RCALL LCD_SEND_NIBBLE
    RCALL LCD_DELAY_SHORT

    ; Step 4: Switch to 4-bit mode by sending 0x20
    LDI  R16, 0x20
    RCALL LCD_SEND_NIBBLE
    RCALL LCD_DELAY_SHORT

    ; Now in 4-bit mode: send complete configuration commands
    ; Function Set: 4-bit, 2 lines, 5x8 font
    LDI  R16, LCD_4BIT_2LINE
    RCALL LCD_CMD

    ; Display OFF
    LDI  R16, 0x08
    RCALL LCD_CMD

    ; Clear Display
    LDI  R16, LCD_CLEAR
    RCALL LCD_CMD
    RCALL LCD_DELAY_LONG

    ; Entry Mode Set: Increment cursor, no display shift
    LDI  R16, LCD_ENTRY_MODE
    RCALL LCD_CMD

    ; Display ON, cursor OFF, blink OFF
    LDI  R16, LCD_DISPLAY_ON
    RCALL LCD_CMD

    POP  R18
    POP  R17
    POP  R16
    RET

; =============================================================================
; LCD_DELAY_SHORT [INTERNAL]
; Description: Delay ~200us @ 16 MHz.
; =============================================================================
LCD_DELAY_SHORT:
    PUSH R16
    PUSH R17
    LDI  R17, 10
_dshort_outer:
    LDI  R16, 0xFF
_dshort_inner:
    DEC  R16
    BRNE _dshort_inner
    DEC  R17
    BRNE _dshort_outer
    POP  R17
    POP  R16
    RET

; =============================================================================
; LCD_DELAY_LONG [INTERNAL]
; Description: Delay ~5ms @ 16 MHz.
; =============================================================================
LCD_DELAY_LONG:
    PUSH R16
    PUSH R17
    LDI  R17, 0xFF
_dlong_outer:
    LDI  R16, 0xFF
_dlong_inner:
    DEC  R16
    BRNE _dlong_inner
    DEC  R17
    BRNE _dlong_outer
    POP  R17
    POP  R16
    RET
