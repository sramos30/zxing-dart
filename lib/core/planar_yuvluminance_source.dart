/*
 * Copyright 2009 ZXing authors
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

import 'dart:typed_data';

import 'luminance_source.dart';

/**
 * This object extends LuminanceSource around an array of YUV data returned from the camera driver,
 * with the option to crop to a rectangle within the full data. This can be used to exclude
 * superfluous pixels around the perimeter and speed up decoding.
 *
 * It works for any pixel format where the Y channel is planar and appears first, including
 * YCbCr_420_SP and YCbCr_422_SP.
 *
 * @author dswitkin@google.com (Daniel Switkin)
 */
class PlanarYUVLuminanceSource extends LuminanceSource {
  static const int _THUMBNAIL_SCALE_FACTOR = 2;

  final Uint8List _yuvData;
  final int _dataWidth;
  final int _dataHeight;
  final int _left;
  final int _top;

  PlanarYUVLuminanceSource(this._yuvData, this._dataWidth, this._dataHeight,
      this._left, this._top, int width, int height, bool isReverseHorizontal)
      : super(width, height) {
    if (_left + width > _dataWidth || _top + height > _dataHeight) {
      throw Exception("Crop rectangle does not fit within image data.");
    }

    if (isReverseHorizontal) {
      _reverseHorizontal(width, height);
    }
  }

  @override
  Uint8List getRow(int y, Uint8List? row) {
    if (y < 0 || y >= getHeight()) {
      throw Exception("Requested row is outside the image: $y");
    }
    int width = getWidth();
    if (row == null || row.length < width) {
      row = Uint8List(width);
    }
    int offset = (y + _top) * _dataWidth + _left;
    List.copyRange(row, 0, _yuvData, offset, offset + width);
    return row;
  }

  @override
  Uint8List getMatrix() {
    int width = getWidth();
    int height = getHeight();

    // If the caller asks for the entire underlying image, save the copy and give them the
    // original data. The docs specifically warn that result.length must be ignored.
    if (width == _dataWidth && height == _dataHeight) {
      return _yuvData;
    }

    int area = width * height;
    Uint8List matrix = Uint8List(area);
    int inputOffset = _top * _dataWidth + _left;

    // If the width matches the full width of the underlying data, perform a single copy.
    if (width == _dataWidth) {
      List.copyRange(matrix, 0, _yuvData, inputOffset, inputOffset + area);
      return matrix;
    }

    // Otherwise copy one cropped row at a time.
    for (int y = 0; y < height; y++) {
      int outputOffset = y * width;
      List.copyRange(matrix, outputOffset, _yuvData, inputOffset, inputOffset + width);
      inputOffset += _dataWidth;
    }
    return matrix;
  }

  @override
  bool isCropSupported() {
    return true;
  }

  @override
  LuminanceSource crop(int left, int top, int width, int height) {
    return PlanarYUVLuminanceSource(_yuvData, _dataWidth, _dataHeight,
        this._left + left, this._top + top, width, height, false);
  }

  List<int> renderThumbnail() {
    int width = getWidth() ~/ _THUMBNAIL_SCALE_FACTOR;
    int height = getHeight() ~/ _THUMBNAIL_SCALE_FACTOR;
    List<int> pixels = List.generate(width * height, (index) => 0);
    Uint8List yuv = _yuvData;
    int inputOffset = _top * _dataWidth + _left;

    for (int y = 0; y < height; y++) {
      int outputOffset = y * width;
      for (int x = 0; x < width; x++) {
        int grey = yuv[inputOffset + x * _THUMBNAIL_SCALE_FACTOR] & 0xff;
        pixels[outputOffset + x] = 0xFF000000 | (grey * 0x00010101);
      }
      inputOffset += _dataWidth * _THUMBNAIL_SCALE_FACTOR;
    }
    return pixels;
  }

  /**
   * @return width of image from {@link #renderThumbnail()}
   */
  int getThumbnailWidth() {
    return getWidth() ~/ _THUMBNAIL_SCALE_FACTOR;
  }

  /**
   * @return height of image from {@link #renderThumbnail()}
   */
  int getThumbnailHeight() {
    return getHeight() ~/ _THUMBNAIL_SCALE_FACTOR;
  }

  void _reverseHorizontal(int width, int height) {
    Uint8List yuvData = this._yuvData;
    for (int y = 0, rowStart = _top * _dataWidth + _left;
        y < height;
        y++, rowStart += _dataWidth) {
      int middle = rowStart + width ~/ 2;
      for (int x1 = rowStart, x2 = rowStart + width - 1;
          x1 < middle;
          x1++, x2--) {
        int temp = yuvData[x1];
        yuvData[x1] = yuvData[x2];
        yuvData[x2] = temp;
      }
    }
  }
}
