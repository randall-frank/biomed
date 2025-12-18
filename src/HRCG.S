
* Original source from:  https://github.com/ursetto/a2-hrcg-teardown
* Thanks to Jim Ursetto!

* Basically a reconstructed version of HRCG from the Apple DOS toolkit.
* I needed a version that worked with ProDOS.  Starting from Jim's work,
* I made a number of modifications/simplifications to insert the engine
* between the ProDOS BI and its buffers with room for 2 typefaces (11 pages)
* and modified the CSW and KSW connections to follow ProDOS.  Note,
* the use of things like pr# and in# could easily disconnect it.

blink_delay     =     $50       ;cursor blink delay
MON_WNDLEFT     =     $20               ;left column of scroll window
MON_WNDWDTH     =     $21               ;width of scroll window
MON_WNDTOP      =     $22               ;top of scroll window
MON_WNDBTM      =     $23               ;bottom of scroll window
MON_CH          =     $24               ;cursor horizontal displacement
MON_CV          =     $25               ;cursor vertical displacement
MON_BASL        =     $28               ;base address for text output (lo)
MON_BASH        =     $29               ;base address for text output (hi)
MON_CSWL        =     $36               ;character output hook (lo)
MON_CSWH        =     $37               ;character output hook (hi)
MON_KSWL        =     $38               ;character input hook (lo)
MON_KSWH        =     $39               ;character input hook (hi)
MON_RNDL        =     $4e               ;low byte of KEYIN "random" value
MON_RNDH        =     $4f               ;high byte of KEYIN "random" value
DOS_CHARIO      =     $03ea             ;jumps to routine that connects DOS KSW/CSW
KBD             =     $c000             ;R last key pressed + 128
KBDSTRB         =     $c010             ;RW keyboard strobe
TXTCLR          =     $c050             ;RW display graphics
MIXCLR          =     $c052             ;RW display full screen
TXTPAGE1        =     $c054             ;RW display page 1
TXTPAGE2        =     $c055             ;RW display page 2 (or read/write aux mem)
HIRES           =     $c057             ;RW display hi-res graphics
MON_BELL        =     $fbdd             ;Sound bell unconditionally
MON_VTAB        =     $fc22             ;tab to row specified in Acc
MON_VTABZ       =     $fc24
MON_CLREOP      =     $fc42             ;clear screen from cursor to end of page
MON_HOME        =     $fc58             ;clear screen and reset text output to top-left
MON_SCROLL      =     $fc70             ;scroll up one line
MON_CLREOL      =     $fc9c             ;clear to end of line
MON_COUT        =     $fded             ;print Acc to output device via $36-37

* ProDOS specific entry points

VECTIN          =     $be32             ; KSWL
VECTOUT         =     $be30             ; CSWL
GETBUFR         =     $bef5             ; Allocate a basic.system buffer

                          ; code addr is $8f00
                          ; file load addr is $2100 to work with HRCG.INST
                org   $8f00
                dsk   ../bin/HRCG#062100
                typ   $06        ; /BIN file

hgr_entry       jmp    setuphgr1   ; $8f00 - hgr1
hgr2_entry      jmp    setuphgr2   ; $8f03 - hgr2
reconnect       jmp    connect     ; $8f06 - reconnect I/O

; Poked by the loader to point to the first alternate charset.
; As this defaults to the builtin charset, both ^A 0 and ^A 1
; will display the builtin charset if no alternates are loaded.
first_charset   da    builtin_charset

setuphgr2       lda     #$40           ; $8f05 - hgr2
                sta     hires_page
setuphgr1       jsr     connect
                bit     MIXCLR            ;select full screen graphics
                bit     HIRES             ;select hires graphics
                jsr     set_defaults
                jsr     showpage
                jsr     clear_gfx
                bit     TXTCLR            ;actually enable graphics mode
                rts

connect         lda     #<ksw_handler
                sta     VECTIN    ; MON_KSWL
                lda     #>ksw_handler
                sta     VECTIN+1  ; MON_KSWH
                lda     #<csw_handler
                sta     VECTOUT   ; MON_CSWL
                lda     #>csw_handler
                sta     VECTOUT+1 ; MON_CSWH
                rts

clear_gfx       lda     hires_page
                sta     bytes+2
                lda     #0
                sta     bytes+1
                lda     #0
                ldy     #$20
bytes           sta     $ffff
                inc     bytes+1
                bne     bytes
                inc     bytes+2
                dey
                bne     bytes
                rts

esc_state       dfb    $00
key_state       dfb    $00               ;keypress state. $80 after ^A, $40 after ^O, or $00
hires_page      dfb    $20               ;$20 (hires1) or $40 (hires2)
inverse_video   dfb    $00               ;$7f if inverse video active, $00 otherwise

       ; NOTE: Looks like a bitfield. If bit 7 ($80) is set, character will overstrike
       ; (i.e. the background is ignored). If bit 6 ($40) is set, character will
       ; complement (in the shape of its fg or bg).  Apparently, "overstrike" and
       ; "transparent" modes ($80) are identical except sourcing from different pages; so
       ; are "complement" and "reverse" ($C0) modes. They are probably named in this odd
       ; way for mnemonic reasons, matching their control chars.

transparent_mode dfb   $00               ;$80=overstrike, $C0=complement, $00=no mask
overlay_mode    dfb    $00               ;$60 to use second screen for overlay (^O ^T/^R)
wrap_mode       dfb    $00               ;$FF if wrap mode, $00 if scroll
lower_case      dfb    $00               ;$80=lower case, $00=upper
active_charset  da    builtin_charset   ;pointer to active charset
var_save        ds   8                 ;save 8 bytes above during block mode
block_mode      dfb    $00               ;$ff=block mode on, $00=off
block_ch        dfb    $00               ;home col in block mode, or else $00
block_cv        dfb    $00               ;home row in block mode, or else $00
; 
; KSW handler
; 
; Wait for a keypress, blinking the cursor (an underscore) while waiting. The
; "random" KEYIN value is updated similarly to the monitor ROM, though at a
; different rate. Also handle ESC state and commands.
; 
; On entry, A is the char that was present on the text screen (the caller may
; have overwritten it with a cursor, and standard KSW restores it). Y is the
; horizontal cursor position (MON_CH).
; 
; On exit, A is the key pressed. X and Y are preserved.
; 
basl            =    $2a  
bash            =    $2b

ksw_handler     sta     (MON_BASL),y      ;restore char to text screen
                stx     saveX             ;we reuse X as a counter
                lda     MON_BASL          ;text screen low byte conveniently
                sta     basl              ;matches low byte for hires line text*8
                lda     MON_BASH          ;convert text screen hi byte to hires line
                ora     #$1c              ;text 04..07 -> 1C..1F
                ora     hires_page        ;-> 3C..3F (page 1) or 5C..5F (page 2) 
                sta     bash              ;== 7th line of each 8-line char
                ldx     #$01              ;initial countdown -- invert almost immediately
                lda     (basl),y          ;grab the 7th (cursor) line to invert it
                pha                       ;also save it on the stack
@jiffy          inc     MON_RNDL          ;count up "random" KEYIN value 0000..FFFF
                bne     @checkkey         ;check for 8-bit wrap
                inc     MON_RNDH          ;and propagate to high byte
                dex                       ;did we cycle to $FFFF X times?
                bne     @checkkey         ;no, not yet time to invert cursor
; Blink the cursor.
                eor     #$7f              ;invert cursor line
                sta     (basl),y          ;and write it to screen
                ldx     #blink_delay      ;countdown until next invert
@checkkey       bit     KBD               ;key pressed?
                bpl     @jiffy            ;no, continue cycling
                pla                       ;an eternity later, a key is pressed
                sta     (basl),y          ;restore the original 7th line
                tsx
       ; NOTE: TODO -- why stack lookbehind? checking to see if we were called from ROM routines???
                lda     $0104,x           ;??
                cmp     #$f8              ;??
                lda     KBD               ;get keypress
                bit     KBDSTRB           ;clear keyboard strobe
                bcc     @doneX            ;if stack value < $f8 (BIT preserved carry)
                pha                       ;save keypress
                bit     esc_state         ;esc flag (bit 7) set earlier?
                bmi     esc_char          ;yes, this is ESC arg
                cmp     #$9b              ;ESC pressed now?
                bne     @check_cr
                lda     #$80              ;yes, ESC pressed
                sta     esc_state         ;set ESC flag for next time
                bne     @doneA            ;always
@check_cr       cmp     #$8d              ;return pressed?
                bne     @doneA
                jsr     clear_hv_eol
       ; NOTE: Need to verify MON_CH is not updated. It's not clear it's absolutely
       ; necessary to restore Y based on the ROM. In particular, look at ESC-@ and cursor
       ; movement.
@doneY          ldy     MON_CH            ;restore Y (horiz pos)
@doneA          pla                       ;restore A (the keypress)
@doneX          ldx     saveX             ;restore X
                rts
; Handle key pressed in escape mode (in accumulator).
esc_char        cmp     #$C9 ; 'I' | $80
                bcc     not_esc_ijkm
                cmp     #$CD ; 'M' | $80
                beq     esc_c_or_m
                bcs     not_esc_ijkm
                cmp     #$CB ;'K' | $80
                beq     esc_a_or_k
       ; NOTE: How does doing nothing work for ESC J?
                bcc     @doneA            ;'J' -- do nothing
; Keypress is not IJKM (cursor keys). Disable ESC state going forward.
not_esc_ijkm    asl     esc_state         ;disable escape state ($80->$00)
                cmp     #$C0 ; '@'' | $80        ;ESC-@ ?
                bne     not_esc_null
                jsr     clear_home
                jmp     @doneY
not_esc_null    cmp     #$C5 ; 'E' | $80
                bne     not_esc_e
                jsr     clear_hv_eol
                jmp     @doneY
not_esc_e       cmp     #$C6 ; 'F' | $80
                bne     not_esc_f
                jsr     clear_hv_eowin
                jmp     @doneY
not_esc_f       cmp     #$C3 ; 'C' | $80
                beq     esc_c_or_m
                cmp     #$C1 ; 'A' | $80
                bne     @doneA
; After ESC, ABCD and IJKM are cursor movement synonyms, except ABCD exits
; escape mode after one keypress, and IJKM remains in escape mode.
esc_a_or_k      iny
                cpy     MON_WNDWDTH
                bcc     @doneY
esc_c_or_m      ldy     MON_CV
                iny
                cpy     MON_WNDBTM
                bcc     @doneY
                jsr     scroll
                jmp     @doneY
saveY           =    $35     ;preserve Y
saveX           =    $eb     ;preserve X
saveA           =    $ff     ;preserve A
csw_handler     sta     saveA             ;preserve A/X/Y
                stx     saveX
                sty     saveY
                jsr     @csw1
                ldy     saveY
                ldx     saveX
                lda     saveA
                rts
@csw1           and     #$7f
                asl     key_state         ;was set to $80 by Ctrl-A keypress
                bcs     ctrl_a_arg        ;so if carry set after ASL, key is arg to Ctrl-A
                cmp     #$20              ;control char 00..1f
                bcc     control_char
                jmp     draw_char         ;draw char to screen, probably
; Control char 00..1f encountered in output string. Jump to corresponding
; function in table if 00..1a (@-Z), or do nothing (?) if 1b..1f. Note Ctrl-@ is
; not documented.
control_char    cmp     #$1b
                bcs     @ret              ;1b..1f are not operations
                asl     A                 ;offset is 2*jump entry
                tax
                lda     function_table+1,x ;put jump table entry on stack
                pha
                lda     function_table,x  ;for jump via RTS
                pha
@ret            asl     key_state         ;sets carry if contained $80
                rts                       ;execute function 00..1b
; Jump table used by previous subroutine to handle control character input (with
; low byte -1 for RTS adjustment). Function names are based on the toolkit
; documentation, with the control char ("CB" for ^B) prepended. This is a state
; machine and a couple chars only have meaning after a ^O; those have e.g. "COR"
; for ^O ^R prepended.
function_table  da    return-1          ;^@ -- noop
                da    CA_select_charset-1 ;^A -- select charset
                da    CB_begin_block-1
                da    CC_carriage_return-1
                da    CD_delimit_block-1
                da    CE_clear_eol-1
                da    CF_clear_eop-1
                da    MON_BELL-1        ;^G -- sound bell
                da    CH_backspace-1    ;^H move cursor left (no rubout)
                da    CI_inverse_video-1 ; ^I
                da    CJ_linefeed-1
                da    CK_caps_lock-1
                da    CL_lower_case-1
                da    CM_unknown?-1
                da    CN_normal_video-1 ; ^N
                da    CO_option_sel-1   ; ^O
                da    CP_clear_page-1   ; ^P
                da    CQ_home_cursor-1  ; ^Q
                da    COR_reverse-1
                da    CS_shift-1
                da    COT_transparent-1
                da    return-1          ;Ctrl-U -- noop
                da    CV_textwin_ul-1
                da    CW_textwin_lr-1
                da    return-1          ;Ctrl-X -- noop
                da    CY_textwin_full-1
                da    CZ_restore_default-1
; Ctrl-A -- select charset.
CA_select_charset bcs   COA_primary_hires1 ;^O ^A -- primary screen 1
                lda     #$80              ;set flag indicating Ctrl-A was pressed
                sta     key_state
                rts
; 
; Process ^A argument, the charset number to activate. Anything other than 1..9
; selects the builtin charset. 1 selects the lowest charset in memory, 2 selects
; lowest + $0300, and so on.
; 
; There is no further bounds check on the charset number, so if you select
; charset 4 when 3 are loaded, you will get garbage. (Since LOADHRCG loads
; charsets directly below HRCG, charsets 4 and 5 would be HRCG code and charset
; 6 is $100 into the builtin charset, which effectively shifts uppercase to
; lowercase!)
; 
temp            =    $ee                  ;temp for multiply by 3
ctrl_a_arg      sbc     #$31              ;convert digit 1..9 ($31..39) to $00..$08
                cmp     #$09              ;check if char was < 1 or > 9
                bcs     use_builtin_fnt   ;via unsigned cmp >= $09, so $00..$08 are valid
                ldx     first_charset     ;X = low byte of lowest charset in memory
                sta     temp              ;now compute page offset; 3 pages per charset
                asl     A
                adc     temp              ;A = A * 3 via temp
                adc     first_charset+1   ;A = high byte of desired charset
                bne     @update_charset   ;questionable -- tests for zero page?
use_builtin_fnt ldx     #<builtin_charset ;select builtin charset, usually when 0 pressed
                lda     #>builtin_charset
@update_charset stx     active_charset
                sta     active_charset+1
                rts
COA_primary_hires1 lda  #$20              ;write to hires 1 ($2000) now
                sta     hires_page
                rts
CB_begin_block  bcs     COB_primary_hires2
                bit     block_mode
                bmi     L8FC2
                lda     #$ff
                sta     block_mode
                ldy     #$07              ;length of variable area
L8FB9           lda     hires_page,y      ;save variables
                sta     var_save,y        ;for when we delimit block
                dey
                bpl     L8FB9
L8FC2           lda     MON_CH
                sta     block_ch
                lda     MON_CV
                sta     block_cv
                rts
COB_primary_hires2 lda  #$40              ;write to hires 2 ($4000) now
                sta     hires_page
                rts
CC_carriage_return bcs  COC_complement    ;^O ^C -- complement
                lda     block_ch
                cmp     MON_CH
                sta     MON_CH
                beq     L8FE0
                bcs     return
L8FE0           jmp     CJ_linefeed
COC_complement  lda     #$c0
                sta     transparent_mode
                lda     #$00
                sta     overlay_mode
                rts
CD_delimit_block bcs    showpage
                bit     block_mode
                bpl     return
                ldy     #$07              ;length of variable area
L8FF7           lda     var_save,y        ;restore original variables
                sta     hires_page,y      ;saved during block begin
                dey
                bpl     L8FF7
                lda     #$00
                sta     block_mode
                sta     block_ch
                lda     MON_WNDTOP
                sta     block_cv
                rts
showpage        bit     TXTPAGE1            ; Display HGR1 or HGR2
                lda     hires_page
                cmp     #$40
                bne     return
                bit     TXTPAGE2
                rts
CE_clear_eol    bcs     return
                jsr     clear_hv_eol
                jmp     MON_CLREOL        ;sync the text screen
; Ctrl-F -- clear to end of page.
CF_clear_eop    bcs     return
                jsr     clear_hv_eowin
                jmp     MON_CLREOP        ;sync the text screen
; Move the cursor backward one space.
CH_backspace    dec     MON_CH
                bpl     return
                lda     MON_WNDWDTH
                sta     MON_CH
                dec     MON_CH
                lda     MON_WNDTOP
                cmp     MON_CV
                bcs     return
                dec     MON_CV
                jmp     MON_VTAB
CI_inverse_video bcs    return
                lda     #$7f
                sta     inverse_video
return          rts
CK_caps_lock    bcs     return
                lda     #$00
                sta     lower_case
                rts
CL_lower_case   bcs     return
                lda     #$80
                sta     lower_case
                rts
CM_unknown?     ldy     KBD
                bpl     L9071
                cpy     #$93
                bne     L9071
                bit     KBDSTRB
L9065           ldy     KBD
                bpl     L9065
                cpy     #$83
                beq     L9071
                bit     KBDSTRB
L9071           jmp     cr_lf
CN_normal_video bcs     return            ;^O ^N -- unused
                lda     #$00
                sta     inverse_video
                rts
CO_option_sel   bcs     set_overstrike    ;second ^O -- overstrike
                lda     #$40              ;first ^O -- record in state machine
                sta     key_state
                rts
set_overstrike  lda     #$80
                sta     transparent_mode
                lda     #$00
                sta     overlay_mode
                rts
CP_clear_page   bcs     COP_print         ;^O ^P -- print
                jsr     clear_home        ;plain ^P
                jmp     MON_HOME
; Set overwrite ("print") mode, the default mode, where character bg and fg both
; replace underlying graphics.
COP_print       lda     #$00
                sta     transparent_mode
                sta     overlay_mode
                rts
CQ_home_cursor  bcs     return            ;^O ^Q -- unused
                lda     block_ch
                sta     MON_CH
                lda     block_cv
                sta     MON_CV
                jmp     MON_VTABZ
COR_reverse     bcc     return1           ;^R -- unused
                lda     #$c0              ;^O ^R
                sta     transparent_mode
                lda     #$60
                sta     overlay_mode
                rts
CS_shift        bcs     COS_scroll
                lda     #$c0
                sta     lower_case
                rts
COS_scroll      lda     #$00
                sta     wrap_mode
                rts
COT_transparent bcc     return1           ;plain ^T -- unused
                lda     #$80              ;^O ^T
                sta     transparent_mode
                lda     #$60
                sta     overlay_mode
                rts
CV_textwin_ul   bcs     return1           ;^O ^V -- unused
                lda     MON_CH            ;window-relative
                adc     MON_WNDLEFT
                cmp     #40               ;Ensure left is < 40
                bcc     @setleft
                lda     #39
@setleft        sta     MON_WNDLEFT
                sec
                lda     MON_WNDWDTH
                sbc     MON_CH
                sta     MON_WNDWDTH
                lda     #$00
                sta     MON_CH
                lda     MON_CV
                cmp     #24               ;Ensure top is < 24
                bcc     @settop
                lda     #23
@settop         sta     MON_WNDTOP
                bit     block_mode
                bmi     @vtab
                sta     block_cv          ;update block top if block mode
@vtab           jmp     MON_VTAB
CW_textwin_lr   bcs     COW_wrap
                lda     MON_CH
                sta     MON_WNDWDTH
                adc     MON_WNDLEFT
                cmp     #40
                bcc     L9117
                lda     #39
                sbc     MON_WNDLEFT
                sta     MON_WNDWDTH
L9117           inc     MON_WNDWDTH
                lda     MON_CV
                cmp     #24
                bcc     L9121
                lda     #23
L9121           sta     MON_WNDBTM
                inc     MON_WNDBTM
return1         rts
COW_wrap        lda     #$ff
                sta     wrap_mode
                rts
CY_textwin_full bcs     COY_userA
textwin_full    lda     MON_WNDLEFT
                adc     MON_CH
                sta     MON_CH
                lda     #$00
                sta     MON_WNDLEFT
                sta     MON_WNDTOP
                bit     block_mode
                bmi     @block
                sta     block_ch          ;set to $00 when not in block mode
                sta     block_cv          ;but should already have been $00 outside block mode
@block          lda     #40
                sta     MON_WNDWDTH
                lda     #24
                sta     MON_WNDBTM
                jmp     MON_VTAB
COY_userA       rts
CZ_restore_default bcs  COZ_userB
set_defaults    jsr     textwin_full
                jsr     use_builtin_fnt
COZ_userB       rts
       ; NOTE: Below, "caps lock" refers to the default state where uppercase and
       ; lowercase are printed without modification (we should call it "unmodified"
       ; state) -- it does not force everything to uppercase. "lowercase mode" prints
       ; both as lowercase. "shift" prints the first char as unmodified, then switches to
       ; lowercase mode.
; Draw char to hires screen and (invisibly) to text screen, scrolling or
; wrapping both as needed.
screen          =    $ec     ;screen address to read from (ec,ed)
charptr         =    $ee     ;pointer to this char bitmap (ee,ef)
draw_char       asl     key_state         ;if waiting for arg to ^O,
                bcs     return1           ;  cancel ^O and return
                bit     lower_case        ;enforced lowercase?
                bpl     @unmodified       ;no, unmodified char
                bvc     @lower            ;lowercase, but shift disengaged
                asl     lower_case        ;shift engaged; mode $c0->$80 sets followup lowercase
                bcs     @unmodified       ;always (unmodified initial char)
; Charsets cover keys $20..$7f, so normally we align the effective char# to
; $00..$5f by subtracting $20 from the key. But if lowercase is enforced, we
; skip the adjustment for A-Z, as lowercase is uppercase+$20.
@lower          cmp     #$41 ; 'A'
                bcc     @unmodified       ;key < A, do not lowercase
                cmp     #$5B ; '[''       ;'Z'+1
                bcc     @draw             ;A-Z -- make it lowercase
@unmodified     sec                       ;key is unmodified, so
                sbc     #$20              ;align $20..$7f to $00..$5f
; A now contains the index into the charset for this key, $00..$5f. We multiply
; this by 8 (bytes/char) to get the byte offset. Finally we add this offset to
; the active charset address to get the char's bitmap pointer. The bit
; manipulation below is just an 8x8=16bit multiply (really a 3-bit left shift of
; 8 bits into 16) followed by a 16-bit add.
@draw           asl     A                 ;Multiply A by 2
                rol     charptr+1         ;shift the overflow into high byte
                asl     A                 ;by 4
                rol     charptr+1         ;shift again
                asl     A                 ;by 8
                rol     charptr+1         ;shift again
                clc
                adc     active_charset    ;16-bit add (low)
                sta     charptr           ;char bitmap (low)
                lda     charptr+1         ;get high byte from 8x8 multiply
                and     #$07              ;limit to the 3 shifted bits
                adc     active_charset+1  ;16-bit add (high)
                sta     charptr+1         ;char bitmap (high)
; charptr now points to the bitmap for this char.
                jsr     compute_cur_base  ;get hires addr of first col of this row
                adc     MON_CH            ;A is basl, add column position
                sta     basl              ;basl += col; dest addr to write to
                sta     screen            ;<screen = basl; source addr when combining
                lda     bash
                eor     overlay_mode      ;eor $60 flips $20 to $40 and vice versa
                sta     screen+1          ;>screen = bash, adjusted for source hires page
                ldy     MON_CH
                lda     saveA             ;recall original keypress value
                sta     (MON_BASL),y      ;and store to text screen
                ldx     #$00              ;for (zp) indexing, X always 0
                ldy     #$00              ;line number in char
; Read a bitmap line, combine it with the source, and write it to the screen.
@charline       lda     (charptr),y       ;load 7-pixel char line
                eor     inverse_video     ;flip all bits if inverted
                bit     transparent_mode  ;check overstrike method
                bpl     @store1            ;if bit 7 clear, opaque
                bvs     @complement       ;if bit 6 set
                bit     inverse_video     ;is inverse_video set ($7f)
                bvs     @invert           ;yes, bit 6 set when $7f
                ora     (screen,x)        ;combine (OR, blend) with source pixels
                bvc     @store1            ;always
@invert         and     (screen,x)        ;combine (AND) source with char mask
                bvs     @store1
@complement     eor     (screen,x)        ;flip (XOR) source with char mask (X=0)
@store1         sta     (basl,x)          ;update screen (X=0)
                iny                       ;next char line
                cpy     #$08
                bcs     @chardone         ;wrote 8 lines, done
                lda     bash
                adc     #$04              ;(carry is clear)
                sta     bash              ;next hires line is +$0400
                eor     overlay_mode      ;adjust source addr for overlay mode again
                sta     screen+1          ;update source addr
                bcc     @charline         ;always
@chardone       inc     MON_CH            ;update horiz pos
                lda     MON_CH
                cmp     MON_WNDWDTH       ;did we exceed window width?
                bcc     @return           ;no, we are done
; Move cursor to beginning of line (CR) and then fall through to linefeed (LF).
cr_lf           lda     #$00              ;reset col to beginning of line
                sta     MON_CH
; Move the cursor to the next row, without changing the column -- a linefeed.
; Wrap or scroll as needed if we reached the bottom.
CJ_linefeed     inc     MON_CV            ;go to next line
                lda     MON_CV
                cmp     MON_WNDBTM        ;check vertical pos
                bcc     @reposition       ;still within window
                bit     wrap_mode         ;in wrap mode (bit 6)?
                bvs     @wrap             ;yes; wrap to top
                dec     MON_CV            ;scrolling; adjust pos to last line
                jsr     scroll            ;scroll hires window
                jmp     MON_SCROLL        ;scroll text window and exit
@wrap           lda     MON_WNDTOP        ;set vert pos to top of window
                sta     MON_CV
@reposition     jsr     MON_VTABZ         ;reposition text mode cursor
@return         rts
; Scroll hires window up one row, clearing the last row.
scroll          lda     MON_WNDTOP
                pha                       ;save row number
                jsr     compute_base
; 
; On the last iteration through the start_eol line loop drawing hires lines 0..7
; of row N, bash is $3c, $3d, $3e or $3f for line 7, and we wind up here again
; for line 0 of row N+1. (bash is not incremented to line 8.) AND #$E3 makes
; that $20, $21, $22, or $23, effectively taking bash back to line 0. Since bash
; always points to the next line (the copy source), we can now store this in
; screen (dest), increasing it by one row. basl/h is then recomputed after
; adding 1 to the row.
; 
; Equivalently, a mask of $e3 zeros the 3 bits 4, 3, and 2. Assume these are
; zeroed in the address corresponding to line 0, the first of 8 lines. Then,
; adding $0400 to this address (to reach the next hires line) sets bit 2, and
; adding $0400 7 times to reach line 7 will set bits 4, 3 and 2 (0b111 == 7). So
; AND #$E3 is the same as subtracting $04*7==$1C (0b00011100) from the high
; byte, returning the pointer to line 0.
; 
@next_row       lda     basl
                sta     screen
                lda     bash
                and     #$e3              ;return bash line 7 to line 0
                sta     screen+1          ;inc dest line by 8 (row by 1)
                pla                       ;restore row number
                clc
                adc     #$01              ;inc row
                cmp     MON_WNDBTM        ;did we hit bottom?
                bcs     @clear_last       ;yes, finish up
                pha                       ;save row number (for next loop, above)
                jsr     compute_base      ;set basl/bash for next line
                ldx     #$07              ;8 rows, char height
@start_eol      ldy     MON_WNDWDTH       ;start at end of window line
                dey
@copy_byte      lda     (basl),y          ;copy byte
                sta     (screen),y
                dey                       ;and move from right to left
                bpl     @copy_byte        ;until beginning of line
                dex                       ;copied all 8 lines?
                bmi     @next_row         ;yes, next row (basl/h not inc'd)
; Go to next hires line in 8-line group, at +$0400. By line 7 we will have added
; $1C00.
                clc
                lda     bash
                adc     #$04
                sta     bash
                lda     screen+1
                adc     #$04
                sta     screen+1
                bne     @start_eol        ;start next row
; Clear the last line to complete the scroll up.
@clear_last     lda     transparent_mode
                pha
                lda     MON_WNDBTM
                sbc     #$01
                ldy     #$00
                sty     transparent_mode
                jsr     clear_eol
                pla
                sta     transparent_mode
                rts
clear_home      lda     MON_WNDTOP
                sta     MON_CV
                ldy     #$00
                sty     MON_CH
                beq     clear_eowin       ;always
clear_hv_eowin  ldy     MON_CH
                lda     MON_CV
; On entry, A/Y are the row/col to begin clearing from. Clears from this
; position to bottom of window.
clear_eowin     pha                       ;preserve line #
                jsr     clear_eol
                pla
                clc
                adc     #$01              ;next line
                cmp     MON_WNDBTM        ;until end of window
                ldy     #$00              ;start at col 0
                bcc     clear_eowin
                rts
; Load current H/V pos into Y/A and fall through to clear_eol.
hpos            =    $ee    ;starting column
clear_hv_eol    ldy     MON_CH
                lda     MON_CV
; Clear line from column Y, row A to end of that line.
clear_eol       sty     hpos              ;save starting column
                jsr     compute_base
                ldx     #$07              ;clear 8 hires lines
; If transparent mode is disabled, we just want to clear by writing 7 black
; (normal, $00)  or white (inverse, $7f) pixels. This conveniently corresponds
; to the value of inverse_video.  
@clrline        lda     inverse_video     ;load $7f or $00 for opaque mode
                bit     transparent_mode
                bpl     @store2            ;if opaque, skip to storing
                lda     basl
                sta     screen
                lda     bash
                eor     overlay_mode
                sta     screen+1
                lda     (screen),y
                bit     transparent_mode
                bvc     @store2
                eor     inverse_video
@store2         sta     (basl),y
                iny
                cpy     MON_WNDWDTH       ;end of screen?
                bcc     @clrline          ;nope, keep clearing line
                dex                       ;one line complete
                bmi     @done             ;if all lines complete, done
                ldy     hpos              ;restore starting column
                lda     bash
                clc
                adc     #$04              ;hi byte adds $04 per line
                sta     bash              ;update hi byte of screen address
                bne     @clrline          ;next line -- always
@done           rts
        
        ********************************************************************************
        * Compute hires base address of a text line, the first line of every 8 line    *
        * character; i.e. 0, 8, 16, ... The line# is the current text row. On exit,    *
        * basl/bash has the address, and A has a copy of basl.                         *
        *                                                                              *
        * The high byte is the same for even/odd pairs, so we divide the row by 2;     *
        * then take this modulo 4 and OR in the hires page.                            *
        *                                                                              *
        * For even/odd pairs the low byte is the same but with bit 7 clear (even) or   *
        * set (odd). We can use a 12-byte (24/2) table lookup and set bit 7 according  *
        * to even/odd.                                                                 *
        *                                                                              *
        * The trick is the LSR A preserves this even/odd information in the carry,     *
        * which is still available when we reach the ROR A, which rotates the carry    *
        * into the high bit, exactly as we needed. The byte values in the address      *
        * table are doubled to account for the ROR. So, for the 24 text lines, the     *
        * hires address base will go                                                   *
        *                                                                              *
        * 2000, 2080, 2100, 2180, 2200, 2280, 2300, 2380,       0..7                   *
        * 2028, 20a8, 2128, 21a8, 2228, 22a8, 2328, 23a8,       8..15                  *
        * 2050, 20d0, 2150, 21d0, 2250, 22d0, 2350, 23d0        16..23                 *
        *                                                                              *
        * as expected for each 8 line interval on the hires screen.                    *
        ********************************************************************************

compute_cur_base lda    MON_CV            ;get current text row
compute_base    lsr                       ;div by 2 *and* set carry if odd
                tax                       ;save for indexing below
                and     #$03              ;$20,$20,$21,$21,$22,$22,$23,$23, then repeat
                ora     hires_page        ;(or $40,$40,$41... if page 2)
                sta     bash              ;is the high byte
                lda     hires_addr_tbl,x  ;index is row/2
; 00, 50, a0 in table become 00, 28, 50 (even rows) or 80, a8, d0 (odd rows).
                ror                       ;/2; carry from LSR becomes high bit
                adc     MON_WNDLEFT       ;adjust for window left (ROR cleared carry)
                sta     basl              ;is the low byte
                rts
hires_addr_tbl  hex   0000000050505050a0a0a0a0 ;12 bytes (24 lines)
                
                ; .align  $0100 (20 bytes)  ;unused area
                ds \

; Standard monochrome (1bpp) 7x8 font bitmap, 1 byte per character line, 8
; consecutive bytes (lines) per character. High bit is unused. Covers 96 high
; ASCII chars A0-FF.

builtin_charset hex   0000000000000000  ; space
                hex   0808080808000800  ; !
                hex   1414140000000000  ; "
                hex   14143e143e141400  ; #
                hex   083c0a1c281e0800  ; $
                hex   0626100804323000  ; etc.
                hex   040a0a042a122c00
                hex   0808080000000000
                hex   0804020202040800
                hex   0810202020100800
                hex   082a1c081c2a0800
                hex   0008083e08080000
                hex   0000000008080400
                hex   0000003e00000000
                hex   0000000000000800
                hex   0020100804020000
                hex   1c22322a26221c00
                hex   080c080808081c00
                hex   1c22201804023e00
                hex   3e20101820221c00
                hex   101814123e101000
                hex   3e021e2020221c00
                hex   3804021e22221c00
                hex   3e20100804040400
                hex   1c22221c22221c00
                hex   1c22223c20100e00
                hex   0000080008000000
                hex   0000080008080400
                hex   1008040204081000
                hex   00003e003e000000
                hex   0408102010080400
                hex   1c22100808000800
                hex   1c222a3a1a023c00
                hex   081422223e222200
                hex   1e22221e22221e00
                hex   1c22020202221c00
                hex   1e22222222221e00
                hex   3e02021e02023e00
                hex   3e02021e02020200
                hex   3c02020232223c00
                hex   2222223e22222200
                hex   1c08080808081c00
                hex   2020202020221c00
                hex   22120a060a122200
                hex   0202020202023e00
                hex   22362a2a22222200
                hex   2222262a32222200
                hex   1c22222222221c00
                hex   1e22221e02020200
                hex   1c2222222a122c00
                hex   1e22221e0a122200
                hex   1c22021c20221c00
                hex   3e08080808080800
                hex   2222222222221c00
                hex   2222222222140800
                hex   2222222a2a362200
                hex   2222140814222200
                hex   2222140808080800
                hex   3e20100804023e00
                hex   3e06060606063e00
                hex   0002040810200000
                hex   3e30303030303e00
                hex   0000081422000000
                hex   000000000000007f
                hex   0408100000000000
                hex   00001c203c223c00
                hex   02021e2222221e00
                hex   00003c0202023c00
                hex   20203c2222223c00
                hex   00001c223e023c00
                hex   1824041e04040400
                hex   00001c22223c201c
                hex   02021e2222222200
                hex   08000c0808081c00
                hex   100018101010120c
                hex   020222120e122200
                hex   0c08080808081c00
                hex   0000362a2a2a2200
                hex   00001e2222222200
                hex   00001c2222221c00
                hex   00001e22221e0202
                hex   00003c22223c2020
                hex   00003a0602020200
                hex   00003c021c201e00
                hex   04041e0404241800
                hex   0000222222322c00
                hex   0000222222140800
                hex   000022222a2a3600
                hex   0000221408142200
                hex   00002222223c201c
                hex   00003e1008043e00
                hex   380c0c060c0c3800
                hex   0808080808080808
                hex   0e18183018180e00
                hex   2c1a000000000000
                hex   7f7f7f7f7f7f7f7f
