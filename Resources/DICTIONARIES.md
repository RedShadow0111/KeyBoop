# Словари

Списки `Sources/KeyBoopCore/Dictionaries/en.txt` и `ru.txt` собраны из частотных списков [Hermit Dave, FrequencyWords](https://github.com/hermitdave/FrequencyWords) (корпус OpenSubtitles 2018, файлы `en_50k.txt` и `ru_50k.txt`).

- Код генератора FrequencyWords — MIT.
- Сами частотные списки — [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
- Условие ShareAlike относится к этим двум файлам, не к исходному коду KeyBoop (он под MIT).

При очистке оставлены только слова из букв языка, `ё` приведена к `е` (так ищется слово; при наборе `ё` не меняется). Строки с цифрами, дефисом и латиницей внутри русского списка отброшены.

`extra_en.txt` и `extra_ru.txt` — короткий собственный список KeyBoop (технические слова вроде `https`, `json`, `клавиатура`). Он распространяется вместе с кодом по MIT.

Повторить сборку списков:

```bash
python3 Scripts/fetch-dictionaries.py
```
