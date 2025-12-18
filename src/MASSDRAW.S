         ORG   $300
         DSK   ../bin/MASSDRAW.OBJ0#060300
         TYP   $06        ; /BIN file

                          ; Simple biblt interface
                          ; Inputs:
                          ; 0=X position in bytes (x*7pixels)
                          ; 1=Y position in scanlines
                          ; 3=image addr high byte
                          ; 4=image addr low byte

                          ; Image:
                          ; 0=width of image in bytes
                          ; 1=height of the image
                          ; ... image bytes

         LDA   $03
         STA   GETB+2
         LDA   $04
         STA   GETB+1
         LDY   $00
         LDX   $01
         JSR   GETB       ; get the width of the image in bytes
         STA   $05
         TYA
         CLC
         ADC   $05
         STA   XCHECK+1   ; end of scanline check
         JSR   GETB       ; get the height of the image in scanlines
         STA   $05
         TXA
         CLC
         ADC   $05
         STA   YCHECK+1
         
NEXTY    TXA              ; X is the Y coordinate
         JSR   CALCADR    ; set up $26 to point at the target scanline
         JSR   LINE
         INX
YCHECK   CPX   #$00
         BNE   NEXTY
         RTS

GETB     LDA   $FFFF      ; get the next byte in the image
         PHA
         LDA   GETB+1
         CLC
         ADC   #$01
         STA   GETB+1
         LDA   GETB+2
         ADC   #$00
         STA   GETB+2
         PLA
         RTS

LINE     STY   $05        ; draw one scanline
LOOP     JSR   GETB
         NOP
         NOP
         STA   ($26),Y
         INY
XCHECK   CPY   #$00
         BNE   LOOP
         LDY   $05
         RTS

CALCADR  PHA              ; compute the starting address of scanline A.
         AND   #$C0
         STA   $26
         LSR
         LSR
         ORA   $26
         STA   $26
         PLA
         STA   $27
         ASL
         ASL
         ASL
         ROL   $27
         ASL
         ROL   $27
         ASL
         ROR   $26
         LDA   $27
         AND   #$1F
         ORA   $E6
         STA   $27
         RTS
