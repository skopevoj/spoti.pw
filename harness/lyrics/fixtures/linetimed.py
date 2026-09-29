#!/usr/bin/env python3
"""Writes the fixtures for lyrics timed by the line and not at all (issue 61), from plain.lrc's timing
and filler words, so they carry no song's lyrics:

- linetimed.ttml  Apple Music TTML with itunes:timing="Line": two voices, a pair of lines sung over
                  each other, a right to left line, an 11 s break, and an English translation of some
                  lines in the head, as BiniLyrics serves its line timed songs
- spotify-line.json    Spotify's color-lyrics JSON, syncType LINE_SYNCED
- spotify-static.json  the same, UNSYNCED, every start 0
- static.txt      plain text with stanza breaks, as LRCLIB's plainLyrics comes

    ./linetimed.py      # rewrites all four next to this script
"""
import json
import re
from pathlib import Path

HERE = Path(__file__).parent
rows = []
for row in (HERE / 'plain.lrc').read_text().splitlines():
    m = re.match(r'\[(\d+):(\d+\.\d+)\]\s?(.*)', row)
    if m:
        rows.append((round((int(m[1]) * 60 + float(m[2])) * 1000), m[3]))


def clock(ms):
    return f'{ms // 60000}:{ms % 60000 / 1000:06.3f}'


lines = []   # (start, end, text, voice)
for i, (start, text) in enumerate(rows):
    if not text or text == '♪':
        continue
    nxt = rows[i + 1][0] if i + 1 < len(rows) else start + 3000
    lines.append([start, min(nxt, start + 4000), text, 'v1'])
# The second voice takes every fourth line; the sixth line is sung over by the seventh, which comes in
# half way through it; the ninth reads right to left.
for n, line in enumerate(lines):
    if n % 4 == 3:
        line[3] = 'v2'
lines[5][1] = lines[6][0] + 1500
lines[6][0] = lines[5][0] + 1200
lines[8][2] = 'שלום עולם אני שר לך'
lines.sort(key=lambda l: l[0])

translations = ''.join(f'<text for="L{n}">Translated {n}: {line[2].lower()}</text>'
                       for n, line in enumerate(lines) if n % 2 == 0)
body = ''.join(f'<p begin="{clock(s)}" end="{clock(e)}" itunes:key="L{n}" ttm:agent="{v}">{t}</p>'
               for n, (s, e, t, v) in enumerate(lines))
(HERE / 'linetimed.ttml').write_text(
    '<tt xmlns="http://www.w3.org/ns/ttml" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" '
    'xmlns:ttm="http://www.w3.org/ns/ttml#metadata" itunes:timing="Line" xml:lang="en"><head><metadata>'
    '<ttm:agent type="person" xml:id="v1"/><ttm:agent type="person" xml:id="v2"/>'
    '<iTunesMetadata xmlns="http://music.apple.com/lyric-ttml-internal"><translations>'
    f'<translation type="subtitle" xml:lang="en-US">{translations}</translation></translations>'
    '</iTunesMetadata></metadata></head><body><div>' + body + '</div></body></tt>\n')


def spotify(synced):
    return json.dumps({'lyrics': {
        'syncType': 'LINE_SYNCED' if synced else 'UNSYNCED',
        'lines': [{'startTimeMs': str(s if synced else 0), 'words': t, 'syllables': [], 'endTimeMs': '0'}
                  for s, t in rows],
    }}, ensure_ascii=False, indent=1) + '\n'


(HERE / 'spotify-line.json').write_text(spotify(True))
(HERE / 'spotify-static.json').write_text(spotify(False))
(HERE / 'static.txt').write_text('\n'.join('' if t in ('', '♪') else t for _, t in rows) + '\n')
