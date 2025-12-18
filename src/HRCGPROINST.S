         org   $2000
         dsk   ../bin/HRCGPROINST#062000
         typ   $06        ; /BIN file

GETBUFR         =     $bef5             ; Allocate a basic.system buffer

* $8f00 - hrcg core source - in and out handlers
* $9400 - default font ($300 bytes = 96*8)
* $9700 - alternate font (actually font #2)
* $9a00 - ProDOS BI begins
                          
        ; $2000 - allocate buffers and copy $2100- to $8f00-

         lda   #11         ; 11 pages should put us at $8f00
         jsr   GETBUFR
         bcc   :ok
         rts
:ok      cmp   #$8f       
         bne   :ok-1
         ldx   #11
:loop    ldy   #0
src      lda   $2100,y
dst      sta   $8f00,y
         iny
         bne   src
         inc   src+2
         inc   dst+2
         dex
         bne   :loop
         jmp   $8f00      ; note: $8f03 for HGR2
         