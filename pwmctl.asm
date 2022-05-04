;
; If simin == 1 port 2 low nybble is virtually used to simulate buttons because
; s48 simulator has no commands to change interrupt and test input "pins"
;
.equ	simin,		0
;
; If speedup == 1 time constants are lowered for faster simulation
;
.equ	speedup,	0

; 804[89] PWM LED control

; This code is under MIT license. Ken Yap

;;;;;;;;;;;;;;;;;;;;;;;;;;

.ifdef	.__.CPU.		; if we are using as8048 this is defined
.8048
.area	CODE	(ABS)
.endif	; .__.CPU.

; 0 = 0 bit turns on, 1 = 1 bit turns on segment
.equ	highison,	0

.if	highison == 1
.equ	allon,		0xff
.equ	alloff,		0x00
.else
.equ	allon,		0x00
.equ	alloff,		0xff
.endif	; highison

; timing information.
; clk / 5 -- ale (osc / 15). "provided continuously" (pin 11)
; ale / 32 -- "normal" timer rate (osc / 480).
; set timer count, tick = period x timerdiv

.if	speedup == 1
.equ	timerdiv,	3	; speed up simulation
.else
.equ	timerdiv,	64	; 4.9152 MHz crystal
.endif	; speedup
.equ	tcount,		-timerdiv

.equ	scanfreq,	160	; resulting scan frequency

; these are in 1/100ths of second, multiply by scanfreq to get counts
.equ	depmin,		scanfreq*10/100	; down 1/10th s to register
.equ	rptthresh,	scanfreq*50/100	; repeat kicks in at 1/2 s
.equ	rptperiod,	scanfreq*25/100	; repeat 4 times / second

; p1.0 thru p1.7 drive segments when driving with edge triggered latch
; p2.0 thru p2.3 are used in simin mode in simulator, not physically
; t0 increase brightness
; t1 decrease brightness
.equ	p21,		0x02
.equ	p22,		0x04
.equ	p22rmask,	~p22
.equ	p23,		0x08
.equ	p23rmask,	~p23
.equ	swmask,		p23|p22

.equ	swstate,	0x28	; previous state of switches
.equ	swtent,		0x29	; tentative state of switches
.equ	swmin,		0x2a	; count of how long state has been stable
.equ	uprepeat,	0x2c	; repeat counter for inc brightness
.equ	downrepeat,	0x2d	; repeat counter for dec brightness
.equ	brightptr,	0x2e	; pointer to brightness table
.equ	brightlvl,	0x2f	; current brightness level

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; reset vector 
	.org	0
	jmp	main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; external interrupt vector (pin 6) not used
	.org	3
	dis	i
	retr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; timer interrupt vector
; r7 saved a to restore on retr
	.org	7
	sel	rb1
	mov	r7, a		; save a
	mov	a, #tcount	; restart timer
	mov	t, a
	strt	t
	mov	a, r7		; restore a
	retr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

main:
	clr	f0		; zero some registers and other cold boot stuff
	sel	rb0
	mov	a, #0xff
	outl	p2, a		; p2 is all input
	anl	a, #swmask	; isolate switch bits
	mov	r0, #swstate
	mov	@r0, a
	mov	r0, #swtent
	mov	@r0, a
	mov	r0, #swmin	; preset switch depression counts
	mov	@r0, #depmin
	mov	r0, #uprepeat	; and repeat thresholds
	mov	@r0, #rptthresh
	mov	r0, #downrepeat
	mov	@r0, #rptthresh
	mov	r0, #brightptr	; set for medium brightness
	mov	a, #(brightend-brighttable)/2
	mov	@r0, a
	movp3	a, @a
	mov	r0, #brightlvl	; store brightness level
	mov	@r0, a
	mov	a, #tcount	; setup timer and enable its interrupt
	mov	t, a
	strt	t
	en	tcnti

; main loop
workloop:
	jtf	ticked
	mov	r0, #brightlvl
	mov	a, t
	add	a, @r0
	jb7	leaveon		; passed threshold?
	mov	a, #alloff
	outl	p1, a		; turn off all segments
	jmp	workloop	; wait until tick is up
leaveon:
	mov	a, #allon
	outl	p1, a		; turn on all segments
	jmp	workloop	; wait until tick is up
ticked:
	call	switch
	jmp	workloop

; switch handling
; t0 low is increase brightness, press to start, then hold to repeat
; t1 low is decrease brightness, press to start, then hold to repeat
; convert to bitmask to easily detect change
; use p2.2 and p2.3 to emulate for debugging
switch:
.if	simin == 1
	in	a, p2
.else
	mov	a, #0xff
	jt0	not0
	anl	a, #p22rmask
not0:
	jt1	not1
	anl	a, #p23rmask
not1:
.endif	; simin
	anl	a, #swmask	; isolate switch bits
	mov	r7, a		; save a copy
	mov	r0, #swtent
	xrl	a, @r0		; compare against last state
	mov	r0, #swmin
	jz	swnochange
	mov	@r0, #depmin	; reload timer
	mov	r0, #swtent
	mov	a, r7
	mov	@r0, a		; save current switch state
	ret
swnochange:
	mov	a, @r0		; check timer
	jz	swaction
	dec	a
	mov	@r0, a
	ret
swaction:
	call	incbright
	call	decbright
	mov	r0, #swtent
	mov	a, @r0
	mov	r0, #swstate
	mov	@r0, a
	ret

incbright:
	mov	r0, #swtent
	mov	a, @r0
	jb2	noincbright	; first time through?
	mov	r0, #swstate
	mov	a, @r0
	jb2	inc1bright
	mov	r0, #uprepeat
	mov	a, @r0
	jz	incwaitover
	dec	a
	mov	@r0, a
	ret
incwaitover:
	mov	r0, #uprepeat
	mov	@r0, #rptperiod
inc1bright:
	mov	r0, #brightptr	
	mov	a, @r0
	xrl	a, #brightend-page3-1	; don't increment past end of table
	jz	noincbright
	mov	a, @r0
	inc	a
	mov	@r0, a
	movp3	a, @a		; get brightness level
	mov	r0, #brightlvl
	mov	@r0, a
	ret
noincbright:
	mov	r0, #uprepeat
	mov	@r0, #rptthresh
	ret

decbright:
	mov	r0, #swtent
	mov	a, @r0
	jb3	nodecbright	; first time through?
	mov	r0, #swstate
	mov	a, @r0
	jb3	dec1bright
	mov	r0, #downrepeat
	mov	a, @r0
	jz	decwaitover
	dec	a
	mov	@r0, a
	ret
decwaitover:
	mov	r0, #downrepeat
	mov	@r0, #rptperiod
dec1bright:
	mov	r0, #brightptr	
	mov	a, @r0
	xrl	a, #brighttable-page3	; don't decrement past start of table
	jz	nodecbright
	mov	a, @r0
	dec	a
	mov	@r0, a
	movp3	a, @a		; get brightness level
	mov	r0, #brightlvl
	mov	@r0, a
	ret
nodecbright:
	mov	r0, #downrepeat
	mov	@r0, #rptthresh
	ret


;
; Tables and lookup routines
;
	.org	0x300

page3:

brighttable:			; PWM table
	.db	timerdiv-timerdiv/16
	.db	timerdiv-(timerdiv*2)/16
	.db	timerdiv-(timerdiv*3)/16
	.db	timerdiv-(timerdiv*4)/16
	.db	timerdiv-(timerdiv*5)/16
	.db	timerdiv-(timerdiv*6)/16
	.db	timerdiv-(timerdiv*7)/16
	.db	timerdiv-(timerdiv*8)/16
	.db	timerdiv-(timerdiv*9)/16
	.db	timerdiv-(timerdiv*10)/16
	.db	timerdiv-(timerdiv*11)/16
	.db	timerdiv-(timerdiv*12)/16
	.db	timerdiv-(timerdiv*13)/16
	.db	timerdiv-(timerdiv*14)/16
	.db	timerdiv-(timerdiv*15)/16
	.db	timerdiv-timerdiv
brightend:

ident:
	.db	0x0
	.db	0x4b, 0x65, 0x6e
	.db	0x20
	.db	0x59, 0x61, 0x70
	.db	0x20
	.db	0x32, 0x30	; 20
	.db	0x32, 0x32	; 22
	.db	0x0

.ifdef	.__.CPU.		; if we are using as8048 this is defined
; embed some option strings to identify ROM
.endif	; .__.CPU.

; end
