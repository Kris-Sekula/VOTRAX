# VSKTEST.COM — CP/M 2.2 bring-up and speech test for the rebuilt card

Files are in `Votrax\S100_CPM22\`:
- VSKTEST.ASM: DRI ASM source in 8080 syntax, which also runs on the 8085.
- VSKTEST.COM: the assembled program, 3413 bytes, version with speech (2026-11-22).
- VSKTEST.HEX: Intel HEX of the same code.
- CCPM22A_Votrax.img: Bootable CP/M 2.2 with VSKTEST.COM included (Tested on my CompuPro with 8085/88 and Disk1A)


## Status
- **Bring-up** Run without VSK module fitted, tested the S and M commands worked, and all 6 data bits checked out fine.
- **Speech version:** next step is was with the VSK fitted, all working fine... 

results on **--> [Youtube](https://youtu.be/ZKPHl1Dtn7s) <--**

## The VSKTEST utility Commands (prompt `VSK[DF]>`)
- `W hh`: write the raw byte to the port, then show the expected level on each 8212 output pin (U4-4/6/8/10/15/17/19/21) and each VSK socket pin (14/13/12/9/10/11, inverted; 6/7 only with the inflection mod).
- `V hh`: write `(~hh & 3F) | (hh & C0)` so that the VSK socket sees hh.
- `B`: bit walk. It writes 00, then FF, then each bit alone, waiting for a key at each step; ESC aborts. The latch is left at 00.
- `R`: read once and show bit 7. Bit 7 = 0 means the clock is high or pin 4 is open. Bit 7 = 1 means the clock is low, pin 4 is grounded, or nothing answered (the bus floats to FF).
- `M`: monitor bit 7 live. It prints `_` or `#` on each change and counts the changes. The keyboard is checked every 256 polls.
- `S`: square wave, writing 00 and 3F alternately for a scope. This also shows the DS1* strobe at U4 pin 1.
- `P hh`: change the port. This patches the IN and OUT instructions.
- `D nnn`: speak digits, e.g. `D 2026`. Each digit's word is followed by PA0.
- `T HELLO`, `T DEMO` ("Hello. I am a talking computer.") and `T COUNT` (0-9).
- `N names...`: speak phoneme names from the Votrax table, or `$hh` raw codes. Unknown names are rejected before anything is spoken. The input line holds up to 100 characters; a phrase holds up to 126 phonemes.
- `Q`: write 00 (the VSK sees 3F, which is silent), then warm boot.

How the speech works:
- SAYPH waits for bit 7 = 1 (the clock pulse), then for bit 7 = 0 (the rising edge), then OUTs `(~code) & 3Fh`.
- Each wait times out after about 0.8 s at 5 MHz and reports "No phoneme clock".
- Every phrase is PA1 + phonemes + PA1 + NULL.
- Any key stops speech; the phrase is then ended with NULL.
- The digit words are from the manual's examples. ONE, FIVE, HELLO and DEMO are guesses.

CCPM22A_Votrax.img format, derived from the image and its own BIOS source GBCBIOS.ASM:
- 625,920 bytes, 8" single sided, 77 tracks.
- Track 0 is FM, 26 × 128 (boot). Tracks 1-76 are MFM, 8 × 1024.
- Two system tracks; the directory starts on track 2.
- 2 KB blocks with 16-bit pointers, DSM 299, 128 directory entries (blocks 0-1).
- Skew table XLTD3: logical 1K sector n → sector ID {0,3,6,1,4,7,2,5}[n]+1. The image is stored in sector-ID order.
- The original disk has 64 files and 74 KB free.
