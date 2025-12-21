; 6502bench SourceGen v1.10.1-dev4
BOTTOM          =     $00
TOP             =     $01
SCRLO           =     $26
MassDrawAddrCalc =    $035b
ImageAddr       =     $4b00

* Note: this file is not assembled, the original code was
* written in miniasm, but the source is reconstructed here
* for clarity.  Basically, the routine draws a white bar
* from bottom to top with the topmost row coming from a
* different image in a fixed size "massdraw" format.
* The net effect is to "slice" transition from one 
* massdraw image to another.  Note that the address of 
* the image is fixed ($4b00) and the routine just skips
* the Dx and Dy header bytes of the massdraw image.

                org     $4a00

                lda     #<ImageAddr+2
                sta     ReadSrcByte+1
                lda     #>ImageAddr+2
                sta     ReadSrcByte+2
                lda     #$1c
                sta     BOTTOM
                lda     #$14
                sta     TOP
Loop            jsr     OneLine
                inc     TOP
                inc     BOTTOM
                lda     TOP
                cmp     #$6c
                bne     Loop
                rts

ProcessLine     lda     BOTTOM            ;00 is the "knife" bottom position
                tax
NextLine        jsr     MassDrawAddrCalc
                ldy     #$0e              ;Draw from column $0e through column $19
                lda     #$7f              ;White pixels
OneColumn       sta     (SCRLO),y
                iny
                cpy     #$1a
                bne     OneColumn
                dex
                cpx     TOP               ;01 is the knife top position
                beq     NewTopLine
                txa
                jmp     NextLine

NewTopLine      txa
                jsr     MassDrawAddrCalc
                ldy     #$0e
NextImageByte   jsr     ReadSrcByte
                sta     (SCRLO),y
                iny
                cpy     #$1a
                bne     NextImageByte
                rts

ReadSrcByte     lda     L4F22
                pha
                lda     ReadSrcByte+1
                clc
                adc     #$01
                sta     ReadSrcByte+1
                lda     ReadSrcByte+2
                adc     #$00
                sta     ReadSrcByte+2
                pla
                rts

OneLine         ldy     #$40
Delay           ldx     #$ff
Delay2          dex
                bne     Delay2
                dey
                bne     Delay
                jmp     ProcessLine
