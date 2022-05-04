#
# Uses GNU make for pattern substitution
#
FIRMWARE_END=0x3FF

default:	pwmctl.rom

# assemble with as8048
%.ihx:		%.asm
		as8048 -l -o $<
		aslink -i -o $(<:.asm=.rel)

# convert to binary
%.ibn:		%.ihx
		hex2bin -e ibn $<

# generate rom from ibn by padding and adding checksum at end
%.rom:		%.ibn
		srec_cat $< -binary -crop 0 $(FIRMWARE_END) -fill 0xFF 0 $(FIRMWARE_END) -checksum-neg-b-e $(FIRMWARE_END) 1 1 -o $(<:.ibn=.rom) -binary

clean:
		rm -f *.sym *.lst *.rel *.hlr *.ihx
