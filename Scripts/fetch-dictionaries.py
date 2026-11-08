#!/usr/bin/env python3
"""Rebuild en.txt and ru.txt from Hermit Dave FrequencyWords (CC BY-SA 4.0)."""

import pathlib
import re
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1] / "Sources" / "KeyBoopCore" / "Dictionaries"
SOURCES = {
    "en": "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt",
    "ru": "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/ru/ru_50k.txt",
}
HEADER = (
    "# Hermit Dave FrequencyWords (OpenSubtitles 2018), CC BY-SA 4.0. "
    "See Resources/DICTIONARIES.md\n"
)


def clean(text: str, pattern: str) -> list[str]:
    seen: set[str] = set()
    words: list[str] = []
    rx = re.compile(pattern)
    for line in text.splitlines():
        word = line.split(" ", 1)[0].strip().lower().replace("ё", "е")
        if not rx.fullmatch(word) or word in seen:
            continue
        seen.add(word)
        words.append(word)
    return words


def main() -> None:
    english = clean(urllib.request.urlopen(SOURCES["en"], timeout=60).read().decode("utf-8"), r"[a-z]+")
    russian = clean(urllib.request.urlopen(SOURCES["ru"], timeout=60).read().decode("utf-8"), r"[а-я]+")
    (ROOT / "en.txt").write_text(HEADER + "\n".join(english) + "\n", encoding="utf-8")
    (ROOT / "ru.txt").write_text(HEADER + "\n".join(russian) + "\n", encoding="utf-8")
    print(f"en {len(english)} ru {len(russian)}")


if __name__ == "__main__":
    main()
