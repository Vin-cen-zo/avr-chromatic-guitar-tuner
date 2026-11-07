; =============================================================================
; FILE: mapping.S
; DESCRIPTION: Note lookup algorithms and guitar tuning status evaluation logic.
;
; DEPENDENCIES (must be #included prior to this file):
;   - lcd_i2c.S      (TWI primitives)
;   - lcd_driver.S   (LCD driver routines)
;   - lookup_table.S (NOTE_TABLE, GUITAR_STRINGS, note limits)
;   - bcd_ascii.S    (PRINT_HZ)
;
; PUBLIC API:
;   FIND_NOTE   -> Performs linear search on NOTE_TABLE based on R25:R24 (Hz).
;                  Returns index in R26 and Flash string pointer in Z.
;   GET_STATUS  -> Determines tuning state: TOO LOOSE / NICE / TOO TIGHT
;                  by comparing measured Hz with target guitar string frequency.
; =============================================================================

#define __SFR_OFFSET 0x00
#include "avr/io.h"

; =============================================================================
; FIND_NOTE
; Description: Searches NOTE_TABLE to locate the musical note containing the
;              current measured frequency in R25:R24.
; Input      : R25:R24 = Measured frequency in Hz
; Output     : R26     = Note index in NOTE_TABLE (0 to 24), or 0xFF if out of range
;              Z       = Flash pointer to note name string (or STR_UNKNOWN)
; Clobbers   : Preserves R16-R21
; =============================================================================
FIND_NOTE:
    PUSH R16
    PUSH R17
    PUSH R18
    PUSH R19
    PUSH R20
    PUSH R21

    ; Initialize Z pointer to start of NOTE_TABLE
    LDI  ZH, hi8(NOTE_TABLE)
    LDI  ZL, lo8(NOTE_TABLE)

    CLR  R26                    ; Note index counter starting at 0

_find_loop:
    ; Check if all 25 notes have been scanned
    CPI  R26, NOTE_COUNT
    BREQ _find_not_found

    ; Read lower bound from Flash (2 bytes, little-endian)
    LPM  R18, Z+                ; Lower bound low byte
    LPM  R19, Z+                ; Lower bound high byte

    ; Read upper bound from Flash (2 bytes)
    LPM  R20, Z+                ; Upper bound low byte
    LPM  R21, Z+                ; Upper bound high byte

    ; Read name pointer from Flash (2 bytes)
    LPM  R16, Z+                ; Name pointer low byte
    LPM  R17, Z+                ; Name pointer high byte

    ; Skip 2 bytes padding
    LPM  R0,  Z+
    LPM  R0,  Z+

    ; Check if measured Hz >= lower_bound
    MOV  R0,  R24
    SUB  R0,  R18
    MOV  R0,  R25
    SBC  R0,  R19
    BRCS _find_next             ; Carry set -> Hz < lower_bound

    ; Check if measured Hz <= upper_bound
    MOV  R0,  R20
    SUB  R0,  R24
    MOV  R0,  R21
    SBC  R0,  R25
    BRCS _find_next             ; Carry set -> Hz > upper_bound

    ; Note match found: point Z to note name
    MOV  ZL, R16
    MOV  ZH, R17
    RJMP _find_done

_find_next:
    INC  R26
    RJMP _find_loop

_find_not_found:
    LDI  R26, 0xFF              ; Out of range flag
    LDI  ZH, hi8(STR_UNKNOWN)
    LDI  ZL, lo8(STR_UNKNOWN)

_find_done:
    POP  R21
    POP  R20
    POP  R19
    POP  R18
    POP  R17
    POP  R16
    RET

; =============================================================================
; GET_TARGET_BOUNDS
; Description: Retrieves frequency bounds and name pointer for the active
;              target string index specified by R23 (0 to 5).
; Input      : R23     = String index (0=E2, 1=A2, 2=D3, 3=G3, 4=B3, 5=E4)
; Output     : R18:R19 = Target lower bound
;              R20:R21 = Target upper bound
;              Z       = Flash pointer to target note name string
; =============================================================================
GET_TARGET_BOUNDS:
    PUSH R16
    PUSH R17

    ; Resolve R23 to NOTE_TABLE index via GUITAR_STRINGS table
    LDI  ZH, hi8(GUITAR_STRINGS)
    LDI  ZL, lo8(GUITAR_STRINGS)

    ADD  ZL, R23
    CLR  R16
    ADC  ZH, R16

    LPM  R16, Z                 ; R16 = NOTE_TABLE index (0, 5, 10, 15, 19, 24)

    ; Calculate byte offset: index * 8
    LSL  R16
    LSL  R16
    LSL  R16

    LDI  ZH, hi8(NOTE_TABLE)
    LDI  ZL, lo8(NOTE_TABLE)
    ADD  ZL, R16
    CLR  R17
    ADC  ZH, R17

    ; Load bounds and name pointer
    LPM  R18, Z+                ; Lower bound low byte
    LPM  R19, Z+                ; Lower bound high byte
    LPM  R20, Z+                ; Upper bound low byte
    LPM  R21, Z+                ; Upper bound high byte
    LPM  R16, Z+                ; Name pointer low byte
    LPM  R17, Z+                ; Name pointer high byte

    MOV  ZL, R16
    MOV  ZH, R17

    POP  R17
    POP  R16
    RET

; =============================================================================
; GET_STATUS
; Description: Compares measured Hz against target string pitch.
;              Evaluates to: TOO LOOSE, NICE, or TOO TIGHT.
; Input      : R25:R24 = Measured frequency in Hz
;              R23     = Target string index (0-5)
; Output     : Z       = Flash pointer to status string (STR_TOO_LOOSE, STR_NICE, STR_TOO_TIGHT)
; =============================================================================
GET_STATUS:
    PUSH R16
    PUSH R17
    PUSH R18
    PUSH R19
    PUSH R20
    PUSH R21

    ; Fetch target reference Hz from TARGET_EXACT_HZ
    LDI  ZH, hi8(TARGET_EXACT_HZ)
    LDI  ZL, lo8(TARGET_EXACT_HZ)
    MOV  R16, R23
    LSL  R16
    ADD  ZL, R16
    CLR  R17
    ADC  ZH, R17
    LPM  R18, Z+             ; Target exact Hz low byte
    LPM  R19, Z              ; Target exact Hz high byte

    ; Lower tolerance threshold = Exact Hz - 2 Hz
    MOV  R20, R18
    MOV  R21, R19
    SUBI R18, 2
    SBCI R19, 0

    ; Upper tolerance threshold = Exact Hz + 2 Hz
    SUBI R20, -2
    SBCI R21, -1

    ; Check if measured Hz < Lower threshold -> LOOSEN
    MOV  R16, R24
    SUB  R16, R18
    MOV  R16, R25
    SBC  R16, R19
    BRCS _status_too_loose

    ; Check if measured Hz > Upper threshold -> TIGHTEN
    MOV  R16, R20
    SUB  R16, R24
    MOV  R16, R21
    SBC  R16, R25
    BRCS _status_too_tight

    ; In-tune -> NICE
_status_nice:
    LDI  ZH, hi8(STR_NICE)
    LDI  ZL, lo8(STR_NICE)
    RJMP _status_done

_status_too_loose:
    LDI  ZH, hi8(STR_TOO_LOOSE)
    LDI  ZL, lo8(STR_TOO_LOOSE)
    RJMP _status_done

_status_too_tight:
    LDI  ZH, hi8(STR_TOO_TIGHT)
    LDI  ZL, lo8(STR_TOO_TIGHT)

_status_done:
    POP  R21
    POP  R20
    POP  R19
    POP  R18
    POP  R17
    POP  R16
    RET
