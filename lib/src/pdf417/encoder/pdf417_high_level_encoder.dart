/*
 * Copyright 2006 Jeremias Maerki in part, and ZXing Authors in part
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:convert';
/*
 * This file has been modified from its original form in Barcode4J.
 */

import 'dart:math' as math;
import 'dart:typed_data';

import '../../common/character_set_eci.dart';
import '../../common/string_builder.dart';
import '../../writer_exception.dart';
import 'compaction.dart';

/// PDF417 high-level encoder following the algorithm described in ISO/IEC 15438:2001(E) in
/// annex P.
class PDF417HighLevelEncoder {
  static final int _blankCode = 32 /*   */;

  /// code for Text compaction
  static const int _TEXT_COMPACTION = 0;

  /// code for Byte compaction
  static const int _BYTE_COMPACTION = 1;

  /// code for Numeric compaction
  static const int _NUMERIC_COMPACTION = 2;

  /// Text compaction submode Alpha
  static const int _SUBMODE_ALPHA = 0;

  /// Text compaction submode Lower
  static const int _SUBMODE_LOWER = 1;

  /// Text compaction submode Mixed
  static const int _SUBMODE_MIXED = 2;

  /// Text compaction submode Punctuation
  static const int _SUBMODE_PUNCTUATION = 3;

  /// mode latch to Text Compaction mode
  static const int _LATCH_TO_TEXT = 900;

  /// mode latch to Byte Compaction mode (number of characters NOT a multiple of 6)
  static const int _LATCH_TO_BYTE_PADDED = 901;

  /// mode latch to Numeric Compaction mode
  static const int _LATCH_TO_NUMERIC = 902;

  /// mode shift to Byte Compaction mode
  static const int _SHIFT_TO_BYTE = 913;

  /// mode latch to Byte Compaction mode (number of characters a multiple of 6)
  static const int _LATCH_TO_BYTE = 924;

  /// identifier for a user defined Extended Channel Interpretation (ECI)
  static const int _ECI_USER_DEFINED = 925;

  /// identifier for a general purpose ECO format
  static const int _ECI_GENERAL_PURPOSE = 926;

  /// identifier for an ECI of a character set of code page
  static const int _ECI_CHARSET = 927;

  /// Raw code table for text compaction Mixed sub-mode
  static const List<int> _TEXT_MIXED_RAW = [
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 38, 13, 9, 44, 58, //
    35, 45, 46, 36, 47, 43, 37, 42, 61, 94, 0, 32, 0, 0, 0
  ];

  /// Raw code table for text compaction: Punctuation sub-mode
  static final List<int> _textPunctuationRaw = [
    59, 60, 62, 64, 91, 92, 93, 95, 96, 126, 33, 13, 9, 44, 58, //
    10, 45, 46, 36, 47, 34, 124, 42, 40, 41, 63, 123, 125, 39, 0
  ];

  static final Uint8List _mixed = Uint8List.fromList(
      List.generate(128, (index) => _TEXT_MIXED_RAW.indexOf(index)));
  static final Uint8List _punctuatuin = Uint8List.fromList(
      List.generate(128, (index) => _textPunctuationRaw.indexOf(index)));

  static final Encoding _defaultEncoding = latin1;

  PDF417HighLevelEncoder._();

  /// Performs high-level encoding of a PDF417 message using the algorithm described in annex P
  /// of ISO/IEC 15438:2001(E). If byte compaction has been selected, then only byte compaction
  /// is used.
  ///
  /// @param msg the message
  /// @param compaction compaction mode to use
  /// @param encoding character encoding used to encode in default or byte compaction
  ///  or `null` for default / not applicable
  /// @return the encoded message (the char values range from 0 to 928)
  static String encodeHighLevel(
      String msg, Compaction compaction, Encoding? encoding) {
    //the codewords 0..928 are encoded as Unicode characters
    StringBuffer sb = StringBuffer();

    if (encoding == null) {
      encoding = _defaultEncoding;
    } else if (_defaultEncoding != encoding) {
      CharacterSetECI? eci = CharacterSetECI.getCharacterSetECI(encoding);
      if (eci != null) {
        _encodingECI(eci.value, sb);
      }
    }

    int len = msg.length;
    int p = 0;
    int textSubMode = _SUBMODE_ALPHA;

    // User selected encoding mode
    switch (compaction) {
      case Compaction.TEXT:
        _encodeText(msg, p, len, sb, textSubMode);
        break;
      case Compaction.BYTE:
        Uint8List msgBytes = Uint8List.fromList(encoding.encode(msg));
        _encodeBinary(msgBytes, p, msgBytes.length, _BYTE_COMPACTION, sb);
        break;
      case Compaction.NUMERIC:
        sb.writeCharCode(_LATCH_TO_NUMERIC);
        _encodeNumeric(msg, p, len, sb);
        break;
      default:
        int encodingMode = _TEXT_COMPACTION; //Default mode, see 4.4.2.1
        while (p < len) {
          int n = _determineConsecutiveDigitCount(msg, p);
          if (n >= 13) {
            sb.writeCharCode(_LATCH_TO_NUMERIC);
            encodingMode = _NUMERIC_COMPACTION;
            textSubMode = _SUBMODE_ALPHA; //Reset after latch
            _encodeNumeric(msg, p, n, sb);
            p += n;
          } else {
            int t = _determineConsecutiveTextCount(msg, p);
            if (t >= 5 || n == len) {
              if (encodingMode != _TEXT_COMPACTION) {
                sb.writeCharCode(_LATCH_TO_TEXT);
                encodingMode = _TEXT_COMPACTION;
                textSubMode =
                    _SUBMODE_ALPHA; //start with submode alpha after latch
              }
              textSubMode = _encodeText(msg, p, t, sb, textSubMode);
              p += t;
            } else {
              int b = _determineConsecutiveBinaryCount(msg, p, encoding);
              if (b == 0) {
                b = 1;
              }
              Uint8List bytes =
                  Uint8List.fromList(encoding.encode(msg.substring(p, p + b)));
              if (bytes.length == 1 && encodingMode == _TEXT_COMPACTION) {
                //Switch for one byte (instead of latch)
                _encodeBinary(bytes, 0, 1, _TEXT_COMPACTION, sb);
              } else {
                //Mode latch performed by encodeBinary()
                _encodeBinary(bytes, 0, bytes.length, encodingMode, sb);
                encodingMode = _BYTE_COMPACTION;
                textSubMode = _SUBMODE_ALPHA; //Reset after latch
              }
              p += b;
            }
          }
        }
        break;
    }

    return sb.toString();
  }

  /// Encode parts of the message using Text Compaction as described in ISO/IEC 15438:2001(E),
  /// chapter 4.4.2.
  ///
  /// @param msg            the message
  /// @param startpos       the start position within the message
  /// @param count          the number of characters to encode
  /// @param sb             receives the encoded codewords
  /// @param initialSubmode should normally be SUBMODE_ALPHA
  /// @return the text submode in which this method ends
  static int _encodeText(String msg, int startpos, int count, StringBuffer sb,
      int initialSubmode) {
    StringBuilder tmp = StringBuilder();
    int submode = initialSubmode;
    int idx = 0;
    while (true) {
      int ch = msg.codeUnitAt(startpos + idx);
      switch (submode) {
        case _SUBMODE_ALPHA:
          if (_isAlphaUpper(ch)) {
            if (ch == _blankCode) {
              tmp.writeCharCode(26); //space
            } else {
              tmp.writeCharCode(ch - 65);
            }
          } else {
            if (_isAlphaLower(ch)) {
              submode = _SUBMODE_LOWER;
              tmp.writeCharCode(27); //ll
              continue;
            } else if (_isMixed(ch)) {
              submode = _SUBMODE_MIXED;
              tmp.writeCharCode(28); //ml
              continue;
            } else {
              tmp.writeCharCode(29); //ps
              tmp.writeCharCode(_punctuatuin[ch]);
              break;
            }
          }
          break;
        case _SUBMODE_LOWER:
          if (_isAlphaLower(ch)) {
            if (ch == _blankCode) {
              tmp.writeCharCode(26); //space
            } else {
              tmp.writeCharCode(ch - 97);
            }
          } else {
            if (_isAlphaUpper(ch)) {
              tmp.writeCharCode(27); //as
              tmp.writeCharCode(ch - 65);
              //space cannot happen here, it is also in "Lower"
              break;
            } else if (_isMixed(ch)) {
              submode = _SUBMODE_MIXED;
              tmp.writeCharCode(28); //ml
              continue;
            } else {
              tmp.writeCharCode(29); //ps
              tmp.writeCharCode(_punctuatuin[ch]);
              break;
            }
          }
          break;
        case _SUBMODE_MIXED:
          if (_isMixed(ch)) {
            tmp.writeCharCode(_mixed[ch]);
          } else {
            if (_isAlphaUpper(ch)) {
              submode = _SUBMODE_ALPHA;
              tmp.writeCharCode(28); //al
              continue;
            } else if (_isAlphaLower(ch)) {
              submode = _SUBMODE_LOWER;
              tmp.writeCharCode(27); //ll
              continue;
            } else {
              if (startpos + idx + 1 < count) {
                int next = msg.codeUnitAt(startpos + idx + 1);
                if (_isPunctuation(next)) {
                  submode = _SUBMODE_PUNCTUATION;
                  tmp.writeCharCode(25); //pl
                  continue;
                }
              }
              tmp.writeCharCode(29); //ps
              tmp.writeCharCode(_punctuatuin[ch]);
            }
          }
          break;
        default: //SUBMODE_PUNCTUATION
          if (_isPunctuation(ch)) {
            tmp.writeCharCode(_punctuatuin[ch]);
          } else {
            submode = _SUBMODE_ALPHA;
            tmp.writeCharCode(29); //al
            continue;
          }
      }
      idx++;
      if (idx >= count) {
        break;
      }
    }
    int h = 0;
    int len = tmp.length;
    for (int i = 0; i < len; i++) {
      bool odd = (i % 2) != 0;
      if (odd) {
        h = (h * 30) + tmp.codePointAt(i);
        sb.writeCharCode(h);
      } else {
        h = tmp.codePointAt(i);
      }
    }
    if ((len % 2) != 0) {
      sb.writeCharCode((h * 30) + 29); //ps
    }
    return submode;
  }

  /// Encode parts of the message using Byte Compaction as described in ISO/IEC 15438:2001(E),
  /// chapter 4.4.3. The Unicode characters will be converted to binary using the cp437
  /// codepage.
  ///
  /// @param bytes     the message converted to a byte array
  /// @param startpos  the start position within the message
  /// @param count     the number of bytes to encode
  /// @param startmode the mode from which this method starts
  /// @param sb        receives the encoded codewords
  static void _encodeBinary(Uint8List bytes, int startpos, int count,
      int startmode, StringBuffer sb) {
    if (count == 1 && startmode == _TEXT_COMPACTION) {
      sb.writeCharCode(_SHIFT_TO_BYTE);
    } else {
      if ((count % 6) == 0) {
        sb.writeCharCode(_LATCH_TO_BYTE);
      } else {
        sb.writeCharCode(_LATCH_TO_BYTE_PADDED);
      }
    }

    int idx = startpos;
    // Encode sixpacks
    if (count >= 6) {
      List<int> chars = [0, 0, 0, 0, 0];
      while ((startpos + count - idx) >= 6) {
        int t = 0;
        for (int i = 0; i < 6; i++) {
          t <<= 8;
          t += bytes[idx + i] & 0xff;
        }
        for (int i = 0; i < 5; i++) {
          chars[i] = t % 900;
          t = t ~/ 900;
        }
        for (int i = chars.length - 1; i >= 0; i--) {
          sb.writeCharCode(chars[i]);
        }
        idx += 6;
      }
    }
    //Encode rest (remaining n<5 bytes if any)
    for (int i = idx; i < startpos + count; i++) {
      int ch = bytes[i] & 0xff;
      sb.writeCharCode(ch);
    }
  }

  static void _encodeNumeric(
      String msg, int startpos, int count, StringBuffer sb) {
    int idx = 0;
    StringBuilder tmp = StringBuilder();
    BigInt num900 = BigInt.from(900);
    BigInt num0 = BigInt.from(0);
    while (idx < count) {
      tmp.clear();
      int len = math.min(44, count - idx);
      String part = '1' + msg.substring(startpos + idx, startpos + idx + len);
      BigInt bigint = BigInt.parse(part);
      do {
        tmp.writeCharCode((bigint % num900).toInt());
        bigint = bigint ~/ num900;
      } while (bigint != num0);

      //Reverse temporary string
      for (int i = tmp.length - 1; i >= 0; i--) {
        sb.writeCharCode(tmp.codePointAt(i));
      }
      idx += len;
    }
  }

  static bool _isDigit(int ch) {
    return ch >= 48 /* 0 */ && ch <= 57 /* 9 */;
  }

  static bool _isAlphaUpper(int ch) {
    return ch == _blankCode || (ch >= 65 /* A */ && ch <= 90 /* Z */);
  }

  static bool _isAlphaLower(int ch) {
    return ch == _blankCode || (ch >= 97 /* a */ && ch <= 122 /* z */);
  }

  static bool _isMixed(int ch) {
    return _mixed[ch] != -1;
  }

  static bool _isPunctuation(int ch) {
    return _punctuatuin[ch] != -1;
  }

  static bool _isText(int chr) {
    return chr == 9 /*'\t'*/ ||
        chr == 10 /*'\n'*/ ||
        chr == 13 /*'\r'*/ ||
        (chr >= 32 && chr <= 126);
  }

  /// Determines the number of consecutive characters that are encodable using numeric compaction.
  ///
  /// @param msg      the message
  /// @param startpos the start position within the message
  /// @return the requested character count
  static int _determineConsecutiveDigitCount(String msg, int startpos) {
    int count = 0;
    int len = msg.length;
    int idx = startpos;
    if (idx < len) {
      int ch = msg.codeUnitAt(idx);
      while (_isDigit(ch) && idx < len) {
        count++;
        idx++;
        if (idx < len) {
          ch = msg.codeUnitAt(idx);
        }
      }
    }
    return count;
  }

  /// Determines the number of consecutive characters that are encodable using text compaction.
  ///
  /// @param msg      the message
  /// @param startpos the start position within the message
  /// @return the requested character count
  static int _determineConsecutiveTextCount(String msg, int startpos) {
    int len = msg.length;
    int idx = startpos;
    while (idx < len) {
      int ch = msg.codeUnitAt(idx);
      int numericCount = 0;
      while (numericCount < 13 && _isDigit(ch) && idx < len) {
        numericCount++;
        idx++;
        if (idx < len) {
          ch = msg.codeUnitAt(idx);
        }
      }
      if (numericCount >= 13) {
        return idx - startpos - numericCount;
      }
      if (numericCount > 0) {
        //Heuristic: All text-encodable chars or digits are binary encodable
        continue;
      }
      ch = msg.codeUnitAt(idx);

      //Check if character is encodable
      if (!_isText(ch)) {
        break;
      }
      idx++;
    }
    return idx - startpos;
  }

  /// Determines the number of consecutive characters that are encodable using binary compaction.
  ///
  /// @param msg      the message
  /// @param startpos the start position within the message
  /// @param encoding the charset used to convert the message to a byte array
  /// @return the requested character count
  static int _determineConsecutiveBinaryCount(
      String msg, int startpos, Encoding encoding) {
    int len = msg.length;
    int idx = startpos;
    while (idx < len) {
      int ch = msg.codeUnitAt(idx);
      int numericCount = 0;

      while (numericCount < 13 && _isDigit(ch)) {
        numericCount++;
        //textCount++;
        int i = idx + numericCount;
        if (i >= len) {
          break;
        }
        ch = msg.codeUnitAt(i);
      }
      if (numericCount >= 13) {
        return idx - startpos;
      }
      ch = msg.codeUnitAt(idx);

      // todo 判断是否超出字符集
      //if (!encoder.canEncode(ch)) {
      //  throw WriterException(
      //      "Non-encodable character detected: ${String.fromCharCode(ch)} (Unicode: $ch)");
      //}
      idx++;
    }
    return idx - startpos;
  }

  static void _encodingECI(int eci, StringBuffer sb) {
    if (eci >= 0 && eci < 900) {
      sb.writeCharCode(_ECI_CHARSET);
      sb.writeCharCode(eci);
    } else if (eci < 810900) {
      sb.writeCharCode(_ECI_GENERAL_PURPOSE);
      sb.writeCharCode((eci ~/ 900 - 1));
      sb.writeCharCode((eci % 900));
    } else if (eci < 811800) {
      sb.writeCharCode(_ECI_USER_DEFINED);
      sb.writeCharCode((810900 - eci));
    } else {
      throw WriterException(
          "ECI number not in valid range from 0..811799, but was $eci");
    }
  }
}
