XPos            =     $06
SCRLO           =     $26
MassDrawAddrCalc =    $035b


* Note: this file is not assembled, the original code was
* written in miniasm, but the source is reconstructed here
* for clarity.  Basically, the routine scans a section of
* the screen as columns of two pixels.  It clears the previous
* column, steps by two and then turns any pixels in finds
* in the new column to white.  When applied to a "red" image
* the effect is to highlight the red pixels in a column width
* white.  Called sequentially, the result is an animated EKG.

                org     $4a00

                lda     XPos
                jsr     ComputeColumn
                lda     BitTable,x        ;X is the bit shift, A is the column byte offset
                sta     Temp
                ldx     #$00
ClearLoop       txa                       ;Remove a column of pixels via AND
                jsr     MassDrawAddrCalc
                lda     Temp
                and     (SCRLO),y
                sta     (SCRLO),y
                inx
                cpx     #$18
                bne     ClearLoop
                inc     XPos              ;Always step by two columns (to preserve "red")
                inc     XPos
                lda     XPos
                cmp     #$52              ;Loop if we've moved too far right
                bne     NoXLoop
                lda     #$02
                sta     XPos
NoXLoop         lda     #$00
                lda     XPos              ;Plot a column of pixels
                jsr     ComputeColumn
                lda     OrTableLo,x
                sta     OrMaskBitsLo
                lda     OrTableHi,x
                sta     OrMaskBitsHi
                ldx     #$00
NextPixel       jsr     CheckAPixel
                inx
                cpx     #$18
                bne     NextPixel
                rts

CheckAPixel     lda     #$00              ;If the point has a pixel neighbor, plot it
                sta     Ypos              ;Use Ypos to record if the pixel should be plotted
                txa
                jsr     MassDrawAddrCalc
                sty     Temp
                lda     OrMaskBitsLo
                and     (SCRLO),y
                cmp     #$00
                beq     NoPix0
                lda     #$01
                sta     Ypos
NoPix0          iny
                lda     OrMaskBitsHi
                and     (SCRLO),y
                cmp     #$00
                beq     NoPix1
                lda     #$01
                sta     Ypos
NoPix1          lda     Ypos
                cmp     #$01
                beq     OnePixel
                ldy     Temp
                rts

OnePixel        ldy     Temp              ;Actually plot the pixel (turning "red" to "white")
                lda     OrMaskBitsLo
                ora     (SCRLO),y
                sta     (SCRLO),y
                iny
                lda     OrMaskBitsHi
                ora     (SCRLO),y
                sta     (SCRLO),y
                ldy     Temp
                rts

ComputeColumn   ldy     #$00              ;Basically int(X/7) and X mod 7
Loop            tax
                txa
                and     #$f8
                cmp     #$00
                beq     IsFull
                jmp     NextColumn

IsFull          txa
                cmp     #$07
                beq     NextColumn
                rts

NextColumn      iny
                txa
                sec
                sbc     #$07
                jmp     Loop

Ypos            dfb    $00
Temp            dfb    $05
OrMaskBitsLo    dfb    $18
OrMaskBitsHi    dfb    $00
OrTableLo       dfb    $03               ;00000011
                dfb    $06               ;00000110
                dfb    $0c               ;00001100
                dfb    $18               ;00011000
                dfb    $30               ;00110000
                dfb    $60               ;01100000
                dfb    $40               ;01000000
OrTableHi       dfb    $00               ;00000000
                dfb    $00               ;00000000
                dfb    $00               ;00000000
                dfb    $00               ;00000000
                dfb    $00               ;00000000
                dfb    $00               ;00000000
                dfb    $01               ;00000001
BitTable        dfb    $fe               ;11111110
                dfb    $fd               ;11111101
                dfb    $fb               ;11111011
                dfb    $f7               ;11110111
                dfb    $ef               ;11101111
                dfb    $df               ;11011111
                dfb    $bf               ;10111111
