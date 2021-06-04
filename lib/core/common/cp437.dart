
import 'dart:convert';

const String wideCharMap = 'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ';
const Map<int, int> wideCharToUtf8 = {
  128: 199,
  129: 252,
  130: 233,
  131: 226,
  132: 228,
  133: 224,
  134: 229,
  135: 231,
  136: 234,
  137: 235,
  138: 232,
  139: 239,
  140: 238,
  141: 236,
  142: 196,
  143: 197,
  144: 201,
  145: 230,
  146: 198,
  147: 244,
  148: 246,
  149: 242,
  150: 251,
  151: 249,
  152: 255,
  153: 214,
  154: 220,
  155: 162,
  156: 163,
  157: 165,
  158: 8359,
  159: 402,
  160: 225,
  161: 237,
  162: 243,
  163: 250,
  164: 241,
  165: 209,
  166: 170,
  167: 186,
  168: 191,
  169: 8976,
  170: 172,
  171: 189,
  172: 188,
  173: 161,
  174: 171,
  175: 187,
  176: 9617,
  177: 9618,
  178: 9619,
  179: 9474,
  180: 9508,
  181: 9569,
  182: 9570,
  183: 9558,
  184: 9557,
  185: 9571,
  186: 9553,
  187: 9559,
  188: 9565,
  189: 9564,
  190: 9563,
  191: 9488,
  192: 9492,
  193: 9524,
  194: 9516,
  195: 9500,
  196: 9472,
  197: 9532,
  198: 9566,
  199: 9567,
  200: 9562,
  201: 9556,
  202: 9577,
  203: 9574,
  204: 9568,
  205: 9552,
  206: 9580,
  207: 9575,
  208: 9576,
  209: 9572,
  210: 9573,
  211: 9561,
  212: 9560,
  213: 9554,
  214: 9555,
  215: 9579,
  216: 9578,
  217: 9496,
  218: 9484,
  219: 9608,
  220: 9604,
  221: 9612,
  222: 9616,
  223: 9600,
  224: 945,
  225: 223,
  226: 915,
  227: 960,
  228: 931,
  229: 963,
  230: 181,
  231: 964,
  232: 934,
  233: 920,
  234: 937,
  235: 948,
  236: 8734,
  237: 966,
  238: 949,
  239: 8745,
  240: 8801,
  241: 177,
  242: 8805,
  243: 8804,
  244: 8992,
  245: 8993,
  246: 247,
  247: 8776,
  248: 176,
  249: 8729,
  250: 183,
  251: 8730,
  252: 8319,
  253: 178,
  254: 9632,
  255: 160,
};
const Map<int, int> utf8ToWide = {
  199: 128,
  252: 129,
  233: 130,
  226: 131,
  228: 132,
  224: 133,
  229: 134,
  231: 135,
  234: 136,
  235: 137,
  232: 138,
  239: 139,
  238: 140,
  236: 141,
  196: 142,
  197: 143,
  201: 144,
  230: 145,
  198: 146,
  244: 147,
  246: 148,
  242: 149,
  251: 150,
  249: 151,
  255: 152,
  214: 153,
  220: 154,
  162: 155,
  163: 156,
  165: 157,
  8359: 158,
  402: 159,
  225: 160,
  237: 161,
  243: 162,
  250: 163,
  241: 164,
  209: 165,
  170: 166,
  186: 167,
  191: 168,
  8976: 169,
  172: 170,
  189: 171,
  188: 172,
  161: 173,
  171: 174,
  187: 175,
  9617: 176,
  9618: 177,
  9619: 178,
  9474: 179,
  9508: 180,
  9569: 181,
  9570: 182,
  9558: 183,
  9557: 184,
  9571: 185,
  9553: 186,
  9559: 187,
  9565: 188,
  9564: 189,
  9563: 190,
  9488: 191,
  9492: 192,
  9524: 193,
  9516: 194,
  9500: 195,
  9472: 196,
  9532: 197,
  9566: 198,
  9567: 199,
  9562: 200,
  9556: 201,
  9577: 202,
  9574: 203,
  9568: 204,
  9552: 205,
  9580: 206,
  9575: 207,
  9576: 208,
  9572: 209,
  9573: 210,
  9561: 211,
  9560: 212,
  9554: 213,
  9555: 214,
  9579: 215,
  9578: 216,
  9496: 217,
  9484: 218,
  9608: 219,
  9604: 220,
  9612: 221,
  9616: 222,
  9600: 223,
  945: 224,
  223: 225,
  915: 226,
  960: 227,
  931: 228,
  963: 229,
  181: 230,
  964: 231,
  934: 232,
  920: 233,
  937: 234,
  948: 235,
  8734: 236,
  966: 237,
  949: 238,
  8745: 239,
  8801: 240,
  177: 241,
  8805: 242,
  8804: 243,
  8992: 244,
  8993: 245,
  247: 246,
  8776: 247,
  176: 248,
  8729: 249,
  183: 250,
  8730: 251,
  8319: 252,
  178: 253,
  9632: 254,
  160: 255,
};

const cp437 = Cp437(true);

class Cp437 extends Encoding{
  final bool _allowInvalid;

  const Cp437([this._allowInvalid = false]):super();

  String get name => "cp437";

  Cp437Encoder get encoder => const Cp437Encoder();

  Cp437Decoder get decoder => _allowInvalid
      ? const Cp437Decoder(true)
      : const Cp437Decoder();
}


class Cp437Encoder extends Converter<String, List<int>>{

  const Cp437Encoder();

  @override
  List<int> convert(String input) => input.codeUnits.map((e) => e > 0x7f ? utf8ToWide[e] ?? 63 : e).toList();
}

class Cp437Decoder extends Converter<List<int>, String>{
  final bool _allowInvalid;
  const Cp437Decoder([this._allowInvalid = false]);

  @override
  String convert(List<int> input) => String.fromCharCodes(input.map((e) => e > 0x7f ? (wideCharToUtf8[e] ?? 63) : e ));

}