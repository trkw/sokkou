#!/usr/bin/env python3
"""azooKey の辞書から、英単語とそのカタカナ読みの表（Sources/SokkouEngine/Resources/loanwords.tsv）を作る。

azooKey の辞書には「読み テスト → 語 test」のような、カタカナの読みに英語の綴りを当てた語がある。
これを逆に引き、英語と判定した test にも テスト を候補として出す。

  git clone https://github.com/ensan-hcl/azooKey_dictionary_storage
  git -C azooKey_dictionary_storage checkout <AzooKeyKanaKanjiConverter が指す版>
  python3 scripts/make-loanwords.py azooKey_dictionary_storage/Dictionary/louds > Sources/SokkouEngine/Resources/loanwords.tsv

辞書は Apache License 2.0。
"""
import glob
import os
import re
import struct
import sys

# 人名（1290 1291）と単位の略号（1300）は外す。tomoe → トモエ や mg → ミリグラム は英単語の読みではない
SKIPPED_IDS = {1290, 1291, 1300}
# 一般の語（名詞・動詞・形容詞）。固有名詞（Bar → バリ など）より先に並べる
GENERAL_IDS = {1283, 1285, 1287}
# 1 語あたりに残す読みの数
MAX_READINGS = 3

# アルファベットの読み。NYSE → エヌワイエスイー のような、文字を 1 つずつ読んだだけの略語を外すのに使う
LETTERS = {
    "a": "エー|エイ", "b": "ビー", "c": "シー", "d": "ディー|デー", "e": "イー", "f": "エフ",
    "g": "ジー|ジ", "h": "エイチ|エッチ|エッチ", "i": "アイ", "j": "ジェー|ジェイ", "k": "ケー|ケイ",
    "l": "エル", "m": "エム", "n": "エヌ|エン", "o": "オー", "p": "ピー", "q": "キュー",
    "r": "アール", "s": "エス", "t": "ティー|テー", "u": "ユー", "v": "ブイ|ヴィー|ヴイ",
    "w": "ダブリュー|ダブル|ダブリュ", "x": "エックス|エクス", "y": "ワイ", "z": "ゼット|ズィー|ゼッド",
}
WORD = re.compile(r"[A-Za-z]{2,}")
KATAKANA = re.compile(r"[ァ-ヴー]+")


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


def main():
    best = {}
    for ruby, word, lcid, score in entries(sys.argv[1]):
        if lcid in SKIPPED_IDS or not WORD.fullmatch(word) or not KATAKANA.fullmatch(ruby):
            continue
        if spelled_out(word, ruby):
            continue
        readings = best.setdefault(word.lower(), {})
        rank = (lcid in GENERAL_IDS, score)
        readings[ruby] = max(rank, readings.get(ruby, rank))
    print("# 英単語\tカタカナの読み（よく使う順）。scripts/make-loanwords.py が azooKey の辞書（Apache License 2.0）から作る")
    for word in sorted(best):
        readings = sorted(best[word], key=lambda ruby: (best[word][ruby], ruby), reverse=True)[:MAX_READINGS]
        print(word + "\t" + "\t".join(readings))


main()
