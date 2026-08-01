;====================================================
; PIC16F877A ADC Example
; Read AN0 and display upper 8 bits on PORTC, and 7-segment on PORTB and PORTD
; Clock: 20 MHz Crystal
; Pin mapping:
; RA0 	-> Analog input
; RA1-5 -> unused
; RB0 	-> External interrupt
; RB1-7 -> 7-segments, segment a-g
; RC0-7	-> for debugging
; RD0-3	-> 7-segments D3-D0, shared for keypad line scan (output)
; RD4-7	-> for keypad input
;====================================================

        LIST    P=16F877A
        #include <P16F877A.INC>

        __CONFIG _CP_OFF & _WDT_OFF & _PWRTE_ON & _XT_OSC & _LVP_OFF

;----------------------------------------------------
; Variables
;----------------------------------------------------
    CBLOCK 0x20
		;main program variable
		COUNT_L
		COUNT_H
		COUNT1
		COUNT2
		TEXT
		BUF
		;variables for ADC
		ADCH
		ADCL
		;variables for timer
		COUNT_4MS	
		COUNT_20MS
		COUNT_40MS
		COUNT_100MS
		COUNT_400MS	
		COUNT_1S	
		METRO_4MS
		METRO_20MS
		METRO_40MS
		METRO_100MS
		METRO_400MS
		METRO_1S
		;variables for BIN2DEC subroutine
		NUMBER_H		;binary value high byte
		NUMBER_L		;binary value low byte
		TENTHOU
		THOU			;decimal representative
		HUND
		TENS
		ONES
		TEXT_BUFFER
		;variables for segment multiplexing
		SEGMENT_IDX
		;variable for debouncing
		PRESSED_KEY
		PRESSED_BUTTON
		;variable for keypad
		KEY_VALUE	;255=no key press,other values=key press
		KEY_ROW		;for lookup
		KEY_COL
		;variables for 16-bit arithmetic
		AH		;A high byte
		AL		;A low byte
		BH		;B high byte
		BL		;B low byte
		RH		;result high byte
		RL		;result low byte
		CARRY	;used by ADD16 and SUB16
		TEMP	;used by MUL_BY_10
		BL_BIT	;used by MUL16
		;to recover from ISR
		W_TEMP
    	STATUS_TEMP
    	PCLATH_TEMP
		;for LFSR
		STATE
		XOR1
		XOR2
		XOR3
		XOR4
		;for running LED
		DIR
    ENDC

;----------------------------------------------------
; Constants (can define values here to control overall behaviour)
;----------------------------------------------------

;Define constant
;timer calculation
;TMR0=256-t_target*Fosc/(4*prescale)
;e.g. 1ms interval at 20MHz = 256-0.0008(20e6/(4*32))=131
T0_PRESCALE	EQU b'00000100';prescale=32
MILLI		EQU	D'131'	;1ms TMR0 value, recalculate if use other Fosc or prescale
MILLI4		EQU D'5'	;4ms counter (base)
MILLI20		EQU D'5'	;20ms counter
MILLI40		EQU D'10'	;40ms counter
MILLI100	EQU D'25'	;100ms counter
MILLI400	EQU D'100'	;400ms counter
ONESEC		EQU D'250'	;1s	counter
DISPLAY_IDX EQU b'00001000' ;start from ONES
LFSR_SEED	EQU .100	;random number seed
;----------------------------------------------------
; Initialize
;----------------------------------------------------

    ORG     0x0000
    GOTO    START
	ORG		0x0004
	GOTO	ISR

;============== Array Definition ==============
;Array should be initialised at the beginning of the code 
;to avoid PCH addressing problem
;lookup table for binary to character
CharTable				
	ADDWF 	PCL,F
	RETLW	b'01111110'	;char '0', RB0 reserved for EXT INT
	RETLW	b'00001100'	;char '1'
	RETLW	b'10110110'	;char '2'
	RETLW	b'10011110'	;char '3'
	RETLW	b'11001100'	;char '4'
	RETLW	b'11011010'	;char '5'
	RETLW	b'11111010'	;char '6'
	RETLW	b'00001110'	;char '7'
	RETLW	b'11111110'	;char '8'
	RETLW	b'11011110'	;char '9'
	RETLW	b'11101110'	;char 'A'
	RETLW	b'11111000'	;char 'b'
	RETLW	b'01110010'	;char 'C'
	RETLW	b'10111100'	;char 'd'
	RETLW	b'11110010'	;char 'E'
	RETLW	b'11100010'	;char 'F'

KeyTable				
	ADDWF 	PCL,F
	RETLW	.1	;1
	RETLW	.2	;2
	RETLW	.3	;3
	RETLW	.10	;A
	RETLW	.4	;4
	RETLW	.5	;5
	RETLW	.6	;6
	RETLW	.11	;B
	RETLW	.7	;7
	RETLW	.8	;8
	RETLW	.9	;9
	RETLW	.12	;C
	RETLW	.15	;Asterisk
	RETLW	.0	;0
	RETLW	.14	;hash
	RETLW	.13	;D
;----------------------------------------------------
; ISR definition
;----------------------------------------------------
ISR
	CALL	SAVE_CONTEXT
    BTFSC   INTCON,T0IF		;check timer 0 interrupt source
    GOTO	T0_ISR			;goto timer interrupt subroutine
    BTFSC   INTCON,INTF 	;check external interrupt source
    GOTO	INTF_ISR		;goto RB0 interrupt subroutine
    GOTO	EXIT_ISR

INTF_ISR					;external interrupt
	BCF		INTCON,INTF		;clear interrupt flag
	MOVF	PRESSED_BUTTON,W;check for zero (flag not set)
	BTFSS	STATUS,Z		;
	GOTO	EXIT_ISR
TASK_EXT_INT
	BSF		PRESSED_BUTTON,0;set flag, b'00000001'
	;task for external interrupt, only run for once if PRESSED is not cleared
	;must clear the PRESSED if you wish to accept EXT INT again
	GOTO	EXIT_ISR

T0_ISR						;Timer 0 interrupt
	MOVLW	MILLI
	MOVWF	TMR0			;reload the timer value
	BCF     INTCON,T0IF		;clear T0 interrupt flag
POOL_4MS
	DECFSZ	COUNT_4MS,F		;decrement F, skip if zero
	GOTO	EXIT_ISR
	MOVLW	MILLI4			;base timer
	MOVWF	COUNT_4MS		;reload the COUNT_4MS value
	BSF		METRO_4MS,0
POOL_20MS
	DECFSZ	COUNT_20MS,F
	GOTO	POOL_40MS
	MOVLW	MILLI20			;reload COUNT_20MS
	MOVWF	COUNT_20MS
	BSF		METRO_20MS,0
POOL_40MS
	DECFSZ	COUNT_40MS,F
	GOTO	POOL_400MS
	MOVLW	MILLI40			;reload COUNT_40MS
	MOVWF	COUNT_40MS
	BSF		METRO_40MS,0
POOL_100MS
	DECFSZ	COUNT_100MS,F
	GOTO	POOL_400MS
	MOVLW	MILLI100		;reload COUNT_100MS
	MOVWF	COUNT_100MS
	BSF		METRO_100MS,0
POOL_400MS
	DECFSZ	COUNT_400MS,F
	GOTO	POOL_1S
	MOVLW	MILLI400		;reload COUNT_400MS
	MOVWF	COUNT_400MS
	BSF		METRO_400MS,0
POOL_1S
	DECFSZ	COUNT_1S,F
	GOTO	EXIT_ISR
	MOVLW	ONESEC			;reload COUNT_1S
	MOVWF	COUNT_1S
	BSF		METRO_1S,0
EXIT_ISR
	CALL	RECOVER_CONTEXT	;commented out to reduce latency
	RETFIE

;====================================================
START
;----------------------------------------------------
; Configure I/O
;----------------------------------------------------

    BSF     STATUS, RP0 	; Bank 1
    MOVLW   b'00000001'
    MOVWF   TRISA           ; RA0 input
	MOVWF	TRISB			; RB0 interrupt input, all output
	CLRF	TRISC			; PORTC all output
	CLRF	TRISE			; PORTE all output
	MOVLW   b'11110000'		
	MOVWF	TRISD			; RD7-4 input, RD3-0 output

;----------------------------------------------------
; Option Register Configuration
;----------------------------------------------------
; OPTION_REG
; RBPU=0	disable internal pullup
; INTEDG=1	interrupt on rising edge
; T0CS=0 	T0 use instruction clock
; T0SE=0	T0 use clock rising edge (only in counter mode)
; PSA=0 	(prescaler -> TMR0)
; PS=000 	000=(1:2) -> 111=(1:256)
	MOVLW   b'01000000'		;prescale template
	XORLW	T0_PRESCALE		
	MOVWF   OPTION_REG

;----------------------------------------------------
; ADC Configuration
;----------------------------------------------------
; ADCON1
; ADFM = 1 (RIGHT Justified for full 10-bit resolution)
; PCFG3:0 = 1110
; AN0 = Analog
; Others = Digital
;
    MOVLW   b'10001110'
    MOVWF   ADCON1

    BCF     STATUS, RP0      ; Back to Bank 0

; ADCON0
; ADCS1:ADCS0 = 10 (Fosc/32)
; CHS = 000 (AN0)
; GO/DONE = 0
; ADON = 1
;
    MOVLW   b'10000001'
    MOVWF   ADCON0

;----------------------------------------------------
; Data configure
;----------------------------------------------------
	MOVLW   MILLI			;Preload Timer0 to interrupt at 1ms
    MOVWF   TMR0
	MOVLW   MILLI4			;Preload COUNT_4MS
    MOVWF   COUNT_4MS
	MOVLW   MILLI20			;Preload COUNT_20MS
    MOVWF   COUNT_20MS
	MOVLW   MILLI40			;Preload COUNT_40MS
    MOVWF   COUNT_40MS
	MOVLW   MILLI400		;Preload COUNT_400MS
    MOVWF   COUNT_400MS
	MOVLW   ONESEC			;Preload COUNT_1S
    MOVWF   COUNT_1S
	MOVLW	DISPLAY_IDX		;Preload SEGMENT_IDX
	MOVWF	SEGMENT_IDX
	MOVLW	LFSR_SEED		;Preload LFSR seed
	MOVWF	STATE
	CLRF	DIR
	CLRF	PORTA
	CLRF	PORTB
	MOVLW	.1
	MOVWF	PORTC
	CLRF	PORTD
	CLRF	PORTE
	CLRF	KEY_VALUE
	CLRF	PRESSED_KEY
	CLRF	PRESSED_BUTTON

;----------------------------------------------------
; Interrupt Configuration
;----------------------------------------------------
	BCF		INTCON,INTF		;clear RB0 interrupt flag
	BCF		INTCON,T0IF		;clear T0 interrupt flag
	BSF 	INTCON,INTE		;enable RB0 interrupt
	BSF 	INTCON,T0IE		;enable T0 interrupt
	BSF		INTCON, GIE		;enable global interrupt
;====================================================
MAIN_LOOP
;check METRO timer and execute accordingly
	BTFSS	METRO_4MS,0	;check flag
	GOTO	TASK_20MS
	BCF		METRO_4MS,0	;clear flag
	;do your stuff of 4ms interval
	NOP
TASK_20MS
	BTFSS	METRO_20MS,0	;check flag
	GOTO	TASK_40MS
	BCF		METRO_20MS,0	;clear flag
	;do your stuff of 20ms interval
	CALL	TASK_DISP_SEGMENT		;manage 7-segment displays
	BTFSC	PRESSED_KEY,0	;check if key is already pressed
	GOTO	TASK_40MS		;if set, skip keypad input
	CALL	KEYPAD_INPUT
	INCFSZ	KEY_VALUE,W	;check if got key pressed, 255=no key
	GOTO	PROCESS_KEY_VALUE
	GOTO	TASK_40MS
PROCESS_KEY_VALUE
	BSF		PRESSED_KEY,0	;set flag
	;limit the 7-segment output to thousands
	;extract thousand
	MOVF	THOU,W			;x100
	MOVWF	AL
	CLRF	AH
	MOVLW	.100
	MOVWF	BL
	CLRF	BH
	CALL	MUL16
	MOVF	RL,W			;x10
	MOVWF	AL
	MOVF	RH,W			;
	MOVWF	AH
	CALL	MUL_BY_10
	;subtract thousands
	MOVF	NUMBER_L,W
	MOVWF	AL
	MOVF	NUMBER_H,W
	MOVWF	AH				;load number
	MOVF	RL,W
	MOVWF	BL
	MOVF	RH,W
	MOVWF	BH
	CALL	SUB16
	;multiply by 10
;	MOVF	NUMBER_L,W
;	MOVWF	AL
;	MOVF	NUMBER_H,W
;	MOVWF	AH
	MOVF	RL,W
	MOVWF	AL
	MOVF	RH,W
	MOVWF	AH				;load number
	CALL	MUL_BY_10		;x10
	MOVF	RL,W
	MOVWF	NUMBER_L
	MOVF	RH,W
	MOVWF	NUMBER_H		;store number
	;add ONES
	MOVF	KEY_VALUE,W		;load A
	MOVWF	AL
	CLRF	AH
	MOVF	NUMBER_L,W		;load B
	MOVWF	BL
	MOVF	NUMBER_H,W
	MOVWF	BH
	CALL	ADD16			;A+B
	MOVF	RL,W
	MOVWF	NUMBER_L
	MOVF	RH,W
	MOVWF	NUMBER_H		;store number
	CALL	BIN2DEC			;convert to decimal
TASK_40MS
	BTFSS	METRO_40MS,0	;check flag
	GOTO	TASK_100MS
	BCF		METRO_40MS,0	;clear flag
	;do your stuff of 40ms interval
	NOP
	
TASK_100MS
	BTFSS	METRO_100MS,0	;check flag
	GOTO	TASK_400MS
	BCF		METRO_100MS,0	;clear flag
	;do your stuff of 100ms interval
	NOP
TASK_400MS
	BTFSS	METRO_400MS,0	;check flag
	GOTO	TASK_1S
	BCF		METRO_400MS,0	;clear flag
	;do your stuff of 400ms interval
;	CALL	INCREMENT_COUNT
;	MOVF	COUNT_L,W
;	MOVWF	NUMBER_L
;	MOVF	COUNT_H,W
;	MOVWF	NUMBER_H
;	CALL	BIN2DEC
	BCF		PRESSED_KEY,0	;clear PRESSED_KEY
	BTFSS	DIR,0		;check direction
	GOTO	ROT_LEFT
	GOTO	ROT_RIGHT
ROT_LEFT
	RLF		PORTC,F		;rotate port c
	BTFSC	PORTC,7
	BSF		DIR,0
	GOTO	TASK_1S
ROT_RIGHT	
	RRF		PORTC,F		;rotate port c
	BTFSC	PORTC,0
	BCF		DIR,0
TASK_1S
	BTFSS	METRO_1S,0	;check flag
	GOTO	FINALIZE
	BCF		METRO_1S,0	;clear flag
	;do your stuff of 1s interval
;	CALL	LFSR8
;	MOVF	STATE,W
;	MOVWF	NUMBER_L
;	CALL	BIN2DEC		;convert NUMBER_L and NUMBER_H to TENTHOU,THOU,HUND,TENS,ONES
	;CALL	KEYPAD_INPUT	;manage keypad input	
	;MOVF	KEY_VALUE,W
	;MOVWF	NUMBER_L
	
FINALIZE
	GOTO MAIN_LOOP

;====================================================
;Subroutine definition
;====================================================
;software delay
DELAY500MS
	MOVLW	D'83'			;move value 83 to COUNT2, 1clk
	MOVWF	COUNT2			;1clk
LOOP2
	MOVLW	D'250'			;move value 250 to COUNT1, 1clk
	MOVWF	COUNT1			;1clk
LOOP1
	NOP						;1clk
	NOP						;1clk
	DECFSZ	COUNT1,F		;decrement COUNT1 and store to F, 2clk
	GOTO	LOOP1			;2clk
	DECFSZ	COUNT2,F		;decrement COUNT2 and store to F, 2clk
	GOTO	LOOP2			;2clk
	RETURN					;2clk

;call CharTable
Get7Seg
    CLRF    PCLATH
    CALL    CharTable
    RETURN

;call CharTable
GetKey
    CLRF    PCLATH
    CALL    KeyTable
    RETURN

;save and recover context, used for ISR
SAVE_CONTEXT
	MOVWF   W_TEMP

    SWAPF   STATUS,W
    MOVWF   STATUS_TEMP

    MOVF    PCLATH,W
    MOVWF   PCLATH_TEMP
	RETURN

RECOVER_CONTEXT
    MOVF    PCLATH_TEMP,W
    MOVWF   PCLATH

    SWAPF   STATUS_TEMP,W
    MOVWF   STATUS

    SWAPF   W_TEMP,F
    SWAPF   W_TEMP,W
	RETURN

;update PORTB for 7-segment
UPDATE_PORTB
	MOVWF	TEXT_BUFFER
	MOVLW	b'00000001'
	ANDWF	PORTB,W
	XORWF	TEXT_BUFFER,W
	MOVWF	PORTB
	RETURN

;ADC data acquisition
ADC 
	; Start Conversion
    BSF     ADCON0, GO
WAIT
    BTFSC   ADCON0, GO
    GOTO    WAIT
	;Read_Result
    MOVF    ADRESH, W	;ADC copy
	MOVWF	ADCH
	MOVF    ADRESL, W	;ADC copy
	MOVWF	ADCL
	RETURN

;for 7-segment display control
TASK_DISP_SEGMENT
	BTFSS	SEGMENT_IDX,3	;test bit position 0
	GOTO	TASK_DISP_HUND
	MOVF	THOU,W
	CALL	Get7Seg			;the W register has the segment data
	CALL	UPDATE_PORTB
	CALL	ON_SEGMENT
	RRF		SEGMENT_IDX,F	;rotate right to HUND
	RETURN
TASK_DISP_HUND
	BTFSS	SEGMENT_IDX,2	;test bit position 2
	GOTO	TASK_DISP_TENS
	MOVF	HUND,W
	CALL	Get7Seg			;the W register has the segment data
	CALL	UPDATE_PORTB
	CALL	ON_SEGMENT
	RRF		SEGMENT_IDX,F	;rotate right to HUND
	RETURN
TASK_DISP_TENS
	BTFSS	SEGMENT_IDX,1	;test bit position 1
	GOTO	TASK_DISP_ONES
	MOVF	TENS,W
	CALL	Get7Seg			;the W register has the segment data
	CALL	UPDATE_PORTB
	CALL	ON_SEGMENT
	RRF		SEGMENT_IDX,F	;rotate right to HUND
	RETURN
TASK_DISP_ONES
	MOVF	ONES,W
	CALL	Get7Seg			;the W register has the segment data
	CALL	UPDATE_PORTB
	CALL	ON_SEGMENT
	MOVLW	DISPLAY_IDX		;restore SEGMENT_IDX
	MOVWF	SEGMENT_IDX
	RETURN

;for binary to decimal converter
BIN2DEC 
 	CLRF 	TENTHOU
	MOVLW   0x27
	MOVWF	BH
	MOVLW	0x10
	MOVWF	BL
	MOVF   	NUMBER_H,W
	MOVWF	AH
	MOVF	NUMBER_L,W
	MOVWF	AL
TenThouLoop
    CALL	SUB16		;NUMBER - 1000, store to RH and RL
    BTFSS   STATUS,C	;check borrow bit
    GOTO    ThouStage	;if underflow (<1000), goto HundStage
    MOVF   	RH,W		;else, copy subtracted NUMBER to W for next loop
	MOVWF	AH
	MOVF	RL,W
	MOVWF	AL
    INCF    TENTHOU,F		;increment THOU
    GOTO    TenThouLoop	;repeat
ThouStage
	CLRF 	THOU
	MOVLW   0x03
	MOVWF	BH
	MOVLW	0xE8
	MOVWF	BL
	MOVF   	NUMBER_H,W
	MOVWF	AH
	MOVF	NUMBER_L,W
	MOVWF	AL
ThouLoop
    CALL	SUB16		;NUMBER - 1000, store to RH and RL
    BTFSS   STATUS,C	;check borrow bit
    GOTO    HundStage	;if underflow (<1000), goto HundStage
    MOVF   	RH,W		;else, copy subtracted NUMBER to W for next loop
	MOVWF	AH
	MOVF	RL,W
	MOVWF	AL
    INCF    THOU,F		;increment THOU
    GOTO    ThouLoop	;repeat
HundStage
	CLRF 	HUND
	MOVLW   0x00
	MOVWF	BH
	MOVLW	0x64		;100 in decimal
	MOVWF	BL
HundLoop
    CALL	SUB16		;NUMBER - 100, store to RH and RL
    BTFSS   STATUS,C	;check borrow bit
    GOTO    TensStage	;if underflow (<100), goto TensStage
    MOVF   	RH,W		;else, copy subtracted NUMBER to W for next loop
	MOVWF	AH
	MOVF	RL,W
	MOVWF	AL
    INCF    HUND,F		;increment HUND
    GOTO    HundLoop	;repeat
TensStage
    CLRF    TENS		;by this stage, 8-bit subtraction is adequate
TenLoop
    MOVLW   D'10'		;move value 10 to W
    SUBWF   AL,W		;NUMBER - 10, store to W
    BTFSS   STATUS,C	;check borrow bit
    GOTO    Finish		;if underflow (<10), goto Finish
    MOVWF   AL			;else, copy subtracted NUMBER to W for next loop
    INCF    TENS,F		;increment TENS
    GOTO    TenLoop		;repeat
Finish
    MOVF    AL,W		;copy remainder to W
    MOVWF   ONES		;move W to F
	;finally, the binary number will be converted to 
	;THOU HUND TENS ONES decimal format
    RETURN	

;turn on segment
ON_SEGMENT
	MOVLW	b'11110000'
	ANDWF	PORTD,W			;clear lower 4 bit
	IORWF	SEGMENT_IDX,W	;set display segment
	MOVWF	PORTD
	RETURN

;subroutine for keypad input
KEYPAD_INPUT
	MOVLW	.0
	MOVWF	KEY_ROW
	BTFSS	PORTD,0
	GOTO	SCAN_L2
	CALL	GET_INPUT
	BTFSS	STATUS,Z	;if zero, no input
	GOTO	PROCESS_KEY	;else, process it
	GOTO	SET_NO_KEY
SCAN_L2
	MOVLW	.4
	MOVWF	KEY_ROW
	BTFSS	PORTD,1
	GOTO	SCAN_L3
	CALL	GET_INPUT
	BTFSS	STATUS,Z	;if zero, no input
	GOTO	PROCESS_KEY	;else, process it
	GOTO	SET_NO_KEY
SCAN_L3
	MOVLW	.8
	MOVWF	KEY_ROW
	BTFSS	PORTD,2
	GOTO	SCAN_L4
	CALL	GET_INPUT
	BTFSS	STATUS,Z	;if zero, no input
	GOTO	PROCESS_KEY	;else, process it
	GOTO	SET_NO_KEY
SCAN_L4
	MOVLW	.12
	MOVWF	KEY_ROW
	BTFSS	PORTD,3
	GOTO	SET_NO_KEY
	CALL	GET_INPUT
	BTFSS	STATUS,Z	;if zero, no input
	GOTO	PROCESS_KEY	;else, process it
	GOTO	SET_NO_KEY
GET_INPUT
	MOVLW	b'11110000'
	ANDWF	PORTD,W
	MOVWF	KEY_COL		
	RETURN
PROCESS_KEY
	BTFSC	KEY_COL,4	;if bit 4 is set
	MOVLW	.0
	BTFSC	KEY_COL,5	;if bit 4 is set
	MOVLW	.1
	BTFSC	KEY_COL,6	;if bit 4 is set
	MOVLW	.2
	BTFSC	KEY_COL,7	;if bit 4 is set
	MOVLW	.3
	ADDWF	KEY_ROW,W
	CALL	GetKey
	MOVWF	KEY_VALUE
	GOTO	FINALIZE_KEY_INPUT
SET_NO_KEY
	MOVLW	.255
	MOVWF	KEY_VALUE
FINALIZE_KEY_INPUT
	RETURN

;subroutine for debouncing
DEBOUNCING
	;check if buttons are released, RB0
	BTFSC	PORTB,0		;if still 1, skip debouncing button
	RETURN				;if set, skip resetting flag
	BTFSS	PRESSED_BUTTON,1	;use rotate to act as delay before resetting flag
	GOTO	ROTATE_DELAY1
	CLRF	PRESSED_BUTTON		;clear flag if released
	RETURN				
ROTATE_DELAY1
	RLF		PRESSED_BUTTON,F
	RETURN				

;subroutine for LFSR
LFSR8	;w register needs to have the input 1st
	CLRF	XOR4
	CLRF	XOR3
	CLRF	XOR2
	CLRF	XOR1
	BTFSC	STATE,4
	BSF		XOR4,0
	BTFSC	STATE,3
	BSF		XOR3,0
	BTFSC	STATE,2
	BSF		XOR2,0
	BTFSC	STATE,0
	BSF		XOR1,0
	MOVF	XOR4,W
	XORWF	XOR3,F
	MOVF	XOR2,W
	XORWF	XOR1,F
	MOVF	XOR3,W
	XORWF	XOR1,F
	BCF		STATUS,C
	RRF		STATE,F
	BTFSC	XOR1,0
	BSF		STATE,7
	RETURN

;use ADD16 and SUB16 for increment and decrement
INCREMENT_COUNT
	MOVF	COUNT_L,W
	MOVWF	AL
	MOVF	COUNT_H,W
	MOVWF	AH
	MOVLW	.1
	MOVWF	BL
	CLRF	BH
	CALL	ADD16
	MOVF	RL,W
	MOVWF	COUNT_L
	MOVF	RH,W
	MOVWF	COUNT_H
	RETURN

DECREMENT_COUNT
	MOVF	COUNT_L,W
	MOVWF	AL
	MOVF	COUNT_H,W
	MOVWF	AH
	MOVLW	.1
	MOVWF	BL
	CLRF	BH
	CALL	SUB16
	MOVF	RL,W
	MOVWF	COUNT_L
	MOVF	RH,W
	MOVWF	COUNT_H
	RETURN

; subroutine for 16-bit addition and subtraction
ADD16
	CLRF	RH			;clear RH
	CLRF	CARRY		;clear CARRY
	MOVF	AL,W		;copy AL to W
	ADDWF	BL,W		;AL+BL, store to W
	MOVWF	RL			;store W to RL
	CLRW				;clear W
	BTFSC	STATUS,C	;check carry
	MOVLW	.1			;if got carry, increment AH
	ADDWF	AH,W		;add and store to W
	BTFSC	STATUS,C	;check carry
	BSF		CARRY,0		;if set, set CARRY
	ADDWF	BH,W		;AH+BH, store to W
	MOVWF	RH			;store W to RH
	BTFSC	CARRY,0		;check CARRY from former stage
	BSF		STATUS,C	;overwrite carry if any
	RETURN

SUB16
	CLRF	RH			;clear RH
	BSF		CARRY,0		;Hypothesis set BORROW
	MOVF	BL,W		;copy AL to W
	SUBWF	AL,W		;AL-BL, store to w
	MOVWF	RL			;store W to RL
	CLRW				;clear W 
	BTFSS	STATUS,C	;check borrow
	MOVLW	.1			;if got borrow, AH-1
	SUBWF	AH,W		;
	MOVWF	RH			;use RH to temporary store borrowed AH
	BTFSS	STATUS,C	;check borrow
	BCF		CARRY,0		;if clear, claer BORROW
	MOVF	BH,W		;copy BH to W
	SUBWF	RH,F		;(RH=AH)-BH, store to F(RH)
	BTFSS	CARRY,0		;check BORROW from former stage
	BCF		STATUS,C	;if borrowed from former stage, clear borrow
	RETURN

MUL_BY_10
	MOVLW	D'10'
	MOVWF	TEMP		;preload loop counter
	CLRF	BH
	CLRF	BL
LOOP_10
	CALL 	ADD16		;execute ADD16
	MOVF	RH,W		;copy paste result for next loop
	MOVWF	BH
	MOVF	RL,W
	MOVWF	BL
	DECFSZ	TEMP,F
	GOTO	LOOP_10
	RETURN

MUL16					;shift add multiplication of two 8-bit A and B
	CLRF	RH			;clear RH
	MOVF	BL,W		;copy BL to BL_BIT
	MOVWF	BL_BIT
	CLRF	BL			;clear BL for reusing
MUL16_S0
	BTFSS	BL_BIT,0	;check BL bit 0
	GOTO	MUL16_S1	;if 0, goto next stage
	MOVF	AL,W		;at 1st stage, just copy paste
	MOVWF	BL			;reuse BL to store partial product
	CLRF	BH			;clear BH, just in case
MUL16_S1
	CALL	MUL16_SHIFT_A
	BTFSS	BL_BIT,1	;check BL bit 1
	GOTO	MUL16_S2	;if 0, goto next stage
	CALL	MUL16_ADD_STORE_PARTIAL	;else, perform add
MUL16_S2
	CALL	MUL16_SHIFT_A
	BTFSS	BL_BIT,2	;check BL bit 2
	GOTO	MUL16_S3	;if 0, goto next stage
	CALL	MUL16_ADD_STORE_PARTIAL	;else, perform add
MUL16_S3
	CALL	MUL16_SHIFT_A
	BTFSS	BL_BIT,3	;check BL bit 3
	GOTO	MUL16_S4	;if 0, goto next stage
	CALL	MUL16_ADD_STORE_PARTIAL	;else, perform add
MUL16_S4
	CALL	MUL16_SHIFT_A
	BTFSS	BL_BIT,4	;check BL bit 4
	GOTO	MUL16_S5	;if 0, goto next stage
	CALL	MUL16_ADD_STORE_PARTIAL	;else, perform add
MUL16_S5
	CALL	MUL16_SHIFT_A
	BTFSS	BL_BIT,5	;check BL bit 5
	GOTO	MUL16_S6	;if 0, goto next stage
	CALL	MUL16_ADD_STORE_PARTIAL	;else, perform add
MUL16_S6
	CALL	MUL16_SHIFT_A
	BTFSS	BL_BIT,6	;check BL bit 6
	GOTO	MUL16_S7	;if 0, goto next stage
	CALL	MUL16_ADD_STORE_PARTIAL	;else, perform add
MUL16_S7
	CALL	MUL16_SHIFT_A
	BTFSS	BL_BIT,7	;check BL bit 7
	GOTO	MUL16_FIN	;if 0, return
	CALL	ADD16		;perform 16-bit addition
MUL16_FIN	
	RETURN

MUL16_SHIFT_A			;shift A variable
	BCF		STATUS,C
	RLF		AH,F		;shift AH left
	BTFSC	AL,7		;check MSB of AL
	INCF	AH,F		;if MSB set, increment AH
	RLF		AL,F		;shift AL left
	RETURN
MUL16_ADD_STORE_PARTIAL
	CALL	ADD16		;perform 16-bit addition
	MOVF	RH,W		;copy partial result to BH and BL
	MOVWF	BH
	MOVF	RL,W
	MOVWF	BL
	RETURN

	END			;end of program