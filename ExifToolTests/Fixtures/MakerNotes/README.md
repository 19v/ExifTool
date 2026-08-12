# MakerNote fixtures

These reduced JPEG files retain real camera EXIF and MakerNote payloads while keeping the test bundle small:

- `Fujifilm_FinePix_E500.jpg`
- `Nikon_D70.jpg`
- `Sony_HDR-HC3.jpg`

The reduced RAW fixtures exercise ImageIO and the vendor MakerNote parsers without bundling full-resolution image data:

- `Fujifilm_FinePix_S5Pro.raf` — verifies that a reduced RAF unsupported by ImageIO fails safely
- `Nikon_D70.nef` — expected make/model `NIKON CORPORATION` / `NIKON D70`

They come from the archived [`ianare/exif-samples`](https://github.com/ianare/exif-samples) test corpus and are used under the [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) license. The files are redistributed unchanged; attribution belongs to that repository and its contributors.

The RAW fixtures come from the official [`exiftool/exiftool`](https://github.com/exiftool/exiftool) test suite. Their expected values are pinned from ExifTool 13.59 output. ExifTool is distributed under the same terms as Perl (Artistic License or GNU GPL).
