# CarPlay Audio Protocol Reference

**Last Updated:** 2025-12-30
**Based On:** 21 controlled capture sessions across 7 scenarios

---

## Overview

The CarPlay audio protocol uses a layered system with two key identifiers:
- **decode_type**: Determines audio mode/quality (playback vs voice)
- **audio_type**: Determines audio channel/routing

All audio data flows through message type `0x07` (AudioData) in the USB protocol.

---

## Audio Packet Structure

```
Offset  Size   Field           Description
------  ----   -----           -----------
0       4      packet_len      Total packet length (LE)
4       4      sequence        Packet sequence/offset
8       4      flags           Direction and type flags
12      4      magic           0xAA55AA55
16      4      payload_len     Payload length (LE)
20      4      msg_type        Always 0x07 for AudioData
24      4      reserved        Usually 0xFFFFFFF8 (-8 signed)
28      4      decode_type     Audio mode (2, 4, or 5)
32      4      volume          Float32 volume level
36      4      audio_type      Audio channel (1, 2, or 3)
40      1+     data            Command byte OR PCM samples
```

### Packet Sizes

| payload_len | Purpose |
|-------------|---------|
| 13 | Control command (12-byte header + 1 command byte) |
| 16 | Extended control (navigation volume) |
| 972 | Voice audio chunk (Siri/phone) |
| 11532 | Standard audio chunk (media/nav) |
| 1856-8204 | Variable microphone data |

---

## decode_type Values (VERIFIED)

| Value | Name | Purpose | Sample Rate | Channels |
|-------|------|---------|-------------|----------|
| **2** | STOP | Channel stop/cleanup signal | N/A | N/A |
| **4** | PLAYBACK | Standard CarPlay audio | 44.1/48 kHz | Stereo |
| **5** | VOICE | Siri and phone call mode | 16 kHz | Mono |

### Previous (Incorrect) Definitions

The following definitions were speculative and have been superseded:

```python
# DEPRECATED - Do not use
DECODE_TYPES = {
    1: (44100, 2, "Media"),
    2: (44100, 2, "Alt Media"),  # Actually: STOP signal
    3: (8000, 1, "Phone Narrow"),
    4: (48000, 2, "Media HD"),   # Actually: Standard playback
    5: (16000, 1, "Siri"),       # Correct purpose, wrong details
    6: (24000, 1, "Voice"),
    7: (16000, 2, "Alt Voice"),
}
```

---

## audio_type Values (VERIFIED)

| Value | Name | Direction | Purpose |
|-------|------|-----------|---------|
| **1** | MAIN | IN | Primary playback (media, alerts, Siri speech, call audio) |
| **2** | NAVIGATION | IN | Navigation voice prompts (ducking channel) |
| **3** | MICROPHONE | OUT | Microphone input (Siri listening, phone call) |

### Direction Convention

- **IN**: Phone/Adapter → Head Unit (playback audio)
- **OUT**: Head Unit → Phone/Adapter (microphone capture)

---

## Audio Commands (0x07 with payload_len=13)

| Byte | Name | decode_type | audio_type | Verified |
|------|------|-------------|------------|----------|
| 0x01 | OUTPUT_START | 4, 5 | 1, 2 | Yes |
| 0x02 | OUTPUT_STOP | 4, 5 | 1, 2 | Yes |
| 0x03 | INPUT_START | 5 | 1 | Yes |
| 0x04 | INPUT_STOP | 5 | 1 | Yes |
| 0x05 | PHONECALL_START | 5 | 1 | Yes |
| 0x06 | PHONECALL_STOP | 2, 4 | 2 | Yes |
| 0x07 | NAVI_START | 4 | 2 | Yes |
| 0x08 | NAVI_STOP | 5 | 1 | Yes* |
| 0x09 | SIRI_START | 5 | 1 | Yes |
| 0x0A | MEDIA_START | 4 | 1 | Yes |
| 0x0B | MEDIA_STOP | 2, 4 | 1 | Yes |
| 0x0C | ALERT_START | 4 | 1 | Yes |
| 0x0D | ALERT_STOP | 4 | 1 | Yes |
| 0x0E | INCOMING_CALL_INIT | 5 | 1 | Yes |
| 0x10 | NAVI_COMPLETE | 4 | 2 | Yes |

*Note: NAVI_STOP (0x08) is used to activate Siri mode, not to stop navigation.

---

## Scenario Command Sequences

### Media Playback

```
MEDIA_START (dt=4, at=1)
OUTPUT_START (dt=4, at=1)
  ↓ [media audio packets: 11532 bytes each]
MEDIA_STOP (dt=4, at=1)
OUTPUT_STOP (dt=4, at=1)
```

### Navigation Prompt

```
PHONECALL_STOP (dt=2, at=2)      ← Channel clear
OUTPUT_START (dt=4, at=2)
NAVI_START (dt=4, at=2)
  ↓ [nav audio ~1.5-2 seconds]
NAVI_COMPLETE (dt=4, at=2)
OUTPUT_STOP (dt=4, at=2)
```

### Media + Navigation (Ducking)

```
MEDIA_START (dt=4, at=1)         ← Media begins
OUTPUT_START (dt=4, at=1)
  ↓ [media plays on audio_type=1]

PHONECALL_STOP (dt=2, at=2)      ← Nav prompt incoming
OUTPUT_START (dt=4, at=2)
NAVI_START (dt=4, at=2)
  ↓ [nav on at=2, media ducks on at=1]
NAVI_COMPLETE (dt=4, at=2)
OUTPUT_STOP (dt=4, at=2)
  ↓ [media resumes full volume]
```

### Siri Invocation

```
NAVI_STOP (dt=5, at=1)           ← Activates Siri mode
INPUT_START (dt=5, at=1)         ← Microphone on
OUTPUT_START (dt=5, at=1)        ← Audio output on
  ↓ [mic data OUT: dt=5, at=3, ~4 packets/sec]
  ↓ [Siri audio IN: dt=5, at=1, 972-byte packets]
SIRI_START (dt=5, at=1)          ← Siri responding
OUTPUT_STOP (dt=5, at=1)
```

### Incoming Phone Call

```
INCOMING_CALL_INIT (dt=5, at=1)  ← Call notification
  ↓ ~300ms
ALERT_START (dt=4, at=1)         ← Ringtone begins
OUTPUT_START (dt=4, at=1)
  ↓ [ringtone audio: dt=4, at=1]
  ↓ [rings 7-13 seconds until answered]
ALERT_STOP (dt=4, at=1)
OUTPUT_STOP (dt=4, at=1)
  ↓ ~150ms
INPUT_START (dt=5, at=1)         ← Mic activates
INPUT_STOP (dt=5, at=1)          ← State transition
OUTPUT_START (dt=5, at=1)        ← Call audio begins
  ↓ [call audio IN: dt=5, at=1]
  ↓ [mic data OUT: dt=5, at=3]
PHONECALL_START (dt=5, at=1)     ← Call connected
  ↓ [call in progress]
OUTPUT_STOP (dt=5, at=1)         ← Call ends
```

### Outgoing Phone Call

```
INPUT_STOP (dt=5, at=1)          ← Clear mic state
INPUT_START (dt=5, at=1)         ← Mic activates
OUTPUT_START (dt=5, at=1)        ← Audio output begins (ringback tone)
PHONECALL_START (dt=5, at=1)     ← Call connected
  ↓ [call audio IN: dt=5, at=1]
  ↓ [mic data OUT: dt=5, at=3]
OUTPUT_STOP (dt=5, at=1)         ← Call ends
```

**Key differences from incoming:**
- No INCOMING_CALL_INIT (0x0E) - that's incoming-specific
- No ALERT_START/STOP (0x0C/0x0D) - no ringtone for outgoing
- Ringback tone comes through regular call audio stream
- Simpler, immediate sequence to PHONECALL_START

---

## Audio Data Characteristics

### By Scenario

| Scenario | decode_type | audio_type | Direction | Packet Size | Rate |
|----------|-------------|------------|-----------|-------------|------|
| Media | 4 | 1 | IN | 11532 | ~85/sec |
| Navigation | 4 | 2 | IN | 11532 | ~85/sec |
| Ringtone/Alert | 4 | 1 | IN | 11532 | ~85/sec |
| Siri Speech | 5 | 1 | IN | 972 | ~33/sec |
| Phone Call Audio | 5 | 1 | IN | 972 | ~33/sec |
| Siri Microphone | 5 | 3 | OUT | 8204 | ~4/sec |
| Phone Call Mic | 5 | 3 | OUT | 1856-4900 | ~4/sec |

### Sample Calculations

**Media (dt=4):**
- Packet: 11532 bytes payload - 12 bytes header = 11520 bytes PCM
- At 48kHz stereo 16-bit: 11520 / 4 = 2880 samples = 60ms audio
- Rate: ~85 packets/sec confirms 48kHz

**Voice (dt=5):**
- Packet: 972 bytes payload - 12 bytes header = 960 bytes PCM
- At 16kHz mono 16-bit: 960 / 2 = 480 samples = 30ms audio
- Rate: ~33 packets/sec confirms 16kHz

---

## Verification Data

### Capture Sessions Analyzed

| Scenario | Sessions | Total Packets | Patterns Consistent |
|----------|----------|---------------|---------------------|
| Video Only | 3 | 9,678 | 100% (no audio) |
| Media Playback | 3 | 11,204 | 100% |
| Navigation | 3 | 1,455 | 100% |
| Media+Navigation | 3 | 5,660 | 100% |
| Siri | 3 | 7,724 | 100% |
| Incoming Phone Call | 3 | 4,459 | 100% |
| Outgoing Phone Call | 3 | 5,128 | 100% |

**Total: 21 sessions across 7 scenarios**

### Command Frequencies

| Command | Media | Nav | Media+Nav | Siri | Incoming | Outgoing |
|---------|-------|-----|-----------|------|----------|----------|
| OUTPUT_START | 9 | 13 | 15 | 25 | 25 | 9 |
| OUTPUT_STOP | 6 | 13 | 12 | 25 | 25 | 9 |
| INPUT_START | 0 | 0 | 0 | 25 | 9 | 9 |
| INPUT_STOP | 0 | 0 | 0 | 0 | 9 | 9 |
| PHONECALL_START | 0 | 0 | 0 | 0 | 18 | 9 |
| PHONECALL_STOP | 0 | 22 | 18 | 0 | 0 | 0 |
| NAVI_START | 0 | 22 | 18 | 0 | 0 | 0 |
| NAVI_STOP | 0 | 0 | 0 | 27 | 0 | 0 |
| NAVI_COMPLETE | 0 | 13 | 12 | 0 | 0 | 0 |
| SIRI_START | 0 | 0 | 0 | 27 | 0 | 0 |
| MEDIA_START | 12 | 0 | 6 | 0 | 0 | 0 |
| MEDIA_STOP | 9 | 0 | 2 | 0 | 0 | 0 |
| ALERT_START | 3 | 0 | 0 | 0 | 16 | 0 |
| ALERT_STOP | 3 | 0 | 0 | 0 | 16 | 0 |
| INCOMING_CALL_INIT | 0 | 0 | 0 | 0 | 9 | 0 |

### Phone Call Comparison

| Aspect | Incoming | Outgoing |
|--------|----------|----------|
| INCOMING_CALL_INIT | ✅ | ❌ |
| ALERT_START/STOP | ✅ (ringtone) | ❌ |
| INPUT_STOP before INPUT_START | ❌ | ✅ |
| Ringback tone | N/A | In audio stream |

---

## Implementation Notes

### For CarPlay Receiver Implementation

1. **Audio Routing**: Use `audio_type` to route to correct output
   - `at=1`: Main speakers
   - `at=2`: Navigation channel (may duck at=1)
   - `at=3`: Microphone input stream

2. **Sample Rate Selection**: Use `decode_type` to set audio format
   - `dt=4`: 48kHz stereo (or 44.1kHz based on negotiation)
   - `dt=5`: 16kHz mono

3. **Command Handling**: Process control packets (payload_len=13) to manage audio state

4. **Microphone**: When `INPUT_START` received, begin streaming `at=3` packets OUT

### Volume Handling

The volume field (offset 32, float32) is typically 0.0 for most packets. Non-zero values observed:
- Navigation volume adjustment: 0.2-1.0 (in 16-byte extended packets)
- May indicate ducking level for at=1 when at=2 is active

---

## References

- `captures/picarplay/carplay/reference/` - Verified capture data
- `tools/analysis/process_all_captures.py` - Analysis scripts
- `docs/hardware/REVERSE_ENGINEERING_NOTES.md` - Protocol details
