; =============================================================================
; FILE: bcd_ascii.S
; DESCRIPTION: 16-bit binary integer to decimal ASCII converter.
;              Used to render real-time measured frequency (Hz) onto the LCD.
;
; DEPENDENCY: lcd_driver.S must be #included BEFORE this file.
;
; PUBLIC FUNCTIONS:
;   PRINT_HZ        -> Prints Hz value from R25:R24 directly to LCD.
;                      Output format: "XXX" (3 digits, zero-padded, max 999).
;                      Cursor position must be preset using LCD_GOTOXY.
;   PRINT_STR_FLASH -> Prints null-terminated string from Flash pointed by Z.
;
; FREQUENCY RANGE:
;   Target guitar range E2 (82 Hz) to E4 (330 Hz) fits within 3 decimal digits.
;
; ALGORITHM:
;   Repeated subtraction division:
;   1. Divide Hz by 100 -> hundreds digit
;   2. Remainder divided by 10 -> tens digit
;   3. Remainder -> units digit
;   4. Convert each digit to ASCII (+0x30) and output to LCD.
; =============================================================================

#define __SFR_OFFSET 0x00
#include "avr/io.h"

; =============================================================================
; DIV16_100 [INTERNAL]
; Description: Divides R25:R24 by 100.
; Input      : R25:R24 = dividend
; Output     : R20     = quotient (hundreds digit)
;              R25:R24 = remainder
; Clobbers   : Preserves R18, R19 via PUSH/POP
; =============================================================================
DIV16_100:
    PUSH R18
    PUSH R19

    CLR  R20                ; quotient = 0

_div100_loop:
    LDI  R18, lo8(100)
    LDI  R19, hi8(100)     ; R19:R18 = 100

    SUB  R24, R18
    SBC  R25, R19           ; subtract with borrow

    BRCS _div100_done       ; exit on carry/negative

    INC  R20
    RJMP _div100_loop

_div100_done:
    ; Restore last overdraft subtraction
    ADD  R24, R18
    ADC  R25, R19

    POP  R19
    POP  R18
    RET

; =============================================================================
; DIV16_10 [INTERNAL]
; Description: Divides R25:R24 by 10.
; Input      : R25:R24 = remainder from DIV16_100 (0-99)
; Output     : R21     = quotient (tens digit)
;              R25:R24 = remainder (units digit, 0-9)
; Clobbers   : Preserves R18, R19 via PUSH/POP
; =============================================================================
DIV16_10:
    PUSH R18
    PUSH R19

    CLR  R21                ; quotient = 0

_div10_loop:
    LDI  R18, lo8(10)
    LDI  R19, hi8(10)      ; R19:R18 = 10

    SUB  R24, R18
    SBC  R25, R19

    BRCS _div10_done

    INC  R21
    RJMP _div10_loop

_div10_done:
    ; Restore last overdraft subtraction
    ADD  R24, R18
    ADC  R25, R19

    POP  R19
    POP  R18
    RET

; =============================================================================
; PRINT_HZ
; Description: Converts 16-bit Hz value to 3-digit ASCII and writes to LCD.
;              Output format: "XXX" (zero-padded, e.g. "082", "110", "330")
; Input      : R25:R24 = frequency in Hz (0-999)
; Output     : None (drawn directly to LCD)
; Clobbers   : None (all registers safely saved/restored)
; =============================================================================
PRINT_HZ:
    PUSH R16
    PUSH R18
    PUSH R19
    PUSH R20
    PUSH R21
    PUSH R24
    PUSH R25

    ; --- Step 1: Extract hundreds digit ---
    RCALL DIV16_100         ; R20 = hundreds, R25:R24 = remainder

    ; --- Step 2: Extract tens digit ---
    RCALL DIV16_10          ; R21 = tens, R25:R24 = remainder

    ; --- Step 3: Units digit is remaining R24 ---

    ; --- Step 4: Convert to ASCII and print ---
    ; Hundreds digit
    MOV  R16, R20
    ORI  R16, 0x30          ; Add 0x30 -> ASCII ('0' = 0x30)
    RCALL LCD_CHAR

    ; Tens digit
    MOV  R16, R21
    ORI  R16, 0x30
    RCALL LCD_CHAR

    ; Units digit
    MOV  R16, R24
    ORI  R16, 0x30
    RCALL LCD_CHAR

    POP  R25
    POP  R24
    POP  R21
    POP  R20
    POP  R19
    POP  R18
    POP  R16
    RET

; =============================================================================
; PRINT_STR_FLASH [PUBLIC HELPER]
; Description: Prints a null-terminated string stored in Flash memory.
; Input      : ZH:ZL = Pointer to string in Flash
; Output     : None
; Clobbers   : Z pointer increments through the string
; =============================================================================
PRINT_STR_FLASH:
    RCALL LCD_STRING
    RET
