#!/usr/bin/env python3
"""英単語とそのカタカナ読みの表（Sources/SokkouEngine/Resources/loanwords.tsv）を作る。

2 つの辞書から集める。
- azooKey の辞書（Apache License 2.0）: 「読み テスト → 語 test」のような、カタカナの読みに英語の綴りを当てた語を逆に引く
- JMdict（CC BY-SA 4.0、EDRDG）: 漢字を持たないカタカナ語のうち、英語の訳語と音が近いもの（ゲーム → game）。
  azooKey の辞書には game や online が無いので、よく使う語をこちらで補う

  git clone https://github.com/ensan-hcl/azooKey_dictionary_storage
  git -C azooKey_dictionary_storage checkout <AzooKeyKanaKanjiConverter が指す版>
  # JMdict は jmdict-simplified（https://github.com/scriptin/jmdict-simplified）のリリースの jmdict-eng-*.json
  python3 scripts/make-loanwords.py azooKey_dictionary_storage/Dictionary/louds jmdict-eng-3.6.1.json \
      > Sources/SokkouEngine/Resources/loanwords.tsv
"""
import difflib
import glob
import json
import os
import re
import struct
import sys

# 人名（1290 1291）と単位の略号（1300）は外す。tomoe → トモエ や mg → ミリグラム は英単語の読みではない
SKIPPED_IDS = {1290, 1291, 1300}
# 一般の語（名詞・動詞・形容詞）。固有名詞（Bar → バリ など）より先に並べる
GENERAL_IDS = {1283, 1285, 1287}
# 読みの並び。小さいほど先。azooKey の読みを先に、JMdict は azooKey に無い語を補うために後ろに置く。
# JMdict は音の近さで拾うので、mobile → メリー（つるす玩具）のような訳語が混じることがある
AZOOKEY_GENERAL, AZOOKEY_OTHER, JMDICT_COMMON, JMDICT_OTHER = range(4)
# 1 語あたりに残す読みの数
MAX_READINGS = 3
# JMdict の訳語と読みの子音の並びが、どれだけ似ていれば読みとみなすか（test と テスト は似ていて、exam と テスト は似ていない）
MIN_SIMILARITY = 0.75

# アルファベットの読み。NYSE → エヌワイエスイー のような、文字を 1 つずつ読んだだけの略語を外すのに使う
LETTERS = {
    "a": "エー|エイ|アー", "b": "ビー", "c": "シー", "d": "ディー|デー", "e": "イー", "f": "エフ",
    "g": "ジー|ジ", "h": "エイチ|エッチ", "i": "アイ", "j": "ジェー|ジェイ", "k": "ケー|ケイ",
    "l": "エル", "m": "エム", "n": "エヌ|エン", "o": "オー", "p": "ピー", "q": "キュー",
    "r": "アール", "s": "エス", "t": "ティー|テー", "u": "ユー", "v": "ブイ|ヴィー|ヴイ",
    "w": "ダブリュー|ダブル|ダブリュ", "x": "エックス|エクス", "y": "ワイ", "z": "ゼット|ズィー|ゼッド",
}
WORD = re.compile(r"[A-Za-z]{2,}")
KATAKANA = re.compile(r"[ァ-ヴー]+")

# カタカナの子音。母音・長音・促音・ヤ行は空にする。マ行は ン と同じ n に（コンピューター の ン と computer の m）、
# ザ行はサ行と同じ s にする（シリーズ と series）
KANA_CONSONANTS = {}
for consonant, row in [
    ("k", "カキクケコ"), ("g", "ガギグゲゴ"), ("s", "サシスセソザズゼゾヅ"), ("j", "ジヂ"),
    ("t", "タツテト"), ("c", "チ"), ("d", "ダデド"), ("n", "ナニヌネノマミムメモン"), ("h", "ハヒヘホ"),
    ("f", "フ"), ("b", "バビブベボヴ"), ("p", "パピプペポ"), ("r", "ラリルレロ"),
]:
    for kana in row:
        KANA_CONSONANTS[kana] = consonant
# 英語の綴りを、カタカナの子音と比べられる形にする置き換え。前から順に当てる
ENGLISH_SOUNDS = [
    ("tion", "sn"), ("sion", "sn"), ("ph", "f"), ("th", "s"), ("ck", "k"), ("sh", "s"), ("ch", "c"),
    ("qu", "k"), ("x", "ks"), ("q", "k"), ("v", "b"), ("l", "r"), ("m", "n"), ("z", "s"),
]


def entries(directory):
    """loudstxt3 の各行を (読み, 語, 品詞の id, 点数) で返す。形式は azooKey の Loudstxt3Builder を見る"""
    for path in sorted(glob.glob(os.path.join(directory, "*.loudstxt3"))):
        data = open(path, "rb").read()
        count = struct.unpack_from("<H", data, 0)[0]
        offsets = list(struct.unpack_from(f"<{count}I", data, 2)) + [len(data)]
        for start, end in zip(offsets, offsets[1:]):
            rows = struct.unpack_from("<H", data, start)[0]
            if rows == 0:
                continue
            fields = [struct.unpack_from("<HHHf", data, start + 2 + 10 * i) for i in range(rows)]
            texts = data[start + 2 + 10 * rows:end].decode("utf-8").split("\t")
            ruby = texts[0]
            for (lcid, _, _, score), word in zip(fields, texts[1:]):
                yield ruby, word or ruby, lcid, score


def spelled_out(word, ruby):
    return re.fullmatch("".join(f"(?:{LETTERS[c]})" for c in word.lower()), ruby) is not None


def squeeze(consonants):
    return re.sub(r"(.)\1+", r"\1", consonants)


def kana_consonants(katakana):
    return squeeze("".join(KANA_CONSONANTS.get(kana, "") for kana in katakana))


def english_consonants(word):
    for spelling, sound in ENGLISH_SOUNDS:
        word = word.replace(spelling, sound)
    word = re.sub(r"c(?=[eiy])", "s", word).replace("c", "k")
    word = re.sub(r"g(?=[eiy])", "j", word)
    return squeeze(re.sub(r"[aeiouhwy]", "", word))


def is_subsequence(short, long):
    rest = iter(long)
    return all(consonant in rest for consonant in short)


def sounds_alike(word, katakana):
    """英語の子音がすべて順に読みに現れ、全体も似ているか。英語の子音を落とした読み（mobile と メリー）は別の語とみなす"""
    kana = kana_consonants(katakana)
    # 語末の r は長音になることが多い（door と ドア）
    for english in {english_consonants(word), english_consonants(word).removesuffix("r")}:
        if (english and kana and english[0] == kana[0] and is_subsequence(english, kana)
                and difflib.SequenceMatcher(None, english, kana).ratio() >= MIN_SIMILARITY):
            return True
    return False


def azookey_readings(directory):
    """(英単語, 読み, 並び, 点数) を返す"""
    for ruby, word, lcid, score in entries(directory):
        if lcid in SKIPPED_IDS or not WORD.fullmatch(word) or not KATAKANA.fullmatch(ruby):
            continue
        if spelled_out(word, ruby):
            continue
        yield word.lower(), ruby, AZOOKEY_GENERAL if lcid in GENERAL_IDS else AZOOKEY_OTHER, score


def jmdict_readings(path):
    """(英単語, 読み, 並び, 点数) を返す。英語以外から来た語、略語、まれな表記や誤った表記は外す"""
    for entry in json.load(open(path, encoding="utf-8"))["words"]:
        if entry["kanji"]:
            continue
        for sense in entry["sense"]:
            if "abbr" in sense["misc"] or any(source["lang"] != "eng" for source in sense["languageSource"]):
                continue
            for gloss in sense["gloss"]:
                word = re.sub(r"\([^)]*\)", "", gloss["text"]).strip().lower()
                if not WORD.fullmatch(word):
                    continue
                for kana in entry["kana"]:
                    katakana = kana["text"].replace("・", "")
                    if not KATAKANA.fullmatch(katakana) or {"ik", "ok", "sk", "rk"} & set(kana["tags"]):
                        continue
                    if sounds_alike(word, katakana):
                        yield word, katakana, JMDICT_COMMON if kana["common"] else JMDICT_OTHER, 0.0


def main():
    best = {}
    readings = list(azookey_readings(sys.argv[1]))
    if len(sys.argv) > 2:
        readings += jmdict_readings(sys.argv[2])
    for word, katakana, order, score in readings:
        found = best.setdefault(word, {})
        rank = (-order, score)
        found[katakana] = max(rank, found.get(katakana, rank))
    print("# 英単語\tカタカナの読み（よく使う順）。scripts/make-loanwords.py が azooKey の辞書（Apache License 2.0）"
          "と JMdict（CC BY-SA 4.0、Electronic Dictionary Research and Development Group）から作る")
    for word in sorted(best):
        found = sorted(best[word], key=lambda katakana: (best[word][katakana], katakana), reverse=True)
        print(word + "\t" + "\t".join(found[:MAX_READINGS]))


main()
