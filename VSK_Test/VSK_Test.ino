/*
  VSK_Test.ino - drive a Votrax VSK speech module directly from an Arduino Nano (ATmega328P, 5 V)

  WIRING (digital only - power and audio are up to you; Nano GND must be common with VSK pin 8)
  ----------------------------------------------------------------------------------------
   VSK pin  Signal             Nano pin   AVR port
     14     DATA0 (LSB)        A0         PC0
     13     DATA1              A1         PC1
     12     DATA2              A2         PC2
      9     DATA3              A3         PC3
     10     DATA4              A4         PC4
     11     DATA5 (MSB)        A5         PC5
      6     INFLECTION LSB     D8         PB0
      7     INFLECTION MSB     D9         PB1
      4     PHONEME CLOCK out  D2 (in)    PD2 / INT0
      8     GND                GND
  (15 = SPARE: leave open)

  The six data bits sit on PORTC bits 0-5 so a phoneme code is written in one instruction.
  Data is positive-true straight to the module (no inverters here, unlike the S-100 card).
  All data high (3Fh) = NULL / silence; that is what the sketch outputs whenever its queue is empty.

  TIMING (from Votrax manual P/N 1964): the phoneme clock idles high and pulses low for ~350 us
  when the module is ready for the next phoneme. New data must be presented on the RISING edge.
  The sketch loads the next queued phoneme (and inflection) from the INT0 interrupt on that edge.

  SERIAL MONITOR (115200 baud, "Newline" line ending). Type a line of tokens:
    PA1 TH TH R E Y PA1   phoneme names (see table; case-insensitive)
    $1F                   raw hex code 00-3F
    0 .. 9                spoken digit,   HELLO  a demo word
    ^0 .. ^3              inflection level for the following phonemes (^0 lowest .. ^3 highest)
    !t   sweep all 63 phonemes        !m   phoneme-clock monitor (5 s)
    !s   stop / flush queue           !?   help
*/

#include <avr/pgmspace.h>

const uint8_t PIN_CLK = 2;          // PHONEME CLOCK from VSK pin 4
const uint8_t NULL_CODE = 0x3F;     // all data high = silence
const uint8_t PA1 = 0x3E, PA0 = 0x03;

// ---------------------------------------------------------------- phoneme table (Votrax code order)
struct Ph { char n[4]; uint8_t c; };
const Ph PHON[] PROGMEM = {
  {"EH3",0x00},{"EH2",0x01},{"EH1",0x02},{"PA0",0x03},{"DT",0x04},{"A2",0x05},{"A1",0x06},{"ZH",0x07},
  {"AH2",0x08},{"I3",0x09},{"I2",0x0A},{"I1",0x0B},{"M",0x0C},{"N",0x0D},{"B",0x0E},{"V",0x0F},
  {"CH",0x10},{"SH",0x11},{"Z",0x12},{"AW1",0x13},{"NG",0x14},{"AH1",0x15},{"OO1",0x16},{"OO",0x17},
  {"L",0x18},{"K",0x19},{"J",0x1A},{"H",0x1B},{"G",0x1C},{"F",0x1D},{"D",0x1E},{"S",0x1F},
  {"A",0x20},{"AY",0x21},{"Y1",0x22},{"UH3",0x23},{"AH",0x24},{"P",0x25},{"O",0x26},{"I",0x27},
  {"U",0x28},{"Y",0x29},{"T",0x2A},{"R",0x2B},{"E",0x2C},{"W",0x2D},{"AE",0x2E},{"AE1",0x2F},
  {"AW2",0x30},{"UH2",0x31},{"UH1",0x32},{"UH",0x33},{"O2",0x34},{"O1",0x35},{"IU",0x36},{"U1",0x37},
  {"THV",0x38},{"TH",0x39},{"ER",0x3A},{"EH",0x3B},{"E1",0x3C},{"AW",0x3D},{"PA1",0x3E},{"STP",0x3F},
};
const uint8_t NPHON = sizeof(PHON) / sizeof(PHON[0]);

// demo words: digits from the VSK manual (OCR cleaned up); ONE, FIVE and HELLO are my own guesses
const char W0[] PROGMEM = "Z AY I3 R UH3 O2 U1";
const char W1[] PROGMEM = "W UH1 UH3 N";
const char W2[] PROGMEM = "T IU IU U1 U1";
const char W3[] PROGMEM = "TH TH R E Y";
const char W4[] PROGMEM = "F O1 O1 R";
const char W5[] PROGMEM = "F AH1 EH3 Y V";
const char W6[] PROGMEM = "S I I3 K PA0 S";
const char W7[] PROGMEM = "S EH3 EH2 V EH2 N N";
const char W8[] PROGMEM = "A2 A2 AY Y T";
const char W9[] PROGMEM = "N AH1 EH2 Y N";
const char WHELLO[] PROGMEM = "H EH1 EH3 L O1 U1";
const char* const DIGITS[] PROGMEM = { W0, W1, W2, W3, W4, W5, W6, W7, W8, W9 };

// ---------------------------------------------------------------- output queue (filled by loop, drained by INT0)
// entry = phoneme code (bits 0-5) | inflection (bits 6-7)
const uint8_t QSZ = 128;
volatile uint8_t q[QSZ];
volatile uint8_t qHead = 0, qTail = 0;
volatile uint32_t tFall = 0, tRise = 0, lowUs = 0, periodUs = 0, edges = 0;
uint8_t inflection = 0;

static inline void vskWrite(uint8_t v) {
  PORTC = (PORTC & 0xC0) | (v & 0x3F);          // DATA0-5
  PORTB = (PORTB & 0xFC) | ((v >> 6) & 0x03);   // inflection LSB/MSB
}

void onClock() {                                // CHANGE interrupt on PHONEME CLOCK
  uint32_t now = micros();
  if (PIND & _BV(PD2)) {                        // rising edge: module wants the next phoneme
    lowUs = now - tFall;
    periodUs = now - tRise;
    tRise = now;
    edges++;
    uint8_t v;
    if (qHead != qTail) { v = q[qTail]; qTail = (qTail + 1) % QSZ; }
    else v = NULL_CODE | (inflection << 6);
    vskWrite(v);
  } else {
    tFall = now;
  }
}

bool enqueue(uint8_t code) {
  uint8_t next = (qHead + 1) % QSZ;
  uint32_t t0 = millis();
  while (next == qTail) {                       // queue full: wait for the module to catch up
    if (millis() - t0 > 1000) return false;     // no phoneme clock -> give up
  }
  q[qHead] = (code & 0x3F) | (inflection << 6);
  qHead = next;
  return true;
}

// ---------------------------------------------------------------- parsing
int8_t lookup(const char* name) {
  Ph p;
  for (uint8_t i = 0; i < NPHON; i++) {
    memcpy_P(&p, &PHON[i], sizeof(Ph));
    if (strcmp(p.n, name) == 0) return p.c;
  }
  if (strcmp(name, "STOP") == 0 || strcmp(name, "NULL") == 0) return NULL_CODE;
  return -1;
}

void sayList(const char* list_P) {              // space-separated phoneme names in PROGMEM
  char buf[48]; strncpy_P(buf, list_P, sizeof(buf) - 1); buf[sizeof(buf) - 1] = 0;
  enqueue(PA1);
  char* save;
  for (char* t = strtok_r(buf, " ", &save); t; t = strtok_r(NULL, " ", &save)) {
    int8_t c = lookup(t); if (c >= 0) enqueue(c);
  }
  enqueue(PA1);
}

void help() {
  Serial.println(F("\nVotrax VSK tester. Tokens: phoneme names, $hex, 0-9, HELLO, ^0-^3 (inflection)"));
  Serial.println(F("Commands: !t sweep  !m clock monitor  !s stop  !? help"));
  Serial.print(F("Phonemes: "));
  Ph p;
  for (uint8_t i = 0; i < NPHON; i++) { memcpy_P(&p, &PHON[i], sizeof(Ph)); Serial.print(p.n); Serial.print(' '); }
  Serial.println(F("\nExample:  PA1 TH TH R E Y PA1     or     1 2 3"));
}

void monitor() {
  Serial.println(F("Phoneme clock monitor (5 s):"));
  uint32_t t0 = millis(), e0 = edges;
  while (millis() - t0 < 5000) {
    delay(500);
    noInterrupts(); uint32_t lw = lowUs, pd = periodUs, e = edges; interrupts();
    Serial.print(F("  edges ")); Serial.print(e - e0);
    Serial.print(F("  low pulse ")); Serial.print(lw); Serial.print(F(" us  period "));
    Serial.print(pd / 1000.0, 1); Serial.println(F(" ms"));
  }
  Serial.println(F("Expect ~350 us low pulses; ~40 ms period while idle (NULL)."));
}

void sweep() {
  Serial.println(F("Sweep: each phoneme twice, with a PA0 pause between"));
  Ph p;
  for (uint8_t i = 0; i < NPHON - 1; i++) {     // skip STOP
    memcpy_P(&p, &PHON[i], sizeof(Ph));
    Serial.print(p.n); Serial.print(' ');
    if (!enqueue(p.c) || !enqueue(p.c) || !enqueue(PA0)) { Serial.println(F("\nNo phoneme clock!")); return; }
  }
  enqueue(PA1); Serial.println();
}

void handleLine(char* line) {
  for (char* s = line; *s; s++) *s = toupper(*s);
  char* save;
  for (char* t = strtok_r(line, " ,\t", &save); t; t = strtok_r(NULL, " ,\t", &save)) {
    if (t[0] == '!') {
      switch (t[1]) {
        case 'T': sweep(); break;
        case 'M': monitor(); break;
        case 'S': noInterrupts(); qTail = qHead; interrupts(); Serial.println(F("stopped")); break;
        default: help();
      }
    } else if (t[0] == '?') help();
    else if (t[0] == '^' && t[1] >= '0' && t[1] <= '3') { inflection = t[1] - '0'; }
    else if (t[0] == '$') { enqueue(strtol(t + 1, NULL, 16)); }
    else if (t[0] >= '0' && t[0] <= '9' && t[1] == 0) { sayList((const char*)pgm_read_ptr(&DIGITS[t[0] - '0'])); }
    else if (strcmp(t, "HELLO") == 0) { sayList(WHELLO); }
    else {
      int8_t c = lookup(t);
      if (c >= 0) enqueue(c);
      else { Serial.print(F("unknown: ")); Serial.println(t); }
    }
  }
}

// ---------------------------------------------------------------- setup / loop
void setup() {
  DDRC |= 0x3F;                                 // A0-A5 outputs (DATA0-5)
  DDRB |= 0x03;                                 // D8, D9 outputs (inflection)
  vskWrite(NULL_CODE);                          // start silent
  pinMode(PIN_CLK, INPUT_PULLUP);
  Serial.begin(115200);
  attachInterrupt(digitalPinToInterrupt(PIN_CLK), onClock, CHANGE);
  help();
  delay(200);
  if (edges == 0) Serial.println(F("WARNING: no PHONEME CLOCK edges yet - check VSK power and pin 4 wiring"));
  else sayList(WHELLO);
}

void loop() {
  static char line[128];
  static uint8_t n = 0;
  static uint32_t lastWarn = 0;
  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == '\r') continue;
    if (ch == '\n') { line[n] = 0; if (n) handleLine(line); n = 0; }
    else if (n < sizeof(line) - 1) line[n++] = ch;
  }
  noInterrupts(); uint32_t tr = tRise; interrupts();
  if (micros() - tr > 1000000UL && millis() - lastWarn > 5000) {
    lastWarn = millis();
    Serial.println(F("no PHONEME CLOCK for >1 s (module unpowered or pin 4 not wired?)"));
  }
}
