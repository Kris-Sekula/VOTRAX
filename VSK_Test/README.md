# VSK module bench test with an Arduino Nano (VSK_Test.ino)

The sketch drives the VSK module directly, without the S-100 card, so the data is positive-true with no inverters. All data high (3Fh) means silence; the sketch outputs that whenever its queue is empty and at startup.

## Wiring (digital signals only; Nano GND must be common with VSK pin 8)

| VSK pin | Signal | Nano | AVR |
|---|---|---|---|
| 14 | DATA0 (LSB) | A0 | PC0 |
| 13 | DATA1 | A1 | PC1 |
| 12 | DATA2 | A2 | PC2 |
| 9 | DATA3 | A3 | PC3 |
| 10 | DATA4 | A4 | PC4 |
| 11 | DATA5 (MSB) | A5 | PC5 |
| 6 | INFLECTION LSB | D8 | PB0 |
| 7 | INFLECTION MSB | D9 | PB1 |
| 4 | PHONEME CLOCK (module output) | D2 (INT0) | PD2 |
| 8 | GND | GND | |

The data bits are on PORTC 0-5, so each code is a single port write. The inflection bits are on PORTB 0-1. A CHANGE interrupt on D2 measures the clock and, on each **rising edge** (the end of the ~350 µs low pulse), loads the next queued phoneme together with its inflection.

## Serial monitor (115200 baud, Newline line ending)
- **Phonemes:** type the names, e.g. `PA1 TH TH R E Y PA1`. A raw code can be typed as hex, e.g. `$1F`.
- **Words:** `0`-`9` speak the digits from the manual's example words; ONE and FIVE are my guesses. `HELLO` is also a guess.
- **Inflection:** `^0`-`^3` set the inflection for the phonemes that follow.
- **Commands:**
  - `!t` sweeps all 63 phonemes.
  - `!m` monitors the clock: it should show ~350 µs pulses and a ~40 ms period while idle.
  - `!s` stops and flushes the queue.
  - `!?` shows help.
- The sketch warns if the phoneme clock is missing for more than 1 s.

