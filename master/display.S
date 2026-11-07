; =============================================================================
; FILE: display.S
; DESCRIPTION: Main display rendering engine - updates all LCD elements.
;
; DEPENDENCIES (must be #included in this exact order):
;   1. lcd_i2c.S
;   2. lcd_driver.S
;   3. lookup_table.S
;   4. bcd_ascii.S
;   5. mapping.S
;   6. display.S  <-- This file, ALWAYS LAST
;
; PUBLIC API:
;   UPDATE_DISPLAY  -> Main routine invoked from main.S upon new frequency data.
;   DISPLAY_STARTUP -> Shows splash screen on boot.
;
; LCD 16x2 LAYOUT:
;   Line 0: "{Target_Name} {Target_Hz}Hz {Status}" (e.g. "E2 082Hz loosen ")
;   Line 1: "{Current_Name} {Current_Hz}Hz      " (e.g. "E#2 083Hz       ")
;
; INPUT REGISTERS:
;   R25 = High Byte of measured Hz
;   R24 = Low Byte of measured Hz
;   R23 = Target string index (0=E2, 1=A2, 2=D3, 3=G3, 4=B3, 5=E4)
; =============================================================================

#define __SFR_OFFSET 0x00
#include "avr/io.h"

; Short flash string literals for units and clearing
_str_hz_space:  .ascii "Hz "
                .byte 0
_str_hz_clear:  .ascii "Hz       "
                .byte 0

; =============================================================================
; UPDATE_DISPLAY
; Description: Renders target string, target Hz, tuning status, detected note,
;              and measured frequency onto the 16x2 LCD.
; Input      : R25:R24 = Measured Hz
;              R23     = Target string index (0-5)
; Output     : None
; Clobbers   : None (all registers preserved via PUSH/POP)
; =============================================================================
UPDATE_DISPLAY:
    PUSH R16
    PUSH R17
    PUSH R23
    PUSH R24
    PUSH R25
    PUSH ZH
    PUSH ZL
    PUSH R20
    PUSH R21

    ; =========================================================
    ; LINE 0: "{T_NAME} {T_HZ}Hz {STATUS}"
    ; =========================================================

    ; --- Column 0: Target Name ---
    LDI  R16, 0
    LDI  R17, 0
    RCALL LCD_GOTOXY
    RCALL GET_TARGET_BOUNDS     ; Z = pointer to target note name (e.g. "E2")
    RCALL LCD_STRING

    ; --- Column 2: Blank separator space ---
    LDI  R16, 0
    LDI  R17, 2
    RCALL LCD_GOTOXY
    LDI  R16, ' '
    RCALL LCD_CHAR

    ; --- Column 3: Target Frequency (Hz) ---
    LDI  R16, 0
    LDI  R17, 3
    RCALL LCD_GOTOXY
    
    ; Load exact target Hz from TARGET_EXACT_HZ based on string index R23
    LDI  ZH, hi8(TARGET_EXACT_HZ)
    LDI  ZL, lo8(TARGET_EXACT_HZ)
    ; offset = R23 * 2
    MOV  R16, R23
    LSL  R16
    ADD  ZL, R16
    CLR  R16
    ADC  ZH, R16
    LPM  R20, Z+                 ; Target Hz Low Byte
    LPM  R21, Z                  ; Target Hz High Byte
    
    ; Temporarily swap R25:R24 to print target Hz
    MOV  R16, R24
    MOV  R17, R25
    MOV  R24, R20
    MOV  R25, R21
    RCALL PRINT_HZ
    
    ; Restore actual measured current Hz
    MOV  R24, R16
    MOV  R25, R17

    ; --- Column 6: "Hz " ---
    LDI  R16, 0
    LDI  R17, 6
    RCALL LCD_GOTOXY
    LDI  ZH, hi8(_str_hz_space)
    LDI  ZL, lo8(_str_hz_space)
    RCALL LCD_STRING

    ; --- Column 9: Tuning Status Message ---
    LDI  R16, 0
    LDI  R17, 9
    RCALL LCD_GOTOXY
    RCALL GET_STATUS            ; Z = pointer to status string (7 chars padded)
    RCALL LCD_STRING

    ; =========================================================
    ; LINE 1: "{CURRENT_NAME} {CURRENT_HZ}Hz       "
    ; =========================================================

    ; Clear columns 2 and 3 to handle 2-char vs 3-char note name differences (e.g. E2 vs E#2)
    LDI  R16, 1
    LDI  R17, 2
    RCALL LCD_GOTOXY
    LDI  R16, ' '
    RCALL LCD_CHAR
    LDI  R16, 1
    LDI  R17, 3
    RCALL LCD_GOTOXY
    LDI  R16, ' '
    RCALL LCD_CHAR

    ; --- Column 0: Current Detected Note Name ---
    LDI  R16, 1
    LDI  R17, 0
    RCALL LCD_GOTOXY
    
    ; Find note based on measured Hz in R25:R24
    RCALL FIND_NOTE             ; Z = pointer to note name, R26 = index
    RCALL LCD_STRING

    ; --- Column 4: Current Frequency (Hz) ---
    LDI  R16, 1
    LDI  R17, 4
    RCALL LCD_GOTOXY
    RCALL PRINT_HZ              ; Print actual measured Hz from R25:R24

    ; --- Column 7: "Hz       " (also clears trailing artifacts) ---
    LDI  R16, 1
    LDI  R17, 7
    RCALL LCD_GOTOXY
    LDI  ZH, hi8(_str_hz_clear)
    LDI  ZL, lo8(_str_hz_clear)
    RCALL LCD_STRING

    POP  R21
    POP  R20
    POP  ZL
    POP  ZH
    POP  R25
    POP  R24
    POP  R23
    POP  R17
    POP  R16
    RET

; =============================================================================
; DISPLAY_STARTUP [OPTIONAL]
; Description: Displays boot splash screen on LCD initialization.
; =============================================================================
_str_startup1: .ascii "  Audio Tuner   "
               .byte 0
_str_startup2: .ascii " Initializing.. "
               .byte 0

DISPLAY_STARTUP:
    PUSH R16
    PUSH R17
    PUSH ZH
    PUSH ZL

    LDI  R16, 0
    LDI  R17, 0
    RCALL LCD_GOTOXY

    LDI  ZH, hi8(_str_startup1)
    LDI  ZL, lo8(_str_startup1)
    RCALL LCD_STRING

    LDI  R16, 1
    LDI  R17, 0
    RCALL LCD_GOTOXY

    LDI  ZH, hi8(_str_startup2)
    LDI  ZL, lo8(_str_startup2)
    RCALL LCD_STRING

    ; Startup display delay (~1 second in simulation)
    LDI  R16, 82
_startup_wait:
    RCALL LCD_DELAY_LONG
    DEC  R16
    BRNE _startup_wait

    POP  ZL
    POP  ZH
    POP  R17
    POP  R16
    RET
