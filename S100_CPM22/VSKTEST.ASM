;	VSKTEST.ASM - bench test for the rebuilt Votrax VSK S-100 card
;	CP/M 2.2, 8080/8085.  Assemble with ASM VSKTEST, then LOAD VSKTEST.
;
;	Card summary (traced from the original):
;	  OUT port (default DFh) -> 8212 latch U4 -> 7404 U5 -> VSK DATA0-5
;	    so the VSK socket sees the COMPLEMENT of bits 0-5.
;	    Bits 6-7 reach 8212 DO7/DO8 (pins 19/21); they only go to the
;	    VSK inflection pins 6/7 if the inflection mod is fitted.
;	  IN port: bit 7 (DI7) = NAND(read select, PHONEME CLOCK), open collector.
;	    PHONEME CLOCK high (idle, or socket pin 4 floating) -> bit 7 = 0
;	    PHONEME CLOCK low  (pulse, or socket pin 4 to GND) -> bit 7 = 1
;
;	Commands (type at the VSK> prompt, then RETURN):
;	  W hh   write raw byte hh to the port, show expected pin levels
;	  V hh   write so the VSK socket sees hh (bits 0-5 complemented)
;	  B      bit walk: 00, FF, then one bit at a time; key = next step
;	  R      read the port once, show bit 7
;	  M      monitor bit 7 live until a key is pressed
;	  S      square wave on the latch (00/3F) for a scope, key = stop
;	  P hh   change the I/O port (default DF)
;	  D nnn  speak digits, e.g. D 2026
;	  T word speak a canned word: HELLO, DEMO, COUNT
;	  N ...  speak phonemes by name, e.g. N PA1 H EH1 EH3 L O1 U1 PA1
;	  H or ? help,  Q quit (writes 00 = VSK silent)
;
;	Speech: wait for the phoneme-clock pulse (bit 7 = 1), then for its
;	rising edge (bit 7 = 0), then OUT the complemented phoneme code.
;	Inflection bits 6-7 are always written as 0 (not wired yet).
;	A NULL (3Fh) ends every phrase so the module goes silent.

BDOS	EQU	5
CR	EQU	0DH
LF	EQU	0AH
ESC	EQU	1BH

	ORG	100H

START:	LXI	SP,STACK
	LXI	D,BANNER
	CALL	PSTR
	CALL	HELP

MAINLP:	LXI	D,PROMPT
	CALL	PSTR
	CALL	PPORT
	LXI	D,PROMP2
	CALL	PSTR
	MVI	C,10		;read console buffer
	LXI	D,BUF
	CALL	BDOS
	CALL	CRLF
	LXI	H,BUF+1		;terminate the line with 0
	MOV	E,M
	MVI	D,0
	INX	H
	SHLD	LPTR
	DAD	D
	MVI	M,0
	LHLD	LPTR
	CALL	SKIPSP
	ORA	A
	JZ	MAINLP		;empty line
	CALL	UPPER
	INX	H
	SHLD	LPTR
	CPI	'W'
	JZ	CMDW
	CPI	'V'
	JZ	CMDV
	CPI	'B'
	JZ	CMDB
	CPI	'R'
	JZ	CMDR
	CPI	'M'
	JZ	CMDM
	CPI	'S'
	JZ	CMDS
	CPI	'P'
	JZ	CMDP
	CPI	'Q'
	JZ	CMDQ
	CPI	'D'
	JZ	CMDD
	CPI	'T'
	JZ	CMDT
	CPI	'N'
	JZ	CMDN
	CPI	'H'
	JZ	CMDH
	CPI	'?'
	JZ	CMDH
	LXI	D,MBAD
	CALL	PSTR
	JMP	MAINLP

CMDH:	CALL	HELP
	JMP	MAINLP

;------------------------------------------------ W hh : raw write
CMDW:	CALL	ARGHEX
	JC	BADARG
	CALL	WRITE
	JMP	MAINLP

;------------------------------------------------ V hh : VSK value
CMDV:	CALL	ARGHEX
	JC	BADARG
	MOV	B,A
	CMA
	ANI	3FH		;complement the 6 data bits
	MOV	C,A
	MOV	A,B
	ANI	0C0H		;inflection bits pass straight through
	ORA	C
	CALL	WRITE
	JMP	MAINLP

BADARG:	LXI	D,MARG
	CALL	PSTR
	JMP	MAINLP

;	write A to the port, report it and show the expected pin levels
WRITE:	STA	RAW
	CALL	OUTP
	LXI	D,MWROTE
	CALL	PSTR
	LDA	RAW
	CALL	PHEX
	LXI	D,MTOPRT
	CALL	PSTR
	CALL	PPORT
	CALL	CRLF
	JMP	SHOWPN

;------------------------------------------------ B : bit walk
CMDB:	LXI	D,MWALK
	CALL	PSTR
	XRA	A
	CALL	WSTEP
	JC	WALKX
	MVI	A,0FFH
	CALL	WSTEP
	JC	WALKX
	MVI	A,1
WALKLP:	STA	WBIT
	CALL	WSTEP
	JC	WALKX
	LDA	WBIT
	RLC
	CPI	1		;back to bit 0 = done
	JNZ	WALKLP
	LXI	D,MDONE
	CALL	PSTR
WALKX:	XRA	A		;leave the latch at 00 (VSK silent)
	CALL	OUTP
	JMP	MAINLP

;	write A, show pins, wait for a key; carry set if ESC
WSTEP:	CALL	WRITE
	LXI	D,MNEXT
	CALL	PSTR
	MVI	C,1
	CALL	BDOS
	PUSH	PSW
	CALL	CRLF
	POP	PSW
	CPI	ESC
	STC
	RZ
	CMC
	RET

;------------------------------------------------ R : read once
CMDR:	CALL	INP
	STA	RAW
	LXI	D,MREAD
	CALL	PSTR
	CALL	PPORT
	LXI	D,MEQ
	CALL	PSTR
	LDA	RAW
	CALL	PHEX
	LXI	D,MBIT7
	CALL	PSTR
	LDA	RAW
	ORA	A
	LXI	D,MB7HI
	JM	CMDR1
	LXI	D,MB7LO
CMDR1:	CALL	PSTR
	JMP	MAINLP

;------------------------------------------------ M : monitor bit 7
CMDM:	LXI	D,MMON
	CALL	PSTR
	LXI	H,0
	SHLD	EDGES
	XRA	A
	STA	COL
	CALL	INP
	ANI	80H
	STA	LAST
	CALL	MARK
MONLP:	CALL	INP
	ANI	80H
	MOV	B,A
	LDA	LAST
	CMP	B
	JZ	MONKEY
	MOV	A,B
	STA	LAST
	LHLD	EDGES
	INX	H
	SHLD	EDGES
	CALL	MARK
MONKEY:	LDA	KCNT		;check the keyboard every 256 polls
	DCR	A
	STA	KCNT
	JNZ	MONLP
	MVI	C,11		;console status
	CALL	BDOS
	ORA	A
	JZ	MONLP
	MVI	C,1		;eat the key
	CALL	BDOS
	LXI	D,MEDGES
	CALL	PSTR
	LHLD	EDGES
	MOV	A,H
	CALL	PHEX
	MOV	A,L
	CALL	PHEX
	LXI	D,MHEX
	CALL	PSTR
	JMP	MAINLP

;	print '_' for bit 7 = 0, '#' for 1; wrap every 64 marks
MARK:	LDA	LAST
	ORA	A
	MVI	E,'_'
	JZ	MARK1
	MVI	E,'#'
MARK1:	CALL	PCHAR
	LDA	COL
	INR	A
	CPI	64
	JNZ	MARK2
	CALL	CRLF
	XRA	A
MARK2:	STA	COL
	RET

;------------------------------------------------ S : square wave
CMDS:	LXI	D,MSQ
	CALL	PSTR
SQLP:	MVI	B,0
SQIN:	XRA	A
	CALL	OUTP
	MVI	A,3FH
	CALL	OUTP
	DCR	B
	JNZ	SQIN
	MVI	C,11
	CALL	BDOS
	ORA	A
	JZ	SQLP
	MVI	C,1
	CALL	BDOS
	XRA	A
	CALL	OUTP
	CALL	CRLF
	JMP	MAINLP

;------------------------------------------------ P hh : change port
CMDP:	CALL	ARGHEX
	JC	BADARG
	STA	OUTP+1		;patch the OUT and IN instructions
	STA	INP+1
	JMP	MAINLP

;------------------------------------------------ Q : quit
CMDQ:	XRA	A		;latch 00 -> VSK sees 3F = silent
	CALL	OUTP
	JMP	0

;------------------------------------------------ D digits : speak digits
CMDD:	CALL	PHINIT
	LHLD	LPTR
DDLP:	CALL	SKIPSP
	ORA	A
	JZ	DDEND
	SUI	'0'
	JC	DDBAD
	CPI	10
	JNC	DDBAD
	PUSH	H
	ADD	A		;index into DIGTAB
	MOV	E,A
	MVI	D,0
	LXI	H,DIGTAB
	DAD	D
	MOV	E,M
	INX	H
	MOV	D,M
	XCHG
	CALL	PHCOPY		;append the word
	MVI	A,03H		;PA0 between digits
	CALL	PHPUT
	POP	H
	INX	H
	JMP	DDLP
DDEND:	JMP	SPEAK
DDBAD:	LXI	D,MDIG
	CALL	PSTR
	JMP	MAINLP

;------------------------------------------------ T word : canned phrases
CMDT:	LHLD	LPTR
	CALL	SKIPSP
	CALL	UPPER
	LXI	D,WHELLO
	CPI	'H'
	JZ	TSAY
	LXI	D,WDEMO
	CPI	'D'
	JZ	TSAY
	CPI	'C'
	JZ	TCOUNT
	LXI	D,MWORD
	CALL	PSTR
	JMP	MAINLP
TSAY:	PUSH	D
	CALL	PHINIT
	POP	H
	CALL	PHCOPY
	JMP	SPEAK
TCOUNT:	LXI	H,MCOUNT	;reuse D with the text 0123456789
	SHLD	LPTR
	JMP	CMDD

;------------------------------------------------ N names : phonemes by name
CMDN:	CALL	PHINIT
	LHLD	LPTR
NLP:	CALL	SKIPSP
	ORA	A
	JZ	SPEAK
	CPI	'$'		;$hh = raw phoneme code
	JZ	NHEX
	LXI	D,TOK		;copy up to 3 chars, space padded
	MVI	B,3
NCP1:	MOV	A,M
	CPI	' '
	JZ	NPAD
	ORA	A
	JZ	NPAD
	CALL	UPPER
	STAX	D
	INX	D
	INX	H
	DCR	B
	JNZ	NCP1
	MOV	A,M		;token longer than 3 chars?
	CPI	' '
	JZ	NLOOK
	ORA	A
	JZ	NLOOK
	JMP	NBAD
NPAD:	MVI	A,' '
NPAD1:	STAX	D
	INX	D
	DCR	B
	JNZ	NPAD1
NLOOK:	PUSH	H
	LXI	H,PHTAB
	MVI	C,64
NLK1:	LXI	D,TOK
	MVI	B,3
	PUSH	H
NLK2:	LDAX	D
	CMP	M
	JNZ	NLK3
	INX	D
	INX	H
	DCR	B
	JNZ	NLK2
	MOV	A,M		;found: code byte
	POP	H
	POP	H
	CALL	PHPUT
	JMP	NLP
NLK3:	POP	H
	INX	H
	INX	H
	INX	H
	INX	H
	DCR	C
	JNZ	NLK1
	POP	H
NBAD:	LXI	D,MPHON
	CALL	PSTR
	JMP	MAINLP
NHEX:	INX	H
	MOV	A,M
	CALL	HEXDIG
	JC	NBAD
	MOV	B,A
	INX	H
	MOV	A,M
	CALL	HEXDIG
	JC	NHEX1
	MOV	C,A
	MOV	A,B
	RLC
	RLC
	RLC
	RLC
	ORA	C
	INX	H
	JMP	NHEX2
NHEX1:	MOV	A,B
NHEX2:	ANI	3FH
	PUSH	H
	CALL	PHPUT
	POP	H
	JMP	NLP

;------------------------------------------------ phrase buffer
PHINIT:	XRA	A
	STA	PHCNT
	LXI	H,PHBUF
	SHLD	PHPTR
	MVI	A,3EH		;start with PA1
	JMP	PHPUT

;	append A to the phrase (ignored when full)
PHPUT:	PUSH	H
	PUSH	PSW
	LDA	PHCNT
	CPI	126
	JNC	PHFULL
	INR	A
	STA	PHCNT
	POP	PSW
	LHLD	PHPTR
	MOV	M,A
	INX	H
	SHLD	PHPTR
	POP	H
	RET
PHFULL:	POP	PSW
	POP	H
	RET

;	append the FFh-terminated list at HL
PHCOPY:	MOV	A,M
	CPI	0FFH
	RZ
	PUSH	H
	CALL	PHPUT
	POP	H
	INX	H
	JMP	PHCOPY

;	speak the phrase: PA1, the phrase, PA1, then NULL
SPEAK:	MVI	A,3EH
	CALL	PHPUT
	LXI	D,MSPEAK
	CALL	PSTR
	LXI	H,PHBUF
SPLP2:	XCHG
	LHLD	PHPTR
	MOV	A,L
	CMP	E
	JNZ	SPMORE
	MOV	A,H
	CMP	D
	JZ	SPDONE
SPMORE:	XCHG
	MOV	A,M
	PUSH	H
	CALL	SAYPH
	POP	H
	JC	SPTIME
	INX	H
	PUSH	H
	MVI	C,11		;any key stops
	CALL	BDOS
	POP	H
	ORA	A
	JZ	SPLP2
	PUSH	H
	MVI	C,1
	CALL	BDOS
	POP	H
	LXI	D,MSTOP
	CALL	PSTR
SPDONE:	MVI	A,3FH		;NULL: silence on the next clock
	CALL	SAYPH
	LXI	D,MOK
	CALL	PSTR
	JMP	MAINLP
SPTIME:	XRA	A
	CALL	OUTP
	LXI	D,MNOCLK
	CALL	PSTR
	JMP	MAINLP

;	SAYPH: present phoneme A on the next rising edge of PHONEME CLOCK
;	carry set if no clock (about 0.8 s at 5 MHz)
SAYPH:	STA	PHC
	LXI	H,0
SW1:	CALL	INP		;wait for the pulse: bit 7 = 1
	ORA	A
	JM	SW2
	DCX	H
	MOV	A,H
	ORA	L
	JNZ	SW1
	STC
	RET
SW2:	LXI	H,0
SW3:	CALL	INP		;wait for the rising edge: bit 7 = 0
	ORA	A
	JP	SW4
	DCX	H
	MOV	A,H
	ORA	L
	JNZ	SW3
	STC
	RET
SW4:	LDA	PHC
	CMA			;the card's 7404 inverts the data again
	ANI	3FH		;inflection bits 6-7 = 0
	CALL	OUTP
	ORA	A		;carry clear
	RET

;------------------------------------------------ port access (patched by P)
OUTP:	OUT	0DFH
	RET
INP:	IN	0DFH
	RET

PPORT:	LDA	OUTP+1
	JMP	PHEX

;------------------------------------------------ expected pin table
;	RAW = byte written.  8212 DO pin = bit, VSK pin = NOT bit (bits 0-5)
SHOWPN:	LXI	D,MHDR
	CALL	PSTR
	XRA	A
	STA	BITN
SPLP:	LXI	D,MD
	CALL	PSTR
	LDA	BITN
	ADI	'0'
	MOV	E,A
	CALL	PCHAR
	LXI	D,MU4
	CALL	PSTR
	LXI	H,U4PIN
	CALL	TABDEC
	CALL	GETBIT		;A = 0 or 1
	STA	LEVEL
	CALL	PLEVEL
	LXI	D,MVSK
	CALL	PSTR
	LXI	H,VSKPIN
	CALL	TABDEC
	LDA	BITN
	CPI	6
	LDA	LEVEL
	JNC	SPINF		;bits 6,7: no inverter
	XRI	1
	CALL	PLEVEL
	JMP	SPNXT
SPINF:	CALL	PLEVEL
	LXI	D,MINFL
	CALL	PSTR
SPNXT:	CALL	CRLF
	LDA	BITN
	INR	A
	STA	BITN
	CPI	8
	JNZ	SPLP
	RET

;	print table entry [BITN] as a 2-digit decimal
TABDEC:	LDA	BITN
	MOV	E,A
	MVI	D,0
	DAD	D
	MOV	A,M
	MVI	B,0
TD1:	CPI	10
	JC	TD2
	SUI	10
	INR	B
	JMP	TD1
TD2:	PUSH	PSW
	MOV	A,B
	ORA	A
	MVI	E,' '
	JZ	TD3
	ADI	'0'
	MOV	E,A
TD3:	CALL	PCHAR
	POP	PSW
	ADI	'0'
	MOV	E,A
	JMP	PCHAR

;	A = bit BITN of RAW (0/1)
GETBIT:	LDA	BITN
	MOV	B,A
	LDA	RAW
GB1:	DCR	B
	JM	GB2
	RRC
	JMP	GB1
GB2:	ANI	1
	RET

;	print HIGH / LOW for A = 1 / 0
PLEVEL:	ORA	A
	LXI	D,MHIGH
	JNZ	PSTR
	LXI	D,MLOW
	JMP	PSTR

;------------------------------------------------ parsing
;	ARGHEX: parse 1-2 hex digits after the command; carry set on error
ARGHEX:	LHLD	LPTR
	CALL	SKIPSP
	CALL	HEXDIG
	RC
	MOV	B,A
	INX	H
	MOV	A,M
	CALL	HEXDIG
	JC	AH1		;only one digit
	MOV	C,A
	MOV	A,B
	RLC
	RLC
	RLC
	RLC
	ORA	C
	ORA	A		;clear carry
	RET
AH1:	MOV	A,B
	ORA	A
	RET

;	A = char -> 0-15, carry set if not a hex digit
HEXDIG:	CALL	UPPER
	SUI	'0'
	RC
	CPI	10
	CMC
	RNC			;0-9
	SUI	'A'-'0'
	RC
	CPI	6
	CMC
	RC
	ADI	10
	RET

;	skip spaces at HL, return the char in A
SKIPSP:	MOV	A,M
	CPI	' '
	RNZ
	INX	H
	JMP	SKIPSP

UPPER:	CPI	'a'
	RC
	CPI	'z'+1
	RNC
	SUI	20H
	RET

;------------------------------------------------ console output
PCHAR:	PUSH	B		;E = char
	PUSH	D
	PUSH	H
	MVI	C,2
	CALL	BDOS
	POP	H
	POP	D
	POP	B
	RET

PSTR:	PUSH	B		;DE = '$'-terminated string
	PUSH	H
	MVI	C,9
	CALL	BDOS
	POP	H
	POP	B
	RET

CRLF:	MVI	E,CR
	CALL	PCHAR
	MVI	E,LF
	JMP	PCHAR

PHEX:	PUSH	PSW		;A as two hex digits
	RRC
	RRC
	RRC
	RRC
	CALL	PNIB
	POP	PSW
PNIB:	ANI	0FH
	ADI	90H
	DAA
	ACI	40H
	DAA
	MOV	E,A
	JMP	PCHAR

HELP:	LXI	D,MHELP
	JMP	PSTR

;------------------------------------------------ data
U4PIN:	DB	4,6,8,10,15,17,19,21
VSKPIN:	DB	14,13,12,9,10,11,6,7

BANNER:	DB	CR,LF,'Votrax VSK S-100 card test (no module needed)',CR,LF,'$'
MHELP:	DB	'  W hh  write raw byte hh to the port',CR,LF
	DB	'  V hh  write so the VSK socket sees hh',CR,LF
	DB	'  B     bit walk (key = next / ESC = stop)',CR,LF
	DB	'  R     read the port once (status = bit 7)',CR,LF
	DB	'  M     monitor bit 7 live (any key stops)',CR,LF
	DB	'  S     square wave 00/3F on the latch for a scope',CR,LF
	DB	'  P hh  change the I/O port',CR,LF
	DB	'  D nnn speak digits  (D 2026)',CR,LF
	DB	'  T w   speak HELLO  DEMO or COUNT  (T HELLO)',CR,LF
	DB	'  N ... speak phoneme names (or hex codes with a dollar prefix)',CR,LF
	DB	'        (N PA1 H EH1 EH3 L O1 U1 PA1)',CR,LF
	DB	'  Q     quit (latch 00 = VSK silent)',CR,LF
	DB	'Status test without the module: socket pin 4 open -> bit 7 = 0',CR,LF
	DB	'and socket pin 4 jumpered to pin 8 (GND) -> bit 7 = 1.',CR,LF,'$'
PROMPT:	DB	'VSK[$'
PROMP2:	DB	']> $'
MBAD:	DB	'Unknown command - H for help',CR,LF,'$'
MARG:	DB	'Need a hex value - for example W 2A',CR,LF,'$'
MWROTE:	DB	'Wrote $'
MTOPRT:	DB	' to port $'
MHDR:	DB	'  bit   8212 U4 pin        VSK socket pin',CR,LF,'$'
MD:	DB	'  D$'
MU4:	DB	'    U4-$'
MVSK:	DB	'        VSK-$'
MHIGH:	DB	' HIGH$'
MLOW:	DB	' LOW $'
MINFL:	DB	'  (inflection mod only)$'
MWALK:	DB	'Bit walk: 00 then FF then each bit alone. Probe and press a key.',CR,LF,'$'
MNEXT:	DB	'-- key for next step / ESC to stop: $'
MDONE:	DB	'Bit walk done - latch left at 00.',CR,LF,'$'
MREAD:	DB	'IN $'
MEQ:	DB	' = $'
MBIT7:	DB	'   bit 7 = $'
MB7HI:	DB	'1  (clock low / pin 4 grounded / or no card)',CR,LF,'$'
MB7LO:	DB	'0  (PHONEME CLOCK high / pin 4 open)',CR,LF,'$'
MMON:	DB	'Monitoring bit 7:  _ = 0 (clock high)  # = 1 (clock low).',CR,LF
	DB	'One mark per change. Any key stops.',CR,LF,'$'
MEDGES:	DB	CR,LF,'Changes seen: $'
MHEX:	DB	'h',CR,LF,'$'
MSQ:	DB	'Square wave 00/3F on the latch. Any key stops.',CR,LF,'$'
MSPEAK:	DB	'Speaking... (any key stops)',CR,LF,'$'
MOK:	DB	'Done.',CR,LF,'$'
MSTOP:	DB	'Stopped.',CR,LF,'$'
MNOCLK:	DB	'No phoneme clock - is the VSK module fitted and powered?',CR,LF,'$'
MDIG:	DB	'Digits only - for example D 2026',CR,LF,'$'
MWORD:	DB	'Words: HELLO  DEMO  COUNT',CR,LF,'$'
MPHON:	DB	'Unknown phoneme - see the table in the docs',CR,LF,'$'
MCOUNT:	DB	'0123456789',0

;	phoneme names (3 chars, space padded) and Votrax codes
PHTAB:	DB	'EH3',00H,'EH2',01H,'EH1',02H,'PA0',03H
	DB	'DT ',04H,'A2 ',05H,'A1 ',06H,'ZH ',07H
	DB	'AH2',08H,'I3 ',09H,'I2 ',0AH,'I1 ',0BH
	DB	'M  ',0CH,'N  ',0DH,'B  ',0EH,'V  ',0FH
	DB	'CH ',10H,'SH ',11H,'Z  ',12H,'AW1',13H
	DB	'NG ',14H,'AH1',15H,'OO1',16H,'OO ',17H
	DB	'L  ',18H,'K  ',19H,'J  ',1AH,'H  ',1BH
	DB	'G  ',1CH,'F  ',1DH,'D  ',1EH,'S  ',1FH
	DB	'A  ',20H,'AY ',21H,'Y1 ',22H,'UH3',23H
	DB	'AH ',24H,'P  ',25H,'O  ',26H,'I  ',27H
	DB	'U  ',28H,'Y  ',29H,'T  ',2AH,'R  ',2BH
	DB	'E  ',2CH,'W  ',2DH,'AE ',2EH,'AE1',2FH
	DB	'AW2',30H,'UH2',31H,'UH1',32H,'UH ',33H
	DB	'O2 ',34H,'O1 ',35H,'IU ',36H,'U1 ',37H
	DB	'THV',38H,'TH ',39H,'ER ',3AH,'EH ',3BH
	DB	'E1 ',3CH,'AW ',3DH,'PA1',3EH,'STP',3FH

;	words (Votrax codes, FFh-terminated). Digits are from the VSK
;	manual examples; ONE, FIVE, HELLO and DEMO are best guesses.
DIGTAB:	DW	W0,W1,W2,W3,W4,W5,W6,W7,W8,W9
W0:	DB	12H,21H,09H,2BH,23H,34H,37H,0FFH	;Z AY I3 R UH3 O2 U1
W1:	DB	2DH,32H,23H,0DH,0FFH			;W UH1 UH3 N
W2:	DB	2AH,36H,36H,37H,37H,0FFH		;T IU IU U1 U1
W3:	DB	39H,39H,2BH,2CH,29H,0FFH		;TH TH R E Y
W4:	DB	1DH,35H,35H,2BH,0FFH			;F O1 O1 R
W5:	DB	1DH,15H,00H,29H,0FH,0FFH		;F AH1 EH3 Y V
W6:	DB	1FH,27H,09H,19H,03H,1FH,0FFH		;S I I3 K PA0 S
W7:	DB	1FH,00H,01H,0FH,01H,0DH,0DH,0FFH	;S EH3 EH2 V EH2 N N
W8:	DB	05H,05H,21H,29H,2AH,0FFH		;A2 A2 AY Y T
W9:	DB	0DH,15H,01H,29H,0DH,0FFH		;N AH1 EH2 Y N
WHELLO:	DB	1BH,02H,00H,18H,35H,37H,0FFH		;H EH1 EH3 L O1 U1
;	Hello. I am a talking computer.
WDEMO:	DB	1BH,02H,00H,18H,35H,37H,3EH,3EH		;H EH1 EH3 L O1 U1 PA1 PA1
	DB	15H,00H,29H,03H				;AH1 EH3 Y PA0
	DB	2FH,00H,0CH,03H				;AE1 EH3 M PA0
	DB	32H,03H					;UH1 PA0
	DB	2AH,13H,30H,19H,0BH,09H,14H,03H		;T AW1 AW2 K I1 I3 NG PA0
	DB	19H,32H,0CH,25H,22H,36H,37H,2AH,3AH,0FFH ;K UH1 M P Y1 IU U1 T ER

RAW:	DS	1
BITN:	DS	1
LEVEL:	DS	1
WBIT:	DS	1
LAST:	DS	1
COL:	DS	1
KCNT:	DS	1
EDGES:	DS	2
LPTR:	DS	2
PHC:	DS	1
PHPTR:	DS	2
PHCNT:	DS	1
TOK:	DS	3
PHBUF:	DS	128
BUF:	DB	100,0
	DS	102
	DS	64
STACK:
	END	START
