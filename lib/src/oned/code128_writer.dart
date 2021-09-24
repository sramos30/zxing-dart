/*
 * Copyright 2010 ZXing authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import '../barcode_format.dart';
import '../encode_hint_type.dart';
import 'code128_reader.dart';
import 'one_dimensional_code_writer.dart';

enum _CType { UNCODABLE, ONE_DIGIT, TWO_DIGITS, FNC_1 }

/// This object renders a CODE128 code as a [BitMatrix].
///
/// @author erik.barbara@gmail.com (Erik Barbara)
class Code128Writer extends OneDimensionalCodeWriter {
  static const int _CODE_START_A = 103;
  static const int _CODE_START_B = 104;
  static const int _CODE_START_C = 105;
  static const int _CODE_CODE_A = 101;
  static const int _CODE_CODE_B = 100;
  static const int _CODE_CODE_C = 99;
  static const int _CODE_STOP = 106;

  // Dummy characters used to specify control characters in input
  static const int _ESCAPE_FNC_1 = 0xf1; //'\u00f1';
  static const int _ESCAPE_FNC_2 = 0xf2; //'\u00f2';
  static const int _ESCAPE_FNC_3 = 0xf3; //'\u00f3';
  static const int _ESCAPE_FNC_4 = 0xf4; //'\u00f4';

  static const int _CODE_FNC_1 = 102; // Code A, Code B, Code C
  static const int _CODE_FNC_2 = 97; // Code A, Code B
  static const int _CODE_FNC_3 = 96; // Code A, Code B
  static const int _CODE_FNC_4_A = 101; // Code A
  static const int _CODE_FNC_4_B = 100; // Code B

  /// Results of minimal lookahead for code C
  //@protected
  @override
  List<BarcodeFormat> get supportedWriteFormats => [BarcodeFormat.CODE_128];

  @override
  List<bool> encodeContent(String contents,
      [Map<EncodeHintType, Object?>? hints]) {
    int length = contents.length;
    // Check length
    if (length < 1 || length > 80) {
      throw Exception(
          "Contents length should be between 1 and 80 characters, but got $length");
    }
    // Check for forced code set hint.
    int forcedCodeSet = -1;
    if (hints != null && hints.containsKey(EncodeHintType.FORCE_CODE_SET)) {
      String codeSetHint = hints[EncodeHintType.FORCE_CODE_SET] as String;
      switch (codeSetHint) {
        case "A":
          forcedCodeSet = _CODE_CODE_A;
          break;
        case "B":
          forcedCodeSet = _CODE_CODE_B;
          break;
        case "C":
          forcedCodeSet = _CODE_CODE_C;
          break;
        default:
          throw ArgumentError("Unsupported code set hint: " + codeSetHint);
      }
    }

    // Check content
    for (int i = 0; i < length; i++) {
      int c = contents.codeUnitAt(i);
      // check for non ascii characters that are not special GS1 characters
      switch (c) {
        // special function characters
        case _ESCAPE_FNC_1:
        case _ESCAPE_FNC_2:
        case _ESCAPE_FNC_3:
        case _ESCAPE_FNC_4:
          break;
        // non ascii characters
        default:
          if (c > 127) {
            // no full Latin-1 character set available at the moment
            // shift and manual code change are not supported
            throw ArgumentError("Bad character in input: ASCII value=: $c");
          }
      }
      // check characters for compatibility with forced code set
      switch (forcedCodeSet) {
        case _CODE_CODE_A:
          // allows no ascii above 95 (no lower caps, no special symbols)
          if (c > 95 && c <= 127) {
            throw ArgumentError(
                "Bad character in input for forced code set A: ASCII value=$c");
          }
          break;
        case _CODE_CODE_B:
          // allows no ascii below 32 (terminal symbols)
          if (c <= 32) {
            throw ArgumentError(
                "Bad character in input for forced code set B: ASCII value=$c");
          }
          break;
        case _CODE_CODE_C:
          // allows only numbers and no FNC 2/3/4
          if (c < 48 ||
              (c > 57 && c <= 127) ||
              c == _ESCAPE_FNC_2 ||
              c == _ESCAPE_FNC_3 ||
              c == _ESCAPE_FNC_4) {
            throw ArgumentError(
                "Bad character in input for forced code set C: ASCII value=$c");
          }
          break;
      }
    }

    List<List<int>> patterns = []; // temporary storage for patterns
    int checkSum = 0;
    int checkWeight = 1;
    int codeSet = 0; // selected code (CODE_CODE_B or CODE_CODE_C)
    int position = 0; // position in contents

    while (position < length) {
      //Select code to use
      int newCodeSet;
      if (forcedCodeSet == -1) {
        newCodeSet = _chooseCode(contents, position, codeSet);
      } else {
        newCodeSet = forcedCodeSet;
      }
      //Get the pattern index
      int patternIndex;
      if (newCodeSet == codeSet) {
        // Encode the current character
        // First handle escapes
        switch (contents.codeUnitAt(position)) {
          case _ESCAPE_FNC_1:
            patternIndex = _CODE_FNC_1;
            break;
          case _ESCAPE_FNC_2:
            patternIndex = _CODE_FNC_2;
            break;
          case _ESCAPE_FNC_3:
            patternIndex = _CODE_FNC_3;
            break;
          case _ESCAPE_FNC_4:
            if (codeSet == _CODE_CODE_A) {
              patternIndex = _CODE_FNC_4_A;
            } else {
              patternIndex = _CODE_FNC_4_B;
            }
            break;
          default:
            // Then handle normal characters otherwise
            switch (codeSet) {
              case _CODE_CODE_A:
                patternIndex = contents.codeUnitAt(position) - 32 /*   */;
                if (patternIndex < 0) {
                  // everything below a space character comes behind the underscore in the code patterns table
                  patternIndex += 96 /* ` */;
                }
                break;
              case _CODE_CODE_B:
                patternIndex = contents.codeUnitAt(position) - 32 /*   */;
                break;
              default:
                // CODE_CODE_C
                if (position + 1 == length) {
                  // this is the last character, but the encoding is C, which always encodes two characers
                  throw ArgumentError(
                      "Bad number of characters for digit only encoding.");
                }
                patternIndex =
                    int.parse(contents.substring(position, position + 2));
                position++; // Also incremented below
                break;
            }
        }
        position++;
      } else {
        // Should we change the current code?
        // Do we have a code set?
        if (codeSet == 0) {
          // No, we don't have a code set
          switch (newCodeSet) {
            case _CODE_CODE_A:
              patternIndex = _CODE_START_A;
              break;
            case _CODE_CODE_B:
              patternIndex = _CODE_START_B;
              break;
            default:
              patternIndex = _CODE_START_C;
              break;
          }
        } else {
          // Yes, we have a code set
          patternIndex = newCodeSet;
        }
        codeSet = newCodeSet;
      }

      // Get the pattern
      patterns.add(Code128Reader.CODE_PATTERNS[patternIndex]);

      // Compute checksum
      checkSum += patternIndex * checkWeight;
      if (position != 0) {
        checkWeight++;
      }
    }

    // Compute and append checksum
    checkSum %= 103;
    patterns.add(Code128Reader.CODE_PATTERNS[checkSum]);

    // Append stop code
    patterns.add(Code128Reader.CODE_PATTERNS[_CODE_STOP]);

    // Compute code width
    int codeWidth = 0;
    for (List<int> pattern in patterns) {
      for (int width in pattern) {
        codeWidth += width;
      }
    }

    // Compute result
    List<bool> result = List.filled(codeWidth, false);
    int pos = 0;
    for (List<int> pattern in patterns) {
      pos += OneDimensionalCodeWriter.appendPattern(result, pos, pattern, true);
    }

    return result;
  }

  static _CType _findCType(String value, int start) {
    int last = value.length;
    if (start >= last) {
      return _CType.UNCODABLE;
    }
    if (value[start] == _ESCAPE_FNC_1) {
      return _CType.FNC_1;
    }
    int c = value.codeUnitAt(start);
    if (c < 48 /* 0 */ || c > 57 /* 9 */) {
      return _CType.UNCODABLE;
    }
    if (start + 1 >= last) {
      return _CType.ONE_DIGIT;
    }
    c = value.codeUnitAt(start + 1);
    if (c < 48 /* 0 */ || c > 57 /* 9 */) {
      return _CType.ONE_DIGIT;
    }
    return _CType.TWO_DIGITS;
  }

  static int _chooseCode(String value, int start, int oldCode) {
    _CType lookahead = _findCType(value, start);
    if (lookahead == _CType.ONE_DIGIT) {
      if (oldCode == _CODE_CODE_A) {
        return _CODE_CODE_A;
      }
      return _CODE_CODE_B;
    }
    if (lookahead == _CType.UNCODABLE) {
      if (start < value.length) {
        int c = value.codeUnitAt(start);
        if (c < 32 /*   */ ||
            (oldCode == _CODE_CODE_A &&
                (c < 96 /* ` */ ||
                    (c >= _ESCAPE_FNC_1 && c <= _ESCAPE_FNC_4)))) {
          // can continue in code A, encodes ASCII 0 to 95 or FNC1 to FNC4
          return _CODE_CODE_A;
        }
      }
      return _CODE_CODE_B; // no choice
    }
    if (oldCode == _CODE_CODE_A && lookahead == _CType.FNC_1) {
      return _CODE_CODE_A;
    }
    if (oldCode == _CODE_CODE_C) {
      // can continue in code C
      return _CODE_CODE_C;
    }
    if (oldCode == _CODE_CODE_B) {
      if (lookahead == _CType.FNC_1) {
        return _CODE_CODE_B; // can continue in code B
      }
      // Seen two consecutive digits, see what follows
      lookahead = _findCType(value, start + 2);
      if (lookahead == _CType.UNCODABLE || lookahead == _CType.ONE_DIGIT) {
        return _CODE_CODE_B; // not worth switching now
      }
      if (lookahead == _CType.FNC_1) {
        // two digits, then FNC_1...
        lookahead = _findCType(value, start + 3);
        if (lookahead == _CType.TWO_DIGITS) {
          // then two more digits, switch
          return _CODE_CODE_C;
        } else {
          return _CODE_CODE_B; // otherwise not worth switching
        }
      }
      // At this point, there are at least 4 consecutive digits.
      // Look ahead to choose whether to switch now or on the next round.
      int index = start + 4;
      while ((lookahead = _findCType(value, index)) == _CType.TWO_DIGITS) {
        index += 2;
      }
      if (lookahead == _CType.ONE_DIGIT) {
        // odd number of digits, switch later
        return _CODE_CODE_B;
      }
      return _CODE_CODE_C; // even number of digits, switch now
    }
    // Here oldCode == 0, which means we are choosing the initial code
    if (lookahead == _CType.FNC_1) {
      // ignore FNC_1
      lookahead = _findCType(value, start + 1);
    }
    if (lookahead == _CType.TWO_DIGITS) {
      // at least two digits, start in code C
      return _CODE_CODE_C;
    }
    return _CODE_CODE_B;
  }
}
