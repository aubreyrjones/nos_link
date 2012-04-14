	;; Lifted from the dcpu16 studio default

				; Try some basic stuff
:main
        SET A, 0x30
        SET [0x1000], 0x20
        SUB A, [0x1000]
        IFN A, 0x10
        SET PC, Crash

; Do a loopy thing
        SET I, 10
        SET A, 0x2000
:Loop   SET [0x2000 + I], [A]
        SUB I, 1
        IFN I, 0
        SET PC, Loop

; Call a subroutine
        SET X, 0x4
        JSR TestSub
        SET PC, Crash

:TestSub
        SHL X, 4
        SET PC, POP

; Hang forever.
; X should now be 0x40 if everything
; went right.
:Crash  SET PC, Crash     

